// monitor-fastcast.mjs — the FastCast protocol SOAK: run for hours/days,
// subscribe a spread of topics, and log every message that deviates from the
// verified protocol (fastcast-plan.md) — with up to N samples of each unique
// anomaly and the context at the time. This is how we upgrade "verified for
// minutes on 2026-07-08" into "watched for days".
//
//   node scripts/monitor-fastcast.mjs                    # v1 event topics + topevents, 72h
//   node scripts/monitor-fastcast.mjs --hours 6          # shorter soak
//   node scripts/monitor-fastcast.mjs --topic event-baseball-mlb gp-baseball-mlb-401816076
//   node scripts/monitor-fastcast.mjs --priority v1,v2 --auto-gp 3
//
// What it watches for (each becomes a SIGNATURE with count + up to --samples
// recorded examples in the output):
//   op-unknown:<op>       an op we've never seen (C/S/H/P/R/B/I are known)
//   op-b / op-i           op:"B" and op:"I" frames (observed, unexplained; "I"
//                         carries pl:"0" AND a mid — it looks like a per-topic
//                         heartbeat, and it consuming mids likely explains the
//                         Phase-0 "mid gaps on a healthy connection")
//   frame-no-tc:<op>      topic-less frames beyond C/B
//   raw-non-json          a text frame that isn't JSON
//   s-ack-rc:<rc>         subscribe acks per rc (samples kept for non-200)
//   h-repeat              a SECOND H on an already-checkpointed topic mid-session
//   mid-gap / mid-regress / mid-dup   mid sequencing anomalies per topic
//   decode-error          P/R payload that fails base64/zlib/JSON decode
//   compress-flag:<~c>    a ~c value other than 0/1/absent
//   pl-not-array          decoded delta that isn't an RFC 6902 array
//   rfc-op:<kind>         move/copy/test ops (supported but never observed)
//   rfc-root-path         a root ('' ) path op
//   gp-path-nonrooted     a gp-* patch path that isn't root-relative
//   apply-error           the REAL check: each patch is applied to the live doc
//                         with the oracle appliers (worker/src/fastcast.js);
//                         any per-op error is recorded with full context
//   checkpoint-keys-changed  a re-fetched checkpoint whose top-level key set drifted
//   checkpoint-fetch-error   H checkpoint GET failures
//   topic-appeared        a topic that was rc:404/silent earlier answered later
//                         (dormant-league retry — Phase 0 finding #2)
//   socket-close / connect-error   connection lifetime + reconnect behavior
//
// Output (default worker/monitor/, gitignored):
//   summary.json   counts, per-topic stats (frames/bytes/mids/gaps), ping stats,
//                  connection history, and every signature's samples — rewritten
//                  every minute and on exit; safe to inspect mid-run.
//   events.jsonl   append-only stream of the sampled anomalies as they happen.
//
// Restart-safe: counts/samples are merged from an existing summary.json.
// Stop with Ctrl-C (flushes) or let --hours expire.

import { writeFileSync, mkdirSync, readFileSync, appendFileSync, existsSync, renameSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import registry from '../../schema/league-profiles.json' with { type: 'json' };
import { leagueKeys, resolve } from '../../schema/tools/resolve.mjs';
import { applyOps, applyEventOps } from '../src/fastcast.js';
import { FastcastSocket, decodeDelta, eventTopicFor, getJson } from './fastcast-ws.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));

// ---- args -------------------------------------------------------------------
function parseArgs(argv) {
  const a = {
    hours: 72, topics: null, priority: 'v1', autoGp: 2, samples: 6,
    out: join(HERE, '..', 'monitor'), resubMin: 360,
  };
  for (let i = 0; i < argv.length; i++) {
    const t = argv[i];
    if (t === '--hours') a.hours = +argv[++i];
    else if (t === '--topic') { a.topics = []; while (argv[i + 1] && !argv[i + 1].startsWith('--')) a.topics.push(argv[++i]); }
    else if (t === '--priority') a.priority = argv[++i];
    else if (t === '--auto-gp') a.autoGp = +argv[++i];
    else if (t === '--samples') a.samples = +argv[++i];
    else if (t === '--out') a.out = argv[++i];
    else if (t === '--resub-min') a.resubMin = +argv[++i];
  }
  return a;
}
const A = parseArgs(process.argv.slice(2));
mkdirSync(A.out, { recursive: true });
const SUMMARY = join(A.out, 'summary.json');
const EVENTS = join(A.out, 'events.jsonl');

// ---- state ------------------------------------------------------------------
const startedAt = new Date().toISOString();
const deadline = Date.now() + A.hours * 3600_000;
let stopping = false;

// signature → {count, samples[]} (merged from a previous run if present)
const sigs = {};
// topic → per-topic state
const topics = new Map();
const connections = []; // {connectedAt, sid, closedAt?, ageSec?, bytesIn?}
const pings = { count: 0, lastAt: 0, gaps: [] }; // gap seconds between server pings (sample cap 50)
let fc = null;
let connEpoch = 0;

if (existsSync(SUMMARY)) {
  try {
    const prev = JSON.parse(readFileSync(SUMMARY, 'utf8'));
    Object.assign(sigs, prev.signatures ?? {});
    console.log(`merged ${Object.keys(sigs).length} signature(s) from previous run`);
  } catch { /* corrupt/absent — start fresh */ }
}

function topicState(tc) {
  let t = topics.get(tc);
  if (!t) {
    t = {
      tc, subscribedAt: null, ackRc: null, checkpointUrl: null, doc: null,
      docKeys: null, lastMid: null, frames: 0, ops: 0, applyErrors: 0,
      gaps: 0, hCount: 0, everLive: false, dormant: false, lastFrameAt: 0,
      // Frames that arrive while the checkpoint is downloading buffer here and
      // apply after it lands (like the app client) — otherwise every race
      // shows up as a bogus apply-error.
      fetching: false, buffered: [], lastSyncAt: 0, lastResyncAt: 0,
    };
    topics.set(tc, t);
  }
  return t;
}

// ---- recording ----------------------------------------------------------------
function record(sig, sample, { sampleAlways = false } = {}) {
  const s = (sigs[sig] ??= { count: 0, samples: [] });
  s.count++;
  const keep = s.samples.length < A.samples || sampleAlways;
  if (!keep) return;
  const entry = { sig, n: s.count, t: new Date().toISOString(), ...sample };
  if (s.samples.length < A.samples) s.samples.push(entry);
  appendFileSync(EVENTS, JSON.stringify(entry) + '\n');
  if (s.count === 1) console.log(`NEW SIGNATURE ${sig}:`, JSON.stringify(sample).slice(0, 300));
}

// Context snapshot for a sample: where were we when this happened?
function ctx(t, msg) {
  const conn = connections[connections.length - 1];
  return {
    topic: t?.tc ?? msg?.tc ?? null,
    mid: msg?.mid ?? null,
    op: msg?.op ?? null,
    connAgeSec: conn ? Math.round((Date.now() - Date.parse(conn.connectedAt)) / 1000) : null,
    topicFrames: t?.frames ?? null,
    lastMid: t?.lastMid ?? null,
    sinceLastFrameSec: t?.lastFrameAt ? Math.round((Date.now() - t.lastFrameAt) / 1000) : null,
    docEvents: t?.doc ? countDocEvents(t) : null,
    raw: truncate(msg),
  };
}

function truncate(v, cap = 4000) {
  try {
    const s = typeof v === 'string' ? v : JSON.stringify(v);
    return s.length > cap ? s.slice(0, cap) + `…(+${s.length - cap})` : s;
  } catch { return String(v); }
}

function countDocEvents(t) {
  const d = t.doc;
  if (t.tc.startsWith('gp-')) return d && typeof d === 'object' ? Object.keys(d).length + ' keys' : null;
  let n = 0;
  for (const s of d?.sports ?? []) for (const l of s?.leagues ?? []) n += (l?.events ?? []).length;
  return n;
}

// ---- topic selection ------------------------------------------------------------
function defaultTopics() {
  const pri = A.priority.split(',').map((s) => s.trim());
  const out = ['event-topevents'];
  for (const key of leagueKeys(registry)) {
    const p = resolve(registry, key);
    if (!pri.includes(p.priority)) continue;
    if (!(p.capabilities?.fastcast)) continue;
    out.push(eventTopicFor(key));
  }
  return out;
}
const WATCH = A.topics ?? defaultTopics();

// ---- frame handling ---------------------------------------------------------------
const KNOWN_OPS = new Set(['C', 'S', 'H', 'P', 'R', 'B', 'I']);

function onMessage(epoch, msg) {
  if (epoch !== connEpoch) return;
  const op = msg?.op;
  const tc = msg?.tc;
  if (op === 'B') { record('op-b', ctx(null, msg)); return; }
  if (op === 'C') return; // handshake acks handled by FastcastSocket
  if (!tc) {
    record(KNOWN_OPS.has(op) ? `frame-no-tc:${op}` : `op-unknown:${op}`, ctx(null, msg));
    return;
  }
  const t = topicState(tc);
  t.frames++;

  if (op === 'S') {
    const rc = msg.rc ?? null;
    t.ackRc = rc;
    record(`s-ack-rc:${rc}`, rc === 200 ? { topic: tc } : ctx(t, msg));
    if (rc !== 200) t.dormant = true;
    return;
  }
  if (t.dormant) {
    // A frame on a topic that 404'd earlier — the dormant league woke up.
    t.dormant = false;
    record('topic-appeared', ctx(t, msg));
  }
  // mid sequencing across EVERY topic frame that carries one — op:"I" frames
  // consume mids too, so excluding them fabricates gaps (the Phase-0 lesson).
  const mid = msg.mid;
  if (typeof mid === 'number' && typeof t.lastMid === 'number' && op !== 'H') {
    if (mid === t.lastMid) record('mid-dup', ctx(t, msg));
    else if (mid < t.lastMid) record('mid-regress', { ...ctx(t, msg), prev: t.lastMid });
    else if (mid > t.lastMid + 1) { t.gaps++; record('mid-gap', { ...ctx(t, msg), prev: t.lastMid, missed: mid - t.lastMid - 1 }); }
  }
  if (typeof mid === 'number') t.lastMid = mid;
  t.lastFrameAt = Date.now();

  if (op === 'I') { record('op-i', ctx(t, msg)); return; }
  if (!KNOWN_OPS.has(op)) { record(`op-unknown:${op}`, ctx(t, msg)); return; }

  if (op === 'H') {
    t.hCount++;
    if (t.hCount > 1) record('h-repeat', { ...ctx(t, msg), priorCheckpoint: t.checkpointUrl });
    t.checkpointUrl = String(msg.pl ?? '');
    fetchCheckpoint(t, epoch);
    return;
  }

  // op P / R
  let decoded;
  try {
    decoded = decodeDelta(msg);
  } catch (e) {
    record('decode-error', { ...ctx(t, msg), error: String(e) });
    return;
  }
  const cf = decoded.compressFlag;
  if (cf !== undefined && cf !== 0 && cf !== 1) record(`compress-flag:${cf}`, ctx(t, msg));
  const ops = decoded.ops;
  if (!Array.isArray(ops)) { record('pl-not-array', { ...ctx(t, msg), decoded: truncate(ops) }); return; }
  t.ops += ops.length;

  for (const o of ops) {
    if (o?.op === 'move' || o?.op === 'copy' || o?.op === 'test') {
      record(`rfc-op:${o.op}`, { ...ctx(t, msg), patchOp: truncate(o) });
    }
    if (o?.path === '') record('rfc-root-path', { ...ctx(t, msg), patchOp: truncate(o) });
    if (t.tc.startsWith('gp-') && typeof o?.path === 'string' && o.path !== '' && !o.path.startsWith('/')) {
      record('gp-path-nonrooted', { ...ctx(t, msg), patchOp: truncate(o) });
    }
  }

  // Checkpoint still downloading → buffer, apply when it lands (as the app does).
  if (t.fetching) { t.buffered.push({ mid, ops }); return; }
  applyBatch(t, mid, ops, epoch);
  // auto-gp: fish live events out of event docs and shadow their gp topics.
  if (!t.tc.startsWith('gp-')) maybeAutoGp(t);
}

// THE core validation: apply against the live doc with the oracle appliers.
// Errors within 15s of a checkpoint sync are classified separately — the R
// replay bridging the checkpoint can race a NEWER snapshot (remove-of-missing
// etc.), which is expected; steady-state errors are the real finding.
function applyBatch(t, mid, ops, epoch) {
  if (t.doc == null) return;
  const apply = t.tc.startsWith('gp-') ? applyOps : applyEventOps;
  const r = apply(t.doc, ops);
  t.doc = r.doc;
  if (!r.errors.length) return;
  t.applyErrors += r.errors.length;
  const postSync = Date.now() - t.lastSyncAt < 15_000;
  record(postSync ? 'apply-error-postsync' : 'apply-error', {
    ...ctx(t, { mid, tc: t.tc }),
    errors: r.errors.slice(0, 4),
    failedOps: truncate(ops.filter((_, i) => r.errors.some((e) => e.startsWith(`${i}:`)))),
  });
  // Resync so one divergence doesn't cascade into days of noise — but at most
  // once a minute per topic (a checkpoint can be ~1MB).
  if (!postSync && Date.now() - t.lastResyncAt > 60_000) {
    t.lastResyncAt = Date.now();
    fetchCheckpoint(t, epoch);
  }
}

async function fetchCheckpoint(t, epoch) {
  if (!t.checkpointUrl || t.fetching) return;
  t.fetching = true;
  t.buffered = [];
  try {
    const doc = await getJson(t.checkpointUrl);
    if (epoch !== connEpoch) return;
    const keys = typeof doc === 'object' && doc ? Object.keys(doc).sort().join(',') : String(typeof doc);
    if (t.docKeys && keys !== t.docKeys) {
      record('checkpoint-keys-changed', { topic: t.tc, before: t.docKeys, after: keys });
    }
    t.docKeys = keys;
    t.doc = doc;
    t.lastSyncAt = Date.now();
  } catch (e) {
    record('checkpoint-fetch-error', { topic: t.tc, url: t.checkpointUrl, error: String(e) });
  } finally {
    t.fetching = false;
    const buffered = t.buffered;
    t.buffered = [];
    for (const b of buffered) applyBatch(t, b.mid, b.ops, epoch);
  }
}

// ---- auto-gp: shadow up to A.autoGp live games' gamepackage topics ---------------
const autoGp = new Set();
function maybeAutoGp(t) {
  if (A.autoGp <= 0 || autoGp.size >= A.autoGp) return;
  const m = /^event-([^-]+)-(.+)$/.exec(t.tc);
  if (!m) return;
  for (const s of t.doc?.sports ?? []) {
    for (const l of s?.leagues ?? []) {
      for (const ev of l?.events ?? []) {
        const state = ev?.fullStatus?.type?.state ?? ev?.status;
        if (state !== 'in') continue;
        const gp = `gp-${m[1]}-${m[2]}-${ev.id}`;
        if (topics.has(gp) || autoGp.size >= A.autoGp) continue;
        autoGp.add(gp);
        console.log(`auto-subscribing ${gp} (live game on ${t.tc})`);
        subscribeTopic(gp);
      }
    }
  }
}

function subscribeTopic(tc) {
  const t = topicState(tc);
  t.subscribedAt = new Date().toISOString();
  try { fc?.subscribe(tc); } catch { /* reconnect path will retry */ }
}

// ---- connection loop --------------------------------------------------------------
async function connectLoop() {
  let backoff = 5000;
  while (!stopping && Date.now() < deadline) {
    const epoch = ++connEpoch;
    try {
      fc = await new FastcastSocket().connect();
      backoff = 5000;
      const conn = { connectedAt: new Date().toISOString(), sid: fc.sid };
      connections.push(conn);
      console.log(`[${conn.connectedAt}] connected sid=${fc.sid} (#${connections.length})`);
      fc.on('message', (msg) => onMessage(epoch, msg));
      fc.on('raw', (text) => record('raw-non-json', { raw: truncate(text) }));
      fc.on('ping', () => {
        const now = Date.now();
        if (pings.lastAt && pings.gaps.length < 50) pings.gaps.push(Math.round((now - pings.lastAt) / 1000));
        pings.lastAt = now;
        pings.count++;
      });
      const closed = new Promise((res) => fc.on('close', res));
      // (Re)subscribe everything we're watching; docs refresh via fresh H frames.
      for (const tc of WATCH) subscribeTopic(tc);
      for (const tc of autoGp) subscribeTopic(tc);
      await closed;
      const sock = fc;
      conn.closedAt = new Date().toISOString();
      conn.ageSec = Math.round((Date.parse(conn.closedAt) - Date.parse(conn.connectedAt)) / 1000);
      conn.bytesIn = sock.bytesIn;
      if (!stopping) record('socket-close', { ageSec: conn.ageSec, bytesIn: sock.bytesIn, sid: conn.sid });
    } catch (e) {
      record('connect-error', { error: String(e) });
      await sleep(backoff);
      backoff = Math.min(backoff * 2, 120_000);
      continue;
    }
    if (!stopping && Date.now() < deadline) await sleep(3000);
  }
}

// Re-poke dormant (rc:404 / silent) topics every --resub-min: does the topic
// appear when its league wakes up? (Phase 0 finding #2's retry-later question.)
async function resubLoop() {
  for (;;) {
    await sleep(A.resubMin * 60_000);
    if (stopping || Date.now() >= deadline) return;
    for (const t of topics.values()) {
      if (t.dormant && WATCH.includes(t.tc)) {
        console.log(`re-probing dormant ${t.tc}`);
        subscribeTopic(t.tc);
      }
    }
  }
}

// ---- summary flush ------------------------------------------------------------------
function flush() {
  const perTopic = {};
  for (const t of topics.values()) {
    perTopic[t.tc] = {
      ackRc: t.ackRc, frames: t.frames, ops: t.ops, gaps: t.gaps,
      applyErrors: t.applyErrors, hCount: t.hCount, lastMid: t.lastMid,
      dormant: t.dormant, docKeys: t.docKeys ? t.docKeys.split(',').length : null,
    };
  }
  const body = JSON.stringify({
    startedAt, updatedAt: new Date().toISOString(),
    hours: A.hours, watch: WATCH, autoGp: [...autoGp],
    connections, pings: { count: pings.count, gapSecSamples: pings.gaps },
    perTopic, signatures: sigs,
  }, null, 1);
  // atomic-ish: write then rename, so a mid-write crash can't corrupt summary.json
  writeFileSync(SUMMARY + '.tmp', body);
  renameSync(SUMMARY + '.tmp', SUMMARY);
}

function heartbeat() {
  let frames = 0; let errs = 0;
  for (const t of topics.values()) { frames += t.frames; errs += t.applyErrors; }
  const sigLine = Object.entries(sigs)
    .filter(([k]) => !k.startsWith('s-ack-rc:200') && k !== 'op-i')
    .map(([k, v]) => `${k}=${v.count}`).join(' ') || '(none)';
  console.log(`[${new Date().toISOString()}] up ${Math.round((Date.now() - Date.parse(startedAt)) / 60000)}m · ` +
    `${topics.size} topics · ${frames} frames · applyErrors=${errs} · ${sigLine}`);
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---- main ---------------------------------------------------------------------------
console.log(`FastCast soak: ${WATCH.length} topics, ${A.hours}h, samples/sig=${A.samples}, auto-gp=${A.autoGp}`);
console.log(`output: ${SUMMARY}`);
const flusher = setInterval(flush, 60_000);
const beat = setInterval(heartbeat, 15 * 60_000);
// Enforce the deadline even while a socket is open — connectLoop only checks
// between connections, and a healthy connection stays up indefinitely.
setTimeout(() => {
  if (stopping) return;
  console.log('deadline reached — closing…');
  stopping = true;
  try { fc?.close(); } catch { /* already gone */ }
}, Math.max(0, deadline - Date.now()));
process.on('SIGINT', () => {
  console.log('stopping (SIGINT) — flushing…');
  stopping = true;
  try { fc?.close(); } catch { /* already gone */ }
  clearInterval(flusher); clearInterval(beat);
  flush();
  process.exit(0);
});

resubLoop();
await connectLoop();
stopping = true;
clearInterval(flusher); clearInterval(beat);
flush();
heartbeat();
console.log('soak complete.');

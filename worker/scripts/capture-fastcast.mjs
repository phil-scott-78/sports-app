// capture-fastcast.mjs — probe + capture tooling for ESPN FastCast (see
// fastcast-plan.md for the verified protocol). Pure Node, no dependencies —
// the WebSocket client is hand-rolled because Node's built-in WebSocket can't
// send the Origin/User-Agent headers the server requires on upgrade.
//
//   node scripts/capture-fastcast.mjs --probe                  # topic existence, v1 leagues
//   node scripts/capture-fastcast.mjs --probe --priority v2    # widen the probe
//   node scripts/capture-fastcast.mjs --probe --topic event-basketball-wnba gp-baseball-mlb-401696639
//   node scripts/capture-fastcast.mjs --capture event-baseball-mlb --duration 120
//       # subscribe, download the checkpoint, record decoded patch frames for
//       # N seconds → mock/fixtures/fastcast/<topic>.json (committed)
//
// Protocol recap (all verified live 2026-07-08):
//   GET websockethost → {ip, securePort, token}; token is short-lived.
//   wss://{ip}:{securePort}/FastcastService/pubsub/profiles/12000?TrafficManager-Token={token}
//     (token raw/unencoded; needs Origin: https://www.espn.com + browser UA).
//   {"op":"C"} → {"rc":200,"sid":...}; {"op":"S","sid","tc":topic} per topic.
//   Per topic: op "H" carries the checkpoint URL; op "P"/"R" carry deltas whose
//   pl is a JSON string {ts,"~c",pl} — "~c":1 → base64 + zlib-deflate, then an
//   RFC 6902 patch array. Server pings; we answer pongs.

import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import registry from '../../schema/league-profiles.json' with { type: 'json' };
import { leagueKeys, resolve } from '../../schema/tools/resolve.mjs';
import { FastcastSocket, decodeDelta, eventTopicFor, getJson } from './fastcast-ws.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT_DIR = join(HERE, '..', 'mock', 'fixtures', 'fastcast');

// ---- args -------------------------------------------------------------------
function parseArgs(argv) {
  const a = { probe: false, capture: null, topics: null, priority: 'v1', duration: 90, wait: 12 };
  for (let i = 0; i < argv.length; i++) {
    const t = argv[i];
    if (t === '--probe') a.probe = true;
    else if (t === '--capture') { a.capture = []; while (argv[i + 1] && !argv[i + 1].startsWith('--')) a.capture.push(argv[++i]); }
    else if (t === '--topic') { a.topics = []; while (argv[i + 1] && !argv[i + 1].startsWith('--')) a.topics.push(argv[++i]); }
    else if (t === '--priority') a.priority = argv[++i];
    else if (t === '--duration') a.duration = +argv[++i];
    else if (t === '--wait') a.wait = +argv[++i];
  }
  return a;
}

// ---- ws client + decode: shared with monitor-fastcast.mjs ---------------------
// (FastcastSocket / decodeDelta / getJson / eventTopicFor live in fastcast-ws.mjs)

// ---- probe --------------------------------------------------------------------
async function probe(topics, waitSec) {
  const fc = await new FastcastSocket().connect();
  console.log(`connected, sid=${fc.sid}; probing ${topics.length} topics (${waitSec}s window)`);
  // An op:"S" ack means only "subscription accepted" — the server acks unknown
  // topics too. A topic EXISTS only when an op:"H" checkpoint frame arrives.
  const acks = new Map(); // topic → rc of the S ack
  const seen = new Map(); // topic → {op, mid, pl} of the first H/P/R frame
  fc.on('message', (msg) => {
    const tc = msg.tc;
    if (!tc) { console.log('  (no tc)', JSON.stringify(msg).slice(0, 160)); return; }
    if (msg.op === 'S') { acks.set(tc, msg.rc ?? null); return; }
    if (seen.has(tc)) return;
    seen.set(tc, { op: msg.op, mid: msg.mid ?? null, pl: msg.op === 'H' ? String(msg.pl).slice(0, 140) : undefined });
    console.log(`  HIT ${tc} op=${msg.op} mid=${msg.mid ?? '-'}`);
  });
  for (const t of topics) { fc.subscribe(t); await new Promise((r) => setTimeout(r, 150)); }
  await new Promise((r) => setTimeout(r, waitSec * 1000));
  fc.close();
  console.log('\n== probe results ==');
  for (const t of topics) {
    const hit = seen.get(t);
    const ack = acks.has(t) ? `ack rc=${acks.get(t)}` : 'NO ACK';
    console.log(`${hit ? 'EXISTS ' : 'silent '} ${t}  [${ack}]${hit?.pl ? `  checkpoint: ${hit.pl}` : ''}`);
  }
  return seen;
}

// ---- capture ------------------------------------------------------------------
async function capture(topic, durationSec) {
  const fc = await new FastcastSocket().connect();
  console.log(`connected, sid=${fc.sid}; capturing ${topic} for ${durationSec}s`);
  const rec = { topic, capturedAt: new Date().toISOString(), checkpointUrl: null, checkpoint: null, frames: [] };
  let done;
  const finished = new Promise((r) => { done = r; });

  fc.on('message', async (msg) => {
    if (msg.tc && msg.tc !== topic) return;
    if (msg.op === 'H') {
      rec.checkpointUrl = msg.pl;
      rec.frames.push({ mid: msg.mid ?? null, op: 'H' });
      console.log(`  H mid=${msg.mid} checkpoint=${msg.pl}`);
      try {
        rec.checkpoint = await getJson(msg.pl);
        console.log(`  checkpoint fetched (${JSON.stringify(rec.checkpoint).length} bytes)`);
      } catch (e) { console.error(`  checkpoint fetch FAILED: ${e.message}`); }
    } else if (msg.op === 'P' || msg.op === 'R') {
      try {
        const { ts, ops } = decodeDelta(msg);
        rec.frames.push({ mid: msg.mid ?? null, op: msg.op, ts, ops });
        console.log(`  ${msg.op} mid=${msg.mid} ops=${Array.isArray(ops) ? ops.length : '?'}`);
      } catch (e) {
        rec.frames.push({ mid: msg.mid ?? null, op: msg.op, decodeError: e.message, raw: msg.pl });
        console.error(`  ${msg.op} mid=${msg.mid} DECODE FAILED: ${e.message}`);
      }
    }
  });
  fc.on('close', () => done());
  fc.subscribe(topic);
  setTimeout(() => done(), durationSec * 1000);
  await finished;
  fc.close();

  mkdirSync(OUT_DIR, { recursive: true });
  const file = join(OUT_DIR, topic.replace(/[^a-zA-Z0-9._-]/g, '_') + '.json');
  writeFileSync(file, JSON.stringify(rec, null, 1));
  console.log(`wrote ${file} (checkpoint ${rec.checkpoint ? 'ok' : 'MISSING'}, ${rec.frames.length} frames)`);
  return rec;
}

// ---- main ---------------------------------------------------------------------
const a = parseArgs(process.argv.slice(2));
if (a.probe) {
  let topics = a.topics;
  if (!topics) {
    topics = ['event-topevents'];
    for (const key of leagueKeys(registry)) {
      const p = resolve(registry, key);
      if (a.priority && p.priority !== a.priority) continue;
      topics.push(eventTopicFor(key));
    }
  }
  await probe(topics, a.wait);
} else if (a.capture?.length) {
  for (const t of a.capture) await capture(t, a.duration);
} else {
  console.log('usage: --probe [--priority v1|v2] [--topic t1 t2 ...] [--wait s] | --capture <topic...> [--duration s]');
  process.exit(1);
}

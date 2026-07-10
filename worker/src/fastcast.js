// fastcast.js — pure functions for ESPN's FastCast push layer (fastcast-plan.md).
// No I/O. Three exports, each with a faithful Dart port in
// app/lib/src/data/fastcast.dart (byte-for-byte parity via
// app/test/port_fastcast_test.dart against goldens from gen-goldens.mjs):
//
//   applyOps(doc, ops)       — standard RFC 6902 JSON Patch (gp-* topics).
//   applyEventOps(doc, ops)  — the event-* variant: paths are uid-prefixed
//                              ("s:1~l:10~e:401816076~c:401816076/situation/balls"),
//                              resolved to the event inside the doc, remainder
//                              applied as a standard pointer within it.
//   normalizeFastcastSlate(reg, key, doc) — event-* doc → per-event PARTIAL
//                              updates (score/phase/clock/detail/situation/
//                              seriesSummary), merged over the last polled
//                              canonical slate by the provider (Track 2). It is
//                              an overlay, NOT a scoreboard replacement — the
//                              event doc has no competitions[]/linescores/
//                              leaders, and (verified) no soccer goal timeline.
//
// Resilience rule (protocol): NEVER throw on a bad patch — apply what resolves,
// report what didn't. Both appliers return {doc, errors}; a non-empty errors
// array is the caller's signal to resync (refetch checkpoint / one poll).
// Both appliers deep-copy the input doc; the input is never mutated.

import { statusToPhase, buildScore, buildSituation } from './normalize.js';
import { resolve } from '../../schema/tools/resolve.mjs';

// JSON-safe deep copy (fixture/patch data is always JSON; keep the copy rule
// trivially portable to Dart — no structuredClone).
function deepCopy(v) {
  if (Array.isArray(v)) return v.map(deepCopy);
  if (v && typeof v === 'object') { const o = {}; for (const k of Object.keys(v)) o[k] = deepCopy(v[k]); return o; }
  return v;
}

// RFC 6901 pointer segment unescape (~1 → /, ~0 → ~; order matters).
const unescapeSeg = (s) => s.replace(/~1/g, '/').replace(/~0/g, '~');

// Split a root-relative pointer ("/a/b") into unescaped segments.
function segsOf(path) {
  if (path === '') return [];
  return path.split('/').slice(1).map(unescapeSeg);
}

// Walk to the PARENT of the pointer target. Returns {parent, key} or a string error.
function walk(root, segs) {
  let node = root;
  for (let i = 0; i < segs.length - 1; i++) {
    const seg = segs[i];
    if (Array.isArray(node)) {
      const idx = /^\d+$/.test(seg) ? +seg : -1;
      if (idx < 0 || idx >= node.length) return `no such index '${seg}'`;
      node = node[idx];
    } else if (node && typeof node === 'object') {
      if (!(seg in node)) return `no such key '${seg}'`;
      node = node[seg];
    } else return `not a container at '${seg}'`;
  }
  return { parent: node, key: segs[segs.length - 1] };
}

// Read the value at segs (for move/copy/test). Returns {value} or a string error.
function readAt(root, segs) {
  if (segs.length === 0) return { value: root };
  const w = walk(root, segs);
  if (typeof w === 'string') return w;
  const { parent, key } = w;
  if (Array.isArray(parent)) {
    const idx = /^\d+$/.test(key) ? +key : -1;
    if (idx < 0 || idx >= parent.length) return `no such index '${key}'`;
    return { value: parent[idx] };
  }
  if (parent && typeof parent === 'object') {
    if (!(key in parent)) return `no such key '${key}'`;
    return { value: parent[key] };
  }
  return `not a container at '${key}'`;
}

function deepEqual(a, b) {
  if (a === b) return true;
  if (Array.isArray(a) && Array.isArray(b)) return a.length === b.length && a.every((x, i) => deepEqual(x, b[i]));
  if (a && b && typeof a === 'object' && typeof b === 'object' && !Array.isArray(a) && !Array.isArray(b)) {
    const ka = Object.keys(a), kb = Object.keys(b);
    return ka.length === kb.length && ka.every((k) => deepEqual(a[k], b[k]));
  }
  return false;
}

// Apply ONE parsed op at segs within root. Returns null (ok) or a string error.
// `replace` is deliberately lenient (acts as set): FastCast replaces paths it
// never added, and strict-RFC existence checks would spray resyncs for nothing.
function applyAt(root, op, segs, value) {
  if (segs.length === 0) return 'root op unsupported'; // never observed; docs are replaced via checkpoint
  const w = walk(root, segs);
  if (typeof w === 'string') return w;
  const { parent, key } = w;
  if (Array.isArray(parent)) {
    if (op === 'add' && key === '-') { parent.push(value); return null; }
    const idx = /^\d+$/.test(key) ? +key : -1;
    if (idx < 0) return `bad array index '${key}'`;
    if (op === 'add') {
      if (idx > parent.length) return `index '${key}' out of range`;
      parent.splice(idx, 0, value); return null;
    }
    if (idx >= parent.length) return `no such index '${key}'`;
    if (op === 'remove') { parent.splice(idx, 1); return null; }
    if (op === 'replace') { parent[idx] = value; return null; }
    if (op === 'test') return deepEqual(parent[idx], value) ? null : 'test failed';
    return `unsupported op '${op}'`;
  }
  if (parent && typeof parent === 'object') {
    if (op === 'add' || op === 'replace') { parent[key] = value; return null; }
    if (op === 'remove') {
      if (!(key in parent)) return `no such key '${key}'`;
      delete parent[key]; return null;
    }
    if (op === 'test') return deepEqual(parent[key], value) ? null : 'test failed';
    return `unsupported op '${op}'`;
  }
  return `not a container at '${key}'`;
}

// Shared driver: `locate(path)` maps an op's path to {root, segs} (or a string
// error) — that's the only difference between the standard and event variants.
function applyWith(doc, ops, locate) {
  const out = deepCopy(doc);
  const errors = [];
  const list = Array.isArray(ops) ? ops : [];
  for (let i = 0; i < list.length; i++) {
    const o = list[i] || {};
    const op = o.op;
    const fail = (why) => errors.push(`${i}:${op} ${o.path}: ${why}`);
    if (typeof o.path !== 'string') { fail('no path'); continue; }
    const loc = locate(out, o.path);
    if (typeof loc === 'string') { fail(loc); continue; }
    if (op === 'add' || op === 'replace' || op === 'test') {
      const err = applyAt(loc.root, op, loc.segs, deepCopy(o.value));
      if (err) fail(err);
    } else if (op === 'remove') {
      const err = applyAt(loc.root, 'remove', loc.segs);
      if (err) fail(err);
    } else if (op === 'move' || op === 'copy') {
      if (typeof o.from !== 'string') { fail('no from'); continue; }
      const fromLoc = locate(out, o.from);
      if (typeof fromLoc === 'string') { fail(fromLoc); continue; }
      const r = readAt(fromLoc.root, fromLoc.segs);
      if (typeof r === 'string') { fail(r); continue; }
      const val = deepCopy(r.value);
      if (op === 'move') {
        const err = applyAt(fromLoc.root, 'remove', fromLoc.segs);
        if (err) { fail(err); continue; }
      }
      const err = applyAt(loc.root, 'add', loc.segs, val);
      if (err) fail(err);
    } else fail(`unsupported op '${op}'`);
  }
  return { doc: out, errors };
}

/** Standard RFC 6902 patch (gp-* topics use root-relative paths). */
export function applyOps(doc, ops) {
  return applyWith(doc, ops, (root, path) =>
    path === '' || path.startsWith('/') ? { root, segs: segsOf(path) } : `non-rooted path '${path}'`);
}

// Find an event by uid across doc.sports[].leagues[].events[].
function findEventByUid(doc, uid) {
  for (const sport of doc?.sports || []) {
    for (const lg of sport?.leagues || []) {
      for (const ev of lg?.events || []) if (ev?.uid === uid) return ev;
    }
  }
  return null;
}

/**
 * event-* topic patch: paths are "<uid>/<pointer...>" where <uid> is the raw
 * event uid (contains '~' and ':' — literal, NOT RFC 6901-escaped; split on '/'
 * BEFORE unescaping). A root-relative path ('/x' or '') applies standardly.
 */
export function applyEventOps(doc, ops) {
  return applyWith(doc, ops, (root, path) => {
    if (path === '' || path.startsWith('/')) return { root, segs: segsOf(path) };
    const slash = path.indexOf('/');
    const uid = slash === -1 ? path : path.slice(0, slash);
    const rest = slash === -1 ? '' : path.slice(slash);
    const ev = findEventByUid(root, uid);
    if (!ev) return `no event with uid '${uid}'`;
    if (rest === '') return `bare uid path`; // replacing a whole event needs a pointer
    return { root: ev, segs: segsOf(rest) };
  });
}

// ---- Track 2 normalizer -------------------------------------------------------
// The event-* doc, flattened per event (no competitions[]): status is a bare
// STRING ('in'), the real status object is `fullStatus` — so the house rule
// (branch on status.type.name, never state alone) reads fullStatus.type.
// Emits the canonical-aligned PARTIAL fields the overlay merge writes onto the
// polled competition; field names/derivations mirror buildCompetition exactly.
export function normalizeFastcastSlate(reg, key, doc) {
  const profile = resolve(reg, key);
  const wantId = profile.espnLeagueId != null ? String(profile.espnLeagueId) : null;
  const slug = key.split('/')[1];
  let league = null;
  for (const sport of doc?.sports || []) {
    for (const lg of sport?.leagues || []) {
      if (String(lg?.id ?? '') === wantId || lg?.slug === slug) { league = lg; break; }
    }
    if (league) break;
  }
  const events = [];
  for (const ev of league?.events || []) {
    const st = ev.fullStatus || {};
    const type = st.type || {};
    const ph = statusToPhase(type);
    const e = {
      id: String(ev.id ?? ''),
      status: {
        phase: ph.phase, live: ph.live, ended: ph.ended,
        period: typeof st.period === 'number' ? st.period : 0,
        periodLabel: type.shortDetail || type.detail || type.description || '',
        espnName: type.name || '', detail: type.detail || '',
      },
      competitors: (ev.competitors || []).map((c) => {
        const out = { id: String(c.id ?? '') };
        if (c.homeAway) out.homeAway = c.homeAway;
        if (c.score != null) out.score = buildScore(profile.scoreKind, c.score);
        if (typeof c.winner === 'boolean') out.winner = c.winner;
        return out;
      }),
    };
    if (ev.uid) e.uid = ev.uid;
    if (type.shortDetail) e.status.shortDetail = type.shortDetail;
    if (ph.live && st.displayClock && st.displayClock !== '0:00') e.status.clock = st.displayClock;
    // situation is scoreboard-shaped on the fastcast event (outsText rides the
    // event, not the situation) — reuse the scoreboard builder verbatim.
    const situation = buildSituation({ situation: ev.situation, outsText: ev.outsText });
    if (situation) e.situation = situation;
    if (ev.seriesSummary) e.seriesSummary = ev.seriesSummary;
    events.push(e);
  }
  return { key, events };
}

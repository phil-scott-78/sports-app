// Deterministic unit tests (no network) for the FastCast pure layer
// (src/fastcast.js): RFC 6902 application, the uid-prefixed event variant, and
// the Track-2 slate normalizer — synthetic shapes for op coverage plus the
// committed live captures (mock/fixtures/fastcast/) replayed end to end.
// Run: node test/fastcast.test.mjs

import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import registry from '../../schema/league-profiles.json' with { type: 'json' };
import { applyOps, applyEventOps, normalizeFastcastSlate } from '../src/fastcast.js';

let pass = 0, fail = 0;
const fails = [];
const ok = (cond, msg) => { if (cond) pass++; else { fail++; fails.push(msg); } };
const eq = (a, b, msg) => ok(JSON.stringify(a) === JSON.stringify(b), `${msg} (got ${JSON.stringify(a)})`);

// ---- applyOps: RFC 6902 coverage ---------------------------------------------
{
  const doc = { a: { b: 1 }, arr: [1, 2, 3], keep: 'x' };
  const { doc: out, errors } = applyOps(doc, [
    { op: 'replace', path: '/a/b', value: 2 },
    { op: 'add', path: '/a/c', value: 'new' },
    { op: 'add', path: '/arr/1', value: 9 },       // insert
    { op: 'add', path: '/arr/-', value: 4 },        // append
    { op: 'remove', path: '/arr/0' },
    { op: 'test', path: '/keep', value: 'x' },
    { op: 'copy', from: '/a/c', path: '/copied' },
    { op: 'move', from: '/a/b', path: '/moved' },
  ]);
  eq(errors, [], 'clean patch has no errors');
  eq(out.a, { c: 'new' }, 'replace+add+move on object');
  eq(out.arr, [9, 2, 3, 4], 'array insert/append/remove');
  eq(out.copied, 'new', 'copy');
  eq(out.moved, 2, 'move');
  eq(doc, { a: { b: 1 }, arr: [1, 2, 3], keep: 'x' }, 'input doc not mutated');
}

// escaped pointer segments (~1 → /, ~0 → ~)
{
  const { doc: out, errors } = applyOps({ 'a/b': 1, 'c~d': 2 }, [
    { op: 'replace', path: '/a~1b', value: 10 },
    { op: 'replace', path: '/c~0d', value: 20 },
  ]);
  eq(errors, [], 'escaped segs apply cleanly');
  eq(out, { 'a/b': 10, 'c~d': 20 }, 'RFC 6901 unescape');
}

// bad paths: recorded, skipped, never thrown; the rest still applies
{
  const { doc: out, errors } = applyOps({ a: 1, arr: [1] }, [
    { op: 'replace', path: '/missing/deep', value: 1 },
    { op: 'remove', path: '/nope' },
    { op: 'add', path: '/arr/9', value: 1 },
    { op: 'test', path: '/a', value: 2 },
    { op: 'frobnicate', path: '/a' },
    { op: 'replace', path: 'relative/no/slash', value: 1 },
    { op: 'replace', path: '/a', value: 99 },
  ]);
  ok(errors.length === 6, `6 errors recorded (got ${errors.length}: ${errors.join(' | ')})`);
  eq(out.a, 99, 'later good op still applied');
  // replace is deliberately lenient (set semantics) on an EXISTING parent
  const lenient = applyOps({ a: {} }, [{ op: 'replace', path: '/a/newkey', value: 1 }]);
  eq(lenient.errors, [], 'replace-as-set on existing parent');
  eq(lenient.doc.a.newkey, 1, 'replace created the key');
}

// ---- applyEventOps: uid-prefixed paths -----------------------------------------
{
  const uid = 's:1~l:10~e:401~c:401';
  const doc = { sports: [{ leagues: [{ events: [
    { uid, id: '401', situation: { balls: 0 }, competitors: [{ id: '5', score: '3' }] },
    { uid: 's:1~l:10~e:402~c:402', id: '402' },
  ] }] }] };
  const { doc: out, errors } = applyEventOps(doc, [
    { op: 'replace', path: `${uid}/situation/balls`, value: 2 },
    { op: 'replace', path: `${uid}/competitors/0/score`, value: '4' },
    { op: 'add', path: `${uid}/situation/outs`, value: 1 },
    { op: 'replace', path: 's:9~l:9~e:9~c:9/x', value: 1 },  // unknown uid
  ]);
  ok(errors.length === 1 && /no event with uid/.test(errors[0]), `unknown uid recorded (${errors.join()})`);
  const ev = out.sports[0].leagues[0].events[0];
  eq(ev.situation, { balls: 2, outs: 1 }, 'uid-prefixed replace+add');
  eq(ev.competitors[0].score, '4', 'nested competitor score');
  ok(doc.sports[0].leagues[0].events[0].situation.balls === 0, 'event-ops input not mutated');
}

// ---- normalizeFastcastSlate: synthetic shapes -----------------------------------
{
  const doc = { sports: [{ leagues: [{ id: '10', slug: 'mlb', events: [{
    id: '401', uid: 's:1~l:10~e:401~c:401', status: 'in', period: 9,
    fullStatus: { period: 9, displayClock: '0:00', type: { id: '2', name: 'STATUS_IN_PROGRESS', state: 'in', completed: false, detail: 'Bot 9th', shortDetail: 'Bot 9th' } },
    situation: { balls: 1, strikes: 2, outs: 2, onFirst: true, onSecond: false, onThird: false },
    outsText: '2 Outs',
    seriesSummary: 'MIN leads series 1-0',
    competitors: [
      { id: '5', homeAway: 'away', score: '5', winner: false },
      { id: '9', homeAway: 'home', score: '2', winner: false },
    ],
  }] }] }] };
  const out = normalizeFastcastSlate(registry, 'baseball/mlb', doc);
  eq(out.key, 'baseball/mlb', 'key passthrough');
  ok(out.events.length === 1, 'one event');
  const e = out.events[0];
  eq(e.status.phase, 'live', 'phase from fullStatus.type');
  eq(e.status.espnName, 'STATUS_IN_PROGRESS', 'espnName');
  ok(e.status.clock === undefined, "displayClock '0:00' suppressed (house rule)");
  eq(e.situation, { balls: 1, strikes: 2, outs: 2, onFirst: true, onSecond: false, onThird: false, outsText: '2 Outs' }, 'situation via scoreboard builder + event-level outsText');
  eq(e.seriesSummary, 'MIN leads series 1-0', 'seriesSummary');
  eq(e.competitors[0].score, { display: '5', value: 5 }, 'numeric score shape');

  // postponed guard: state 'post' but name POSTPONED must NOT read as final
  const pp = JSON.parse(JSON.stringify(doc));
  pp.sports[0].leagues[0].events[0].fullStatus.type = { name: 'STATUS_POSTPONED', state: 'post', completed: false };
  eq(normalizeFastcastSlate(registry, 'baseball/mlb', pp).events[0].status.phase, 'postponed', 'postponed beats state=post');

  // league matched by espnLeagueId, not slug
  const bySlugless = JSON.parse(JSON.stringify(doc));
  delete bySlugless.sports[0].leagues[0].slug;
  ok(normalizeFastcastSlate(registry, 'baseball/mlb', bySlugless).events.length === 1, 'league matched by id');
  // wrong league → empty overlay, never a crash
  eq(normalizeFastcastSlate(registry, 'hockey/nhl', doc).events, [], 'unmatched league → empty events');
}

// ---- live captures: replay every committed fixture end to end -------------------
{
  const FIX = join(dirname(fileURLToPath(import.meta.url)), '..', 'mock', 'fixtures', 'fastcast');
  const files = existsSync(FIX) ? readdirSync(FIX).filter((f) => f.endsWith('.json')) : [];
  ok(files.length >= 5, `fastcast fixtures committed (got ${files.length})`);
  for (const f of files) {
    const fx = JSON.parse(readFileSync(join(FIX, f), 'utf8'));
    const isGp = fx.topic.startsWith('gp-');
    const apply = isGp ? applyOps : applyEventOps;
    let doc = fx.checkpoint;
    let applied = 0, errs = [];
    for (const frame of fx.frames) {
      if (!frame.ops) continue;
      const r = apply(doc, frame.ops);
      doc = r.doc; errs.push(...r.errors); applied++;
    }
    ok(errs.length === 0, `${fx.topic}: ${applied} frames apply cleanly (${errs.slice(0, 3).join(' | ')})`);
    if (!isGp) {
      const m = fx.topic.match(/^event-(.+?)-(.+)$/);
      const key = `${m[1]}/${m[2]}`;
      const slate = normalizeFastcastSlate(registry, key, doc);
      ok(slate.events.length > 0, `${fx.topic}: overlay has events`);
      ok(slate.events.every((e) => ['live', 'final', 'scheduled', 'postponed', 'canceled', 'suspended', 'abandoned'].includes(e.status.phase)),
        `${fx.topic}: every phase known (got ${slate.events.map((e) => e.status.phase).join(',')})`);
      ok(slate.events.every((e) => e.competitors.every((c) => c.score === undefined || typeof c.score.display === 'string')),
        `${fx.topic}: scores canonical`);
    } else {
      // gp checkpoint stores intra-doc $ref values verbatim — confirm they survive
      const atBats = doc.atBats && JSON.stringify(doc.atBats);
      ok(!atBats || atBats.includes('$ref'), `${fx.topic}: $ref values stored verbatim`);
    }
  }
}

console.log('='.repeat(48));
console.log(`${pass} passed · ${fail} failed`);
if (fail) { for (const f of fails) console.log('  FAIL', f); process.exit(1); }

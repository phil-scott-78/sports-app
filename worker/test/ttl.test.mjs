// Unit test for the cache-TTL policy (pure, no network).
// Run: node test/ttl.test.mjs

import { TTL, idleTtl, pastDatedTtl } from '../src/ttl.js';

let pass = 0, fail = 0;
const fails = [];
const ok = (cond, msg) => { if (cond) pass++; else { fail++; fails.push(msg); } };

const NOW = Date.parse('2026-06-14T18:00:00Z'); // fixed reference instant
const min = (m) => NOW + m * 60_000;

// No scheduled game → full idle TTL (5m).
ok(idleTtl(undefined, NOW) === TTL.idle, 'no kickoff → idle');
ok(idleTtl(null, NOW) === TTL.idle, 'null kickoff → idle');

// Kickoff far away (idle window is 5m) → still idle.
ok(idleTtl(min(60), NOW) === TTL.idle, 'kickoff 60m out → idle');
ok(idleTtl(min(5.1), NOW) === TTL.idle, 'kickoff 5.1m out → idle (just past window)');

// Kickoff approaching within one idle window → short TTL.
ok(idleTtl(min(5), NOW) === TTL.soon, 'kickoff 5m out → soon');
ok(idleTtl(min(2), NOW) === TTL.soon, 'kickoff 2m out → soon');
ok(idleTtl(min(0), NOW) === TTL.soon, 'kickoff right now → soon');

// Started but ESPN still says 'pre' (negative dt within the window) → short TTL.
ok(idleTtl(min(-2), NOW) === TTL.soon, 'kicked off 2m ago, still pre → soon');
ok(idleTtl(min(-5), NOW) === TTL.soon, 'kicked off 5m ago, still pre → soon');
ok(idleTtl(min(-6), NOW) === TTL.idle, 'kicked off 6m ago, still pre → idle (abnormal, accept)');

// soon must actually be tighter than idle, or the whole exercise is pointless.
ok(TTL.soon < TTL.idle, 'soon TTL is tighter than idle');
ok(TTL.scoresLive <= TTL.soon, 'live TTL is at least as tight as soon');

// ---- pastDatedTtl: long TTL for immutable past days -------------------------
// NOW = 14:00 EDT on the 15th → ET-today is 20260615.
const D = Date.parse('2026-06-15T18:00:00Z');
ok(pastDatedTtl(undefined, false, D) === null, 'no date param → not a past day');
ok(pastDatedTtl('20260614', false, D) === TTL.pastDay, 'yesterday → pastDay TTL');
ok(pastDatedTtl('20260601', false, D) === TTL.pastDay, 'last week → pastDay TTL');
ok(pastDatedTtl('20260615', false, D) === null, 'today → NOT a past day');
ok(pastDatedTtl('20270101', false, D) === null, 'future date → not a past day');
// range: take the range END (newest day). Fully-past range → pastDay; range
// ending today → not past.
ok(pastDatedTtl('20260601-20260614', false, D) === TTL.pastDay, 'range ending yesterday → pastDay');
ok(pastDatedTtl('20260610-20260615', false, D) === null, 'range ending today → NOT past');
// anyLive guard: a suspended game on a past day keeps the normal cadence.
ok(pastDatedTtl('20260614', true, D) === null, 'past day but anyLive → guard, no long TTL');
// UTC-vs-ET boundary: at 02:00Z on the 15th it is still the 14th in ET.
const D2 = Date.parse('2026-06-15T02:00:00Z');
ok(pastDatedTtl('20260614', false, D2) === null, 'UTC-15th but ET-14th → the 14th is today, not past');
ok(pastDatedTtl('20260613', false, D2) === TTL.pastDay, 'the 13th is still past across the UTC/ET boundary');
// garbage date param → no long TTL (falls through to idle)
ok(pastDatedTtl('nope', false, D) === null, 'non-YYYYMMDD date → null');
ok(TTL.pastDay > TTL.idle, 'pastDay TTL is much longer than idle');

console.log(`\n${'='.repeat(48)}\n${pass} passed · ${fail} failed`);
if (fails.length) { console.log('\nFAILURES:'); for (const f of fails) console.log('  ✗ ' + f); }
process.exit(fail ? 1 : 0);

// Unit test for the cache-TTL policy (pure, no network).
// Run: node test/ttl.test.mjs

import { TTL, idleTtl } from '../src/ttl.js';

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

console.log(`\n${'='.repeat(48)}\n${pass} passed · ${fail} failed`);
if (fails.length) { console.log('\nFAILURES:'); for (const f of fails) console.log('  ✗ ' + f); }
process.exit(fail ? 1 : 0);

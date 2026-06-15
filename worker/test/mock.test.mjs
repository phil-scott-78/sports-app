// Unit test for the offline mock synthesizer (mock/synth.mjs). Pure, no network.
// Asserts the contract the mock backend relies on: a captured pool — whatever
// phase it was captured in — projects to a current final + live + scheduled slate
// that the REAL normalizers accept, and that the result is deterministic (so
// polling never makes a frozen game flicker). Run: node test/mock.test.mjs

import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import registry from '../../schema/league-profiles.json' with { type: 'json' };
import { synthScoreboard, synthSummary, synthTeamScoreboard, synthTeams } from '../mock/synth.mjs';
import { normalizeScoreboard } from '../src/normalize.js';
import { normalizeSummary } from '../src/summary.js';

let pass = 0, fail = 0; const fails = [];
const ok = (cond, msg) => { if (cond) pass++; else { fail++; fails.push(msg); } };

const NOW = Date.parse('2026-06-15T18:00:00Z'); // fixed reference instant
const HERE = dirname(fileURLToPath(import.meta.url));
const FIX_DIR = join(HERE, '..', 'mock', 'fixtures');

const phasesOf = (norm) => {
  const ph = {};
  for (const e of norm.events) for (const c of e.competitions) ph[c.status.phase] = (ph[c.status.phase] || 0) + 1;
  return ph;
};

// ---- inline fixtures (no capture needed) ------------------------------------
const ls9 = () => Array.from({ length: 9 }, (_, i) => ({ value: 0, displayValue: '0', period: i + 1 }));
const mlbFinal = (id, h, a) => ({
  id, date: '2026-06-10T18:00Z', name: 'Away at Home', shortName: 'AWY @ HOM',
  competitions: [{
    id, status: { type: { name: 'STATUS_FINAL', state: 'post', completed: true, detail: 'Final', shortDetail: 'Final' } },
    competitors: [
      { id: '9', homeAway: 'home', order: 0, winner: h > a, team: { id: '9', displayName: 'Twins', abbreviation: 'MIN' }, score: String(h), linescores: ls9() },
      { id: '24', homeAway: 'away', order: 1, winner: a > h, team: { id: '24', displayName: 'Cardinals', abbreviation: 'STL' }, score: String(a), linescores: ls9() },
    ],
  }],
});
const mlbFixture = { key: 'baseball/mlb', league: { id: '10', name: 'MLB', slug: 'mlb' }, events: [mlbFinal('1', 5, 3), mlbFinal('2', 2, 7), mlbFinal('3', 1, 0), mlbFinal('4', 8, 6)], teams: null, standings: null, summaries: {} };

// ---- 1. today slate has all three phases + anyLive --------------------------
{
  const norm = normalizeScoreboard(registry, 'baseball/mlb', synthScoreboard(registry, 'baseball/mlb', mlbFixture, { now: NOW }));
  const ph = phasesOf(norm);
  ok(ph.final > 0, 'today: has final games');
  ok(ph.live > 0, 'today: has live games');
  ok(ph.scheduled > 0, 'today: has scheduled games');
  ok(norm.anyLive === true, 'today: anyLive true');
  ok(norm.day === '2026-06-15', `today: day stamped (${norm.day})`);
}

// ---- 2. deterministic on id (no flicker between polls) ----------------------
{
  const a = synthScoreboard(registry, 'baseball/mlb', mlbFixture, { now: NOW });
  const b = synthScoreboard(registry, 'baseball/mlb', mlbFixture, { now: NOW });
  ok(JSON.stringify(a) === JSON.stringify(b), 'same (fixture, now) → identical output');
}

// ---- 3. dates land in the right window ---------------------------------------
{
  const sb = synthScoreboard(registry, 'baseball/mlb', mlbFixture, { now: NOW });
  for (const ev of sb.events) {
    const ms = Date.parse(ev.date); const ph = ev.competitions[0].status.type.state;
    if (ph === 'in') ok(ms <= NOW && ms > NOW - 6 * 3600000, 'live game started recently (past, <6h)');
    if (ph === 'pre') ok(ms > NOW, 'scheduled game is in the future');
    if (ph === 'post') ok(ms < NOW, 'final game is in the past');
  }
}

// ---- 4. a past day → finals; a future day → scheduled -----------------------
{
  const past = normalizeScoreboard(registry, 'baseball/mlb', synthScoreboard(registry, 'baseball/mlb', mlbFixture, { now: NOW, date: '20260601' }));
  const fut = normalizeScoreboard(registry, 'baseball/mlb', synthScoreboard(registry, 'baseball/mlb', mlbFixture, { now: NOW, date: '20270101' }));
  ok(Object.keys(phasesOf(past)).every((p) => p === 'final'), 'past day → only finals');
  ok(Object.keys(phasesOf(fut)).every((p) => p === 'scheduled'), 'future day → only scheduled');
}

// ---- 5. authentic finals are preserved (scores not recomputed) --------------
{
  const sb = synthScoreboard(registry, 'baseball/mlb', mlbFixture, { now: NOW });
  const finals = sb.events.filter((e) => e.competitions[0].status.type.state === 'post');
  // every final's scoreline must be one of the captured pairs (5-3, 2-7, 1-0, 8-6)
  const pairs = new Set(['5,3', '2,7', '1,0', '8,6']);
  ok(finals.every((e) => pairs.has(e.competitions[0].competitors.map((c) => c.score).join(','))), 'captured final scores preserved verbatim');
}

// ---- 6. fabrication: empty pool + a teams list → a full slate ----------------
{
  const teams = { sports: [{ leagues: [{ teams: Array.from({ length: 8 }, (_, i) => ({ team: { id: String(i + 1), displayName: `Team ${i + 1}`, abbreviation: `T${i + 1}` } })) }] }] };
  const fx = { key: 'baseball/mlb', league: { id: '10', name: 'MLB', slug: 'mlb' }, events: [], teams, standings: null, summaries: {} };
  const norm = normalizeScoreboard(registry, 'baseball/mlb', synthScoreboard(registry, 'baseball/mlb', fx, { now: NOW }));
  const ph = phasesOf(norm);
  ok(ph.live > 0 && ph.final > 0 && ph.scheduled > 0, 'fabricated-from-teams slate has all three phases');
  ok(synthTeams(fx).sports[0].leagues[0].teams.length === 8, 'synthTeams passes the picker list through');
}

// ---- 7. team card slate gives the team a last + next -------------------------
{
  const sb = synthTeamScoreboard(registry, 'baseball/mlb', mlbFixture, '9', { now: NOW });
  const states = sb.events.map((e) => e.competitions[0].status.type.state);
  ok(sb.events.length >= 2, 'team slate has multiple games');
  ok(states.includes('post') && states.includes('pre'), 'team slate has a final (last) + a scheduled (next)');
  ok(sb.events.every((e) => e.competitions[0].competitors.some((c) => String(c.id) === '9')), 'every team-slate game features the team');
}

// ---- 8. minimal summary for an uncaptured event is valid --------------------
{
  const s = normalizeSummary(registry, 'baseball/mlb', synthSummary(mlbFixture, 'nope-123'));
  ok(s.eventId === 'nope-123', 'minimal summary carries the event id');
  ok(Array.isArray(s.boxGroups) && s.boxGroups.length === 0, 'minimal summary degrades to empty box groups');
}

// ---- 9. sweep captured fixtures (if any): every one normalizes -------------
{
  let files = [];
  try { files = readdirSync(FIX_DIR).filter((f) => f.endsWith('.json') && f !== '_manifest.json'); } catch { /* none */ }
  for (const f of files) {
    let fx; try { fx = JSON.parse(readFileSync(join(FIX_DIR, f), 'utf8')); } catch { continue; }
    if (!fx.key || !registry.leagues[fx.key]) continue;
    let norm;
    try { norm = normalizeScoreboard(registry, fx.key, synthScoreboard(registry, fx.key, fx, { now: NOW })); }
    catch (e) { ok(false, `${fx.key}: synth+normalize threw — ${e.message}`); continue; }
    ok(Array.isArray(norm.events), `${fx.key}: produces events array`);
    if (fx.events?.length) {
      const ph = phasesOf(norm);
      ok((ph.live || 0) > 0, `${fx.key}: today slate has a live game`);
      ok((ph.final || 0) > 0 && (ph.scheduled || 0) > 0, `${fx.key}: today slate has final + scheduled`);
    }
  }
}

console.log(`\n${'='.repeat(48)}\n${pass} passed · ${fail} failed`);
if (fails.length) { console.log('\nFAILURES:'); for (const f of fails) console.log('  ✗ ' + f); }
process.exit(fail ? 1 : 0);

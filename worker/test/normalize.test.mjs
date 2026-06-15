// Live smoke test for the normalizer. Fetches real ESPN scoreboards and asserts
// canonical invariants across sport families. Run: node test/normalize.test.mjs
// (no wrangler/build needed — the normalizer is pure.)

import registry from '../../schema/league-profiles.json' with { type: 'json' };
import { fetchScoreboard } from '../src/espn.js';
import { normalizeScoreboard, statusToPhase, nextScheduledStart } from '../src/normalize.js';

const PHASES = new Set(['scheduled', 'live', 'final', 'postponed', 'suspended', 'canceled', 'abandoned', 'delayed', 'unknown']);

// representative coverage: team sports, field sports, multi-competition, individual
const CASES = [
  { key: 'soccer/fifa.world' },                    // live today (WC 2026)
  { key: 'baseball/mlb' },                          // in season
  { key: 'basketball/wnba' },                       // in season
  { key: 'basketball/nba', date: '20250101' },      // captured finals/regular state
  { key: 'football/nfl', date: '20250105' },        // final-state, linescores + OT possible
  { key: 'golf/pga' },                              // layout: field, scoreKind: toPar
  { key: 'racing/f1' },                            // multi-competition event
  { key: 'tennis/atp' },                           // individual / possible doubles
];

let pass = 0, fail = 0;
const fails = [];
const ok = (cond, msg) => { if (cond) pass++; else { fail++; fails.push(msg); } };

function checkResponse(key, r) {
  ok(typeof r.sport === 'string' && r.sport, `${key}: sport set`);
  ok(typeof r.leagueId === 'string' && r.leagueId, `${key}: leagueId is non-empty string (got ${JSON.stringify(r.leagueId)})`);
  ok(typeof r.anyLive === 'boolean', `${key}: anyLive boolean`);
  ok(!Number.isNaN(Date.parse(r.updated)), `${key}: updated is ISO date`);
  ok(Array.isArray(r.events), `${key}: events is array`);

  // leagueId should match the registry's verified id (when we declared one)
  const declared = registry.leagues[key]?.espnLeagueId;
  if (declared) ok(String(declared) === r.leagueId, `${key}: leagueId matches registry (${declared} vs ${r.leagueId})`);

  for (const ev of r.events) {
    for (const c of ev.competitions) {
      ok(PHASES.has(c.status.phase), `${key} ${ev.id}: valid phase (${c.status.phase})`);
      ok(typeof c.periods.unit === 'string', `${key} ${ev.id}: periods.unit set`);
      ok(['headToHead', 'field'].includes(c.layout), `${key} ${ev.id}: layout valid`);

      if (c.layout === 'headToHead' && c.competitors.length)
        ok(c.competitors.length === 2, `${key} ${ev.id}: headToHead has 2 competitors (got ${c.competitors.length})`);
      if (c.layout === 'field' && c.competitors.length > 1) {
        const orders = c.competitors.map(x => x.order ?? Infinity);
        ok(orders.every((o, i) => i === 0 || orders[i - 1] <= o), `${key} ${ev.id}: field sorted by order`);
      }

      // numeric scoreKind: a final/live game with a score string parses to a number
      if (c.scoreKind === 'numeric' && (c.status.phase === 'final' || c.status.live)) {
        for (const comp of c.competitors)
          if (comp.score?.display && /^-?\d+$/.test(comp.score.display))
            ok(typeof comp.score.value === 'number', `${key} ${ev.id}: numeric score parsed (${comp.displayName})`);
      }
      // OT detection is period-driven, not string-driven
      if (c.periods.isOvertime) ok(c.periods.played > c.periods.regulation, `${key} ${ev.id}: isOvertime ⇒ played>regulation`);

      // structured playoff series (when present): well-formed competitors with win counts
      if (c.meta?.series) {
        const s = c.meta.series;
        ok(Array.isArray(s.competitors) && s.competitors.length >= 2
          && s.competitors.every(x => x.id && Number.isFinite(x.wins)), `${key} ${ev.id}: series competitors well-formed`);
      }
      // cheap scoring timeline (when present): valid event types, team is home/away/absent
      if (Array.isArray(c.events)) {
        ok(c.events.every(e => SCORING_EVENT_TYPES.has(e.type)), `${key} ${ev.id}: scoring events typed`);
        ok(c.events.every(e => e.team == null || e.team === 'home' || e.team === 'away'), `${key} ${ev.id}: scoring event side valid`);
      }
    }
  }
}

const SCORING_EVENT_TYPES = new Set([
  'goal', 'own-goal', 'penalty-goal', 'penalty-missed', 'yellow-card', 'red-card', 'substitution',
  'touchdown', 'field-goal', 'extra-point', 'two-point', 'safety', 'hockey-goal', 'shootout-goal', 'score', 'other',
]);

function sampleLine(r) {
  const ev = r.events.find(e => e.competitions[0]?.status.live) || r.events.find(e => e.competitions.length) || r.events[0];
  if (!ev) return '  (no events — off-season window)';
  const c = ev.competitions[0];
  if (!c) return '  (event has no parsed competitions)';
  if (c.layout === 'field') {
    const top = c.competitors[0];
    return `  ${ev.shortName || ev.name} · ${c.status.periodLabel} · leader ${top?.displayName} ${top?.score?.display ?? ''} (${c.competitors.length} in field)`;
  }
  const [a, b] = c.competitors;
  const sc = x => x?.score?.display ?? '–';
  return `  ${a?.abbreviation || a?.displayName} ${sc(a)} – ${sc(b)} ${b?.abbreviation || b?.displayName} · ${c.status.phase}/${c.status.periodLabel}${c.decision ? ` [${c.decision}]` : ''}`;
}

// unit checks (no network)
ok(statusToPhase({ name: 'STATUS_FINAL', state: 'post', completed: true }).phase === 'final', 'unit: STATUS_FINAL→final');
ok(statusToPhase({ name: 'STATUS_FINAL_PEN', state: 'post', completed: true }).phase === 'final', 'unit: STATUS_FINAL_PEN→final');
ok(statusToPhase({ name: 'STATUS_POSTPONED', state: 'post', completed: false }).phase === 'postponed', 'unit: postponed not final');
ok(statusToPhase({ name: 'STATUS_IN_PROGRESS', state: 'in' }).live === true, 'unit: in_progress→live');

// nextScheduledStart: soonest 'scheduled' kickoff; live/final events ignored.
{
  const ev = (start, phase) => ({ start, competitions: [{ status: { phase } }] });
  const t1 = '2026-06-14T18:00:00Z', t2 = '2026-06-14T15:00:00Z', t3 = '2026-06-14T20:00:00Z';
  ok(nextScheduledStart([]) === undefined, 'unit: no events → undefined');
  ok(nextScheduledStart([ev(t1, 'live'), ev(t2, 'final')]) === undefined, 'unit: nothing scheduled → undefined');
  ok(nextScheduledStart([ev(t1, 'scheduled'), ev(t3, 'scheduled')]) === Date.parse(t1), 'unit: picks soonest scheduled');
  // a live/final game earlier than the scheduled one must not win
  ok(nextScheduledStart([ev(t2, 'live'), ev(t1, 'scheduled')]) === Date.parse(t1), 'unit: ignores earlier non-scheduled');
  ok(nextScheduledStart([{ start: 'not-a-date', competitions: [{ status: { phase: 'scheduled' } }] }]) === undefined, 'unit: unparsable date skipped');
}

for (const { key, date } of CASES) {
  try {
    const sb = await fetchScoreboard(key, date);
    const r = normalizeScoreboard(registry, key, sb);
    checkResponse(key, r);
    const live = r.anyLive ? ' LIVE' : '';
    console.log(`\n${key}${date ? ` @${date}` : ''} — ${r.events.length} events${live} (leagueId ${r.leagueId})`);
    console.log(sampleLine(r));
    // multi-competition assertion for F1 (only when events present)
    if (key === 'racing/f1' && r.events.length)
      ok(r.events.some(e => e.competitions.length > 1), 'racing/f1: multi-competition event present');
  } catch (e) {
    fail++; fails.push(`${key}: threw ${e.message}`);
    console.log(`\n${key} — ERROR ${e.message}`);
  }
}

console.log(`\n${'='.repeat(48)}\n${pass} passed · ${fail} failed`);
if (fails.length) { console.log('\nFAILURES:'); for (const f of fails) console.log('  ✗ ' + f); }
process.exit(fail ? 1 : 0);

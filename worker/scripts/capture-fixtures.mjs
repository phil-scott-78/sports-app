// capture-fixtures.mjs — one-time (occasional) capture of REAL raw ESPN payloads
// for the offline mock backend. Run with network; commits a slim per-league
// fixture that the mock server (scripts/mock-server.mjs) replays forever through
// the SAME pure normalizers the production worker uses.
//
//   node scripts/capture-fixtures.mjs                 # every concrete league
//   node scripts/capture-fixtures.mjs --priority v1   # just the v1 leagues
//   node scripts/capture-fixtures.mjs --league baseball/mlb basketball/nba
//   node scripts/capture-fixtures.mjs --no-summaries  # skip the rich /summary tier
//   node scripts/capture-fixtures.mjs --concurrency 6 --max-events 14 --max-summaries 3
//
// What it grabs per league (best-effort; a route that 404s is simply omitted):
//   - a POOL of distinct raw scoreboard events (the default slate + a few recent
//     calendar game-days), prioritising completed games so the box-score tier has
//     real data. The synthesizer rebases their dates + states; see mock/synth.mjs.
//   - the raw /teams list (favorites picker) and raw /standings (both ~season-
//     independent, captured as-is).
//   - up to N raw /summary payloads for the richest events (box score / feed).
// ESPN is undocumented + unofficial — we stay gentle (small concurrency, sleeps).

import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import registry from '../../schema/league-profiles.json' with { type: 'json' };
import { leagueKeys, resolve } from '../../schema/tools/resolve.mjs';
import { statusToPhase } from '../src/normalize.js';
import {
  fetchScoreboard, fetchSummary, fetchStandings, fetchTeams,
} from '../src/espn.js';

const HERE = dirname(fileURLToPath(import.meta.url));
const FIX_DIR = join(HERE, '..', 'mock', 'fixtures');
const DAY = 86400000;

// ---- args -------------------------------------------------------------------
function parseArgs(argv) {
  const a = {
    leagues: null, priority: null, sport: null,
    summaries: true, maxEvents: 14, maxSummaries: 3, concurrency: 4,
  };
  for (let i = 0; i < argv.length; i++) {
    const t = argv[i];
    if (t === '--no-summaries') a.summaries = false;
    else if (t === '--priority') a.priority = argv[++i];
    else if (t === '--sport') a.sport = argv[++i];
    else if (t === '--max-events') a.maxEvents = +argv[++i];
    else if (t === '--max-summaries') a.maxSummaries = +argv[++i];
    else if (t === '--concurrency') a.concurrency = +argv[++i];
    else if (t === '--league') { a.leagues = []; while (argv[i + 1] && !argv[i + 1].startsWith('--')) a.leagues.push(argv[++i]); }
  }
  return a;
}

// ---- helpers ----------------------------------------------------------------
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const fileFor = (key) => join(FIX_DIR, key.replace(/\//g, '__') + '.json');
function ymd(d) {
  const x = d instanceof Date ? d : new Date(d);
  return `${x.getUTCFullYear()}${String(x.getUTCMonth() + 1).padStart(2, '0')}${String(x.getUTCDate()).padStart(2, '0')}`;
}
const phaseOf = (ev) => {
  const t = ev?.competitions?.[0]?.status?.type || ev?.status?.type || {};
  return statusToPhase(t).phase;
};
const pick = (o, keys) => Object.fromEntries(keys.filter((k) => o?.[k] != null).map((k) => [k, o[k]]));

// Recent PAST game-days from the default scoreboard's calendar (so we fetch slates
// that actually had games — blind probing wastes requests + risks rate limits).
// Falls back to day-by-day back-stepping when there's no usable calendar.
function recentPastGameDays(def, n, now) {
  const lg = def?.leagues?.[0] || {};
  const cal = lg.calendar;
  const days = new Set();
  if (Array.isArray(cal) && cal.length) {
    const isDay = lg.calendarType === 'day' || typeof cal[0] === 'string';
    const add = (s) => { const ms = Date.parse(s); if (!Number.isNaN(ms) && ms < now) days.add(ymd(new Date(ms))); };
    if (isDay) for (const s of cal) add(s);
    else for (const e of cal) {
      const kids = Array.isArray(e.entries) && e.entries.length ? e.entries : [e];
      for (const k of kids) if (k?.startDate) add(k.startDate);
    }
  }
  let arr = [...days].sort().reverse().slice(0, n);
  if (!arr.length) for (let i = 1; i <= n; i++) arr.push(ymd(new Date(now - i * DAY)));
  return arr;
}

// Trim a /teams payload to only what normalizeTeams reads — the rest is bulky noise
// (logos arrays especially balloon a 360-team college list to ~1 MB).
function trimTeams(raw) {
  const teams = raw?.sports?.[0]?.leagues?.[0]?.teams;
  if (!Array.isArray(teams)) return null;
  const slim = teams.map(({ team: t }) => {
    const o = pick(t || {}, ['id', 'displayName', 'name', 'shortDisplayName', 'abbreviation', 'logo', 'color', 'alternateColor']);
    if (Array.isArray(t?.logos)) o.logos = t.logos.slice(0, 2).map((l) => pick(l, ['href', 'rel']));
    return { team: o };
  });
  return { sports: [{ leagues: [{ teams: slim }] }] };
}

// Trim standings to what normalizeStandings reads, capping rows per group (a 360-team
// college table is ~6 MB raw; the app only ever shows a handful of screens of it).
function trimStandings(raw, maxRows = 60) {
  if (!raw || typeof raw !== 'object') return raw;
  const trimEntry = (en) => {
    const team = pick(en.team || {}, ['id', 'displayName', 'name', 'abbreviation']);
    if (Array.isArray(en.team?.logos)) team.logos = en.team.logos.slice(0, 2).map((l) => pick(l, ['href', 'rel']));
    // ESPN repeats the full stat set per split (overall/Home/Road/vs Top 25/…) — the
    // app only reads the overall split (~13 keys), so keep the first 16.
    return { team, stats: (en.stats || []).slice(0, 16).map((s) => pick(s, ['name', 'type', 'displayValue', 'value'])) };
  };
  const walk = (n) => {
    const out = pick(n, ['name', 'abbreviation', 'displayName']);
    if (Array.isArray(n.standings?.entries)) out.standings = { entries: n.standings.entries.slice(0, maxRows).map(trimEntry) };
    if (Array.isArray(n.children)) out.children = n.children.map(walk);
    return out;
  };
  return walk(raw);
}

// Drop the heaviest summary payloads the normalizer never reads: full play-by-play
// (only scoringPlay rows survive — exactly what buildScoringPlays keeps), plus
// win-probability/news/video/odds blocks. Keeps boxscore + scoring feed + lineups.
function trimSummary(raw) {
  if (!raw || typeof raw !== 'object') return raw;
  const header = raw.header && {
    id: raw.header.id,
    competitions: (raw.header.competitions || []).map((c) => ({
      id: c.id, date: c.date, status: c.status,
      competitors: (c.competitors || []).map((x) => {
        const o = pick(x, ['id', 'homeAway', 'order', 'winner', 'score', 'linescores']);
        o.team = pick(x.team || {}, ['id', 'abbreviation', 'displayName']);
        return o;
      }),
    })),
  };
  const out = {};
  if (header) out.header = header;
  if (raw.boxscore) out.boxscore = raw.boxscore;
  if (Array.isArray(raw.plays)) out.plays = raw.plays.filter((p) => p.scoringPlay === true);
  if (Array.isArray(raw.scoringPlays)) out.scoringPlays = raw.scoringPlays;
  if (Array.isArray(raw.keyEvents)) out.keyEvents = raw.keyEvents;
  if (Array.isArray(raw.rosters)) out.rosters = raw.rosters;
  return out;
}

// Collapse golf's deep per-hole nesting: keep the per-round value/toPar + the hole
// COUNT (drives 'THRU'), drop the 18 per-hole objects + round statistics. A golf
// fixture goes from ~4.8 MB to a few hundred KB.
function slimEvent(ev) {
  const comps = [...(ev.competitions || []), ...((ev.groupings || []).flatMap((g) => g.competitions || []))];
  for (const comp of comps) for (const c of comp.competitors || []) {
    if (!Array.isArray(c.linescores)) continue;
    for (const ls of c.linescores) {
      if (Array.isArray(ls.linescores)) ls.linescores = ls.linescores.map(() => 0); // preserve length (THRU), drop content
      delete ls.statistics;
    }
  }
  return ev;
}

// Does a standings payload actually carry rows? (ESPN returns an empty shell for a
// season that hasn't started — EPL queried with the calendar year is off by one.)
function standingsHasData(raw) {
  let found = false;
  const walk = (n) => { if (found || !n) return; if (Array.isArray(n.standings?.entries) && n.standings.entries.length) { found = true; return; } for (const c of n.children || []) walk(c); };
  walk(raw);
  return found;
}
// First populated standings across candidate seasons (current year, then back —
// soccer/leagues mid-season use the START year). Falls back to the last fetched.
async function firstNonEmptyStandings(key, years) {
  let last = null;
  for (const y of years) {
    try { const raw = await fetchStandings(key, y); last = raw; if (standingsHasData(raw)) return raw; } catch { /* try next */ }
    await sleep(80);
  }
  return last;
}

// League skeleton the scoreboard normalizer + overview classifier read. The synth
// overrides calendar/season to anchor around "now"; we keep originals for reference.
function leagueSkeleton(def) {
  const lg = def?.leagues?.[0] || {};
  return pick(lg, ['id', 'uid', 'name', 'abbreviation', 'shortName', 'slug', 'season', 'calendarType', 'calendar', 'logos']);
}

// ---- per-league capture -----------------------------------------------------
async function captureLeague(key, opts) {
  const profile = resolve(registry, key);
  const now = Date.now();
  const out = {
    key,
    espnSport: profile.espnSport,
    name: profile.name || key,
    capturedAt: new Date(now).toISOString(),
    league: null,        // leagues[0] skeleton
    day: null,
    events: [],          // pool of distinct raw scoreboard events
    teams: null,
    standings: null,
    summaries: {},        // eventId -> raw summary
    stats: {},
  };
  const seen = new Set();
  const addEvents = (sb) => {
    for (const ev of sb?.events || []) {
      const id = String(ev?.id ?? '');
      if (!id || seen.has(id)) continue;
      seen.add(id);
      out.events.push(ev);
    }
  };

  // teams + standings (best-effort). Teams ~season-independent; standings needs the
  // right season year (current, else back a year or two for a just-ended season).
  try { out.teams = trimTeams(await fetchTeams(key)); } catch { /* picker optional */ }
  await sleep(80);
  const yr = new Date(now).getUTCFullYear();
  try { out.standings = trimStandings(await firstNonEmptyStandings(key, [yr, yr - 1, yr - 2])); } catch { /* offseason/none */ }
  await sleep(80);

  // default slate first — carries the live/scheduled games + the calendar
  let def = null;
  try { def = await fetchScoreboard(key); out.league = leagueSkeleton(def); out.day = def.day || null; addEvents(def); } catch { /* try dates below */ }
  await sleep(80);

  // recent past game-days → completed games (real box-score material)
  if (out.events.filter((e) => phaseOf(e) === 'final').length < 8) {
    for (const d of recentPastGameDays(def, 6, now)) {
      if (out.events.length >= opts.maxEvents + 6) break;
      try { const sb = await fetchScoreboard(key, d); if (sb?.events?.length) { if (!out.league) out.league = leagueSkeleton(sb); addEvents(sb); } } catch { /* skip bad date */ }
      await sleep(100);
    }
  }

  // keep a varied, bounded pool: prefer finals (box data) but retain live + scheduled
  const byPhase = { final: [], live: [], scheduled: [], other: [] };
  for (const ev of out.events) (byPhase[phaseOf(ev)] || byPhase.other).push(ev);
  const pool = [
    ...byPhase.final.slice(0, opts.maxEvents),
    ...byPhase.live.slice(0, 4),
    ...byPhase.scheduled.slice(0, 4),
  ];
  // if we somehow over/under-filled, cap to a sane number while keeping variety,
  // and slim each event (golf's per-hole nesting is the big one).
  out.events = pool.slice(0, opts.maxEvents + 8).map(slimEvent);
  out.stats = {
    events: out.events.length,
    final: byPhase.final.length, live: byPhase.live.length, scheduled: byPhase.scheduled.length,
    teams: out.teams?.sports?.[0]?.leagues?.[0]?.teams?.length || 0,
    hasStandings: !!out.standings,
  };

  // rich summaries for the most useful events (finals first → real box scores)
  if (opts.summaries) {
    const wanted = [
      ...byPhase.final.slice(0, opts.maxSummaries),
      ...byPhase.live.slice(0, 1),
      ...byPhase.scheduled.slice(0, 1),
    ].slice(0, opts.maxSummaries + 1);
    for (const ev of wanted) {
      const id = String(ev.id);
      if (out.summaries[id]) continue;
      try { out.summaries[id] = trimSummary(await fetchSummary(key, id)); } catch { /* summary optional */ }
      await sleep(100);
    }
    out.stats.summaries = Object.keys(out.summaries).length;
  }

  mkdirSync(FIX_DIR, { recursive: true });
  writeFileSync(fileFor(key), JSON.stringify(out));
  return out.stats;
}

// ---- pool runner ------------------------------------------------------------
async function runPool(items, n, fn) {
  const results = [];
  let i = 0;
  const workers = Array.from({ length: Math.min(n, items.length) }, async () => {
    while (i < items.length) {
      const idx = i++;
      results[idx] = await fn(items[idx], idx);
    }
  });
  await Promise.all(workers);
  return results;
}

// ---- main -------------------------------------------------------------------
const args = parseArgs(process.argv.slice(2));
const keys = (args.leagues && args.leagues.length)
  ? args.leagues
  : leagueKeys(registry, { priority: args.priority || undefined, sport: args.sport || undefined });

console.log(`Capturing ${keys.length} league(s) → ${FIX_DIR}`);
console.log(`  summaries=${args.summaries} maxEvents=${args.maxEvents} maxSummaries=${args.maxSummaries} concurrency=${args.concurrency}\n`);

const manifest = { capturedAt: new Date().toISOString(), leagues: {} };
await runPool(keys, args.concurrency, async (key) => {
  try {
    const s = await captureLeague(key, args);
    manifest.leagues[key] = s;
    const ok = s.events > 0;
    console.log(`${ok ? '✓' : '·'} ${key.padEnd(38)} events=${s.events} (F${s.final}/L${s.live}/S${s.scheduled}) teams=${s.teams} std=${s.hasStandings ? 'y' : '-'} sum=${s.summaries ?? 0}`);
  } catch (e) {
    manifest.leagues[key] = { error: String(e?.message || e) };
    console.log(`✗ ${key.padEnd(38)} ${String(e?.message || e)}`);
  }
});

writeFileSync(join(FIX_DIR, '_manifest.json'), JSON.stringify(manifest, null, 2));
const ok = Object.values(manifest.leagues).filter((s) => s.events > 0).length;
console.log(`\nDone. ${ok}/${keys.length} leagues have events. Manifest → mock/fixtures/_manifest.json`);

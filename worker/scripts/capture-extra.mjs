// capture-extra.mjs — one-time capture of the RAW ESPN inputs that the committed
// mock fixtures don't carry (team schedule/roster/stats, MMA core event + per-bout
// refs). Needed so the Dart port of team.js / teamdetail.js / summary.js(MMA) can
// be golden-verified against real ESPN shapes. Commits worker/mock/fixtures/
// _extra.json; gen-goldens.mjs reads it (no network at golden-gen time).
//
//   node scripts/capture-extra.mjs
//
// Uses the same espn.js fetchers + the same MMA ref-following the worker route does.

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  fetchTeamSchedule, fetchTeamRoster, fetchTeamStatistics, fetchStandings,
  fetchCoreEvent, fetchCoreRef, fetchScoreboard,
} from '../src/espn.js';
import { athleteIdFromRef } from '../src/teamleaders.js';

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = join(HERE, '..', 'mock', 'fixtures', '_extra.json');

// team pages to capture (key, teamId). NBA = flat roster; a World Cup national
// team = the schedule-fallback path (events:[] → scoreboard backfill).
const TEAM_CASES = [
  { key: 'basketball/nba', teamId: '1' },
  { key: 'soccer/fifa.world', teamId: '624' },
];
const MMA_CASES = [{ key: 'mma/ufc', eventId: '600058854' }];
// Venue facts (§2.9): the CORE venues/{id} resource behind the Venue tab — photo,
// grass→surface, indoor→roof, address. Pinned to STABLE, evergreen venue ids (a
// stadium resource doesn't move) so the golden never drifts, NOT discovered from
// today's slate. Coverage spans the presence gradient: Oracle Park (grass+images+
// address), Coca-Cola Coliseum (indoor, no image), Emirates (no grass/indoor bool
// — the sparse soccer path), and the Spa racing venue (length/turns — the non-F1
// degrade path, no grass/indoor).
const VENUE_CASES = [
  { key: 'baseball/mlb', venueId: '43' },     // Oracle Park — grass, day image, city/state
  { key: 'basketball/wnba', venueId: '7546' },// Coca-Cola Coliseum — indoor, no image
  { key: 'soccer/eng.1', venueId: '2267' },   // Emirates — sparse (no surface/roof bool)
  { key: 'racing/f1', venueId: '257' },        // Spa track venue — length/turns degrade path
];
// racing: the site /summary 404s, so the rich detail (circuit dossier + the
// dark-SVG track MAP) is core-only — event → circuit.$ref → the circuit doc, which
// the cheap scoreboard's {id,fullName,address} circuit block does NOT carry. Spa
// (event 600057439 → circuit 616) is a stable, evergreen snapshot.
const RACING_CASES = [{ key: 'racing/f1', eventId: '600057439' }];
// Championship & award futures (title odds / MVP race) — season-scoped, so a
// stable snapshot: leagues/{}/seasons/{yr}/futures → items[].futures[].books[] =
// per-book {team|athlete:$ref, value:"+350"} American-odds lines. Core-only.
const FUTURES_CASES = [
  { key: 'baseball/mlb', season: '2026' },
  { key: 'basketball/nba', season: '2026' },
  { key: 'football/nfl', season: '2026' },
  { key: 'hockey/nhl', season: '2026' },
];
// Player salary/cap: athletes/{id}/contracts → items are per-season $ref stubs;
// resolving one yields salary + Bird status, trade kicker, cap exceptions, etc.
const CONTRACT_CASES = [{ key: 'basketball/nba', teamId: '1' }];
// Pre-game betting line via the CORE competition-odds list (the per-team moneyline
// the inline scoreboard odds[] lacks — hML/aML, + soccer's draw line). Fetched on
// detail open for a SCHEDULED event when inline odds are absent. The scheduled
// event id is discovered from today's scoreboard (network; recapture is rare and
// picks whatever game is next), so the golden regenerates from a real ESPN shape.
// mlb = US moneyline; eng.1 = soccer draw line; wnba = basketball total.
const ODDS_CASES = [
  { key: 'baseball/mlb' },
  { key: 'soccer/eng.1' },
  { key: 'basketball/wnba' },
];
// Detail-open CORE situation + predictor (the live gridiron down/distance,
// basketball bonus/timeouts, hockey power play, and the win-prob fallback). Both
// are LIVE-only: real ESPN 404s them for a scheduled/final game, so a capture needs
// a game actually in progress at run time. In-season now (2026-07): MLB (baseball
// core situation = balls/strikes/outs) + WNBA (basketball bonus/timeouts). Football/
// NBA/NHL are offseason → captureSituation returns raw:null and gen-goldens emits
// nothing for them (the normalizer stays covered by the guide-shaped unit tests).
const SITUATION_CASES = [
  { key: 'baseball/mlb' },
  { key: 'basketball/wnba' },
  { key: 'football/college-football' },
  { key: 'basketball/nba' },
  { key: 'hockey/nhl' },
];

// Athlete/player profile (§2.6 "Player rows"): identity + season stats + a last-N
// game log — every piece CORE-tier + fanned-out ($ref resolves), exactly what
// api.dart's athleteProfile() assembles at runtime. Two identity paths are covered:
//   • roster-row  (MLB) — the denser single-call identity when arriving from a team
//   • core-athlete (WNBA) — the athletes/{id} doc fallback (+ its team.$ref)
// The player is discovered from the team roster (network; recapture is rare → picks
// whatever the roster's first row is), so the golden regenerates from real shapes.
const ATHLETE_CASES = [
  { key: 'baseball/mlb', teamId: '19', useRosterIdentity: true },   // Dodgers
  { key: 'basketball/wnba', teamId: '3', useRosterIdentity: false },// Wings
];
const ATHLETE_GAME_CAP = 5; // matches api.dart's _athleteGameCap (most-recent N)

// Team SEASON leaders (§2.6 TEAM LEADERS row): the CORE .../types/2/teams/{id}/leaders
// doc + each category's top-leader athlete.$ref resolved, exactly what api.dart's
// teamLeaders() assembles. Season year rides the team schedule; type 2 (regular).
// In-season now (2026-07): MLB + WNBA carry season leaders.
const LEADERS_CASES = [
  { key: 'baseball/mlb', teamId: '19' },    // Dodgers
  { key: 'basketball/wnba', teamId: '3' },  // Wings
];
const LEADERS_CATEGORY_CAP = 6; // matches api.dart's _leaderCategoryCap
// Standings sub-records (§2.8 L10/DIV/CONF): discover season year + each group's
// id/seasonType/standingsId off the SITE standings, then pull the CORE group
// standings-id docs (standings[].records[]). Exactly what api.dart's
// _fetchStandingsRecords() does. MLB + WNBA standings are live now.
const STANDINGS_RECORD_CASES = [
  { key: 'baseball/mlb' },
  { key: 'basketball/wnba' },
];
// Standings qualification bands (§2.7/2.8): the SITE standings entries[].note
// {color, description} — the coloured cut-line + tag. VERIFIED soccer-only (~12%,
// schema/espn-guide/standings.md). The committed per-league soccer fixtures were
// captured without bands (offseason), so pull a fresh doc that serves them: eng.1
// (Champions League / Europa / Relegation), uefa.champions (round-of-16 seeding),
// and fifa.world (Advance / Eliminated — knockouts live now, 2026-07).
const STANDINGS_NOTES_CASES = [
  { key: 'soccer/eng.1' },
  { key: 'soccer/uefa.champions' },
  { key: 'soccer/fifa.world' },
];
// Tournaments (§2.7): RAW date-range scoreboards (+ standings where the profile
// has group tables) → the inputs of the tournament normalizer pair
// (worker/src/tournament.js oracle / app/lib/src/data/tournament.dart). Windows
// are the REAL 2026 calendar (captured 2026-07 — WC knockout + Wimbledon LIVE,
// CWS just finished):
//   • soccer/fifa.world     — Jun 11–Jul 19 range: 72 group games + R32/R16
//     (altGameNote rounds, pens headlines, shootoutScore) + scheduled QFs, plus
//     the 12-group standings with note{color,description}.
//   • tennis/atp Wimbledon  — VERIFIED 2026-07: ONE day-scoped fetch returns the
//     ENTIRE draw (all rounds incl. pre-created future matches); the slam is the
//     events[].major==true event. No range needed.
//   • baseball/college-baseball CWS — Jun 13–24 range: double-elim pool games
//     ('Double Elimination Round'/'Elimination Game' headlines) + the best-of-3
//     championship (series block).
// REAL captures, size-trimmed to the normalizer's read-set (a 39-day WC
// scoreboard is ~1 MB raw) — nothing fabricated. See trimTournamentSb.
const TOURNAMENT_CASES = [
  { key: 'soccer/fifa.world', window: '20260611-20260719', standings: true },
  { key: 'tennis/atp', window: '20260708', grouping: 'mens-singles', pickMajor: true },
  { key: 'baseball/college-baseball', window: '20260613-20260624' },
];

// ---- tournament scoreboard trim (read-set of worker/src/tournament.js) --------
const keepKeys = (o, keys) => {
  if (!o || typeof o !== 'object') return undefined;
  const out = Object.fromEntries(keys.filter((k) => o[k] !== undefined).map((k) => [k, o[k]]));
  return Object.keys(out).length ? out : undefined;
};
const compact = (o) => {
  for (const k of Object.keys(o)) if (o[k] === undefined) delete o[k];
  return o;
};
function trimTournamentSide(c) {
  return compact({
    id: c?.id, homeAway: c?.homeAway, winner: c?.winner, order: c?.order,
    score: c?.score, shootoutScore: c?.shootoutScore,
    curatedRank: keepKeys(c?.curatedRank, ['current']),
    linescores: Array.isArray(c?.linescores)
      ? c.linescores.map((ls) => keepKeys(ls, ['value', 'tiebreak', 'winner']) ?? {})
      : undefined,
    team: keepKeys(c?.team, ['id', 'abbreviation', 'displayName', 'shortDisplayName', 'name']),
    athlete: keepKeys(c?.athlete, ['id', 'displayName', 'shortName']),
    roster: keepKeys(c?.roster, ['displayName', 'shortDisplayName']),
  });
}
function trimTournamentComp(rc) {
  return compact({
    id: rc?.id, date: rc?.date, altGameNote: rc?.altGameNote,
    notes: Array.isArray(rc?.notes) ? rc.notes.map((n) => keepKeys(n, ['headline', 'type']) ?? {}) : undefined,
    round: keepKeys(rc?.round, ['displayName']),
    series: rc?.series ? compact({
      title: rc.series.title, totalCompetitions: rc.series.totalCompetitions,
      completed: rc.series.completed,
      competitors: Array.isArray(rc.series.competitors)
        ? rc.series.competitors.map((x) => keepKeys(x, ['id', 'wins']) ?? {}) : undefined,
    }) : undefined,
    status: rc?.status ? compact({
      type: keepKeys(rc.status.type, ['name', 'state', 'completed', 'detail', 'shortDetail', 'description']),
    }) : undefined,
    competitors: Array.isArray(rc?.competitors) ? rc.competitors.map(trimTournamentSide) : undefined,
  });
}
function trimTournamentSb(sb) {
  if (!sb || typeof sb !== 'object') return sb;
  return compact({
    leagues: Array.isArray(sb.leagues)
      ? sb.leagues.slice(0, 1).map((l) => keepKeys(l, ['id', 'name', 'slug']) ?? {}) : undefined,
    day: sb.day,
    events: (sb.events || []).map((e) => compact({
      id: e?.id, date: e?.date, name: e?.name, shortName: e?.shortName, major: e?.major,
      season: keepKeys(e?.season, ['type', 'slug', 'year']),
      competitions: Array.isArray(e?.competitions) ? e.competitions.map(trimTournamentComp) : undefined,
      groupings: Array.isArray(e?.groupings) ? e.groupings.map((g) => compact({
        grouping: keepKeys(g?.grouping, ['slug', 'displayName']),
        competitions: Array.isArray(g?.competitions) ? g.competitions.map(trimTournamentComp) : undefined,
      })) : undefined,
    })),
  });
}

async function captureTournament({ key, window, grouping, standings, pickMajor }) {
  const sb = await fetchScoreboard(key, window).catch(() => null);
  const out = { key, window };
  if (grouping) out.grouping = grouping;
  if (sb && pickMajor) {
    const major = (sb.events || []).find((e) => e?.major === true && Array.isArray(e.groupings));
    if (major) out.eventId = String(major.id);
  }
  out.scoreboards = sb ? [trimTournamentSb(sb)] : [];
  // group tables ride the SAME trimmed standings shape the standingsNotes capture
  // uses (trimStandingsNode keeps team/stats/note — the normalizer's read-set).
  out.standings = standings ? trimStandingsNode(await fetchStandings(key).catch(() => null)) : null;
  return out;
}

// Flatten a roster (grouped OR flat) to its athlete rows — mirrors teamdetail.js.
function rosterRows(roster) {
  const athletes = roster?.athletes;
  if (!Array.isArray(athletes)) return [];
  const grouped = athletes.some((e) => Array.isArray(e?.items));
  return grouped ? athletes.flatMap((g) => (Array.isArray(g?.items) ? g.items : [])) : athletes;
}

// A resolved eventlog event carries a 70+-field competitions[] the profile
// normalizer never reads (it wants only date/name/shortName). Trim to the metadata
// scalars so the committed fixture stays small — this is a REAL capture, just
// size-trimmed to the fields under test. Nothing fabricated.
function trimEvent(ev) {
  if (!ev || typeof ev !== 'object') return ev;
  const keep = ['$ref', 'id', 'date', 'name', 'shortName', 'season', 'seasonType', 'week'];
  return Object.fromEntries(keep.filter((k) => ev[k] !== undefined).map((k) => [k, ev[k]]));
}

async function captureAthlete({ key, teamId, useRosterIdentity }) {
  const roster = await fetchTeamRoster(key, teamId).catch(() => null);
  const row = rosterRows(roster)[0];
  const aid = row?.id;
  if (!aid) return { key, athleteId: null, teamId, identity: null, team: null, statistics: null, games: [] };
  const base = `https://sports.core.api.espn.com/v2/sports/${corePath(key)}/athletes/${aid}`;
  const coreAthlete = await fetchCoreRef(`${base}?lang=en&region=us`).catch(() => null);
  const identity = useRosterIdentity ? row : (coreAthlete || row);
  // team (name+color+logo): the core athlete's team.$ref, else built from teamId.
  let team = null;
  const teamRef = coreAthlete?.team?.$ref;
  if (teamRef) team = await fetchCoreRef(teamRef).catch(() => null);
  if (!team && teamId) {
    team = await fetchCoreRef(`https://sports.core.api.espn.com/v2/sports/${corePath(key)}/teams/${teamId}?lang=en&region=us`).catch(() => null);
  }
  const statistics = await fetchCoreRef(`${base}/statistics?lang=en&region=us`).catch(() => null);
  // last-N game log: eventlog items (oldest→newest within the page) → take the most
  // recent PLAYED N, resolve each row's event.$ref (trimmed) + statistics.$ref.
  const el = await fetchCoreRef(`${base}/eventlog?lang=en&region=us`).catch(() => null);
  const items = Array.isArray(el?.events?.items) ? el.events.items : [];
  const played = items.filter((e) => e?.played === true);
  const recent = (played.length > ATHLETE_GAME_CAP ? played.slice(-ATHLETE_GAME_CAP) : played).reverse();
  const games = [];
  for (const it of recent) {
    const g = {};
    const evRef = it?.event?.$ref;
    if (evRef) {
      const id = /\/events\/(\d+)/.exec(evRef)?.[1];
      if (id) g.eventId = id;
      const ev = await fetchCoreRef(evRef).catch(() => null);
      if (ev) g.event = trimEvent(ev);
    }
    if (it?.teamId != null) g.teamId = String(it.teamId);
    const stRef = it?.statistics?.$ref;
    if (stRef) { const s = await fetchCoreRef(stRef).catch(() => null); if (s) g.statistics = s; }
    if (g.eventId) games.push(g);
  }
  return { key, athleteId: String(aid), teamId, identity, team, statistics, games };
}

// Trim a resolved athlete doc to the fields the leaders normalizer reads (mirrors
// trimEvent: a REAL capture, size-trimmed to the fields under test — nothing faked).
function trimAthlete(a) {
  if (!a || typeof a !== 'object') return a;
  const out = {};
  for (const k of ['id', 'displayName', 'fullName', 'shortName']) if (a[k] !== undefined) out[k] = a[k];
  if (a.headshot) out.headshot = a.headshot.href ? { href: a.headshot.href } : a.headshot;
  if (a.position && typeof a.position === 'object') {
    out.position = {};
    for (const k of ['abbreviation', 'displayName']) if (a.position[k] !== undefined) out.position[k] = a.position[k];
  }
  return out;
}

async function captureLeaders({ key, teamId }) {
  const sched = await fetchTeamSchedule(key, teamId).catch(() => null);
  const year = sched?.season?.year || sched?.requestedSeason?.year || new Date().getFullYear();
  const url = `https://sports.core.api.espn.com/v2/sports/${corePath(key)}/seasons/${year}/types/2/teams/${teamId}/leaders?lang=en&region=us`;
  const raw = await fetchCoreRef(url).catch(() => null);
  const cats = Array.isArray(raw?.categories) ? raw.categories.slice(0, LEADERS_CATEGORY_CAP) : [];
  // Resolve each UNIQUE top-leader athlete.$ref once (dedupe by id), like api.dart.
  const refs = {};
  for (const c of cats) {
    const ref = c?.leaders?.[0]?.athlete?.$ref;
    const id = athleteIdFromRef(ref);
    if (id && ref && !refs[id]) refs[id] = ref;
  }
  const athletes = {};
  for (const [id, ref] of Object.entries(refs)) {
    const a = await fetchCoreRef(ref).catch(() => null);
    if (a) athletes[id] = trimAthlete(a);
  }
  return { key, teamId, year, raw, athletes };
}

// Trim a CORE group standings-id doc to what extractGroupRecords reads.
function trimRecordDoc(doc) {
  const standings = Array.isArray(doc?.standings) ? doc.standings : [];
  return {
    standings: standings.map((s) => ({
      team: { $ref: s?.team?.$ref },
      records: (Array.isArray(s?.records) ? s.records : []).map((r) => ({ type: r?.type, summary: r?.summary })),
    })),
  };
}

async function captureStandingsRecords({ key }) {
  const raw = await fetchStandings(key).catch(() => null);
  const year = raw?.season?.year;
  const groups = [];
  const seen = new Set();
  const walk = (node) => {
    const s = node?.standings;
    const entries = s?.entries;
    const gid = node?.id;
    if (s && Array.isArray(entries) && entries.length && gid != null && !seen.has(String(gid))) {
      seen.add(String(gid));
      groups.push({ g: String(gid), t: s.seasonType, s: String(s.id ?? '0'), y: s.season ?? year });
    }
    for (const c of node?.children || []) walk(c);
  };
  walk(raw);
  const recordDocs = [];
  for (const g of groups.slice(0, 12)) {
    if (g.y == null || g.t == null) continue;
    const url = `https://sports.core.api.espn.com/v2/sports/${corePath(key)}/seasons/${g.y}/types/${g.t}/groups/${g.g}/standings/${g.s}?lang=en&region=us`;
    const doc = await fetchCoreRef(url).catch(() => null);
    if (doc) recordDocs.push(trimRecordDoc(doc));
  }
  return { key, recordDocs };
}

// Trim a SITE standings doc to what normalizeStandings reads (mirrors trimEvent:
// a REAL capture, size-trimmed to the fields under test — nothing fabricated).
// Keeps the group tree (name/children), each entry's team/athlete identity +
// stats + the qualification note {color, description, rank}.
function trimStandingsEntry(en) {
  const out = {};
  const who = en?.team || en?.athlete;
  if (who && typeof who === 'object') {
    const w = {};
    for (const k of ['id', 'displayName', 'name', 'shortDisplayName', 'abbreviation']) if (who[k] !== undefined) w[k] = who[k];
    if (Array.isArray(who.logos)) w.logos = who.logos.map((l) => ({ href: l?.href, rel: l?.rel }));
    out[en.team ? 'team' : 'athlete'] = w;
  }
  if (Array.isArray(en?.stats)) {
    out.stats = en.stats.map((s) => {
      const o = {};
      for (const k of ['name', 'type', 'displayValue', 'value']) if (s?.[k] !== undefined) o[k] = s[k];
      return o;
    });
  }
  if (en?.note && typeof en.note === 'object') {
    const n = {};
    for (const k of ['color', 'description', 'rank']) if (en.note[k] !== undefined) n[k] = en.note[k];
    out.note = n;
  }
  return out;
}
function trimStandingsNode(node) {
  if (!node || typeof node !== 'object') return node;
  const out = {};
  for (const k of ['name', 'abbreviation', 'displayName', 'id']) if (node[k] !== undefined) out[k] = node[k];
  const entries = node.standings?.entries;
  if (Array.isArray(entries)) out.standings = { entries: entries.map(trimStandingsEntry) };
  if (Array.isArray(node.children)) out.children = node.children.map(trimStandingsNode);
  return out;
}

async function captureStandingsNotes({ key }) {
  const raw = await fetchStandings(key).catch(() => null);
  return { key, standings: raw ? trimStandingsNode(raw) : null };
}

async function captureTeam({ key, teamId }) {
  const [schedule, roster, stats, standingsRaw] = await Promise.all([
    fetchTeamSchedule(key, teamId).catch(() => null),
    fetchTeamRoster(key, teamId).catch(() => null),
    fetchTeamStatistics(key, teamId).catch(() => null),
    fetchStandings(key).catch(() => null),
  ]);
  return { key, teamId, schedule, roster, stats, standingsRaw };
}

// Mirror worker/src/index.js mmaSummary(): core event → per-bout status refs →
// judge linescore refs (decisions only).
async function captureMma({ key, eventId }) {
  const core = await fetchCoreEvent(key, eventId);
  const comps = Array.isArray(core?.competitions) ? core.competitions : [];
  const statuses = {};
  await Promise.all(comps.map(async (c) => {
    const ref = c?.status?.$ref;
    if (!c?.id || !ref) return;
    try { statuses[String(c.id)] = await fetchCoreRef(ref); } catch { /* skip */ }
  }));
  const linescores = {};
  await Promise.all(comps.flatMap((c) => {
    const st = statuses[String(c?.id)];
    if (!/decision/i.test(st?.result?.name || st?.result?.displayName || '')) return [];
    return (c.competitors || []).map(async (comp) => {
      const ref = comp?.linescores?.$ref;
      if (!ref) return;
      try { linescores[`${c.id}/${comp.id}`] = await fetchCoreRef(ref); } catch { /* skip */ }
    });
  }));
  return { key, eventId, coreEvent: core, statuses, linescores };
}

// Mirror the MMA path: core event → circuit.$ref (the circuit dossier + track-map
// diagrams the scoreboard lacks), the lap-record holder athlete behind
// fastestLapDriver.$ref (a nice delighter), and each session's statistics.$ref
// (laps/pole/avgSpeed — .000 until the session runs).
async function captureRacing({ key, eventId }) {
  const core = await fetchCoreEvent(key, eventId);
  const comps = Array.isArray(core?.competitions) ? core.competitions : [];
  let circuit = null;
  let fastestLapDriver = null;
  const circRef = core?.circuit?.$ref;
  if (circRef) {
    try { circuit = await fetchCoreRef(circRef); } catch { /* skip */ }
    const drvRef = circuit?.fastestLapDriver?.$ref;
    if (drvRef) { try { fastestLapDriver = await fetchCoreRef(drvRef); } catch { /* skip */ } }
  }
  const statistics = {};
  await Promise.all(comps.map(async (c) => {
    const ref = c?.statistics?.$ref;
    if (!c?.id || !ref) return;
    try { statistics[String(c.id)] = await fetchCoreRef(ref); } catch { /* skip */ }
  }));
  return { key, eventId, coreEvent: core, circuit, fastestLapDriver, statistics };
}

function corePath(key) { return key.replace('/', '/leagues/'); } // baseball/mlb → baseball/leagues/mlb

// Pull one CORE venues/{id} doc (stable resource → an evergreen fixture). Best-effort.
async function captureVenue({ key, venueId }) {
  const url = `https://sports.core.api.espn.com/v2/sports/${corePath(key)}/venues/${venueId}?lang=en&region=us`;
  const venue = await fetchCoreRef(url).catch(() => null);
  return { key, venueId, venue };
}

// Discover the next SCHEDULED event on today's scoreboard and pull its CORE
// competition-odds list (the lazy detail-open fetch, mirrored). Best-effort.
async function captureOdds({ key }) {
  const sb = await fetchScoreboard(key).catch(() => null);
  const events = Array.isArray(sb?.events) ? sb.events : [];
  let eid = null, cid = null, shortName = null;
  for (const e of events) {
    const c = (e.competitions || [])[0];
    if (c?.status?.type?.name === 'STATUS_SCHEDULED') {
      eid = String(e.id); cid = String(c.id); shortName = e.shortName; break;
    }
  }
  if (!eid) return { key, eventId: null, competitionId: null, shortName: null, raw: null };
  const url = `https://sports.core.api.espn.com/v2/sports/${corePath(key)}/events/${eid}/competitions/${cid}/odds?lang=en&region=us`;
  const raw = await fetchCoreRef(url).catch(() => null);
  return { key, eventId: eid, competitionId: cid, shortName, raw };
}

// Discover a LIVE event on today's scoreboard and pull its CORE situation +
// predictor (both 404 unless the game is in progress). Mirrors the app's
// _enrichLiveDetail: situation.lastPlay.$ref is resolved to its text too. Best-effort.
async function captureSituation({ key }) {
  const sb = await fetchScoreboard(key).catch(() => null);
  const events = Array.isArray(sb?.events) ? sb.events : [];
  let eid = null, cid = null, shortName = null;
  for (const e of events) {
    const c = (e.competitions || [])[0];
    if (c?.status?.type?.state === 'in') { eid = String(e.id); cid = String(c.id); shortName = e.shortName; break; }
  }
  if (!eid) return { key, eventId: null, competitionId: null, shortName: null, situation: null, lastPlayText: null, predictor: null };
  const base = `https://sports.core.api.espn.com/v2/sports/${corePath(key)}/events/${eid}/competitions/${cid}`;
  const situation = await fetchCoreRef(`${base}/situation?lang=en&region=us`).catch(() => null);
  let lastPlayText = null;
  const lpRef = situation?.lastPlay?.$ref;
  if (lpRef) { const play = await fetchCoreRef(lpRef).catch(() => null); lastPlayText = typeof play?.text === 'string' ? play.text : null; }
  const predictor = await fetchCoreRef(`${base}/predictor?lang=en&region=us`).catch(() => null);
  return { key, eventId: eid, competitionId: cid, shortName, situation, lastPlayText, predictor };
}

async function captureFutures({ key, season }) {
  const url = `https://sports.core.api.espn.com/v2/sports/${corePath(key)}/seasons/${season}/futures?lang=en&region=us`;
  let futures = null;
  try { futures = await fetchCoreRef(url); } catch { /* skip */ }
  return { key, season, futures };
}

async function captureContracts({ key, teamId }) {
  const roster = await fetchTeamRoster(key, teamId).catch(() => null);
  const athItem = roster?.athletes?.[0]?.items?.[0] || roster?.athletes?.[0];
  const aid = athItem?.id;
  if (!aid) return { key, teamId, athlete: null, contracts: [] };
  const listUrl = `https://sports.core.api.espn.com/v2/sports/${corePath(key)}/athletes/${aid}/contracts?lang=en&region=us`;
  const list = await fetchCoreRef(listUrl).catch(() => null);
  const contracts = [];
  for (const it of (list?.items || [])) {
    if (it?.$ref) { try { contracts.push(await fetchCoreRef(it.$ref)); } catch { /* skip */ } }
    else contracts.push(it);
  }
  return { key, teamId, athlete: { id: aid, displayName: athItem?.displayName }, contracts };
}

// --only <section...> re-captures just those sections and MERGES onto the existing
// file, so a targeted `--only racing` run doesn't refresh (and risk drifting the
// committed goldens of) team/mma. No arg = full regen of every section.
const onlyIdx = process.argv.indexOf('--only');
const ONLY = onlyIdx >= 0 ? process.argv.slice(onlyIdx + 1).filter((a) => !a.startsWith('--')) : null;
const want = (section) => !ONLY || ONLY.includes(section);

const out = existsSync(OUT) ? JSON.parse(readFileSync(OUT, 'utf8')) : {};
out.capturedAt = new Date().toISOString();
out.teams ||= [];
out.mma ||= [];
out.racing ||= [];
out.venues ||= [];
out.futures ||= [];
out.contracts ||= [];
out.odds ||= [];
out.situation ||= [];
out.athletes ||= [];
out.leaders ||= [];
out.standingsRecords ||= [];
out.standingsNotes ||= [];
out.tournaments ||= [];

if (want('teams')) {
  out.teams = [];
  for (const t of TEAM_CASES) {
    out.teams.push(await captureTeam(t));
    console.log(`✓ team ${t.key}/${t.teamId}`);
  }
}
if (want('mma')) {
  out.mma = [];
  for (const m of MMA_CASES) {
    out.mma.push(await captureMma(m));
    console.log(`✓ mma ${m.key}/${m.eventId} (${out.mma[out.mma.length - 1].coreEvent?.competitions?.length ?? 0} bouts)`);
  }
}
if (want('racing')) {
  out.racing = [];
  for (const r of RACING_CASES) {
    out.racing.push(await captureRacing(r));
    const last = out.racing[out.racing.length - 1];
    console.log(`✓ racing ${r.key}/${r.eventId} — circuit: ${last.circuit?.fullName ?? '(none)'}, `
      + `diagrams: ${last.circuit?.diagrams?.length ?? 0}, sessions: ${last.coreEvent?.competitions?.length ?? 0}`);
  }
}
if (want('venues')) {
  out.venues = [];
  for (const v of VENUE_CASES) {
    out.venues.push(await captureVenue(v));
    const last = out.venues[out.venues.length - 1];
    console.log(`✓ venue ${v.key}/${v.venueId} — ${last.venue?.fullName ?? '(none)'}: `
      + `grass ${last.venue?.grass ?? '—'}, indoor ${last.venue?.indoor ?? '—'}, `
      + `images ${last.venue?.images?.length ?? 0}, length ${last.venue?.length ?? '—'}`);
  }
}
if (want('futures')) {
  out.futures = [];
  for (const f of FUTURES_CASES) {
    out.futures.push(await captureFutures(f));
    console.log(`✓ futures ${f.key} ${f.season} — ${out.futures[out.futures.length - 1].futures?.items?.length ?? 0} markets`);
  }
}
if (want('contracts')) {
  out.contracts = [];
  for (const c of CONTRACT_CASES) {
    out.contracts.push(await captureContracts(c));
    const last = out.contracts[out.contracts.length - 1];
    console.log(`✓ contracts ${c.key} — ${last.athlete?.displayName ?? '?'}: ${last.contracts.length} seasons, `
      + `latest salary ${last.contracts[0]?.salary ?? '?'}`);
  }
}
if (want('odds')) {
  out.odds = [];
  for (const o of ODDS_CASES) {
    out.odds.push(await captureOdds(o));
    const last = out.odds[out.odds.length - 1];
    console.log(`✓ odds ${o.key} — ${last.shortName ?? '(no scheduled game)'}: ${last.raw?.items?.length ?? 0} providers`);
  }
}
if (want('situation')) {
  out.situation = [];
  for (const s of SITUATION_CASES) {
    out.situation.push(await captureSituation(s));
    const last = out.situation[out.situation.length - 1];
    console.log(`✓ situation ${s.key} — ${last.shortName ?? '(no live game)'}: `
      + `situation ${last.situation ? 'ok' : '—'}, predictor ${last.predictor ? 'ok' : '—'}`);
  }
}
if (want('athletes')) {
  out.athletes = [];
  for (const a of ATHLETE_CASES) {
    out.athletes.push(await captureAthlete(a));
    const last = out.athletes[out.athletes.length - 1];
    console.log(`✓ athlete ${a.key}/${last.athleteId ?? '(none)'} — ${last.identity?.displayName ?? '?'}: `
      + `team ${last.team?.displayName ?? '—'}, statCats ${last.statistics?.splits?.categories?.length ?? 0}, `
      + `games ${last.games.length}`);
  }
}
if (want('leaders')) {
  out.leaders = [];
  for (const l of LEADERS_CASES) {
    out.leaders.push(await captureLeaders(l));
    const last = out.leaders[out.leaders.length - 1];
    console.log(`✓ leaders ${l.key}/${l.teamId} — ${last.raw?.categories?.length ?? 0} categories, `
      + `${Object.keys(last.athletes).length} athletes resolved`);
  }
}
if (want('standingsRecords')) {
  out.standingsRecords = [];
  for (const s of STANDINGS_RECORD_CASES) {
    out.standingsRecords.push(await captureStandingsRecords(s));
    const last = out.standingsRecords[out.standingsRecords.length - 1];
    const teams = last.recordDocs.reduce((n, d) => n + (d.standings?.length ?? 0), 0);
    console.log(`✓ standingsRecords ${s.key} — ${last.recordDocs.length} group docs, ${teams} team records`);
  }
}
if (want('standingsNotes')) {
  out.standingsNotes = [];
  for (const s of STANDINGS_NOTES_CASES) {
    out.standingsNotes.push(await captureStandingsNotes(s));
    const last = out.standingsNotes[out.standingsNotes.length - 1];
    let entries = 0, withNote = 0;
    const walk = (n) => { const es = n?.standings?.entries; if (Array.isArray(es)) for (const e of es) { entries++; if (e.note) withNote++; } for (const c of n?.children || []) walk(c); };
    walk(last.standings);
    console.log(`✓ standingsNotes ${s.key} — ${entries} entries, ${withNote} with a band`);
  }
}
if (want('tournaments')) {
  out.tournaments = [];
  for (const t of TOURNAMENT_CASES) {
    out.tournaments.push(await captureTournament(t));
    const last = out.tournaments[out.tournaments.length - 1];
    const evs = last.scoreboards[0]?.events?.length ?? 0;
    let groupsN = 0;
    const walk = (n) => { if (n?.standings?.entries?.length) groupsN++; for (const c of n?.children || []) walk(c); };
    walk(last.standings);
    console.log(`✓ tournament ${t.key} ${t.window} — ${evs} events, `
      + `${groupsN} standings groups${last.eventId ? `, event ${last.eventId}` : ''}`);
  }
}
writeFileSync(OUT, JSON.stringify(out));
console.log(`\nWrote ${OUT}`);

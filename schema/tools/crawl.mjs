// crawl.mjs — evidence pass for the definitive ESPN field guide.
//
// Hits the endpoint families documented at
// https://github.com/pseudo-r/Public-ESPN-API/tree/main/docs with REAL data
// from the past year, across every sport in league-profiles.json, and persists
// the raw responses verbatim. No normalization, no interpretation — this is
// the corpus. rollup.mjs is the second pass that turns the corpus into an
// LLM-consumable field guide (paths, types, presence, enums, per-sport variance).
//
// Usage:
//   node schema/tools/crawl.mjs                     # coverage scope: v1 + 2 leagues per sport
//   node schema/tools/crawl.mjs --priority v1       # just the v1 leagues
//   node schema/tools/crawl.mjs --sport hockey      # one sport
//   node schema/tools/crawl.mjs --league golf/pga mma/ufc
//   node schema/tools/crawl.mjs --all               # every concrete league (heavy; ~230)
//   node schema/tools/crawl.mjs --force             # refetch even if the file exists
//   node schema/tools/crawl.mjs --concurrency 4 --months 12 --max-summaries 4
//   node schema/tools/crawl.mjs --no-graph          # skip the core-API $ref crawl
//   node schema/tools/crawl.mjs --graph-depth 7 --graph-max-nodes 500
//
// The site/web API (scoreboard, summary, standings, teams, roster, …) is flat, so
// it's hit by fixed URL templates. The core API (sports.core.api.espn.com) is
// HATEOAS — every resource links to its children via $ref — so it's DISCOVERED by
// following those links (see crawlGraph), which is the only way to reach data
// whose URL we can't guess (e.g. tennis competition/set-by-set linescores, where
// the competition id differs from the event id).
//
// Output: schema/crawl-data/ (gitignored — it's a multi-hundred-MB corpus)
//   manifest.jsonl                      one line per request (also 404s — a 404
//                                       is evidence too: "this tier doesn't exist
//                                       for this sport")
//   <league key, / → __>/<endpoint>/<name>.json   raw body, exactly as served
//
// Resumable: an existing file is skipped (manifest line re-emitted with
// note:"cached"), so an interrupted crawl continues where it left off.
// ESPN is undocumented + unofficial — stay gentle: small concurrency, sleeps,
// one retry on 429/5xx.

import { readFileSync, writeFileSync, mkdirSync, existsSync, appendFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { leagueKeys, resolve } from './resolve.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const REG = JSON.parse(readFileSync(join(HERE, '..', 'league-profiles.json'), 'utf8'));
const DATA_DIR = join(HERE, '..', 'crawl-data');
const MANIFEST = join(DATA_DIR, 'manifest.jsonl');
const DAY = 86400000;

const SITE = 'https://site.api.espn.com/apis/site/v2/sports';
const SITE_V2 = 'https://site.api.espn.com/apis/v2/sports';        // standings lives here, NOT apis/site/v2
const CORE = 'https://sports.core.api.espn.com/v2/sports';
const WEB = 'https://site.web.api.espn.com/apis/site/v2/sports';
const HEADERS = { 'user-agent': 'Mozilla/5.0 (sports-app schema crawl)' };

// ---- args -------------------------------------------------------------------
function parseArgs(argv) {
  const a = {
    leagues: null, priority: null, sport: null, all: false, force: false,
    months: 12, maxSummaries: 4, concurrency: 4,
    graph: true, graphMaxNodes: 500, graphDepth: 7,
  };
  for (let i = 0; i < argv.length; i++) {
    const t = argv[i];
    if (t === '--all') a.all = true;
    else if (t === '--force') a.force = true;
    else if (t === '--no-graph') a.graph = false;        // skip the core-API $ref crawl
    else if (t === '--graph-max-nodes') a.graphMaxNodes = +argv[++i];
    else if (t === '--graph-depth') a.graphDepth = +argv[++i];
    else if (t === '--priority') a.priority = argv[++i];
    else if (t === '--sport') a.sport = argv[++i];
    else if (t === '--months') a.months = +argv[++i];
    else if (t === '--max-summaries') a.maxSummaries = +argv[++i];
    else if (t === '--concurrency') a.concurrency = +argv[++i];
    else if (t === '--league') { a.leagues = []; while (argv[i + 1] && !argv[i + 1].startsWith('--')) a.leagues.push(argv[++i]); }
  }
  return a;
}

/** Default scope: every v1 league PLUS the first 2 registry leagues of any
 *  sport v1 doesn't reach — full sport coverage without crawling 230 leagues. */
function coverageScope() {
  const v1 = leagueKeys(REG, { priority: 'v1' });
  const covered = new Set(v1.map(k => k.split('/')[0]));
  const extra = [];
  const perSport = {};
  for (const k of leagueKeys(REG, {})) {
    const sport = k.split('/')[0];
    perSport[sport] = perSport[sport] || 0;
    if ((!covered.has(sport) && perSport[sport] < 2)) { extra.push(k); perSport[sport]++; }
  }
  return [...v1, ...extra];
}

// ---- fetch + persist --------------------------------------------------------
const sleep = ms => new Promise(r => setTimeout(r, ms));
let manifestLines = 0;

function record(entry) {
  appendFileSync(MANIFEST, JSON.stringify(entry) + '\n');
  manifestLines++;
}

/** Fetch url → persist raw body at <league>/<endpoint>/<name>.json.
 *  Returns the parsed JSON (or null on any failure). Every attempt — success,
 *  404, network error — leaves a manifest line. */
async function grab(league, endpoint, name, url) {
  const dir = join(DATA_DIR, league.replace(/\//g, '__'), endpoint);
  const file = join(dir, name + '.json');
  const base = { ts: new Date().toISOString(), league, sport: league.split('/')[0], endpoint, name, url };

  if (!ARGS.force && existsSync(file)) {
    record({ ...base, status: 200, note: 'cached' });
    return JSON.parse(readFileSync(file, 'utf8'));
  }

  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const res = await fetch(url, { headers: HEADERS, signal: AbortSignal.timeout(30000) });
      if (res.status === 429 || res.status >= 500) {
        if (attempt === 0) { await sleep(2500); continue; }
      }
      if (!res.ok) {
        record({ ...base, status: res.status });
        return null;
      }
      const text = await res.text();
      let json;
      try { json = JSON.parse(text); } catch {
        record({ ...base, status: res.status, note: 'non-json' });
        return null;
      }
      mkdirSync(dir, { recursive: true });
      writeFileSync(file, text);
      record({ ...base, status: res.status, bytes: text.length });
      await sleep(150); // politeness between live hits
      return json;
    } catch (e) {
      if (attempt === 0) { await sleep(2000); continue; }
      record({ ...base, status: 0, note: String(e.message || e).slice(0, 120) });
      return null;
    }
  }
  return null;
}

// ---- per-league crawl plan ----------------------------------------------------
const ymd = d => {
  const x = new Date(d);
  return `${x.getUTCFullYear()}${String(x.getUTCMonth() + 1).padStart(2, '0')}${String(x.getUTCDate()).padStart(2, '0')}`;
};

/** 10-day windows, one per month back over the past year (window 0 = the last
 *  10 days, so live/scheduled states get sampled too). */
function monthWindows(months) {
  const now = Date.now();
  const out = [];
  for (let m = 0; m <= months; m++) {
    const end = now - m * 30 * DAY;
    out.push({ tag: ymd(end - 9 * DAY), range: `${ymd(end - 9 * DAY)}-${ymd(end)}` });
  }
  return out;
}

function scoreboardUrl(key, range) {
  const qs = new URLSearchParams();
  if (range) qs.set('dates', range);
  if (key.includes('college')) {
    qs.set('limit', '400');
    if (key.includes('basketball')) qs.set('groups', '50'); // all Division I
    if (key.includes('football')) qs.set('groups', '80');   // FBS
  }
  const q = qs.toString();
  return `${SITE}/${key}/scoreboard${q ? '?' + q : ''}`;
}

/** Pick up to n event ids from the sampled scoreboards, maximising diversity:
 *  one per distinct (status.state, season.type) combo, completed games first. */
function pickEvents(events, n) {
  const byCombo = new Map();
  for (const ev of events) {
    const st = ev.competitions?.[0]?.status?.type?.state || ev.status?.type?.state || '?';
    const combo = `${st}|${ev.season?.type ?? '?'}`;
    if (!byCombo.has(combo)) byCombo.set(combo, []);
    byCombo.get(combo).push(ev);
  }
  const order = [...byCombo.keys()].sort((a, b) => {
    const rank = s => (s.startsWith('post') ? 0 : s.startsWith('in') ? 1 : 2);
    return rank(a) - rank(b);
  });
  const picked = [];
  let round = 0;
  while (picked.length < n) {
    let took = false;
    for (const combo of order) {
      const list = byCombo.get(combo);
      if (list[round]) { picked.push(list[round]); took = true; }
      if (picked.length >= n) break;
    }
    if (!took) break;
    round++;
  }
  return picked;
}

// ---- core-API hypermedia graph crawl ----------------------------------------
// ESPN's core API (sports.core.api.espn.com) is HATEOAS: every resource is a bag
// of $ref links to child resources. GUESSING those URLs breaks the moment an
// event's competition id != its event id — true for tennis/golf/MMA/racing, where
// one "event" (a tournament, a fight card, a race weekend) holds many
// "competitions" (matches, bouts, sessions). So instead of guessing, we FOLLOW
// the refs: BFS from a few seeds, and — the key to staying bounded — fetch only
// the FIRST representative of each distinct URL *template* (ids collapsed to
// {n}). A 333-match tournament collapses to one competition sample, yet we still
// discover competition → competitors → linescores (the per-set scores) and the
// whole league tree (seasons / types / calendar / tournaments / athletes …).

const CORE_HOST = 'sports.core.api.espn.com';
const normRef = u => String(u).replace(/^http:/, 'https:').replace('espn.pvt', 'espn.com');
const isIdSeg = s => /^\d[\d.\-]*$/.test(s);        // 2026 · 188-2026 · 180004 · 50 · 2

/** Canonical shape of a core URL: pathname after /v2/sports/{sport}/, every
 *  id-ish segment (and the league slug) → {n}. Two matches map to one template. */
function coreTemplate(url, sport) {
  let pathname;
  try { pathname = new URL(url).pathname; } catch { return null; }
  const marker = `/v2/sports/${sport}/`;
  const at = pathname.indexOf(marker);
  if (at === -1) return null;
  const tail = pathname.slice(at + marker.length).replace(/\/+$/, '');
  return tail.split('/')
    .map((s, i, arr) => (isIdSeg(s) || arr[i - 1] === 'leagues') ? '{n}' : s)
    .join('/');
}

/** Same-host, same-sport, and — if league-scoped — the SAME league (don't wander
 *  from wta into atp just because Wimbledon shares a tournament ref). */
function allowedCoreUrl(url, sport, leagueSlug) {
  let u;
  try { u = new URL(url); } catch { return false; }
  if (u.hostname !== CORE_HOST) return false;
  if (!u.pathname.startsWith(`/v2/sports/${sport}/`)) return false;
  const m = u.pathname.match(/\/leagues\/([^/]+)/);
  return !m || m[1] === leagueSlug;
}

// Nice, stable bucket names for the well-known shapes (keeps the guide's existing
// core-*.md filenames and merges samples across sports); everything else is
// auto-slugged from its template. One template → one bucket (injective).
const SHAPE_NAMES = new Map([
  ['leagues/{n}', 'core-league'],
  ['leagues/{n}/events/{n}', 'core-event'],
  ['leagues/{n}/events/{n}/competitions/{n}', 'core-competition'],
  ['leagues/{n}/events/{n}/competitions/{n}/status', 'core-competition-status'],
  ['leagues/{n}/events/{n}/competitions/{n}/odds', 'core-odds'],
  ['leagues/{n}/events/{n}/competitions/{n}/situation', 'core-situation'],
  ['leagues/{n}/events/{n}/competitions/{n}/probabilities', 'core-probabilities'],
  ['leagues/{n}/events/{n}/competitions/{n}/plays', 'core-plays'],
  ['leagues/{n}/events/{n}/competitions/{n}/predictor', 'core-predictor'],
  ['leagues/{n}/events/{n}/competitions/{n}/powerindex/{n}', 'core-powerindex'],
  ['leagues/{n}/events/{n}/competitions/{n}/competitors/{n}', 'core-competitor'],
  ['leagues/{n}/events/{n}/competitions/{n}/competitors/{n}/linescores', 'core-competitor-linescores'],
  ['leagues/{n}/events/{n}/competitions/{n}/competitors/{n}/statistics', 'core-competitor-statistics'],
  ['leagues/{n}/events/{n}/competitions/{n}/competitors/{n}/roster', 'core-competitor-roster'],
  ['leagues/{n}/events/{n}/competitions/{n}/competitors/{n}/record', 'core-competitor-record'],
  ['leagues/{n}/events/{n}/competitions/{n}/competitors/{n}/leaders', 'core-competitor-leaders'],
  ['athletes/{n}', 'core-athlete'],
  ['athletes', 'core-athletes'],
  ['leagues/{n}/athletes', 'core-league-athletes'],
  ['leagues/{n}/seasons', 'core-seasons'],
  ['leagues/{n}/seasons/{n}', 'core-season'],
  ['leagues/{n}/seasons/{n}/types', 'core-season-types'],
  ['leagues/{n}/seasons/{n}/types/{n}', 'core-season-type'],
  ['leagues/{n}/calendar', 'core-calendar'],
  ['leagues/{n}/tournaments', 'core-tournaments'],
  ['leagues/{n}/transactions', 'core-transactions'],
]);
// Fallback bucket name for shapes not in SHAPE_NAMES: strip the common nesting
// prefix so e.g. …/competitions/{n}/broadcasts → core-competition-broadcasts and
// …/competitors/{n}/roster → core-competitor-roster, instead of a long id-laden
// path. Collision-free: intermediate/trailing ids survive as `id` tokens.
const NEST = [
  ['leagues/{n}/events/{n}/competitions/{n}/competitors/{n}/', 'core-competitor'],
  ['leagues/{n}/events/{n}/competitions/{n}/', 'core-competition'],
  ['leagues/{n}/events/{n}/', 'core-event'],
  ['leagues/{n}/seasons/{n}/', 'core-season'],
  ['leagues/{n}/', 'core'],
];
function endpointFor(tmpl) {
  const named = SHAPE_NAMES.get(tmpl);
  if (named) return named;
  let prefix = 'core', rest = tmpl;
  for (const [p, name] of NEST) {
    if (tmpl.startsWith(p)) { prefix = name; rest = tmpl.slice(p.length); break; }
  }
  const slug = rest.replace(/\{n\}/g, 'id').replace(/\//g, '-');
  return slug ? `${prefix}-${slug}` : prefix;
}

/** A filesystem-safe, per-doc name from the concrete path (one file per bucket
 *  per league, since template↔bucket is 1:1 and we fetch one URL per template). */
function coreName(url, sport) {
  const marker = `/v2/sports/${sport}/`;
  const p = new URL(url).pathname;
  const tail = p.slice(p.indexOf(marker) + marker.length).replace(/\/+$/, '');
  return tail.replace(/[^\w.\-]+/g, '_').slice(0, 90) || 'root';
}

/** Recursively collect every $ref string in a parsed body. */
function collectRefs(node, out) {
  if (Array.isArray(node)) { for (const v of node) collectRefs(v, out); return; }
  if (node && typeof node === 'object') {
    for (const [k, v] of Object.entries(node)) {
      if (k === '$ref' && typeof v === 'string') out.push(v);
      else collectRefs(v, out);
    }
  }
}

/** BFS the core graph from `seeds`, one fetch per distinct template. */
async function crawlGraph(key, sport, leagueSlug, seeds, args) {
  const seen = new Set();
  const queue = [];
  const enqueue = (url, depth) => {
    const norm = normRef(url);
    if (depth > args.graphDepth || !allowedCoreUrl(norm, sport, leagueSlug)) return;
    const tmpl = coreTemplate(norm, sport);
    if (!tmpl || seen.has(tmpl)) return;
    seen.add(tmpl);
    queue.push({ url: norm, depth, tmpl });
  };
  for (const s of seeds) enqueue(s, 0);

  let fetched = 0;
  while (queue.length && fetched < args.graphMaxNodes) {
    const { url, tmpl, depth } = queue.shift();
    const json = await grab(key, endpointFor(tmpl), coreName(url, sport), url);
    fetched++;
    if (!json) continue;
    const refs = [];
    collectRefs(json, refs);
    for (const r of refs) enqueue(r, depth + 1);
  }
  return { fetched, templates: seen.size };
}

async function crawlLeague(key, args) {
  const profile = resolve(REG, key);
  const sport = key.split('/')[0];
  const core = `${CORE}/${key.replace('/', '/leagues/')}`;

  // 1. scoreboard — the no-param default slate (the app's primary call shape),
  //    then monthly windows over the past year. QUIRK (verified live 2026-07):
  //    cricket 404s on `dates=` RANGES — single YYYYMMDD or no param only.
  const allEvents = [];
  const dflt = await grab(key, 'scoreboard', 'default', scoreboardUrl(key, null));
  if (dflt?.events) allEvents.push(...dflt.events);
  for (const w of monthWindows(args.months)) {
    const sb = await grab(key, 'scoreboard', w.tag,
      scoreboardUrl(key, sport === 'cricket' ? w.tag : w.range));
    if (sb?.events) allEvents.push(...sb.events);
  }

  const picked = pickEvents(allEvents, args.maxSummaries);

  // 2. summary — one per distinct (state, seasonType); 404s here document
  //    which sports lack the site summary tier (e.g. MMA).
  for (const ev of picked) {
    const st = ev.competitions?.[0]?.status?.type?.state || ev.status?.type?.state || 'x';
    await grab(key, 'summary', `${ev.id}-${st}`, `${SITE}/${key}/summary?event=${ev.id}`);
  }

  // 3. standings — current season (ESPN's default IS current), plus one
  //    explicit prior season to document the ?season= shape.
  await grab(key, 'standings', 'current', `${SITE_V2}/${key}/standings`);
  await grab(key, 'standings', 'prev-season', `${SITE_V2}/${key}/standings?season=${new Date().getFullYear() - 1}`);

  // 4. teams + per-team tiers (roster / schedule / statistics / injuries)
  const teams = await grab(key, 'teams', 'list', `${SITE}/${key}/teams`);
  const teamIds = (teams?.sports?.[0]?.leagues?.[0]?.teams || [])
    .map(t => t.team?.id).filter(Boolean).slice(0, 2);
  for (const tid of teamIds) {
    await grab(key, 'team-roster', String(tid), `${SITE}/${key}/teams/${tid}/roster`);
  }
  if (teamIds[0]) {
    await grab(key, 'team-schedule', String(teamIds[0]), `${SITE}/${key}/teams/${teamIds[0]}/schedule`);
    await grab(key, 'team-stats', String(teamIds[0]), `${SITE}/${key}/teams/${teamIds[0]}/statistics`);
    await grab(key, 'injuries', String(teamIds[0]), `${SITE}/${key}/teams/${teamIds[0]}/injuries`);
  }

  // 5. rankings — only where the profile declares a feed (college polls,
  //    ATP/WTA tours, UFC divisions)
  if (profile.rankingsFeed) {
    await grab(key, 'rankings', 'current', `${SITE}/${key}/rankings`);
  }

  // 6. news — site tier, documented in the repo's response_schemas
  await grab(key, 'news', 'latest', `${SITE}/${key}/news?limit=5`);

  // 7. core API — FOLLOW the hypermedia graph instead of guessing URLs. Seed from
  //    the league root (→ seasons / types / rankings / athletes / tournaments /
  //    calendar / transactions) and each picked event (→ its competitions →
  //    competitors → linescores / statistics / roster, plus status / odds /
  //    situation / plays / probabilities). Correct by construction for tennis,
  //    golf, MMA, racing, where competition id != event id.
  if (args.graph) {
    const leagueSlug = key.slice(key.indexOf('/') + 1);  // everything after sport/
    const seeds = [`${core}?lang=en&region=us`,
      ...picked.map(ev => `${core}/events/${ev.id}?lang=en&region=us`)];
    await crawlGraph(key, sport, leagueSlug, seeds, args);
  }

  // 8. golf hole-by-hole playersummary (the one web-host endpoint)
  if (sport === 'golf' && picked[0]) {
    const ev = picked[0];
    const player = ev.competitions?.[0]?.competitors?.find(c => c.id)?.id;
    const season = new Date(ev.date || Date.now()).getFullYear();
    if (player) {
      await grab(key, 'golf-playersummary', `${ev.id}-${player}`,
        `${WEB}/${key}/leaderboard/${ev.id}/playersummary?season=${season}&player=${player}`);
    }
  }
}

// ---- main ---------------------------------------------------------------------
const ARGS = parseArgs(process.argv.slice(2));

let keys;
if (ARGS.leagues) keys = ARGS.leagues;
else if (ARGS.all) keys = leagueKeys(REG, { sport: ARGS.sport });
else if (ARGS.priority) keys = leagueKeys(REG, { priority: ARGS.priority, sport: ARGS.sport });
else if (ARGS.sport) keys = leagueKeys(REG, { sport: ARGS.sport });
else keys = coverageScope();

mkdirSync(DATA_DIR, { recursive: true });
console.log(`crawl: ${keys.length} leagues, ${ARGS.months + 1} scoreboard windows each, concurrency ${ARGS.concurrency}`
  + (ARGS.graph ? `, core graph ON (depth ${ARGS.graphDepth}, ≤${ARGS.graphMaxNodes} nodes/league)` : ', core graph OFF'));
console.log(keys.join(' '));

const queue = [...keys];
let done = 0;
async function worker() {
  while (queue.length) {
    const key = queue.shift();
    const t0 = Date.now();
    try {
      await crawlLeague(key, ARGS);
      console.log(`  [${++done}/${keys.length}] ${key} (${((Date.now() - t0) / 1000).toFixed(1)}s)`);
    } catch (e) {
      console.error(`  [${++done}/${keys.length}] ${key} FAILED: ${e.message}`);
      record({ ts: new Date().toISOString(), league: key, endpoint: '_league', name: 'crash', status: 0, note: String(e.message).slice(0, 200) });
    }
  }
}
await Promise.all(Array.from({ length: ARGS.concurrency }, worker));
console.log(`done. ${manifestLines} manifest lines → ${MANIFEST}`);

// rollup.mjs — second pass over the crawl corpus (schema/crawl-data/, built by
// crawl.mjs): infer, for every endpoint, the observed field tree — path, types,
// presence, per-sport variance, enum values, $ref URL templates — and emit an
// LLM-consumable field guide.
//
// Usage:
//   node schema/tools/rollup.mjs                 # roll up everything crawled
//   node schema/tools/rollup.mjs --endpoint scoreboard summary
//
// Output: schema/espn-guide/
//   index.md            what was crawled, per-sport endpoint support matrix
//                       (200 vs 404 — a 404 IS the answer for "does sport X
//                       have tier Y"), + links into the per-sport guides
//   <endpoint>.md       one field-guide file per endpoint, formatted for an
//                       LLM: flat path table + fully-enumerated small-cardinality
//                       value sets (status names, competitor types, …)
//   by-sport/<sport>.md the READER'S ENTRY POINT: one page per sport — registry
//                       leagues + competition shape, which site endpoints work
//                       (and which 404), reachable core-graph resources, and the
//                       fields that make that sport distinctive (its fingerprint).
//                       A curated re-slice of the same corpus; regenerated here.
//   by-sport/index.md   the per-sport landing page (served/404 matrix at a glance)
//   fields.json         the same data machine-readable (path → stats)
//
// (The `espn-api` Claude skill, .claude/skills/espn-api/, routes ESPN-data
//  questions to these files — keep it in mind if the output layout changes.)
//
// Inference rules:
//   - array elements collapse into `path[]`; only the first 25 elements of any
//     array are sampled (shape converges fast, corpora are huge)
//   - presence % = docs where the field appears / docs where its PARENT appears
//   - a field with ≤ 15 distinct primitive values across ≥ 8 occurrences is an
//     enum → all values listed
//   - $ref/href URL values are normalized (digits → {id}, dates → {date}) so
//     link templates surface instead of thousands of unique URLs

import { readFileSync, writeFileSync, mkdirSync, readdirSync, existsSync, rmSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadRegistry, resolve, leagueKeys } from './profiles.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const DATA_DIR = join(HERE, '..', 'crawl-data');
const OUT_DIR = join(HERE, '..', 'espn-guide');
const MANIFEST = join(DATA_DIR, 'manifest.jsonl');
const REG = loadRegistry();

// ---- per-sport guide scaffolding --------------------------------------------
// Real hosts (mirrors crawl.mjs) so the per-sport URL templates are copy-pasteable.
const SITE = 'https://site.api.espn.com/apis/site/v2/sports';
const SITE_V2 = 'https://site.api.espn.com/apis/v2/sports';      // standings lives here
const WEB = 'https://site.web.api.espn.com/apis/site/v2/sports';

// The site/summary endpoints in "which do I reach for" order, each with the human
// role and a URL template. `{L}` is filled with a representative crawled league.
const SITE_GUIDE = [
  { ep: 'scoreboard', need: 'Scores & live state', url: L => `${SITE}/${L}/scoreboard`,
    note: 'The cheap poll — scores, status, line scores, and (situationally) situation, leaders, records, odds. The primary call. College needs `?groups=<id>&limit=400`; `?dates=YYYYMMDD-YYYYMMDD` for a range (cricket: single day only).' },
  { ep: 'summary', need: 'Rich game detail', url: L => `${SITE}/${L}/summary?event={eventId}`,
    note: 'One extra fetch when a game is opened — box scores, scoring plays, rosters, penalty shootouts, method of victory. A 404 for the whole sport means this tier does not exist (build detail from the core graph instead).' },
  { ep: 'standings', need: 'League table', url: L => `${SITE_V2}/${L}/standings`,
    note: '⚠ `apis/v2`, NOT `apis/site/v2` (the site path returns a `{fullViewLink}` stub). Omit `?season=` — ESPN defaults to the current season.' },
  { ep: 'teams', need: 'Team directory', url: L => `${SITE}/${L}/teams`,
    note: 'Team ids, names, abbreviations, logos, colors. The id feeds the roster/schedule/stats/injuries calls.' },
  { ep: 'team-roster', need: 'Roster', url: L => `${SITE}/${L}/teams/{teamId}/roster`,
    note: 'Per-team roster with positions and headshots.' },
  { ep: 'team-schedule', need: 'Schedule', url: L => `${SITE}/${L}/teams/{teamId}/schedule`,
    note: 'Per-team schedule, past results + upcoming fixtures.' },
  { ep: 'team-stats', need: 'Team season stats', url: L => `${SITE}/${L}/teams/{teamId}/statistics`,
    note: 'Per-team season statistics.' },
  { ep: 'rankings', need: 'Polls / rankings', url: L => `${SITE}/${L}/rankings`,
    note: 'College polls, ATP/WTA tour rankings, UFC divisional rankings. Only where a poll exists for the league.' },
  { ep: 'news', need: 'News', url: L => `${SITE}/${L}/news?limit=5`,
    note: 'Latest articles for the league.' },
  { ep: 'injuries', need: 'Injuries', url: L => `${SITE}/${L}/teams/{teamId}/injuries`,
    note: 'Per-team injury report.' },
  { ep: 'golf-playersummary', need: 'Hole-by-hole', url: L => `${WEB}/${L}/leaderboard/{eventId}/playersummary?player={athleteId}`,
    note: 'Golf only — per-player hole-by-hole scoring (web host, not the site host).' },
];

// The high-value core-graph resources, surfaced by name so a sport guide can say
// "yes, win probability / play-by-play / set scores are reachable here." The full
// 200-shape matrix stays in index.md.
const CORE_HIGHLIGHTS = [
  ['core-competitor-linescores', 'Per-period / per-set / per-inning scores — reachable even when the site scoreboard omits them (tennis sets, cricket innings).'],
  ['core-situation', 'Live game situation (baseball base/out, gridiron down & distance).'],
  ['core-plays', 'Play-by-play feed.'],
  ['core-competition-plays-id', 'Individual play detail.'],
  ['core-odds', 'Betting lines / odds.'],
  ['core-competition-odds-id-propBets', 'Prop bets.'],
  ['core-probabilities', 'Win-probability timeline.'],
  ['core-predictor', 'Pre-game matchup prediction.'],
  ['core-competition-powerindex', 'Team power-index / matchup metrics.'],
  ['core-competition-statistics', 'Team box statistics for the game.'],
  ['core-competitor-roster', 'Game-day lineup.'],
  ['core-competitor-statistics', "Competitor's game statistics."],
  ['core-competition-commentaries', 'Text commentary stream.'],
  ['core-season-types-id-groups-id-standings', 'Standings through the core graph (grouped).'],
  ['core-rankings', 'Rankings through the core graph.'],
  ['core-athlete', 'Athlete bio / profile.'],
  ['core-season-futures', 'Season futures (championship odds).'],
  ['core-competition-officials', 'Match officials / referees.'],
];

// Field-path noise to keep out of the "what's distinctive" fingerprint: link
// bags, logos, images, refs, and the generic athlete-identity block (a name/id/
// jersey under every sport) — present everywhere, informative nowhere. The
// sport-defining signal is the CONTAINER (situation.batter, dueUp[]) and the
// non-identity leaves (balls, outs, batOrder, statistics), which all survive.
const FP_NOISE = new RegExp([
  '(\\.|^)(links|logos|images|logo|headshot|\\$ref|uid|guid|rel|href)(\\.|\\[|$)',
  'flag\\.', '\\.alternateIds',
  '\\.link\\.',                                                  // link-metadata bag
  '\\.(isExternal|isPremium|language|shortText)(\\.|\\[|$)',
  '\\.athlete\\.(id|guid|displayName|fullName|shortName|jersey|playerId|position|team|active)(\\.|\\[|$)',
  '\\.hotZones',                                                 // per-pixel heat-map coords
  '\\.(broadcasts|geoBroadcasts|headlines|video|media)(\\.|\\[|$)', // broadcast/media bags
  '\\.dataSourceIdentifier',
].join('|'), 'i');

const MAX_ARRAY_SAMPLE = 25;
const MAX_DEPTH = 14;
const MAX_EXAMPLES = 4;
const ENUM_MAX_DISTINCT = 15;
const ENUM_MIN_SEEN = 8;
const EXAMPLE_MAX_LEN = 80;

// ---- args -------------------------------------------------------------------
const args = process.argv.slice(2);
let onlyEndpoints = null;
const ei = args.indexOf('--endpoint');
if (ei !== -1) { onlyEndpoints = []; for (let i = ei + 1; i < args.length && !args[i].startsWith('--'); i++) onlyEndpoints.push(args[i]); }

// ---- manifest ----------------------------------------------------------------
if (!existsSync(MANIFEST)) {
  console.error('no crawl corpus found — run crawl.mjs first');
  process.exit(1);
}
// last line per (league, endpoint, name) wins (re-crawls supersede)
const manifest = new Map();
for (const line of readFileSync(MANIFEST, 'utf8').split('\n')) {
  if (!line.trim()) continue;
  const e = JSON.parse(line);
  manifest.set(`${e.league}|${e.endpoint}|${e.name}`, e);
}
const entries = [...manifest.values()];

// ---- schema inference ----------------------------------------------------------
const typeOf = v =>
  v === null ? 'null'
  : Array.isArray(v) ? 'array'
  : typeof v; // string | number | boolean | object

const looksNumericStr = s => /^-?\d+(\.\d+)?$/.test(s);
const looksUrl = s => /^https?:\/\//.test(s);
const looksIsoDate = s => /^\d{4}-\d{2}-\d{2}T/.test(s);

/** Collapse a URL to its template: digits → {id}, ISO dates → {date}. */
const urlTemplate = u => u
  .replace(/\?.*$/, '?…')
  .replace(/\d{8,}/g, '{id}')
  .replace(/\/\d+/g, '/{id}');

function newNode() {
  return { count: 0, types: {}, values: new Map(), truncated: false, numericStr: 0, children: null };
}

/** Walk one JSON value into the trie rooted at `node`. `sport` tags variance. */
function addValue(node, value, sport, depth) {
  node.count++;
  (node.sports ??= new Set()).add(sport);
  (node.sportCounts ??= new Map()).set(sport, (node.sportCounts.get(sport) || 0) + 1);
  const t = typeOf(value);
  node.types[t] = (node.types[t] || 0) + 1;

  if (t === 'object') {
    if (depth >= MAX_DEPTH) return;
    node.children ??= {};
    const keys = Object.keys(value);
    // map-like object: keys are data (play ids, atBat ids, …), not field names —
    // collapse them into a `{key}` wildcard so the trie shows the VALUE shape
    const idKey = k => /\d/.test(k) && /^[A-Za-z]*[\d.-]+$/.test(k);
    if (keys.length >= 6 && keys.filter(idKey).length >= keys.length * 0.8) {
      const el = node.children['{key}'] ??= newNode();
      for (const v of Object.values(value).slice(0, MAX_ARRAY_SAMPLE)) addValue(el, v, sport, depth + 1);
      return;
    }
    for (const [k, v] of Object.entries(value)) {
      addValue(node.children[k] ??= newNode(), v, sport, depth + 1);
    }
  } else if (t === 'array') {
    if (depth >= MAX_DEPTH) return;
    node.children ??= {};
    const el = node.children['[]'] ??= newNode();
    for (const v of value.slice(0, MAX_ARRAY_SAMPLE)) addValue(el, v, sport, depth + 1);
    if (value.length > MAX_ARRAY_SAMPLE) el.truncated = true;
  } else {
    if (t === 'string' && looksNumericStr(value)) node.numericStr++;
    let key = value;
    if (t === 'string') {
      if (looksUrl(value)) key = urlTemplate(value);
      else if (looksIsoDate(value)) key = '{iso-datetime}';
      else if (value.length > EXAMPLE_MAX_LEN) key = value.slice(0, EXAMPLE_MAX_LEN) + '…';
    }
    if (node.values.size < 400) {
      node.values.set(key, (node.values.get(key) || 0) + 1);
    } else node.truncated = true;
  }
}

// group corpus docs by endpoint
const endpoints = new Map(); // endpoint → {root, docs, leagues:Set, sports:Set, urls:Set}
for (const e of entries) {
  if (e.status !== 200 || e.endpoint === '_league') continue;
  if (onlyEndpoints && !onlyEndpoints.includes(e.endpoint)) continue;
  const file = join(DATA_DIR, e.league.replace(/\//g, '__'), e.endpoint, e.name + '.json');
  if (!existsSync(file)) continue;
  let json;
  try { json = JSON.parse(readFileSync(file, 'utf8')); } catch { continue; }
  const g = endpoints.get(e.endpoint) ?? (endpoints.set(e.endpoint, {
    root: newNode(), docs: 0, leagues: new Set(), sports: new Set(), urls: new Set(),
  }).get(e.endpoint));
  g.docs++;
  g.leagues.add(e.league);
  g.sports.add(e.sport || e.league.split('/')[0]);
  g.urls.add(urlTemplate(e.url).replace(/^https?:\/\//, '').replace('{id}', '…'));
  addValue(g.root, json, e.sport || e.league.split('/')[0], 0);
}

// ---- emit ----------------------------------------------------------------------
mkdirSync(OUT_DIR, { recursive: true });
// Clean slate: the core graph is open-ended, so a shape that vanishes from the
// corpus (e.g. a resource ESPN retired, or the old URL-guessing crawler's buckets)
// must not leave a stale .md behind. Regenerate every file from the corpus.
for (const f of readdirSync(OUT_DIR)) {
  if (f.endsWith('.md') || f === 'fields.json') rmSync(join(OUT_DIR, f));
}
// clear stale per-sport guides by file (removing the dir handle EPERMs on Windows)
const BY_SPORT = join(OUT_DIR, 'by-sport');
if (existsSync(BY_SPORT)) {
  for (const f of readdirSync(BY_SPORT)) if (f.endsWith('.md')) rmSync(join(BY_SPORT, f));
}

function flatten(node, path, parentCount, allSports, out) {
  if (!node.children) return;
  for (const [k, child] of Object.entries(node.children).sort(([a], [b]) => a.localeCompare(b))) {
    const wild = k === '[]' || k === '{key}';
    const p = k === '[]' ? path + '[]' : (path ? path + '.' + k : k);
    const types = Object.entries(child.types).sort((a, b) => b[1] - a[1]).map(([t]) => t);
    const presence = wild ? null : Math.round(100 * child.count / Math.max(1, parentCount));
    const sports = child.sports ?? new Set();
    const sportNote = sports.size === allSports.size ? 'all' : [...sports].sort().join(', ');

    let values = null, example = null;
    const prim = child.values;
    if (prim.size) {
      const sorted = [...prim.entries()].sort((a, b) => b[1] - a[1]);
      if (!child.truncated && prim.size <= ENUM_MAX_DISTINCT && child.count >= ENUM_MIN_SEEN
          && !sorted.every(([v]) => typeof v === 'string' && (v.includes('{id}') || v === '{iso-datetime}'))) {
        values = sorted.map(([v, n]) => ({ v, n }));
      } else {
        example = sorted.slice(0, MAX_EXAMPLES).map(([v]) => v);
      }
    }
    const numericStr = types[0] === 'string' && child.numericStr > 0 && child.numericStr >= 0.9 * (child.types.string || 0);

    out.push({ path: p, types, presence, count: child.count, sports: sportNote, values, example, numericStr });
    flatten(child, p, child.count, allSports, out);
  }
}

const fmtVal = v => {
  const s = typeof v === 'string' ? `"${v}"` : String(v);
  return s.replace(/\|/g, '\\|').replace(/\n/g, ' ');
};

// ---- per-sport helpers ------------------------------------------------------
/** Enum/example summary for a trie node (same rules as flatten, factored out). */
function valueSummary(child) {
  const types = Object.entries(child.types).sort((a, b) => b[1] - a[1]).map(([t]) => t);
  let values = null, example = null;
  const prim = child.values;
  if (prim.size) {
    const sorted = [...prim.entries()].sort((a, b) => b[1] - a[1]);
    if (!child.truncated && prim.size <= ENUM_MAX_DISTINCT && child.count >= ENUM_MIN_SEEN
        && !sorted.every(([v]) => typeof v === 'string' && (v.includes('{id}') || v === '{iso-datetime}'))) {
      values = sorted.map(([v, n]) => ({ v, n }));
    } else {
      example = sorted.slice(0, MAX_EXAMPLES).map(([v]) => v);
    }
  }
  const numericStr = types[0] === 'string' && child.numericStr > 0 && child.numericStr >= 0.9 * (child.types.string || 0);
  return { types, values, example, numericStr };
}

/** Like flatten(), but only walks paths this `sport` was actually observed in, and
 *  computes presence relative to the sport's own parent count (not the global one). */
function flattenForSport(node, path, sport, parentSportCount, out) {
  if (!node.children) return;
  for (const [k, child] of Object.entries(node.children).sort(([a], [b]) => a.localeCompare(b))) {
    const sc = child.sportCounts?.get(sport) || 0;
    if (!sc) continue; // this sport never carries this field
    const wild = k === '[]' || k === '{key}';
    const p = k === '[]' ? path + '[]' : (path ? path + '.' + k : k);
    const presence = wild ? null : Math.round(100 * sc / Math.max(1, parentSportCount));
    const { types, values, example, numericStr } = valueSummary(child);
    out.push({ path: p, types, presence, sportsSize: child.sports?.size || 0, values, example, numericStr });
    flattenForSport(child, p, sport, sc, out);
  }
}

/** The sport's "fingerprint" for one endpoint: value-bearing leaves that this sport
 *  carries but that are NOT near-universal — the fields that make the sport itself. */
function fingerprint(endpointName, sport) {
  const g = endpoints.get(endpointName);
  if (!g || !g.root.sportCounts?.has(sport)) return [];
  const rows = [];
  flattenForSport(g.root, '', sport, g.root.sportCounts.get(sport), rows);
  const maxSports = Math.min(6, Math.max(2, Math.ceil(g.sports.size / 2)));
  return rows
    .filter(r => (r.values || r.example)                                  // a leaf with samples
      && r.sportsSize <= maxSports                                        // not near-universal
      && !FP_NOISE.test(r.path)
      && !(r.example && !r.values && r.example.every(v =>                 // not just ids/dates
        typeof v === 'string' && /\{id\}|\{iso-datetime\}/.test(v))))
    .sort((a, b) => a.sportsSize - b.sportsSize || (b.presence || 0) - (a.presence || 0) || a.path.localeCompare(b.path))
    .slice(0, 55);
}

/** One markdown cell for a fingerprint/field row's value samples. */
const fpValue = r => r.values ? 'values: ' + r.values.map(x => `${fmtVal(x.v)} (${x.n})`).join(', ')
  : r.example ? 'e.g. ' + r.example.map(fmtVal).join(', ') : '';

const machine = {};
const endpointNames = [...endpoints.keys()].sort();
for (const name of endpointNames) {
  const g = endpoints.get(name);
  const rows = [];
  flatten(g.root, '', g.docs, g.sports, rows);
  machine[name] = {
    docs: g.docs, leagues: [...g.leagues].sort(), urls: [...g.urls].sort(),
    fields: rows.map(r => ({ ...r, values: r.values?.map(x => x.v) })),
  };

  const md = [];
  md.push(`# ESPN \`${name}\` — observed field guide`);
  md.push('');
  md.push(`> Generated by \`schema/tools/rollup.mjs\` from ${g.docs} real responses across ${g.leagues.size} leagues (${g.sports.size} sports: ${[...g.sports].sort().join(', ')}). Everything below was OBSERVED in live data — nothing is guessed from documentation.`);
  md.push('');
  md.push('URL template(s) crawled:');
  for (const u of [...g.urls].sort()) md.push(`- \`${u}\``);
  md.push('');
  md.push('How to read the table:');
  md.push('- **presence** = % of responses (or parent objects) that carry the field. Low % usually means sport-specific or situational.');
  md.push('- **sports** = which sports the field was observed in (`all` = every sport crawled for this endpoint).');
  md.push('- `[]` in a path = array element; `{key}` = a dictionary whose keys are ids (play ids, atBat ids). `str-numeric` = string that always holds a number (ESPN serves scores as strings).');
  md.push('- **values** exhaustively lists small closed sets (enums) with observation counts; **e.g.** shows samples of open sets.');
  md.push('');
  if (!rows.length) {
    md.push('**Every crawled response was empty** (e.g. `[]`) — the endpoint exists but served no data during the crawl window.');
    md.push('');
  }
  md.push('| path | type | presence | sports | values / examples |');
  md.push('|---|---|---|---|---|');
  for (const r of rows) {
    const type = r.types.map(t => (t === 'string' && r.numericStr ? 'str-numeric' : t)).join(' \\| ');
    const pres = r.presence == null ? '—' : r.presence + '%';
    let val = '';
    if (r.values) val = 'values: ' + r.values.map(x => `${fmtVal(x.v)} (${x.n})`).join(', ');
    else if (r.example) val = 'e.g. ' + r.example.map(fmtVal).join(', ');
    md.push(`| \`${r.path}\` | ${type} | ${pres} | ${r.sports} | ${val} |`);
  }
  md.push('');
  writeFileSync(join(OUT_DIR, name + '.md'), md.join('\n'));
  console.log(`  ${name}.md — ${rows.length} paths from ${g.docs} docs`);
}

// ---- index: per-sport endpoint support matrix -----------------------------------
const support = new Map(); // sport → endpoint → {ok, notFound, other}
const repLeague = new Map(); // sport → a representative crawled league key (for URL templates)
const crawledLeagues = new Map(); // sport → Set(league keys that returned ≥1 200)
for (const e of entries) {
  if (e.endpoint === '_league') continue;
  const sport = e.sport || e.league.split('/')[0];
  const s = support.get(sport) ?? support.set(sport, new Map()).get(sport);
  const c = s.get(e.endpoint) ?? s.set(e.endpoint, { ok: 0, notFound: 0, other: 0 }).get(e.endpoint);
  if (e.status === 200) c.ok++;
  else if (e.status === 404 || e.status === 400) c.notFound++;
  else c.other++;
  if (e.status === 200) {
    (crawledLeagues.get(sport) ?? crawledLeagues.set(sport, new Set()).get(sport)).add(e.league);
    // prefer a scoreboard hit for the URL template; else first success wins
    if (!repLeague.has(sport) || e.endpoint === 'scoreboard') repLeague.set(sport, e.league);
  }
}
const sportsSorted = [...support.keys()].sort();

// ---- per-sport guides -----------------------------------------------------------
emitSportGuides();
function emitSportGuides() {
  const supCell = (sport, ep) => {
    const c = support.get(sport)?.get(ep);
    if (!c) return null; // not attempted
    const tried = c.ok + c.notFound + c.other;
    return { ok: c.ok, tried };
  };
  const dir = join(OUT_DIR, 'by-sport');
  mkdirSync(dir, { recursive: true });

  for (const sport of sportsSorted) {
    const keys = leagueKeys(REG, { sport });
    const crawled = [...(crawledLeagues.get(sport) || [])].sort();
    const rep = repLeague.get(sport) || crawled[0] || `${sport}/…`;
    const okTotal = [...(support.get(sport)?.values() || [])].reduce((n, c) => n + c.ok, 0);

    // distinct competition shapes across the registry's leagues for this sport
    const shapes = new Map();
    for (const k of keys) {
      let r; try { r = resolve(REG, k); } catch { continue; }
      const shape = `${r.layout || '?'} · ${r.scoreKind || '?'} · ${r.competitorKind || '?'}`;
      const g = shapes.get(shape) ?? shapes.set(shape, { count: 0, ex: [] }).get(shape);
      g.count++;
      if (g.ex.length < 4) g.ex.push(k.split('/').slice(1).join('/'));
    }

    const md = [];
    md.push(`# ESPN API — ${sport}`);
    md.push('');
    md.push(`> Per-sport slice of the [observed data guide](../index.md): what ESPN actually serves for **${sport}**, and which endpoint answers each need. Built from ${okTotal} real ${sport} responses — OBSERVED live, not documented. Regenerate: \`node schema/tools/rollup.mjs\`.`);
    md.push('');

    // --- leagues / shape ---
    md.push(`## Leagues — ${keys.length} in the registry`);
    md.push('');
    md.push('Competition **shape** drives rendering (see the discriminators in `schema/canonical.ts`): `layout · scoreKind · competitorKind`.');
    md.push('');
    md.push('| shape (layout · scoreKind · competitorKind) | leagues | examples |');
    md.push('|---|---|---|');
    for (const [shape, g] of [...shapes.entries()].sort((a, b) => b[1].count - a[1].count)) {
      md.push(`| \`${shape}\` | ${g.count} | ${g.ex.map(x => `\`${x}\``).join(', ')} |`);
    }
    md.push('');
    md.push(`**Crawled for this guide** (${crawled.length}): ${crawled.map(k => `\`${k}\``).join(', ') || '—'}. The evidence below is from these leagues; other ${sport} leagues in the registry inherit the same shape.`);
    md.push('');

    // --- site endpoints ---
    md.push('## Which endpoint to use');
    md.push('');
    md.push(`URL templates use \`${rep}\` as a representative league. Swap in any league key from the table above.`);
    md.push('');
    md.push('| need | endpoint | status | URL template | fields |');
    md.push('|---|---|---|---|---|');
    for (const s of SITE_GUIDE) {
      const cell = supCell(sport, s.ep);
      if (!cell) continue; // not attempted for this sport → omit the row
      const status = cell.ok > 0 ? `✅ ${cell.ok}/${cell.tried}` : `❌ not served`;
      md.push(`| ${s.need} | \`${s.ep}\` | ${status} | \`${s.url(rep)}\` | [guide](../${s.ep}.md) |`);
    }
    md.push('');
    // notes for the endpoints that matter for this sport
    for (const s of SITE_GUIDE) {
      const cell = supCell(sport, s.ep);
      if (!cell) continue;
      const flag = cell.ok > 0 ? '' : ' _(every attempt 404/400 — this tier does not exist for the sport)_';
      md.push(`- **${s.ep}** — ${s.note}${flag}`);
    }
    md.push('');

    // --- core graph highlights ---
    const coreOk = [...(support.get(sport)?.entries() || [])].filter(([ep, c]) => ep.startsWith('core-') && c.ok > 0).length;
    md.push('## Core API — `sports.core.api.espn.com`');
    md.push('');
    md.push(`${coreOk} of the core resource shapes were reachable for ${sport} by following \`$ref\` links from the league root and its events (full matrix: [index.md](../index.md#core-api-resource-graph)). High-value shapes:`);
    md.push('');
    md.push('| resource | reachable | what it adds |');
    md.push('|---|---|---|');
    for (const [res, blurb] of CORE_HIGHLIGHTS) {
      const cell = supCell(sport, res);
      if (!cell) continue; // never even linked for this sport → skip
      const status = cell.ok > 0 ? `✅` : `❌`;
      md.push(`| \`${res}\` | ${status} | ${blurb} |`);
    }
    md.push('');

    // --- fingerprint ---
    md.push('## What\'s sport-specific in the data');
    md.push('');
    md.push(`Value-bearing fields observed for ${sport} that are **not** near-universal — the sport's fingerprint. **presence** = % of this sport's crawled responses (or parent objects) that carry the field (${sport}-specific). Field paths, types, and presence are ${sport}-only; the **value/example samples are pooled** across the handful of sports that share a field (a nested \`period\` may show golf's "18" next to a fight's "1–3"), so read them as shape hints. The full per-sport field tables live in the per-endpoint guides linked above.`);
    md.push('');
    for (const ep of ['scoreboard', 'summary']) {
      const cell = supCell(sport, ep);
      if (!cell || cell.ok === 0) continue;
      const fp = fingerprint(ep, sport);
      if (!fp.length) continue;
      md.push(`### ${ep}`);
      md.push('');
      md.push('| field | type | presence | values / examples |');
      md.push('|---|---|---|---|');
      for (const r of fp) {
        const type = r.types.map(t => (t === 'string' && r.numericStr ? 'str-numeric' : t)).join(' \\| ');
        md.push(`| \`${r.path}\` | ${type} | ${r.presence == null ? '—' : r.presence + '%'} | ${fpValue(r)} |`);
      }
      md.push('');
    }

    // --- deeper ---
    md.push('## Go deeper');
    md.push('');
    md.push('- Full field tables: [scoreboard](../scoreboard.md) · [summary](../summary.md) · [standings](../standings.md) · [teams](../teams.md) · [team-roster](../team-roster.md) · [rankings](../rankings.md)');
    md.push('- Canonical shape, ESPN→canonical mappings, per-league period/OT matrix: `schema/SCHEMA.md`, `schema/canonical.ts`');
    md.push('- Cross-sport support matrix: [index.md](../index.md)');
    md.push('');
    writeFileSync(join(dir, `${sport}.md`), md.join('\n'));
  }

  // by-sport index
  const idx = [];
  idx.push('# ESPN API — per-sport guides');
  idx.push('');
  idx.push('> One page per sport: the registry leagues + their competition shape, the site/summary endpoints that work (and the ones that 404), the reachable core-graph resources, and the fields that make each sport distinctive. Generated by `schema/tools/rollup.mjs` from the live crawl corpus. Start here, then drop into the per-endpoint field tables for exhaustive detail.');
  idx.push('');
  idx.push('| sport | leagues | scoreboard | summary | standings | rankings | guide |');
  idx.push('|---|---|---|---|---|---|---|');
  const mark = (sport, ep) => {
    const c = support.get(sport)?.get(ep);
    if (!c) return '·';
    return c.ok > 0 ? '✅' : '❌';
  };
  for (const sport of sportsSorted) {
    const n = leagueKeys(REG, { sport }).length;
    idx.push(`| ${sport} | ${n} | ${mark(sport, 'scoreboard')} | ${mark(sport, 'summary')} | ${mark(sport, 'standings')} | ${mark(sport, 'rankings')} | [${sport}](./${sport}.md) |`);
  }
  idx.push('');
  idx.push('✅ served · ❌ every attempt 404/400 (the tier genuinely does not exist for that sport) · · not attempted. See the full cross-sport matrix and the core-graph breakdown in [../index.md](../index.md).');
  idx.push('');
  writeFileSync(join(dir, 'index.md'), idx.join('\n'));
  console.log(`by-sport/ — ${sportsSorted.length} sport guides → ${dir}`);
}

const idx = [];
idx.push('# ESPN API — observed data guide');
idx.push('');
idx.push('> A definitive, evidence-based guide to what ESPN\'s unofficial API actually serves, built by crawling real responses from the past year across every sport in `schema/league-profiles.json` (crawler: `schema/tools/crawl.mjs`, corpus: `schema/crawl-data/`, this rollup: `schema/tools/rollup.mjs`). The **site/summary API** is crawled by fixed URL templates (endpoint families per https://github.com/pseudo-r/Public-ESPN-API); the **core API** (`sports.core.api.espn.com`) is a hypermedia graph, so it is *discovered* by following every `$ref` from each league root and its events — reaching resources whose URLs can\'t be guessed (e.g. tennis competitions, where the competition id differs from the event id). Everything below was OBSERVED live; nothing is from documentation. Regenerate: crawl, then roll up.');
idx.push('');
idx.push(`Corpus: ${entries.filter(e => e.status === 200).length} successful responses, ${new Set(entries.map(e => e.league)).size} leagues, ${sportsSorted.length} sports. Crawled ${entries[0]?.ts?.slice(0, 10)} → ${entries[entries.length - 1]?.ts?.slice(0, 10)}.`);
idx.push('');
idx.push('## Start here: per-sport guides');
idx.push('');
idx.push('**If you\'re building for one sport, read its [per-sport guide](./by-sport/index.md) first** — it names the leagues + their competition shape, the endpoints that work (and the ones that 404), the reachable core-graph resources, and the fields unique to that sport, in one page. The tables below are the exhaustive cross-sport reference behind those guides.');
idx.push('');
for (const sport of sportsSorted) idx.push(`- [\`${sport}\`](./by-sport/${sport}.md)`);
idx.push('');
// The site/web API is a flat set of named endpoints hit by fixed URL templates;
// the core API (sports.core.api.espn.com) is a hypermedia graph DISCOVERED by
// following $ref links, so its endpoint set is open-ended (one bucket per distinct
// resource template). Split the two so neither table drowns the other.
const isCore = n => n.startsWith('core-');
const siteNames = endpointNames.filter(n => !isCore(n));
const coreNames = endpointNames.filter(isCore);
const sportsOf = ep => sportsSorted.filter(s => (support.get(s).get(ep)?.ok ?? 0) > 0);
// core resources ranked by breadth (how many sports expose them), then name
const coreByBreadth = [...coreNames].sort((a, b) => sportsOf(b).length - sportsOf(a).length || a.localeCompare(b));

idx.push('## Per-endpoint field guides');
idx.push('');
idx.push('**Site / summary API** (flat, fixed URL templates):');
idx.push('');
for (const n of siteNames) {
  const g = endpoints.get(n);
  idx.push(`- [\`${n}\`](./${n}.md) — ${g.docs} responses, ${g.sports.size} sports`);
}
idx.push('');
idx.push(`**Core API resource graph** (${coreNames.length} distinct resource shapes, discovered by following \`$ref\` links from each league root + its events — see \`crawlGraph\` in \`crawl.mjs\`):`);
idx.push('');
for (const n of coreByBreadth) {
  const g = endpoints.get(n);
  idx.push(`- [\`${n}\`](./${n}.md) — ${g.docs} responses, ${g.sports.size} sports`);
}
idx.push('');
idx.push('## Endpoint support by sport');
idx.push('');
idx.push('Cell = successful / attempted requests. `—` = every attempt failed (a 404/400 — for the site API, the tier genuinely does not exist for that sport; for the core graph, no reachable resource linked to it). `·` = not attempted for that sport.');
idx.push('');
idx.push('### Site / summary API');
idx.push('');
const cell = (sport, ep) => {
  const c = support.get(sport)?.get(ep);
  if (!c) return '·';
  const tried = c.ok + c.notFound + c.other;
  return c.ok === 0 ? '—' : `${c.ok}/${tried}`;
};
idx.push('| sport | ' + siteNames.join(' | ') + ' |');
idx.push('|---' + '|---'.repeat(siteNames.length) + '|');
for (const sport of sportsSorted) {
  idx.push(`| ${sport} | ${siteNames.map(ep => cell(sport, ep)).join(' | ')} |`);
}
idx.push('');
idx.push('### Core API resource graph');
idx.push('');
idx.push('Transposed (resource shapes as rows, sports as columns) since the graph has far more shapes than sports. Sorted by breadth — the cross-sport resources (competition, competitor, season …) surface first; the tail is sport-specific. A populated row that used to read `—` under the old URL-guessing crawler (e.g. tennis odds/linescores) is the whole point: those resources were always there, just not at a guessable URL.');
idx.push('');
idx.push('| resource | ' + sportsSorted.join(' | ') + ' |');
idx.push('|---' + '|---'.repeat(sportsSorted.length) + '|');
for (const ep of coreByBreadth) {
  idx.push(`| \`${ep}\` | ${sportsSorted.map(sport => cell(sport, ep)).join(' | ')} |`);
}
idx.push('');
writeFileSync(join(OUT_DIR, 'index.md'), idx.join('\n'));
writeFileSync(join(OUT_DIR, 'fields.json'), JSON.stringify(machine));
console.log(`index.md + fields.json → ${OUT_DIR}`);

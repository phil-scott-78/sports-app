// probe.mjs — deterministic structural fingerprint of a live ESPN endpoint.
// No LLM. Single source of truth for "what does this endpoint actually look
// like right now." Used by verify.mjs and by the onboard-league workflow.
//
// Usage:
//   node probe.mjs soccer/eng.1
//   node probe.mjs basketball/nba --date 20250622      # capture a known game day
//   node probe.mjs golf/pga --deep                      # also probe summary of first event
//   node probe.mjs racing/f1 --raw > raw.json           # dump raw scoreboard JSON
//
// Output: a JSON fingerprint on stdout (machine-readable; feed to verify/onboard).

const SCOREBOARD = 'https://site.api.espn.com/apis/site/v2/sports/{p}/scoreboard';
const SUMMARY = 'https://site.api.espn.com/apis/site/v2/sports/{p}/summary?event={id}';
const UA = { 'User-Agent': 'Mozilla/5.0 (sports-app probe)' };

export async function fetchJson(url) {
  const res = await fetch(url, { headers: UA });
  if (!res.ok) {
    const e = new Error(`HTTP ${res.status} for ${url}`);
    e.httpStatus = res.status;
    throw e;
  }
  return res.json();
}

const isNumericStr = s => typeof s === 'string' && /^-?\d+$/.test(s.trim());
const isToParStr = s => typeof s === 'string' && /^(E|[+-]\d+)$/.test(s.trim());
const isCricketStr = s => typeof s === 'string' && /\d+\/\d+.*ov/i.test(s);

function guessScoreKind(scores, maxCompetitors) {
  const nonEmpty = scores.filter(s => s != null && s !== '');
  if (nonEmpty.some(isCricketStr)) return 'cricket';
  if (nonEmpty.length && nonEmpty.every(isToParStr)) return 'toPar';
  if (nonEmpty.some(isNumericStr)) return 'numeric';
  if (maxCompetitors > 2 || nonEmpty.length === 0) return 'none';
  return 'unknown';
}

/** Build a structural fingerprint from a scoreboard payload. */
export function fingerprint(path, sb) {
  const league = (sb.leagues || [{}])[0];
  const events = sb.events || [];

  const statusNames = new Set();
  const statusStates = new Set();
  const seasonTypes = new Set();
  const scoreSamples = [];
  let competitionsPerEvent = [Infinity, 0];
  let competitorsPerComp = [Infinity, 0];
  let maxPeriod = 0;
  let hasLinescores = false, homeAwayPresent = false, curatedRankPresent = false;
  let hadPlayoffSeen = false, formatRegulation = null, shootoutSeen = false;
  let competitorTypes = new Set();

  for (const ev of events) {
    const comps = ev.competitions || [];
    competitionsPerEvent = [Math.min(competitionsPerEvent[0], comps.length), Math.max(competitionsPerEvent[1], comps.length)];
    if (ev.season?.type != null) seasonTypes.add(ev.season.type);
    for (const c of comps) {
      const st = c.status || ev.status || {};
      if (st.type?.name) statusNames.add(st.type.name);
      if (st.type?.state) statusStates.add(st.type.state);
      if (typeof st.period === 'number') maxPeriod = Math.max(maxPeriod, st.period);
      if (c.status?.hadPlayoff) hadPlayoffSeen = true;
      if (c.format?.regulation && !formatRegulation) formatRegulation = c.format.regulation;
      const cs = c.competitors || [];
      competitorsPerComp = [Math.min(competitorsPerComp[0], cs.length), Math.max(competitorsPerComp[1], cs.length)];
      for (const comp of cs) {
        if (comp.type) competitorTypes.add(comp.type);
        if (Array.isArray(comp.linescores) && comp.linescores.length) hasLinescores = true;
        if (comp.homeAway) homeAwayPresent = true;
        if (comp.curatedRank?.current != null) curatedRankPresent = true;
        if (comp.shootoutScore != null) shootoutSeen = true;
        if (comp.score != null && scoreSamples.length < 8) scoreSamples.push(comp.score);
      }
    }
  }

  const fix = a => (a[0] === Infinity ? [0, 0] : a);
  competitorsPerComp = fix(competitorsPerComp);
  competitionsPerEvent = fix(competitionsPerEvent);

  return {
    path,
    fetchedDate: sb.day?.date ?? null,
    ok: true,
    league: {
      id: league.id ?? null,
      uid: league.uid ?? null,
      abbreviation: league.abbreviation ?? null,
      name: league.name ?? null,
      slug: league.slug ?? null,
      seasonYear: league.season?.year ?? null,
    },
    eventCount: events.length,
    observed: {
      competitionsPerEvent,
      competitorsPerComp,
      multiCompetition: competitionsPerEvent[1] > 1,
      layoutGuess: competitorsPerComp[1] > 2 ? 'field' : 'headToHead',
      scoreKindGuess: guessScoreKind(scoreSamples, competitorsPerComp[1]),
      competitorTypes: [...competitorTypes],
      hasLinescores,
      maxPeriod,
      homeAwayPresent,
      curatedRankPresent,
      hadPlayoffSeen,
      shootoutSeen,
      formatRegulation,
      statusNames: [...statusNames].sort(),
      statusStates: [...statusStates].sort(),
      seasonTypes: [...seasonTypes].sort(),
      scoreSamples,
    },
  };
}

export async function probe(path, { date, deep } = {}) {
  let url = SCOREBOARD.replace('{p}', path);
  if (date) url += `?dates=${date}`;
  let sb;
  try {
    sb = await fetchJson(url);
  } catch (e) {
    return { path, ok: false, httpStatus: e.httpStatus ?? null, error: String(e.message || e) };
  }
  const fp = fingerprint(path, sb);
  if (deep && (sb.events || []).length) {
    const id = sb.events[0].id;
    try {
      const sum = await fetchJson(SUMMARY.replace('{p}', path).replace('{id}', id));
      fp.summary = {
        eventId: id,
        topLevelKeys: Object.keys(sum).sort(),
        hasBoxscore: !!sum.boxscore,
        hasPlays: Array.isArray(sum.plays) && sum.plays.length > 0,
        hasHeader: !!sum.header,
        format: sum.format ?? sum.boxscore?.format ?? null,
        hasOdds: !!(sum.odds?.length || sum.pickcenter?.length),
      };
    } catch (e) {
      fp.summary = { eventId: id, error: String(e.message || e) };
    }
  }
  return fp;
}

// ---- CLI ----
if (import.meta.url === `file://${process.argv[1]}` || process.argv[1]?.endsWith('probe.mjs')) {
  const args = process.argv.slice(2);
  const path = args.find(a => !a.startsWith('--'));
  const date = args.includes('--date') ? args[args.indexOf('--date') + 1] : undefined;
  const deep = args.includes('--deep');
  const raw = args.includes('--raw');
  if (!path) { console.error('usage: node probe.mjs <sport>/<league> [--date YYYYMMDD] [--deep] [--raw]'); process.exit(2); }
  if (raw) {
    let url = SCOREBOARD.replace('{p}', path);
    if (date) url += `?dates=${date}`;
    console.log(JSON.stringify(await fetchJson(url), null, 2));
  } else {
    console.log(JSON.stringify(await probe(path, { date, deep }), null, 2));
  }
}

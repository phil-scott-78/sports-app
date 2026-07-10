// probe-plays-coords.mjs — which sports' CORE plays feeds carry coordinates?
// Feeds the SCHEMA.md §2b matrix (shot charts / pitch views / spray charts ride
// on this). Plays persist after finals, so any recent completed event answers —
// but in-season probes are strictly better (offseason scoreboards often carry
// only scheduled events whose feeds read count:0 → "unknown", not "no").
//
//   node schema/tools/probe-plays-coords.mjs                 # the default league set
//   node schema/tools/probe-plays-coords.mjs hockey/nhl      # one league (e.g. the October NHL re-probe)
//   node schema/tools/probe-plays-coords.mjs hockey/nhl 20261015   # + a dated scoreboard
//
// Reading results: 'coords: NONE' on a COMPLETED event with plays is a real no;
// 'plays EMPTY (count=0)' or a scheduled-only slate is INCONCLUSIVE — re-probe in
// season. Basketball's coordinate sentinel -214748340 means "no coord on this
// play" (filter |x| < 200 before trusting ranges). After a positive probe,
// CALIBRATE orientation from known-location events (SCHEMA.md §2b) before
// building anything on the feed.

const DEFAULT_LEAGUES = [
  'basketball/nba', 'basketball/wnba', 'basketball/mens-college-basketball',
  'hockey/nhl', 'football/nfl', 'football/college-football',
  'baseball/mlb', 'soccer/fifa.world', 'soccer/eng.1',
  'rugby/267979', 'rugby-league/3', 'lacrosse/pll',
  'australian-football/afl',
];

const [, , argLeague, argDate] = process.argv;
const leagues = argLeague ? [argLeague] : DEFAULT_LEAGUES;

const j = async (u) => {
  const r = await fetch(u);
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  return r.json();
};
const corePath = (k) => k.replace('/', '/leagues/');

for (const key of leagues) {
  const pad = key.padEnd(40);
  try {
    const sb = await j(`https://site.api.espn.com/apis/site/v2/sports/${key}/scoreboard${argDate ? `?dates=${argDate}` : ''}`);
    const evs = sb.events || [];
    const ev = evs.find((e) => ['post', 'in'].includes(e.competitions?.[0]?.status?.type?.state)) || evs[0];
    if (!ev) { console.log(`${pad} — no events on scoreboard (INCONCLUSIVE: try a dated in-season slate)`); continue; }
    const comp = ev.competitions[0];
    const state = comp.status?.type?.state;
    let feed;
    try {
      feed = await j(`https://sports.core.api.espn.com/v2/sports/${corePath(key)}/events/${ev.id}/competitions/${comp.id || ev.id}/plays?limit=100`);
    } catch (e) {
      console.log(`${pad} plays: ${e.message} (${ev.shortName}, ${state})`);
      continue;
    }
    const items = feed.items || [];
    if (!items.length) {
      console.log(`${pad} plays EMPTY (count=${feed.count ?? '?'}) — ${state === 'post' ? 'real no?' : 'INCONCLUSIVE (event not played)'} (${ev.shortName}, ${state})`);
      continue;
    }
    const keys = new Set();
    for (const p of items) for (const k of Object.keys(p)) keys.add(k);
    const coordKeys = [...keys].filter((k) => /coordinate|fieldPosition/i.test(k));
    // A sample carrying a real (non-sentinel) value, if any.
    const sane = (v) => v != null && (typeof v !== 'object' || Object.values(v).every((n) => typeof n !== 'number' || Math.abs(n) < 10000));
    const sample = items.find((p) => coordKeys.some((k) => sane(p[k])));
    const detail = sample
      ? coordKeys.map((k) => `${k}=${JSON.stringify(sample[k])}`).join(' ').slice(0, 100)
      : coordKeys.length ? '(keys present, only sentinel values in sample)' : '';
    console.log(`${pad} plays: ${feed.count ?? items.length} | coords: ${coordKeys.length ? coordKeys.join(',') : 'NONE'} ${detail ? '| ' + detail : ''} (${ev.shortName}, ${state})`);
  } catch (e) {
    console.log(`${pad} scoreboard: ${e.message}`);
  }
}

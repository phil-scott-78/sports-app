// Standings normalizer. ESPN nests entries under children[] (conferences/groups/
// divisions); we flatten to { groups: [{ name, rows: [{ rank, team, stats }] }] }.
// Stat keys vary by sport (handled generically: name → displayValue map).
// Racing (VERIFIED 2026-07): the same path serves championship tables — F1 =
// Driver Standings (ATHLETE-shaped entries) + Constructor Standings, NASCAR =
// one flat athlete-shaped group. Athlete entries normalize into the same `team`
// slot (name, no logo) so the client renders one table shape.

const https = u => (typeof u === 'string' ? u.replace(/^http:/, 'https:') : undefined);

// Dark-mode logo: explicit ESPN 'dark' rel when present, else derived from the
// team-logo CDN path. Client falls back to the light logo on 404.
function darkLogoOf(team) {
  const ls = team?.logos;
  if (Array.isArray(ls)) {
    const d = ls.find(l => (l.rel || []).includes('dark') && !(l.rel || []).includes('scoreboard'))
      || ls.find(l => (l.rel || []).includes('dark'));
    if (d?.href) return https(d.href);
  }
  const light = https(ls?.[0]?.href);
  return (light && light.includes('/i/teamlogos/') && light.includes('/500/'))
    ? light.replace('/500/', '/500-dark/')
    : undefined;
}

// L10 + division/conference sub-records (§2.8) are NOT on the site standings — they
// ride the CORE group standings-id doc. Map ESPN's record `type` → the canonical
// column key the app merges into the row's stats. Anything else (total/leaguestandings/
// intradivision/…) is ignored — we surface only what a US-league table shows.
// Two record-type vocabularies show up depending on the group level the doc is
// keyed at: a CONFERENCE-level group (NBA/WNBA) emits vsdiv/vsconf; a LEAGUE-level
// group (MLB AL/NL) emits intradivision/intraleague for the same idea. Both fold
// onto div/conf. (VERIFIED live 2026-07: MLB=intradivision/intraleague,
// WNBA=vsdiv/vsconf.)
const SUBRECORD_TYPES = {
  lasttengames: 'l10',
  vsdiv: 'div',
  intradivision: 'div',
  vsconf: 'conf',
  intraleague: 'conf',
  home: 'home',
  road: 'away',
};

// team id from a `.../teams/{id}?...` (or `.../teams/{id}/...`) $ref.
function teamIdFromRef(ref) {
  if (typeof ref !== 'string') return undefined;
  const m = /\/teams\/(\d+)/.exec(ref);
  return m ? m[1] : undefined;
}

// One or more CORE group standings-id docs → { teamId: { l10, div, conf, home, away } }.
// Each doc: standings[] with team.$ref + records[] (type + summary '4-6'). Pure; a
// malformed/empty input yields {}. Later docs win on a duplicate team (dedupe by id).
export function extractGroupRecords(docs) {
  const out = {};
  const list = Array.isArray(docs) ? docs : (docs ? [docs] : []);
  for (const doc of list) {
    const standings = doc?.standings;
    if (!Array.isArray(standings)) continue;
    for (const s of standings) {
      const id = teamIdFromRef(s?.team?.$ref);
      if (!id) continue;
      const bag = out[id] || (out[id] = {});
      for (const rec of Array.isArray(s?.records) ? s.records : []) {
        const key = SUBRECORD_TYPES[rec?.type];
        if (!key) continue;
        const summary = rec?.summary ?? rec?.displayValue;
        if (summary != null && summary !== '') bag[key] = String(summary);
      }
    }
  }
  return out;
}

// `records` (optional) = the extractGroupRecords() map; when passed, each row's stats
// gets its team's sub-records merged in (l10/div/conf/home/away). Omit it → the site
// standings shape, byte-identical to before (every existing golden unchanged).
export function normalizeStandings(raw, records) {
  const groups = [];
  const recs = records && typeof records === 'object' ? records : null;
  const walk = node => {
    const entries = node?.standings?.entries;
    if (Array.isArray(entries) && entries.length) {
      groups.push({
        name: node.name || node.abbreviation || node.displayName || '',
        rows: entries.map(en => {
          const stats = {};
          for (const s of en.stats || []) {
            const k = s.name || s.type;
            if (k) stats[k] = s.displayValue ?? s.value;
          }
          const who = en.team || en.athlete; // racing: driver championships are athlete-shaped
          const id = String(who?.id ?? '');
          if (recs && recs[id]) for (const [k, v] of Object.entries(recs[id])) stats[k] = v;
          return {
            team: {
              id,
              name: who?.displayName || who?.name || who?.shortDisplayName || '',
              abbr: who?.abbreviation,
              logo: https(who?.logos?.[0]?.href),
              logoDark: darkLogoOf(who),
            },
            rank: stats.rank != null ? Number(stats.rank) : undefined,
            stats,
          };
        }),
      });
    }
    for (const child of node?.children || []) walk(child);
  };
  walk(raw);
  return groups;
}

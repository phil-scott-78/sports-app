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

export function normalizeStandings(raw) {
  const groups = [];
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
          return {
            team: {
              id: String(who?.id ?? ''),
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

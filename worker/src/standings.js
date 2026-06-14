// Standings normalizer. ESPN nests entries under children[] (conferences/groups/
// divisions); we flatten to { groups: [{ name, rows: [{ rank, team, stats }] }] }.
// Stat keys vary by sport (handled generically: name → displayValue map).

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
          return {
            team: {
              id: String(en.team?.id ?? ''),
              name: en.team?.displayName || en.team?.name || '',
              abbr: en.team?.abbreviation,
              logo: https(en.team?.logos?.[0]?.href),
              logoDark: darkLogoOf(en.team),
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

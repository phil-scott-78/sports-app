// rankings.js — ESPN college polls (AP / Coaches / CFP) → a compact Top-25 list.
// Pure (no I/O). Distinct from the per-team curatedRank we already surface inline
// on the scoreboard: this is the standalone "who's #1 this week" list for the
// college league-detail page. The payload is unusually clean — ESPN pre-renders
// the trend delta ('+8' / '-') and record — so the normalizer stays trivial.

const https = u => (typeof u === 'string' ? u.replace(/^http:/, 'https:') : undefined);
const pick = (o, keys) => Object.fromEntries(keys.filter(k => o[k] != null && o[k] !== '').map(k => [k, o[k]]));

// Dark-mode logo: explicit ESPN 'dark' rel when present, else derived from the
// team-logo CDN path (matches standings.js). Client falls back to light on 404.
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

function teamOf(t = {}) {
  const logo = https(t.logos?.[0]?.href || t.logo);
  const name = t.displayName
    || [t.location, t.name].filter(Boolean).join(' ')
    || t.nickname || t.shortDisplayName || t.abbreviation || '';
  return pick({
    id: String(t.id ?? ''),
    name,
    abbr: t.abbreviation,
    logo,
    logoDark: darkLogoOf(t),
    color: t.color,
  }, ['id', 'name', 'abbr', 'logo', 'logoDark', 'color']);
}

export function normalizeRankings(raw) {
  const polls = (raw?.rankings || []).map(p => ({
    name: p.name || p.shortName || '',
    shortName: p.shortName || p.name || '',
    occurrence: p.occurrence?.displayValue || p.shortHeadline || p.headline || '',
    ranks: (p.ranks || []).slice(0, 25).map(r => pick({
      current: typeof r.current === 'number' ? r.current : undefined,
      previous: typeof r.previous === 'number' ? r.previous : undefined,
      trend: r.trend,                 // ESPN pre-renders '+8' / '-2' / '-'
      record: r.recordSummary,        // '16-0'
      team: teamOf(r.team),
    }, ['current', 'previous', 'trend', 'record', 'team'])),
  })).filter(p => p.ranks.length);
  return { polls };
}

// rankings.js — ESPN rankings → a compact list. Pure (no I/O). One site endpoint
// serves three feeds (VERIFIED 2026-07): college polls (AP/Coaches/CFP,
// team-based), ATP/WTA world rankings (athlete-based, points, 150 deep — capped
// here), and UFC divisional/P4P lists (athlete-based, recordSummary +
// hasAccolade champion flag). Distinct from the per-team curatedRank we already
// surface inline on the scoreboard. The payload is unusually clean — ESPN
// pre-renders the trend delta ('+8' / '-') — so the normalizer stays trivial.
// Entries carry EITHER `team` OR `athlete`, never both (see canonical.ts).

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

function athleteOf(a = {}) {
  return pick({
    id: String(a.id ?? ''),
    name: a.displayName || a.shortname || a.fullName || '',
    country: a.flag?.alt || a.citizenship,
    headshot: https(a.headshot?.href || a.headshot),
  }, ['id', 'name', 'country', 'headshot']);
}

export function normalizeRankings(raw) {
  // occurrence is a SHORT caption ('Week 5' / 'Final Rankings'); UFC's
  // headline/shortHeadline are prose sentences — never ship those.
  const occOf = p => {
    const o = p.occurrence?.displayValue || p.shortHeadline || '';
    return o.length <= 40 ? o : '';
  };
  const polls = (raw?.rankings || []).map(p => ({
    name: p.name || p.shortName || '',
    shortName: p.shortName || p.name || '',
    occurrence: occOf(p),
    ranks: (p.ranks || []).slice(0, 25).map(r => {
      const e = pick({
        current: typeof r.current === 'number' ? r.current : undefined,
        previous: typeof r.previous === 'number' ? r.previous : undefined,
        trend: r.trend,                 // ESPN pre-renders '+8' / '-2' / '-'
        record: r.recordSummary,        // '16-0' / MMA '21-4-0'
        points: typeof r.points === 'number' ? r.points : undefined, // tennis
        champion: r.hasAccolade === true ? true : undefined,         // MMA belt
      }, ['current', 'previous', 'trend', 'record', 'points', 'champion']);
      if (r.team) e.team = teamOf(r.team);
      else if (r.athlete) e.athlete = athleteOf(r.athlete);
      return e;
    }).filter(e => e.team?.name || e.athlete?.name),
  })).filter(p => p.ranks.length);
  return { polls };
}

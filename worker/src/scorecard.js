// scorecard.js — golf hole-by-hole player summary → canonical
// GolfScorecardResponse (see canonical.ts). Pure (no I/O); the raw payload is
// the web-host `leaderboard/{event}/playersummary` (VERIFIED 2026-07):
//   profile — id/displayName/headshot(url string)/…
//   rounds[] — per round: value(strokes)/displayValue(to-par)/inScore/outScore/
//              teeTime/startTee/groupNumber/currentPosition + linescores[] per
//              hole {period, value, par, scoreType{name}}. Future rounds ship
//              teeTime with no holes — that IS the pre-start glance.
//   stats[] — tournament stat line; we keep a small curated subset.

import { https } from './normalize.js';

const pick = (o, keys) => Object.fromEntries(keys.filter(k => o[k] != null && o[k] !== '').map(k => [k, o[k]]));

// The glanceable tournament stats — everything else (strokes gained tables etc.)
// is analyst depth the product excludes.
const STAT_KEEP = new Set([
  'scoreToPar', 'regScore', 'birdies', 'eagles',
  'driveDistAvg', 'driveAccuracyPct', 'greensInRegulationPct', 'puttsPerHole',
]);

export function normalizeGolfScorecard(key, eventId, playerId, raw) {
  const prof = raw?.profile || {};
  const player = pick({
    id: String(prof.id ?? playerId),
    name: prof.displayName || prof.shortName || '',
    headshot: https(prof.headshot?.href || prof.headshot),
    country: prof.flag?.alt || prof.citizenship,
  }, ['id', 'name', 'headshot', 'country']);

  const rounds = (Array.isArray(raw?.rounds) ? raw.rounds : []).map(r => {
    const holes = (Array.isArray(r.linescores) ? r.linescores : []).map(h => pick({
      hole: typeof h.period === 'number' ? h.period : undefined,
      par: typeof h.par === 'number' ? h.par : undefined,
      strokes: typeof h.value === 'number' ? h.value : undefined,
      scoreType: h.scoreType?.name, // 'BIRDIE' | 'PAR' | 'BOGEY' …
    }, ['hole', 'par', 'strokes', 'scoreType'])).filter(h => h.hole != null);
    const round = pick({
      round: typeof r.period === 'number' ? r.period : undefined,
      strokes: typeof r.value === 'number' && r.value > 0 ? r.value : undefined,
      toPar: r.displayValue != null && r.displayValue !== '-' ? String(r.displayValue) : undefined,
      outScore: typeof r.outScore === 'number' && r.outScore > 0 ? r.outScore : undefined,
      inScore: typeof r.inScore === 'number' && r.inScore > 0 ? r.inScore : undefined,
      teeTime: r.teeTime,
      startTee: typeof r.startTee === 'number' ? r.startTee : undefined,
      groupNumber: typeof r.groupNumber === 'number' ? r.groupNumber : undefined,
      currentPosition: typeof r.currentPosition === 'number' ? r.currentPosition : undefined,
    }, ['round', 'strokes', 'toPar', 'outScore', 'inScore', 'teeTime', 'startTee', 'groupNumber', 'currentPosition']);
    round.holes = holes; // [] pre-round, per contract
    return round;
  }).filter(r => r.round != null);

  const stats = (Array.isArray(raw?.stats) ? raw.stats : [])
    .filter(s => STAT_KEEP.has(s.name) && s.displayValue != null && s.displayValue !== '')
    .map(s => ({ name: s.name, label: s.displayName || s.name, value: String(s.displayValue) }));

  const out = { league: key, eventId: String(eventId), player, rounds };
  if (stats.length) out.stats = stats;
  return out;
}

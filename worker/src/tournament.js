// tournament.js — raw (range) scoreboard(s) + optional league standings →
// canonical TournamentResponse (schema/canonical.ts §Tournament, spec §2.7).
// Pure map→map, no I/O — the golden-parity ORACLE for the Dart port
// (app/lib/src/data/tournament.dart). Behavior is driven by data presence and
// the resolved profile's discriminators, never by sport name:
//   • events with groupings[] (tennis)      → ONE event is the tournament; its
//     grouping's competitions are the draw (round.displayName is the label).
//   • a standings doc passed in             → group tables (+ qualification note).
//   • competitions with a series block      → the championship best-of-N.
//   • labels reading 'Elimination'/'advances to' → double-elim POOL games,
//     reconstructed into pool standings (no ESPN standings doc exists for CWS).
//   • everything else with a round label    → rounds[] buckets.
// Unknown labels become a pass-through bucket (round: null) — never a crash.

import { resolve } from '../../schema/tools/resolve.mjs';
import { statusToPhase } from './normalize.js';
import { normalizeStandings } from './standings.js';

const pick = (o, keys) => Object.fromEntries(keys.filter(k => o[k] != null).map(k => [k, o[k]]));

// ---- round classification -----------------------------------------------------
// One canonical key from any of the three observed label vocabularies. Checked in
// specificity order ('Qualifying Final' is qualifying, not final; 'NCAA …
// Championship - First Round' resolves on the LAST classifiable ' - ' segment).
// Returns a canonical key, 'pool' (double-elim pool game), or null (unknown).
export function classifyRound(label) {
  const s = String(label == null ? '' : label);
  if (!s) return null;
  if (/elimination|advances to/i.test(s)) return 'pool';
  if (/qualif/i.test(s)) return 'qualifying';
  if (/group|league phase/i.test(s)) return 'group';
  const ro = s.match(/round of (\d+)/i);
  if (ro) return roundOfKey(+ro[1]);
  if (/sweet (16|sixteen)/i.test(s)) return 'roundOf16';
  if (/elite (8|eight)/i.test(s)) return 'quarterfinal';
  if (/final four/i.test(s)) return 'semifinal';
  if (/quarter/i.test(s)) return 'quarterfinal';
  if (/semi/i.test(s)) return 'semifinal';
  if (/third place|3rd place|bronze/i.test(s)) return 'thirdPlace';
  if (/\bfinals?\b|championship/i.test(s)) return 'final';
  return null;
}

function roundOfKey(n) {
  if (n === 2) return 'final';
  if (n === 4) return 'semifinal';
  if (n === 8) return 'quarterfinal';
  if (n === 16 || n === 32 || n === 64 || n === 128) return `roundOf${n}`;
  return null;
}

// Ordinal round number in a segment ('1st Round', 'Round 2', 'First Round') →
// { n, rest } where rest is the segment minus the round words (a region/bracket
// tag like 'East'), or null when the segment carries no ordinal round.
const WORD_ORDINALS = { first: 1, second: 2, third: 3, fourth: 4, fifth: 5, sixth: 6 };
export function ordinalRound(seg) {
  const s = String(seg == null ? '' : seg);
  let m = s.match(/(\d+)(?:st|nd|rd|th)\s+round\b/i);
  if (!m) {
    const w = s.match(/\b(first|second|third|fourth|fifth|sixth)\s+round\b/i);
    if (w) m = [w[0], String(WORD_ORDINALS[w[1].toLowerCase()])];
  }
  if (!m) {
    const r = s.match(/\bround\s+(\d+)\b/i);
    if (r) m = [r[0], r[1]];
  }
  if (!m) return null;
  const rest = s.replace(m[0], ' ').replace(/\s+/g, ' ').trim();
  return { n: parseInt(m[1], 10), rest };
}

// ---- label parsing --------------------------------------------------------------
// A cleaned label (tournament-title prefix already stripped) → its round bucket.
// Segments split on ' - '; 'Game N' is lifted out; the LAST classifiable segment
// names the round; leftover segments (region / 'Group A') become the bracket tag.
function parseLabel(cleaned) {
  const out = { key: null, roundLabel: '', bracket: undefined, gameNumber: undefined, ordinal: undefined };
  let s = String(cleaned == null ? '' : cleaned).trim();
  const gm = s.match(/[\s\-–]*\bgame\s+(\d+)\b/i);
  if (gm) { out.gameNumber = parseInt(gm[1], 10); s = s.replace(gm[0], ' ').replace(/\s+/g, ' ').trim(); }
  s = s.replace(/[\s,\-–]+$/, '');
  if (!s) return out;
  const segs = s.split(' - ').map(x => x.trim()).filter(Boolean);
  const leftovers = [];
  for (const seg of segs) {
    const k = classifyRound(seg);
    if (k != null) { out.key = k; out.roundLabel = seg; out.ordinal = undefined; continue; }
    const ord = ordinalRound(seg);
    if (ord) {
      // ordinal round, possibly with an inline region ('East 1st Round')
      out.key = null;
      out.ordinal = ord.n;
      out.roundLabel = ord.rest ? seg.replace(ord.rest, ' ').replace(/\s+/g, ' ').trim() : seg;
      if (ord.rest) leftovers.unshift(ord.rest);
      continue;
    }
    leftovers.push(seg);
  }
  if (out.key === 'group') out.bracket = out.roundLabel;           // 'Group A' IS the tag
  else if (leftovers.length) out.bracket = leftovers[0];
  if (!out.roundLabel) out.roundLabel = s;
  return out;
}

// Longest common ' '-safe prefix over labels — the tournament name shared by every
// event's headline ("Men's College World Series - …"). Cut back to a word
// boundary, trim trailing separators; '' when <2 labels or too short to trust.
export function commonLabelPrefix(labels) {
  const list = labels.filter(l => typeof l === 'string' && l.length);
  if (list.length < 2) return '';
  let p = list[0];
  for (const l of list.slice(1)) {
    let i = 0;
    while (i < p.length && i < l.length && p[i] === l[i]) i++;
    p = p.slice(0, i);
    if (!p) return '';
  }
  // never cut mid-word: if any label continues with a non-space, back up to the last space
  if (/\S$/.test(p) && list.some(l => l.length > p.length && /\S/.test(l[p.length]))) {
    const sp = p.lastIndexOf(' ');
    p = sp < 0 ? '' : p.slice(0, sp);
  }
  p = p.replace(/[\s,\-–:]+$/, '');
  return p.length >= 8 ? p : '';
}

const stripPrefix = (label, prefix) => {
  const s = String(label == null ? '' : label);
  if (!prefix || !s.toLowerCase().startsWith(prefix.toLowerCase())) return s.trim();
  return s.slice(prefix.length).replace(/^[\s,\-–:]+/, '').trim();
};

// ---- matchup building -----------------------------------------------------------
const scoreDisplay = raw => {
  if (raw != null && typeof raw === 'object') raw = raw.displayValue ?? raw.value ?? '';
  return raw == null ? '' : String(raw);
};

function buildSide(profile, raw, phase) {
  const team = raw.team;
  const ath = raw.athlete;
  const roster = raw.roster;
  const side = {
    id: String(raw.id ?? team?.id ?? ath?.id ?? ''),
    name: team?.displayName || ath?.displayName || roster?.displayName || team?.name || team?.shortDisplayName || '',
  };
  const short = ath?.shortName || roster?.shortDisplayName || team?.shortDisplayName;
  if (short) side.shortName = short;
  if (team?.abbreviation) side.abbr = team.abbreviation;
  if (raw.homeAway) side.homeAway = raw.homeAway;
  // seed: ONLY where curatedRank IS the seed — athlete draws (tennis). For team
  // sports curatedRank is a poll rank (basketball seeds = core tournamentMatchup,
  // a documented hook we never fan out here).
  if (profile.competitorKind === 'athlete') {
    const cr = raw.curatedRank?.current;
    if (cr != null && cr !== 99) side.seed = cr;
  }
  if (raw.winner === true) side.winner = true;
  if (raw.score != null && phase !== 'scheduled') {
    const d = scoreDisplay(raw.score);
    if (d !== '') side.score = d;
  }
  if (raw.shootoutScore != null) side.shootout = raw.shootoutScore;
  if (Array.isArray(raw.linescores) && raw.linescores.length) {
    side.sets = raw.linescores.map(ls => pick({
      value: ls?.value, tiebreak: ls?.tiebreak, winner: ls?.winner,
    }, ['value', 'tiebreak', 'winner']));
  }
  return side;
}

function buildMatchup(profile, ev, rc, parsed, usedHeadline) {
  const ph = statusToPhase(rc.status?.type || ev.status?.type || {});
  const m = { eventId: String(ev.id) };
  if (rc.id != null && String(rc.id) !== String(ev.id)) m.competitionId = String(rc.id);
  const date = rc.date || ev.date;
  if (date) m.date = date;
  m.phase = ph.phase;
  if (ph.live) m.live = true;
  const head = (rc.notes || []).map(n => n?.headline).filter(Boolean)[0];
  if (head && head !== usedHeadline) m.note = head;
  if (parsed.gameNumber != null) m.gameNumber = parsed.gameNumber;
  if (parsed.bracket) m.bracket = parsed.bracket;
  m.competitors = (rc.competitors || []).map(c => buildSide(profile, c, ph.phase));
  return m;
}

const dateMs = m => { const t = Date.parse(m.date || ''); return Number.isNaN(t) ? Infinity : t; };
const matchupRef = m => m.competitionId || m.eventId;
// deterministic order: date, then id (stable across JS/Dart sort implementations)
const byDate = (a, b) => dateMs(a) - dateMs(b) || (matchupRef(a) < matchupRef(b) ? -1 : matchupRef(a) > matchupRef(b) ? 1 : 0);

// ---- pools (CWS double-elim reconstruction) --------------------------------------
// No ESPN standings doc exists for the CWS pools — split the non-series events into
// pools by TEAM CONNECTIVITY (who played whom), count pool W–L, and derive status:
// 2 pool losses → eliminated; a championship-series participant or the winner of an
// '… advances to Championship …' game → advances; else alive.
function buildPools(items, seriesTeamIds) {
  if (!items.length) return [];
  const games = items.map(({ ev, rc, parsed }) => {
    const ph = statusToPhase(rc.status?.type || {});
    const head = (rc.notes || []).map(n => n?.headline).filter(Boolean)[0] || '';
    return {
      eventId: String(ev.id), date: rc.date || ev.date, phase: ph.phase, headline: head,
      gameNumber: parsed.gameNumber,
      sides: (rc.competitors || []).map(c => ({
        id: String(c.id ?? c.team?.id ?? ''),
        name: c.team?.displayName || c.team?.name || '',
        abbr: c.team?.abbreviation,
        winner: c.winner === true,
      })),
    };
  }).sort((a, b) => (dateMs(a) - dateMs(b)) || (a.eventId < b.eventId ? -1 : 1));

  // connectivity: union teams that met
  const parent = {};
  const find = x => (parent[x] === x ? x : (parent[x] = find(parent[x])));
  const union = (a, b) => { parent[find(a)] = find(b); };
  const teams = {};
  for (const g of games) {
    for (const s of g.sides) {
      if (!s.id) continue;
      parent[s.id] ??= s.id;
      if (!teams[s.id]) teams[s.id] = { id: s.id, name: s.name, abbr: s.abbr, w: 0, l: 0, advances: false };
      if (s.name && !teams[s.id].name) teams[s.id].name = s.name;
      if (s.abbr && !teams[s.id].abbr) teams[s.id].abbr = s.abbr;
    }
    const ids = g.sides.map(s => s.id).filter(Boolean);
    for (let i = 1; i < ids.length; i++) union(ids[0], ids[i]);
    if (g.phase === 'final') {
      for (const s of g.sides) {
        if (!s.id) continue;
        if (s.winner) { teams[s.id].w++; if (/advances to/i.test(g.headline)) teams[s.id].advances = true; }
        else teams[s.id].l++;
      }
    }
  }
  // components → pools, ordered by each pool's earliest game
  const compOf = {};
  const order = [];
  for (const g of games) {
    const id = g.sides.map(s => s.id).find(Boolean);
    if (!id) continue;
    const root = find(id);
    if (compOf[root] == null) { compOf[root] = order.length; order.push(root); }
  }
  const pools = order.map(() => []);
  for (const t of Object.values(teams)) pools[compOf[find(t.id)]].push(t);
  return pools.filter(p => p.length > 1).map((p, i) => ({
    label: `Bracket ${i + 1}`,
    rows: p
      .map(t => ({
        team: pick({ id: t.id, name: t.name, abbr: t.abbr }, ['id', 'name', 'abbr']),
        w: t.w, l: t.l,
        status: t.l >= 2 ? 'eliminated' : (t.advances || seriesTeamIds.has(t.id)) ? 'advances' : 'alive',
      }))
      .sort((a, b) => {
        const rank = r => (r.status === 'advances' ? 0 : r.status === 'alive' ? 1 : 2);
        return rank(a) - rank(b) || b.w - a.w || a.l - b.l
          || (a.team.name < b.team.name ? -1 : a.team.name > b.team.name ? 1 : 0);
      }),
  }));
}

// ---- series (championship best-of-N) ----------------------------------------------
// From the scoreboard `series` block (VERIFIED: rides every CWS finals event; the
// latest game's block carries the current wins/completed state). When several
// distinct series appear in the window, keep the LATEST — the championship.
function buildSeries(items) {
  if (!items.length) return undefined;
  const groups = new Map(); // sorted competitor ids → items
  for (const it of items) {
    const ids = (it.rc.series.competitors || []).map(c => String(c.id ?? '')).sort().join('|');
    if (!groups.has(ids)) groups.set(ids, []);
    groups.get(ids).push(it);
  }
  let best = null, bestMs = -Infinity;
  for (const list of groups.values()) {
    const ms = Math.max(...list.map(it => { const t = Date.parse(it.rc.date || it.ev.date || ''); return Number.isNaN(t) ? 0 : t; }));
    if (ms > bestMs) { bestMs = ms; best = list; }
  }
  const games = best.map(({ ev, rc, parsed }) => {
    const ph = statusToPhase(rc.status?.type || {});
    const g = { eventId: String(ev.id) };
    const date = rc.date || ev.date;
    if (date) g.date = date;
    g.phase = ph.phase;
    if (parsed.gameNumber != null) g.gameNumber = parsed.gameNumber;
    g.sides = (rc.competitors || []).map(c => pick({
      id: String(c.id ?? c.team?.id ?? ''),
      abbr: c.team?.abbreviation,
      score: ph.phase === 'scheduled' ? undefined : (scoreDisplay(c.score) || undefined),
      winner: c.winner === true ? true : undefined,
    }, ['id', 'abbr', 'score', 'winner']));
    return g;
  }).sort((a, b) => (a.gameNumber ?? 0) - (b.gameNumber ?? 0) || dateMs(a) - dateMs(b));
  const last = best.reduce((x, y) => (Date.parse(y.rc.date || y.ev.date || '') || 0) >= (Date.parse(x.rc.date || x.ev.date || '') || 0) ? y : x);
  const sr = last.rc.series;
  // name/abbr join from the latest game's competitor rows
  const meta = {};
  for (const c of (last.rc.competitors || [])) {
    meta[String(c.id ?? c.team?.id ?? '')] = { name: c.team?.displayName || c.team?.name, abbr: c.team?.abbreviation };
  }
  // title: the common cleaned game label ('Championship Final'), else ESPN's series.title
  const labels = [...new Set(best.map(it => it.parsed.roundLabel).filter(Boolean))];
  const title = labels.length === 1 ? labels[0] : (commonLabelPrefix(labels) || sr.title);
  const out = pick({
    title: title || undefined,
    total: typeof sr.totalCompetitions === 'number' ? sr.totalCompetitions : undefined,
    completed: typeof sr.completed === 'boolean' ? sr.completed : undefined,
  }, ['title', 'total', 'completed']);
  out.competitors = (sr.competitors || []).map(c => pick({
    id: String(c.id ?? ''),
    name: meta[String(c.id ?? '')]?.name,
    abbr: meta[String(c.id ?? '')]?.abbr,
    wins: Number(c.wins) || 0,
  }, ['id', 'name', 'abbr', 'wins']));
  out.games = games;
  return out;
}

// ---- groups (round-robin tables) ---------------------------------------------------
// EXACTLY the rows the standings renderer consumes — normalizeStandings already
// carries the soccer qualification note {color, description} on each row.
export function buildTournamentGroups(standingsRaw) {
  if (!standingsRaw) return [];
  return normalizeStandings(standingsRaw).map(g => ({ label: g.name, rows: g.rows }));
}

// ---- top level ----------------------------------------------------------------------
// input: { scoreboards: [raw…] | scoreboard: raw, standings?: raw, grouping?: slug,
//          eventId?: id }. Range chunks merge; events dedupe by id (later wins).
export function normalizeTournament(reg, key, input = {}) {
  const profile = resolve(reg, key);
  const raws = Array.isArray(input.scoreboards) ? input.scoreboards
    : (input.scoreboard ? [input.scoreboard] : []);
  const evMap = new Map();
  let league = null;
  for (const sbRaw of raws) {
    if (!league && Array.isArray(sbRaw?.leagues) && sbRaw.leagues[0]) league = sbRaw.leagues[0];
    for (const e of (sbRaw?.events || [])) if (e && e.id != null) evMap.set(String(e.id), e);
  }
  const events = [...evMap.values()];

  // ---- pick the item list + title/subtitle -----------------------------------
  // Draw mode (events[].groupings — tennis): ONE event is the tournament; prefer
  // an explicit eventId, else the slam (major==true), else the first. One grouping
  // (draw) at a time — explicit slug, else the first.
  const drawEvents = events.filter(e => Array.isArray(e.groupings) && e.groupings.length);
  let items = []; // { ev, rc }
  let title = '', subtitle;
  if (drawEvents.length) {
    const ev = (input.eventId != null && drawEvents.find(e => String(e.id) === String(input.eventId)))
      || drawEvents.find(e => e.major === true) || drawEvents[0];
    title = ev.name || ev.shortName || '';
    const gs = ev.groupings;
    const g = (input.grouping && gs.find(x => x?.grouping?.slug === input.grouping)) || gs[0];
    subtitle = g?.grouping?.displayName || undefined;
    for (const rc of (g?.competitions || [])) items.push({ ev, rc });
  } else {
    for (const e of events) for (const rc of (e.competitions || [])) items.push({ ev: e, rc });
    // title: the common headline prefix every event shares ("Men's College World
    // Series"), else the league name off the payload, else the registry name.
    const heads = events.map(e => (e.competitions?.[0]?.notes || []).map(n => n?.headline).filter(Boolean)[0]);
    title = commonLabelPrefix(heads.filter(Boolean)) || league?.name || profile.name || '';
  }

  // ---- label each item ---------------------------------------------------------
  for (const it of items) {
    const rc = it.rc;
    const candidates = [
      rc.round?.displayName,
      ...(rc.notes || []).map(n => n?.headline),
      rc.altGameNote,
      rc.series?.title,
    ].filter(l => typeof l === 'string' && l.trim());
    it.rawLabel = '';
    it.usedHeadline = undefined;
    for (const cand of candidates) {
      const cleaned = stripPrefix(cand, title);
      const parsed = parseLabel(cleaned);
      if (parsed.key != null || parsed.ordinal != null) {
        it.rawLabel = cand; it.parsed = parsed;
        // structured draw source? round.displayName rides a PRE-CREATED complete
        // draw (tennis) — the only source where bucket size == round size.
        it.fromRound = cand === rc.round?.displayName;
        if ((rc.notes || []).some(n => n?.headline === cand)) it.usedHeadline = cand;
        break;
      }
    }
    if (!it.parsed) {
      const fallback = rc.altGameNote || (rc.notes || []).map(n => n?.headline).filter(Boolean)[0] || '';
      it.rawLabel = fallback;
      it.parsed = parseLabel(stripPrefix(fallback, title));
    }
  }

  // ---- route: series / pools / rounds ------------------------------------------
  const seriesItems = items.filter(it => {
    const sr = it.rc.series;
    return sr && Array.isArray(sr.competitors) && sr.competitors.length
      && typeof sr.totalCompetitions === 'number' && sr.totalCompetitions > 1;
  });
  const seriesSet = new Set(seriesItems);
  const poolItems = items.filter(it => !seriesSet.has(it) && it.parsed.key === 'pool');
  const roundItems = items.filter(it => !seriesSet.has(it) && it.parsed.key !== 'pool');

  const series = buildSeries(seriesItems);
  const seriesTeamIds = new Set((series?.competitors || []).map(c => c.id));
  const pools = buildPools(poolItems.map(it => ({ ev: it.ev, rc: it.rc, parsed: it.parsed })), seriesTeamIds);

  // rounds: bucket by (group-collapsed) round label
  const buckets = new Map(); // bucketId → { key, label, matchups, ordinal }
  for (const it of roundItems) {
    const p = it.parsed;
    const bucketId = p.key === 'group' ? '#group' : (p.roundLabel || '#unlabeled');
    if (!buckets.has(bucketId)) {
      buckets.set(bucketId, {
        key: p.key,
        label: p.key === 'group' ? 'Group Stage' : (p.roundLabel || ''),
        ordinal: p.ordinal,
        structured: true,
        matchups: [],
      });
    }
    const b = buckets.get(bucketId);
    if (!it.fromRound) b.structured = false;
    b.matchups.push(buildMatchup(profile, it.ev, it.rc, p, it.usedHeadline));
  }
  // ordinal refinement: 'Round 4' with 8 UNIQUE pairings → roundOf16. ONLY for
  // buckets sourced entirely from round.displayName (a pre-created COMPLETE draw,
  // tennis) — a headline-sourced ordinal bucket may be a PARTIAL slate (a
  // mid-window March-Madness range), where bucket size lies about round size:
  // those pass through with round: null and keep their observed label.
  for (const b of buckets.values()) {
    if (b.key != null || b.ordinal == null || !b.structured) continue;
    const pairs = b.matchups.map(m => m.competitors.map(c => c.id).filter(Boolean).sort().join('|'));
    const unique = new Set(pairs).size === pairs.length && pairs.every(Boolean);
    if (unique) b.key = roundOfKey(b.matchups.length * 2);
  }
  const rounds = [...buckets.values()].map(b => {
    b.matchups.sort(byDate);
    return { round: b.key ?? null, label: b.label, matchups: b.matchups };
  }).sort((a, b) => {
    const am = a.matchups.length ? dateMs(a.matchups[0]) : Infinity;
    const bm = b.matchups.length ? dateMs(b.matchups[0]) : Infinity;
    return am - bm || (a.label < b.label ? -1 : a.label > b.label ? 1 : 0);
  });

  // ---- cheap-path bracket linkage ----------------------------------------------
  // A DECIDED matchup links forward to the earliest later matchup IN A DIFFERENT
  // ROUND that contains its winner (real ids only) — a winner never advances
  // within its own round, so same-bucket candidates (e.g. two same-day games in a
  // partial slate) are never edges. Group/pool games never link; the 'Winner
  // E1/F2' placeholder for undecided slots is core-only → omitted (spec gap).
  const linkable = [];
  rounds.forEach((r, ri) => {
    if (r.round === 'group') return;
    for (const m of r.matchups) linkable.push({ m, ri });
  });
  for (const { m, ri } of linkable) {
    const w = m.competitors.find(c => c.winner === true);
    const wid = w && w.id && !w.id.startsWith('-') ? w.id : null;
    if (!wid || !Number.isFinite(dateMs(m))) continue;
    let best = null;
    for (const { m: n, ri: ni } of linkable) {
      if (n === m || ni === ri || !(dateMs(n) > dateMs(m))) continue;
      if (!n.competitors.some(c => c.id === wid)) continue;
      if (!best || byDate(n, best) < 0) best = n;
    }
    if (best) m.advancesTo = matchupRef(best);
  }

  // ---- assemble ------------------------------------------------------------------
  const groups = buildTournamentGroups(input.standings);
  const out = { league: key, title };
  if (subtitle) out.subtitle = subtitle;
  if (groups.length) out.groups = groups;
  if (rounds.length) out.rounds = rounds;
  if (pools.length) out.pools = pools;
  if (series) out.series = series;
  return out;
}

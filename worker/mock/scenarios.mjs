// scenarios.mjs — optional "director's cut" overlays for the offline mock. A
// scenario is a tiny, PURE policy object that synth.mjs consults (only when one is
// passed) to bend an otherwise-normal synthesized slate toward a story. synth stays
// the schedule projector; a scenario just answers two questions per league:
//   roles(profile, key, dayOffset, n) → the phase each pooled event should take
//   frame(ev, ctx)                     → light, data-level dressing (no renames)
// Everything stays deterministic on event id (never on `now`) so polling doesn't
// flicker, and nothing branches on sport NAME — same contract as synth/renderers.
//
// Ship a scenario by pointing the mock server at it: `--scenario megaweek`
// (see scripts/mock-espn-server.mjs) → `npm run mock:megaweek`.

const DAY = 86400000;

// tiny FNV-1a (same family as synth's) so day-of-week staggering is stable per key
function hashStr(s) {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619); }
  return h >>> 0;
}

/**
 * "The biggest sporting week in history." Every league is lit up LIVE right now,
 * and each one stages a Championship on a deterministic day this week — the
 * marquee (priority `v1`) leagues clustering toward tomorrow, the long tail
 * spread across the week — so browsing the schedule forward tells a story and
 * today is wall-to-wall live. Framing is intentionally LIGHT: real matchups and
 * team names are kept; only a "Championship" note + postseason flag are added
 * (flip FLAVOR on for real championship names).
 */
const MEGA_WEEK = {
  name: 'megaweek',
  minPool: 6, // guarantee a fat slate even for a single-event pool (UCL, a lone tournament)

  // Which day THIS league crowns a champion. Offset ≥1 (never today — today is for
  // live spectacle). Priority weights the spread: v1 → tomorrow/day-after; the tail
  // fans out to ~a week. Deterministic per league key → stable across polls.
  champOffset(profile, key) {
    const spread = profile.priority === 'v1' ? 2 : profile.priority === 'v2' ? 4 : 6;
    return 1 + (hashStr(`megaweek:champ:${key}`) % spread);
  },

  // Phase plan for a day's pooled events. Past → finals, future → scheduled, today →
  // mostly LIVE but always keeping ≥1 final + ≥1 scheduled so every UI state stays
  // reachable and the "final/upcoming" rails aren't empty.
  roles(profile, key, dayOffset, n) {
    if (dayOffset < 0) return Array.from({ length: n }, () => 'final');
    if (dayOffset > 0) return Array.from({ length: n }, () => 'scheduled');
    const r = Array.from({ length: n }, () => 'live');
    if (n >= 2) r[n - 1] = 'scheduled';
    if (n >= 3) r[n - 2] = 'final';
    return r;
  },

  // Light, data-level framing for the one hero of each league's champion day. Reads
  // through the SAME normalizer fields real ESPN uses: competition.notes[].headline
  // (→ meta.round, the card/detail badge), competition.headlines[] (→ the detail
  // HeadlineCard), and event.season type 3 (→ postseason labelling).
  frame(ev, { role, profile, key, dayOffset, firstOfDay }) {
    if (role !== 'scheduled' || !firstOfDay) return;      // one upcoming hero per league-day
    if (dayOffset !== this.champOffset(profile, key)) return;
    const label = FLAVOR ? (CHAMPIONSHIP_NAME[key] || 'Championship') : 'Championship';
    const c0 = ev.competitions?.[0];
    if (!c0) return;
    c0.notes = [{ type: 'event', headline: label }];
    c0.headlines = [{ shortLinkText: label, description: label }];
    c0.neutralSite = true;
    ev.season = { type: 3, slug: 'post-season' };
  },
};

// Real championship names — OFF by default (the mock keeps ESPN's real matchup
// names, per the "light framing" choice). Flip FLAVOR to true for the full opus.
const FLAVOR = false;
const CHAMPIONSHIP_NAME = {
  'football/nfl': 'Super Bowl',
  'basketball/nba': 'NBA Finals',
  'basketball/mens-college-basketball': 'National Championship',
  'basketball/womens-college-basketball': 'National Championship',
  'hockey/nhl': 'Stanley Cup Final',
  'baseball/mlb': 'World Series',
  'soccer/uefa.champions': 'Champions League Final',
  'football/college-football': 'CFP National Championship',
};

const SCENARIOS = { megaweek: MEGA_WEEK, 'greatest-week': MEGA_WEEK, 'mega-week': MEGA_WEEK };

/** Resolve a scenario by name (case-insensitive). null → normal mock behavior. */
export function getScenario(name) {
  return name ? (SCENARIOS[String(name).toLowerCase()] || null) : null;
}

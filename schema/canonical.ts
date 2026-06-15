// ============================================================================
// Canonical sports data contract  (worker output / client input)
// ----------------------------------------------------------------------------
// ONE shape for every sport. The worker normalizes ESPN's (or any provider's)
// raw JSON into this; the Flutter client only ever sees this. Swapping data
// providers must never change anything below this line.
//
// Design: a thin UNIVERSAL envelope + a small set of DISCRIMINATORS
// (`layout`, `scoreKind`, `competitorKind`) that tell a consumer how to read
// the otherwise-optional fields. Sport- and league-specific behavior lives in
// data (see league-profiles.json), not in new types.
//
// Field choices are grounded in live ESPN responses verified 2026-06. Inline
// `// VERIFIED:` / `// QUIRK:` notes capture the traps the adversarial pass
// caught (hallucinated ids, wrong status names, cumulative rugby scores, etc.).
// ============================================================================

// ---------------------------------------------------------------------------
// Discriminators
// ---------------------------------------------------------------------------

/** How a competition is shaped. */
export type Layout =
  | 'headToHead' // exactly 2 sides (soccer, football, basketball, baseball,
                 // hockey, rugby, cricket, MMA bout). Has home/away EXCEPT
                 // tennis/MMA where homeAway is present-but-meaningless.
  | 'field';     // N competitors ranked by `order` (golf leaderboard, a race).

/** How `Competitor.score` is encoded — pick the reader, don't guess. */
export type ScoreKind =
  | 'numeric'   // string→int points/goals/runs. Most team sports.
  | 'toPar'     // golf: '-10' | 'E' | '+3' (numeric total only via core API).
  | 'cricket'   // composite string '161/5 (18/20 ov, target 156)'; real
                // numbers live in periodScores[].cricket, NOT in score.value.
  | 'none';     // racing & MMA: no scalar score. Outcome = order / winner+method.

/** What a competitor IS. */
export type CompetitorKind =
  | 'team'     // club/national side.
  | 'athlete'  // one person (tennis singles, golfer, driver, fighter).
  | 'pair';    // two people as one entry (tennis/golf doubles). QUIRK: ESPN
               // models this as competitor.type='team' with roster.athletes[].

/** Period unit. Drives how `period` integers are labeled. */
export type PeriodUnit =
  | 'half' | 'quarter' | 'period' | 'inning' | 'set' | 'round' | 'lap'
  | 'over_innings' /* cricket */ | 'hole_rounds' /* golf */ | 'none';

/** Normalized lifecycle. Branch on this, never on raw status strings. */
export type Phase =
  | 'scheduled'
  | 'live'
  | 'final'      // decisive, completed===true
  | 'postponed'
  | 'suspended'  // incl. cricket multi-day "Stumps", rain delay, red flag
  | 'canceled'
  | 'abandoned'
  | 'delayed'
  | 'unknown';   // present-but-unmapped status name → pass through, don't crash

/** How the result was decided — decorates a `final` outcome. */
export type Decision =
  | 'regulation'
  | 'overtime'    // extra timed period(s): NFL OT, NHL/NBA OT, soccer AET
  | 'shootout'    // soccer penalty shootout, NHL SO  (see shootoutScore)
  | 'aggregate'   // soccer two-leg tie decided on aggregate (see aggregateScore)
  | 'retirement'  // tennis 'ret' / golf WD mid-event
  | 'walkover'    // tennis w/o
  | 'default'     // tennis def / DQ
  | 'draw'        // both winner=false, a legitimate result (league soccer, MMA,
                  // college hockey/rugby, cricket "Match drawn")
  | 'noResult'    // cricket abandoned / no result
  | 'forfeit'
  | 'method'      // MMA: decided by KO/SUB/DEC — see `method`
  | null;         // not yet decided

// ---------------------------------------------------------------------------
// Envelope
// ---------------------------------------------------------------------------

export interface ScoresResponse {
  sport: string;          // canonical family key, e.g. 'soccer', 'basketball'
  league: string;         // ESPN slug, e.g. 'eng.1', 'nba', 'fifa.world'
  leagueId: string;       // VERIFIED numeric id as STRING from live JSON.
                          // (eng.1=700, nba=46, mlb=10, atp=851 — never invent.)
  leagueName: string;
  season: Season;
  day?: string;           // ESPN's reference "sports day" (YYYY-MM-DD), ET-bucketed.
                          // Does NOT roll at local midnight — the client anchors
                          // its Yesterday/Upcoming date math to this, not `now`.
  updated: string;        // ISO-8601 UTC, stamped by the worker
  anyLive: boolean;       // true if ≥1 event is `live` — client uses this to
                          // decide 15s vs 60s poll cadence
  events: SportEvent[];   // EMPTY [] off-season is normal, not an error
}

export interface Season {
  year: number;
  type: number;           // OPEN enum. 1=pre 2=regular 3=post 4=off — but
                          // VERIFIED 6='championship-series' (CWS) exists.
                          // Never assert a closed 1..4 set.
  slug?: string;          // 'regular-season', 'championship-series', ...
  displayName?: string;   // '2025-26'
}

/** A scheduled occasion. Usually ONE competition; a Grand Prix weekend has
 *  several (FP1/FP2/FP3/Qualifying/Race) — QUIRK: never assume length===1. */
export interface SportEvent {
  id: string;
  name: string;           // 'Away at Home'
  shortName: string;      // 'CAR @ ATL'
  start: string;          // ISO-8601 UTC ('...Z'). Always convert locally.
  neutralSite: boolean;
  venue?: Venue;
  broadcasts: string[];   // flattened network names
  notes: string[];        // 'NBA Finals - Game 7', bowl name, aggregate line
  weekLabel?: string;     // CHEAP: 'Week 5' (gridiron) / 'Round 15' (rugby) from
                          // event.week.number — regular season only, see normalize.js
  weather?: Weather;      // CHEAP: event.weather for OUTDOOR venues only
  links: { web?: string; box?: string };
  competitions: Competition[];
}

export interface Venue {
  name: string;
  city?: string;
  country?: string;
  indoor?: boolean;
}

/** Outdoor-game weather (scoreboard event.weather). Emitted only when the venue
 *  is not indoor — the one bit of pre-game context that moves the read (baseball). */
export interface Weather {
  temperature?: number;   // Fahrenheit, as ESPN reports
  condition?: string;     // conditionId, e.g. 'Cloudy' | 'Sunny'
}

// ---------------------------------------------------------------------------
// Competition
// ---------------------------------------------------------------------------

export interface Competition {
  id: string;
  label?: string;   // racing: session name (FP1 | Qual | Race) for multi-competition events
  layout: Layout;
  scoreKind: ScoreKind;
  competitorKind: CompetitorKind;

  status: Status;
  periods: Periods;
  decision: Decision;

  competitors: Competitor[]; // 2 for headToHead, N for field (already ordered)

  events?: ScoringEvent[];   // normalized timeline (goals/cards/scoring plays)
  method?: Method;           // MMA only: how the bout ended
  meta?: CompetitionMeta;    // round/cut/flag/series/cricket-class etc.
  situation?: Situation;     // live "what's happening now" strip (CHEAP); render only when live
}

/** Live game situation — a sport-agnostic union; only present keys are set.
 *  Baseball: count/outs/baserunners/pitcher/batter. Gridiron: down/distance/
 *  possession/red-zone/timeouts. (scoreboard competition.situation) */
export interface Situation {
  // baseball
  balls?: number;
  strikes?: number;
  outs?: number;
  onFirst?: boolean;
  onSecond?: boolean;
  onThird?: boolean;
  pitcher?: string;   // short name
  batter?: string;    // short name
  pitcherLine?: string; // CHEAP: situation.pitcher.summary — '0.2 IP, 0 ER, K, BB'
  batterLine?: string;  // CHEAP: situation.batter.summary — the batter's day '1-3, RBI'
  outsText?: string;  // '2 Outs' (lives on competition, not situation, upstream)
  // gridiron
  down?: number;
  distance?: number;
  downDistanceText?: string; // '3rd & 7 at NE 42'
  possession?: string;       // team id of side with the ball
  isRedZone?: boolean;
  homeTimeouts?: number;
  awayTimeouts?: number;
  // any sport
  lastPlay?: string;  // human-readable last play text
}

export interface Status {
  phase: Phase;
  live: boolean;       // phase==='live'
  ended: boolean;      // ESPN status.type.completed === true
  period: number;      // raw current/final period integer
  periodLabel: string; // humanized via league profile: '3rd Quarter',
                       // "45'+2'", 'Top 5th', 'Round 2', 'thru 14', 'FT'
  clock?: string;      // displayClock when the sport has one (omit golf/baseball)
  // Raw passthrough — keep for debugging & unmapped cases. Branch on `phase`,
  // not these. QUIRK: a single canonical Phase can come from many espnName
  // values; e.g. final from STATUS_FINAL(3), STATUS_FULL_TIME(28),
  // STATUS_FINAL_AET(45), STATUS_FINAL_PEN(47), STATUS_RETIRED(38).
  espnName: string;    // e.g. 'STATUS_FINAL'
  detail: string;      // 'Final/OT', 'FT-Pens', 'Top 5th'
  shortDetail?: string;
  altDetail?: string;  // 'OT' | '2OT' | 'SO' — present on some OT games
}

/** Resolved period model: league profile defaults reconciled with live data. */
export interface Periods {
  unit: PeriodUnit;
  regulation: number;   // from the league profile (NBA 4, NCAAM 2, MLB 9,
                        // softball 7, soccer 2). DO NOT trust ESPN
                        // format.regulation.periods for tennis (unreliable).
  played: number;       // max observed period (= linescores length for most)
  isOvertime: boolean;  // played > regulation. Derive from THIS, never from
                        // parsing the detail string (NCAAF 7OT shows 'Final').
  lengthMin?: number;   // regulation period length when fixed (NBA 12, WNBA 10)
}

// ---------------------------------------------------------------------------
// Competitor  (universal; most fields optional, gated by the discriminators)
// ---------------------------------------------------------------------------

export interface Competitor {
  kind: CompetitorKind;
  id: string;
  displayName: string;
  shortName?: string;
  abbreviation?: string;

  // team identity
  logo?: string;        // forced HTTPS
  logoDark?: string;    // dark-background variant (white/light logo); the client
                        // uses this in dark mode and falls back to `logo` on 404
  color?: string;
  altColor?: string;    // ESPN alternateColor; a cheap-tier fallback the client
                        // tints with when `color` is near-black/near-white (e.g.
                        // the team-color card gradient on the scores home)

  // athlete / pair identity
  athletes?: Athlete[]; // 1 for athlete, 2 for pair

  // placement
  homeAway?: 'home' | 'away'; // omit for field sports; IGNORE for tennis/MMA
  order?: number;             // finishing rank / leaderboard position / fight corner
  startOrder?: number;        // racing grid position
  rank?: number | null;       // poll rank (curatedRank.current); 99 → null
  seed?: number;

  // outcome
  winner?: boolean | null;    // null when undecided or draw

  // score (read per scoreKind)
  score?: Score;
  periodScores?: PeriodScore[]; // ESPN linescores[] normalized

  // records: type-tagged, summary string already formatted for the league
  // ('8-3' / '8-3-1' W-L-T / '40-30-12' NHL W-L-OTL / 'W-D-L' soccer)
  records?: { type: string; summary: string }[];

  // ---- edge-case decorations (only present when relevant) ----
  shootoutScore?: number;   // soccer PK / NHL SO decider. QUIRK: winner is set
                            // from THIS, not from score (which stays level).
  aggregateScore?: string;  // VERIFIED a STRING ('8.0'), not a number.
  advance?: boolean;        // bracket progression
  amateur?: boolean;        // golf
  vehicle?: Vehicle;        // racing
  stats?: Record<string, string | number>; // team stat line, keyed by ESPN abbr
                            // (CHEAP: from scoreboard competitor.statistics[])

  // ---- cheap-tier context already in the scoreboard ----
  hits?: number;            // baseball: the H in R/H/E
  errors?: number;          // baseball: the E in R/H/E
  form?: string;            // soccer/rugby recent form ('WLWWW', newest last)
  leaders?: Leader[];       // game/team statistical leaders
  probables?: Probable[];   // probable starting pitcher / goalie (pre-game)
}

/** A statistical leader for one category (scoreboard competitor.leaders[]). */
export interface Leader {
  name: string;      // category key, e.g. 'avg' | 'points' | 'goals'
  label: string;     // short display label, e.g. 'AVG' | 'PTS' | 'G'
  display?: string;  // formatted value, e.g. '.291' | '25.0' | '2-3, RBI'
  athlete?: string;  // short athlete name, e.g. 'R. O'Hearn'
}

/** A probable/announced starter (scoreboard competitor.probables[]). */
export interface Probable {
  role: string;      // 'Starter' (SP) | 'Probable Starting Goalie' etc.
  athlete: string;   // short athlete name
  record?: string;   // CHEAP MLB: probables[].record — '(5-4, 3.30)' (W-L, ERA)
  confirmed?: boolean;// CHEAP NHL: probables[].status.type==='confirmed' (goalie locked vs projected)
}

export interface Athlete {
  id: string;
  name: string;
  jersey?: string;
  country?: string;   // flag/nationality
  headshot?: string;
  position?: string;
}

export interface Score {
  display: string;       // canonical display string for ANY scoreKind
  value?: number;        // scoreKind==='numeric' → parsed int
  toPar?: number;        // scoreKind==='toPar' → e.g. -10 (0 for 'E')
  strokes?: number;      // golf total strokes (core API)
  cricket?: CricketScore;// scoreKind==='cricket'
}

export interface CricketScore {
  runs: number;
  wickets: number;
  overs: number;
  target?: number;
  declared?: boolean;
  allOut?: boolean;      // QUIRK: distinct from overs-completed
}

/** One period/inning/set/round/hole-round row (ESPN linescores[]). */
export interface PeriodScore {
  period: number;
  value: number;
  display: string;
  // tennis: this competitor's tiebreak point count for the set. QUIRK: present
  // on BOTH competitors (each side's points); not just the loser. Can exceed
  // 10 in super-tiebreaks (11-9 etc.) — do NOT use ==10 as a marker.
  tiebreak?: number;
  setWinner?: boolean;   // tennis per-set winner flag
  // cricket per-innings authoritative numbers
  cricket?: CricketScore & { isBatting?: boolean; reason?: string /* 'all out' | 'target reached' | 'complete' | 'No result' */ };
  holesPlayed?: number;  // golf: holes completed in this round (drives 'THRU')
  // NOTE rugby: value is CUMULATIVE — period 2 === final score, period 1 ===
  // running total at half time (may be 0 if ESPN didn't backfill).
  // NEVER sum period1+period2.
}

export interface Vehicle {
  number?: string;
  manufacturer?: string;
  team?: string;
  owner?: string;
  sponsor?: string;
}

// ---------------------------------------------------------------------------
// Scoring timeline (normalized plays/details)
// ---------------------------------------------------------------------------

export type ScoringEventType =
  // soccer
  | 'goal' | 'own-goal' | 'penalty-goal' | 'penalty-missed'
  | 'yellow-card' | 'red-card' | 'substitution'
  // gridiron
  | 'touchdown' | 'field-goal' | 'extra-point' | 'two-point' | 'safety'
  // hockey
  | 'hockey-goal' | 'shootout-goal'
  // generic / other
  | 'score' | 'other';

export interface ScoringEvent {
  type: ScoringEventType;
  team?: 'home' | 'away';
  clock?: string;        // "12'", "7:32"
  period?: number;
  athlete?: string;
  detail?: string;
  scoreValue?: number;   // points/goals this play added
  flags?: {
    ownGoal?: boolean;
    penalty?: boolean;
    redCard?: boolean;
  };
}

// ---------------------------------------------------------------------------
// MMA method of victory
// ---------------------------------------------------------------------------

export interface Method {
  // QUIRK: NOT in the site scoreboard — sourced from core API status $ref.
  kind: 'KO/TKO' | 'Submission' | 'Decision' | 'Draw' | 'No Contest' | string;
  detail?: string;       // 'Punches', 'Rear-Naked Choke', 'Unanimous'
  target?: string;       // 'head' | 'body' | 'leg'
  finishRound?: number;
  finishTime?: string;   // QUIRK: for a decision this is the round length
                         // ('5:00'), NOT a stoppage time.
}

// ---------------------------------------------------------------------------
// Competition meta (sport-flavored, all optional)
// ---------------------------------------------------------------------------

export interface CompetitionMeta {
  round?: string;          // tournament round label / cricket '2nd Match, Group 2'
  seriesSummary?: string;  // playoff series '2-1' (legacy prose; prefer `series`)
  series?: SeriesInfo;     // STRUCTURED playoff series state (NBA/NHL/MLB-playoff) — drives the pip row
  cardSegment?: string;    // MMA 'Main Card' | 'Prelims' (core API)
  featured?: boolean;      // MMA main event
  flag?: string;           // racing F1-ONLY: GREEN|YELLOW|RED|CHECKER
  cricketClass?: string;   // 'Twenty20' | 'ODI' | 'T20I' | 'First-class' | 'Women T20'
  cricketSummary?: string; // 'RCB won by 5 wkts (12b rem)'
  hadPlayoff?: boolean;    // golf: the reliable OT signal (status.hadPlayoff)
  golf?: GolfMeta;
}

/** Structured best-of-N playoff series (scoreboard competition.series). ESPN ships
 *  this on NBA/NHL/MLB postseason games; we used to keep only the prose summary.
 *  competitors[].id matches Competitor.id so the UI can color each side's pips. */
export interface SeriesInfo {
  type?: string;           // 'playoff'
  total?: number;          // totalCompetitions — best-of-N (e.g. 7)
  completed?: boolean;     // series decided
  competitors: { id: string; wins: number }[];
}

export interface GolfMeta {
  numberOfRounds: number;  // 4 (72-hole) or 3 (Champions Tour, 54-hole)
  currentRound?: number;
  cutRound?: number;       // 0 = no cut (signature/Champions)
  cutScore?: number;       // to-par cut line
  cutCount?: number;
  major?: boolean;
  scoringSystem?: string;  // 'Medal' (stroke) | 'Teamstroke' (team event)
}

// ===========================================================================
// Game summary — the RICH tier. A SEPARATE /summary fetch, made only when a
// game detail is opened (the scoreboard tier above is what the home feed polls).
// Endpoint: GET /v1/summary/{sport}/{league}/{eventId}. All arrays default to
// [] so the client can render unconditionally. Shapes are deliberately generic
// so ONE set of widgets renders every sport (sport differences are data, not
// types) — verified against live MLB/NBA/NFL/NHL/soccer summaries 2026-06.
// ===========================================================================

export interface GameSummary {
  eventId: string;
  live: boolean;
  teamStats: TeamStatRow[];   // mirrored this-game comparison (NOT season records)
  boxGroups: BoxGroup[];      // per-player tables (batting/pitching/skaters/passing…)
  scoringPlays: SummaryPlay[];// scoring feed / soccer key-event timeline
  periodLines?: PeriodLines;  // per-period splits (NBA/NFL quarters, NHL periods)
  lineups: Lineup[];          // soccer/rugby starting XI + bench
}

/** One mirrored stat row: 'Possession 61% — 39%'. */
export interface TeamStatRow {
  label: string;
  away?: string;
  home?: string;
}

/** A per-player table, e.g. Batting / Pitching / Passing / Skaters / Goalies. */
export interface BoxGroup {
  title: string;
  columns: string[];   // stat column headers (ESPN labels[])
  teams: BoxTeam[];     // one per side present
}
export interface BoxTeam {
  side?: 'home' | 'away';
  abbr?: string;
  rows: BoxRow[];
}
export interface BoxRow {
  name: string;        // short athlete name
  pos?: string;
  stats: string[];     // aligned 1:1 with BoxGroup.columns
}

/** A scoring play (or soccer key event) for the timeline feed. */
export interface SummaryPlay {
  period?: number;
  periodLabel?: string;  // '3rd Inning', '2nd', "67'"
  clock?: string;
  side?: 'home' | 'away';
  teamAbbr?: string;
  text: string;
  away?: number;         // running score after the play
  home?: number;
  type?: string;         // 'Goal' | 'Field Goal' | 'play-result'…
}

/** Per-period scoreboard split sourced from the summary header. */
export interface PeriodLines {
  unit: PeriodUnit;
  labels: string[];      // ['1','2','3','4'] | ['1','2','3','OT'] | ['1','2','3','OT','SO']
  away: SidePeriods;
  home: SidePeriods;
}
export interface SidePeriods {
  abbr?: string;
  values: string[];      // aligned 1:1 with labels
  total?: string;
}

/** A team's lineup (soccer/rugby). */
export interface Lineup {
  side?: 'home' | 'away';
  abbr?: string;
  formation?: string;    // '4-3-3'
  starters: LineupPlayer[];
  bench: LineupPlayer[];
}
export interface LineupPlayer {
  name: string;
  pos?: string;
  jersey?: string;
}

// =============================================================================
// Favorite team — a per-(league, teamId) card. The teams list backs the picker;
// the card shows the LIVE game (if any), else the previous result + next fixture.
// Built from the ESPN team-list + team-schedule endpoints, normalized through
// the SAME buildEvent() as the scoreboard. VERIFIED against live ESPN 2026-06.
// =============================================================================

/** A lightweight team reference for the favorites picker (one per league team). */
export interface TeamRef {
  id: string;             // VERIFIED unique only WITHIN a league — always scope with `league`.
  displayName: string;    // 'Arsenal', 'Boston Celtics'
  abbreviation?: string;  // 'ARS', 'BOS'
  logo?: string;          // forced HTTPS
  logoDark?: string;      // dark-bg variant (explicit rel:'dark' or derived /500-dark/)
  color?: string;         // bare hex, no '#'
}

/** GET /v1/teams/{sport}/{league} — the picker source for one league. */
export interface TeamsResponse {
  league: string;         // ESPN key 'basketball/nba'
  sport: string;          // family key 'basketball'
  teams: TeamRef[];       // sorted by displayName; [] is valid (offseason/unprobed)
}

/** GET /v1/team/{sport}/{league}/{teamId} — one favorite's card payload. */
export interface TeamCardResponse {
  league: string;         // 'basketball/nba'
  sport: string;          // 'basketball'
  leagueName: string;     // resolved profile name — for card/detail titles
  team: {
    id: string;
    displayName: string;
    abbreviation?: string;
    logo?: string;        // VERIFIED schedule.team.logo is a STRING (not a logos[] array)
    logoDark?: string;
    color?: string;
    record?: string;      // VERIFIED a STRING ('46-36'); from schedule.team.recordSummary
  };
  live: SportEvent | null;  // a currently-live game, else null
  last: SportEvent | null;  // most-recent ENDED game (final/called), else null
  next: SportEvent | null;  // earliest upcoming SCHEDULED game, else null
  anyLive: boolean;         // live != null — client uses for 15s vs 60s cadence
}

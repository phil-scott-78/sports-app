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
  // CHEAP: ESPN's season skeleton, lifted from the SAME scoreboard payload
  // (leagues[0].calendar) — no extra fetch. Present only for "day"-type calendars;
  // omitted for "list" (gridiron/golf/F1/MMA, where the calendar is week/event
  // buckets, not days). QUIRK (VERIFIED 2026-06): density is NOT uniform —
  // NBA(229)/NHL(226)/soccer-eng.1(114) ship a DENSE one-entry-per-game-day list,
  // but MLB ships a SPARSE 48-entry season-boundary calendar (spring-training
  // start / All-Star break / season end — NOT game days). So treat this as a
  // hint, NEVER as an exhaustive game-day set: a consumer must cross-check actual
  // events before dimming a day "empty" (the app's Schedule strip keeps deriving
  // precise in-window days from a range scoreboard fetch for exactly this reason).
  calendarDays?: string[];          // sorted 'YYYYMMDD' (ET) — see density QUIRK above
  seasonWindow?: { startDate?: string; endDate?: string }; // leagues[0].season window (reliable)
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

  // ---- cheap-tier context already on the scoreboard (VERIFIED 2026-07) ----
  attendance?: number;       // competitions[].attendance; omitted when 0/absent
  headline?: string;         // competitions[].headlines[0] one-line recap/preview
                             // (shortLinkText ?? description) — a single calm line,
                             // NOT a news feed; emitted only when ESPN sends one
  conferenceGame?: boolean;  // college: conferenceCompetition === true
  wasSuspended?: boolean;    // MLB: game was suspended and later resumed
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
  // hockey (CHEAP: scoreboard competition.situation)
  powerPlay?: boolean;   // VERIFIED: NHL scoreboard situation.powerPlay
  emptyNet?: boolean;    // VERIFIED: NHL scoreboard situation.emptyNet
  strength?: string;     // 'power-play'|'short-handed'|'even-strength'|'empty-net' — from situation.lastPlay.strength (ids 701/702/703/903)
  strengthTeam?: string; // competitor id of the side on the man advantage (situation.lastPlay.team.id)
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
  serving?: boolean;        // tennis/volleyball: this competitor is serving (CHEAP: scoreboard competitor.possession)
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
  // QUIRK: NOT structured in the site scoreboard — the cheap tier scrapes it from
  // details[].type.text ('Unofficial Winner …'); the rich tier upgrades it from
  // the core status resource via GameSummary.bouts (structured result + judges).
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

/** Golf tournament meta. VERIFIED 2026-07: NOT on the site scoreboard — sourced
 *  from the core API tournament resource (event → tournament.$ref →
 *  `.../tournaments/{id}/seasons/{yyyy}`: {major, scoringSystem.name,
 *  numberOfRounds, currentRound, cutRound, cutScore, cutCount}). The worker's
 *  scores route fetches it for golf leagues only (2 extra subrequests per event,
 *  cached with the response) and omits meta.golf when the fetch fails — treat as
 *  best-effort enrichment, never required. */
export interface GolfMeta {
  numberOfRounds: number;  // 4 (72-hole) or 3 (Champions/LIV, 54-hole)
  currentRound?: number;
  cutRound?: number;       // 0 = no cut (signature/Champions)
  cutScore?: number;       // to-par cut line
  cutCount?: number;       // players who made the cut
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
  boxGroups: BoxGroup[];      // per-player tables (batting/pitching/skaters/passing…).
                              // QUIRK: soccer's per-player lines live on the lineup
                              // entries (rosters[].roster[].stats), NOT boxscore.players
                              // (empty) — the worker distills them into 'Players'
                              // (G,A,SH,ST,YC,RC,FC,FA) + 'Goalkeepers' (SHF,SV,GA)
                              // groups, appeared players only. VERIFIED 2026-07 live.
  scoringPlays: SummaryPlay[];// CONDENSED scoring feed / soccer key-event timeline (default view)
  periodLines?: PeriodLines;  // per-period splits (NBA/NFL quarters, NHL periods)
  lineups: Lineup[];          // soccer/rugby starting XI + bench
  // ---- enrichments that ride this SAME /summary payload (zero extra fetch) ----
  // Each emitted only when present; all source from raw keys we used to discard.
  plays?: SummaryPlay[];      // FULL chronological play-by-play (NBA/NHL/MLB; gridiron
                              // flattened from drives). QUIRK: soccer/rugby ship no
                              // plays[] — their full feed is summary commentary[]
                              // (timestamped fouls/shots/corners/VAR narrative;
                              // keyEvents is only goals/cards/subs, EMPTY timeline in
                              // a 0-0 game). commentary play.team carries display name
                              // only (no id), so sides attribute by name. The core
                              // /plays resource is touch-by-touch noise (700+ by
                              // halftime) — deliberately not used. VERIFIED 2026-07
                              // live (fifa.world). Capped (≤800). Same shape.
  seasonSeries?: SeasonSeries;// head-to-head this season ('Series tied 1-1')
  recentForm?: SideForm[];    // per-side last-5 form string (MLB/NBA/NFL/NHL),
                              // newest LAST — mirrors the cheap scoreboard `form`
  injuries?: TeamInjuries[];  // per-side "key absences" (structured; comments dropped)
  winProbability?: WinProbability; // single CURRENT/FINAL win% (NBA/NFL/MLB only;
                              // absent NHL/soccer). ESPN analytic, not a betting line;
                              // never the full curve. Render passively on detail.
  attendance?: number;        // gameInfo.attendance (VERIFIED 2026-07: NFL/soccer/cricket)
  officials?: Official[];     // gameInfo.officials — referee/umpires, capped
  drives?: DriveSummary[];    // gridiron ONLY (raw.drives.previous): compact per-drive
                              // rows. The full drive play-by-play is FLATTENED into
                              // `plays` (chronological) so gridiron gets feed parity
                              // with NBA/NHL/MLB — see worker/src/summary.js.
  cricketInnings?: CricketInningsCard[]; // cricket ONLY (raw.matchcards): the real
                              // scorecard — per-innings batting + bowling figures.
                              // VERIFIED 2026-07 riding the SAME site /summary we
                              // already fetch (fixture trimming had hidden it).
  bouts?: BoutResult[];       // MMA ONLY. QUIRK: the site /summary 404s for MMA
                              // (it proxies a broken core call), so the worker
                              // builds this from core per-bout status resources:
                              // structured method of victory + judge scorecards.
  timeline?: MatchEvent[];    // SOCCER ONLY (raw.keyEvents): the curated event feed
                              // (goals/cards/subs/VAR) for the Timeline tab, scorer
                              // & assist split out of participants[]. When present,
                              // `plays` (commentary) is NOT shipped. See MatchEvent.
}

/** One soccer match event (worker `timeline`, from ESPN keyEvents[]). VERIFIED
 *  2026-07 (fifa.world): keyEvent participants[] are [scorer, assist] for goals
 *  and [playerIn, playerOut] for subs; team is {id} only (side via id maps); and
 *  awayScore/homeScore are UNDEFINED — so the running score is NOT carried, the UI
 *  tallies it from each scoring event's `side` (ESPN credits an Own Goal to the
 *  BENEFITING team). Kickoff/Halftime/Start-2nd-Half/injury-delay rows are dropped
 *  as noise; the UI derives half dividers from `period`. */
export interface MatchEvent {
  t?: number;            // minutes incl. stoppage ("45'+7'"→52), ordering only
  period?: number;       // 1 | 2 | 3 | 4 (extra time) | 5 (shootout)
  kind: string;          // 'goal' | 'own-goal' | 'penalty-goal' | 'penalty-missed'
                         //  | 'yellow-card' | 'red-card' | 'substitution' | 'var'
  clock?: string;        // "45'+7'"
  side?: 'home' | 'away';
  teamAbbr?: string;
  athlete?: string;      // scorer / booked player / player coming ON
  assist?: string;       // goal assist, or (for subs) the player going OFF
  text?: string;         // ESPN prose, subtitle fallback
  scoring?: boolean;     // true for goals (own/penalty included)
}

/** A match official (summary gameInfo.officials). */
export interface Official {
  name: string;        // fullName
  role?: string;       // position.name: 'Referee' | 'Home Plate Umpire' | …
}

/** One gridiron drive (raw.drives.previous[]). Compact glance row; the plays
 *  themselves live flattened in GameSummary.plays. */
export interface DriveSummary {
  side?: 'home' | 'away';
  teamAbbr?: string;
  description?: string;  // '8 plays, 51 yards, 3:02'
  result?: string;       // displayResult: 'Touchdown' | 'Punt' | 'Field Goal' …
  isScore?: boolean;
  yards?: number;
  playCount?: number;    // offensivePlays
}

/** One innings of a cricket scorecard (raw.matchcards, typeID-tagged cards merged
 *  by inningsNumber: the batting side's card + the opposing bowling card).
 *  VERIFIED 2026-07: all figures arrive as STRINGS ('137', '9.0', '4.77') — kept
 *  as strings, aligned with BoxRow.stats. Partnerships cards are dropped (depth). */
export interface CricketInningsCard {
  innings: number;         // inningsNumber (1-based; Tests go to 4)
  battingTeam: string;     // teamName on the Batting card
  total?: string;          // '241 (4 wkts; 43 ovs)' — runs + wickets/overs suffix
  extras?: string;         // '(b 5, lb 2, w 11)'
  batting: CricketBatRow[];
  bowlingTeam?: string;    // teamName on the matching Bowling card
  bowling: CricketBowlRow[];
}
export interface CricketBatRow {
  name: string;            // 'DA Warner'
  dismissal?: string;      // 'caught' | 'lbw' | 'not out' | 'run out' …
  runs?: string;
  balls?: string;
  fours?: string;
  sixes?: string;
}
export interface CricketBowlRow {
  name: string;            // 'JJ Bumrah'
  overs?: string;          // '9.0'
  maidens?: string;
  runs?: string;           // conceded
  wickets?: string;
  economy?: string;        // '4.77'
}

/** One bout's structured result (MMA summary). `id` matches Competition.id so the
 *  detail page can find its bout. Sourced from the core status resource
 *  (VERIFIED 2026-07: result {name:'decision---unanimous', displayName, short}). */
export interface BoutResult {
  id: string;              // bout competition id
  result?: string;         // 'Decision - Unanimous' | 'KO/TKO' …
  shortResult?: string;    // 'U Dec' | 'KO'
  round?: number;          // finish round (decision → final round)
  clock?: string;          // '5:00' — QUIRK: for a decision this is round length
  judges?: BoutJudge[];    // decision bouts only: per-competitor judge totals
}
/** Judge scorecards for one competitor: totals[] is per-judge (aligned across the
 *  bout's competitors by index — zip both sides to read '29-28, 29-28, 30-27'). */
export interface BoutJudge {
  competitorId: string;
  total?: number;          // summed card (e.g. 81)
  totals: number[];        // one entry per judge (e.g. [27,27,27])
}

/** Season head-to-head series (raw.seasonseries, best non-preseason entry). */
export interface SeasonSeries {
  summary: string;   // 'Series tied 1-1' | 'MIA leads 2-1'
  score?: string;    // '1-1'
  title?: string;    // 'Regular Season Series'
}

/** One side's last-5 form (raw.lastFiveGames). `form` newest LAST, e.g. 'WLWWL'. */
export interface SideForm {
  side?: 'home' | 'away';
  abbr?: string;
  form: string;      // chars ∈ W|L|T|D
}

/** One side's injury list (raw.injuries) — structured only; long/short comments dropped. */
export interface TeamInjuries {
  side?: 'home' | 'away';
  abbr?: string;
  items: InjuryItem[];
}
export interface InjuryItem {
  name: string;        // short athlete name
  pos?: string;        // position abbreviation
  status: string;      // 'Out' | 'Doubtful' | 'Questionable' | 'Day-To-Day' | …
  detail?: string;     // body part / nature ('Knee')
  returnDate?: string; // ISO, when ESPN provides an expected return
}

/** Current/final win probability (raw.winprobability last entry). Percentages 0-100. */
export interface WinProbability {
  home: number;
  away: number;
  tie?: number;        // soccer/draw-capable only (usually absent)
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
  scoring?: boolean;     // true when this row is an actual score — set per play on
                         // BOTH the condensed scoringPlays[] and the full plays[]
                         // feed (from ESPN's scoringPlay), so the app's unified
                         // action feed lifts scores (running score + team wash) out
                         // of the run of play. Soccer's key-event scoring feed also
                         // carries cards/subs (scoring:false). Absent ⇒ treat as
                         // scoring (every scoringPlays row is a score).
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
    standingSummary?: string; // VERIFIED a STRING ('2nd in AL East'); from
                          // schedule.team.standingSummary. Absent for national teams.
  };
  live: SportEvent | null;  // a currently-live game, else null
  last: SportEvent | null;  // most-recent ENDED game (final/called), else null
  next: SportEvent | null;  // earliest upcoming SCHEDULED game, else null
  anyLive: boolean;         // live != null — client uses for 15s vs 60s cadence
}

// =============================================================================
// Team detail — the RICH tier for a team (the scoreboard-vs-summary split, but
// for a team): the lean TeamCardResponse above is what the home feed polls; this
// is the one-off page a team opens. GET /v1/teamdetail/{sport}/{league}/{teamId}.
// Lazy + a 30m TTL (4 coalesced subrequests). Gated to competitorKind==='team'
// leagues by the app (a golfer / an F1 constructor has no page). VERIFIED 2026-07
// against live NFL/NBA/MLB/NHL/EPL/college. Everything except identity is
// best-effort — an unavailable roster/stats/standing degrades to [] / omitted.
// =============================================================================

export interface TeamDetailResponse {
  league: string;          // 'basketball/nba'
  sport: string;           // 'basketball'
  leagueName: string;
  team: {                  // same identity block as TeamCardResponse.team
    id: string;
    displayName: string;
    abbreviation?: string;
    logo?: string;
    logoDark?: string;
    color?: string;
    record?: string;
    standingSummary?: string;
  };
  schedule: SportEvent[];  // FULL season (played + upcoming), start-ascending, via
                           // the SAME buildEvent() as the scoreboard — the client
                           // slices "last N / next N". [] when the schedule is empty.
  roster: RosterGroup[];   // [] when absent. QUIRK (VERIFIED 2026-07): ESPN returns
                           // EITHER a flat athletes[] (NBA/MLB/NHL → one 'Roster'
                           // group) OR grouped athletes[{position, items[]}] (NFL by
                           // offense/defense/specialTeam, soccer by position). The
                           // worker discriminates STRUCTURALLY (items[] present),
                           // never by sport name.
  stats: TeamStatGroup[];  // season stats. [] when absent — VERIFIED EPL ships an
                           // empty results:{} in the offseason. When the family
                           // curates registry.teamStatKeys, collapses to ONE ordered
                           // 'Season' group; else the natural categories, capped.
  standing?: TeamStanding; // this team's standings GROUP only; omitted when the team
                           // isn't found (national team / athlete-shaped racing table).
}

export interface RosterGroup {
  name: string;            // 'Roster' (flat) | 'Offense' | 'Defense' | 'Goalkeepers'…
  athletes: RosterAthlete[];
}
export interface RosterAthlete {
  id: string;
  name: string;
  jersey?: string;
  position?: string;       // abbreviation ('QB', 'G')
  headshot?: string;       // forced HTTPS
}

export interface TeamStatGroup {
  name: string;            // 'Season' (curated) | ESPN category displayName ('Offensive')
  stats: TeamStatItem[];
}
export interface TeamStatItem {
  name: string;            // ESPN stat key ('avgPoints')
  label: string;           // short display label ('PPG')
  abbr?: string;           // ESPN abbreviation
  value: string;           // VERIFIED kept as a STRING (aligns with StandingsRow.stats)
  rank?: number;           // league rank when ESPN provides one (absent on the site endpoint)
}

/** This team's row within its standings group — the exact StandingsRow[] the
 *  standings page renders, filtered to the one group containing the team, with
 *  the same per-family `columns` /v1/standings carries (so the team page shows
 *  W/L/PCT labels, not raw stat keys). */
export interface TeamStanding {
  groupName: string;
  columns: StandingColumn[] | null;
  rows: StandingsRow[];
}

// =============================================================================
// Standings — GET /v1/standings/{sport}/{league}[?season=YYYY]. Declared here
// retroactively (the shape has shipped in worker/src/standings.js + the client
// mirror); closing the contract gap so a future reshape is caught by the /v2
// rule. ESPN nests entries under children[] (conferences/divisions/groups); the
// worker flattens to groups[].rows[]. Stat keys vary by sport (a name→string map).
// =============================================================================

export interface StandingsResponse {
  league: string;               // 'basketball/nba'
  season?: number;              // resolved season year (raw.season.year), when known
  columns: StandingColumn[] | null; // per-family preferred columns (registry
                                // standingsColumns) so the app shows W/L/PCT/GB not
                                // ESPN's internal 'points'; null → client heuristic
  groups: StandingsGroup[];     // one per conference/division/group
}
export interface StandingColumn {
  key: string;                  // ESPN stat key ('winPercent')
  label: string;                // display header ('PCT')
}
export interface StandingsGroup {
  name: string;                 // 'Eastern Conference' | 'AL East' | ''
  rows: StandingsRow[];
}
export interface StandingsRow {
  // QUIRK: racing driver-championship rows are ATHLETE-shaped upstream (no team),
  // but the worker normalizes the athlete into this same `team` slot (name, no
  // logo) so the client renders ONE table shape.
  team: { id: string; name: string; abbr?: string; logo?: string; logoDark?: string };
  rank?: number;                // stats.rank when present
  stats: Record<string, string>; // ESPN stat name → displayValue
}

// =============================================================================
// Rankings — the standalone list for a league-detail page, DISTINCT from the
// per-team curatedRank we already surface inline on the scoreboard. Three feeds
// share one shape (registry `rankingsFeed` flag says which a league has):
//   'polls'     — college AP/Coaches/CFP Top-25 (team-based)
//   'tour'      — ATP/WTA world rankings (athlete-based, points). VERIFIED
//                 2026-07 on the SAME site rankings endpoint as the polls.
//   'divisions' — UFC divisional + P4P rankings (athlete-based, records)
// Endpoint: GET /v1/rankings/{sport}/{league}; lazy + long TTL; never in the
// overview fan-out. Entries carry EITHER `team` OR `athlete`, never both.
// =============================================================================

export interface RankingsResponse {
  league: string;       // 'football/college-football' | 'tennis/atp' | 'mma/ufc'
  polls: Poll[];        // [] when none (offseason / league without a feed)
}
export interface Poll {
  name: string;         // 'AP Top 25' | 'ATP' | "Men's Pound for Pound Rankings"
  shortName: string;    // 'AP Poll' | 'ATP'
  occurrence?: string;  // 'Week 5' | 'Final Rankings'
  ranks: RankEntry[];   // ≤25 (tennis' 150-deep list is capped by the worker)
}
export interface RankEntry {
  current?: number;     // this week's rank
  previous?: number;    // last week's rank
  trend?: string;       // ESPN pre-rendered delta: '+8' | '-2' | '-'
  record?: string;      // college/MMA '16-0' | '21-4-0' (recordSummary)
  points?: number;      // tennis ranking points (13450)
  champion?: boolean;   // MMA: hasAccolade (division champ / belt holder)
  team?: RankTeam;      // team-based polls (college)
  athlete?: RankAthlete;// athlete-based rankings (tennis/MMA)
}
export interface RankTeam {
  id: string;
  name: string;
  abbr?: string;
  logo?: string;
  logoDark?: string;
  color?: string;
}
export interface RankAthlete {
  id: string;
  name: string;         // 'Jannik Sinner'
  country?: string;     // flag alt / citizenship when present
  headshot?: string;
}

// =============================================================================
// Golf player scorecard — hole-by-hole detail for one leaderboard row.
// GET /v1/scorecard/{sport}/{league}/{eventId}/{playerId}[?season=YYYY]
// Source (VERIFIED 2026-07, live): site.web.api.espn.com
// `.../golf/{tour}/leaderboard/{eventId}/playersummary?season=&player=` — per
// round: per-hole strokes + par + named scoreType (BIRDIE/PAR/BOGEY…), front/back
// splits, and — for a round not yet started — teeTime/startTee/groupNumber.
// Fetched lazily on a leaderboard-row tap; never polled by the home feed.
// =============================================================================

export interface GolfScorecardResponse {
  league: string;          // 'golf/pga'
  eventId: string;
  player: {
    id: string;
    name: string;          // 'Chris Gotterup'
    headshot?: string;
    country?: string;      // birthPlace country is NOT this; from flag when present
  };
  rounds: ScorecardRound[];// one per round ESPN has (future rounds: teeTime only)
  stats?: { name: string; label: string; value: string }[]; // tournament stat line
                           // (scoreToPar, driving distance …) — small, curated
}
export interface ScorecardRound {
  round: number;           // 1-based round number (raw `period`)
  strokes?: number;        // round total strokes (66); absent before the round
  toPar?: string;          // round score to par ('-5'); raw displayValue
  outScore?: number;       // front-nine strokes
  inScore?: number;        // back-nine strokes
  teeTime?: string;        // ISO — present pre-round (the pre-start glance)
  startTee?: number;       // 1 or 10 (split tees)
  groupNumber?: number;
  currentPosition?: number;// live position as of this round
  holes: ScorecardHole[];  // 18 when played/in progress; [] pre-round
}
export interface ScorecardHole {
  hole: number;            // 1..18 (raw `period`)
  par?: number;
  strokes?: number;        // raw value
  scoreType?: string;      // 'EAGLE' | 'BIRDIE' | 'PAR' | 'BOGEY' | 'DOUBLE_BOGEY' …
                           // (scoreType.name; displayValue is the +/- delta)
}

// =============================================================================
// Health + the advisory client-version gate (GET /v1/health).
// -----------------------------------------------------------------------------
// VERSIONING CONTRACT: this whole file is versioned as a DISCIPLINE, not a wire
// protocol. The client parses tolerantly (unknown keys ignored, missing fields
// defaulted, discriminators stored as pass-through strings), so the worker may
// ADD to any payload above and every already-installed app keeps working — `/v1`
// is a contract NAME that absorbs additive change forever. A NEW major (`/v2`) is
// minted ONLY for a breaking reshape: (1) changing an existing field's type,
// (2) changing the count/order of positionally-zipped parallel arrays
// (BoxGroup.columns↔BoxRow.stats, PeriodLines.labels↔SidePeriods.values),
// (3) renaming a map key indexed by abbr (Competitor.stats, StandingsRow.stats).
// Rule of thumb: never reshape an existing field in place — add a new one.
// See schema/SCHEMA.md §11 for the full policy + release ritual.
// =============================================================================

export interface HealthResponse {
  ok: boolean;
  leagues: number;        // count of registry leagues (liveness sanity check)
  updated: string;        // ISO timestamp
  client: ClientGate | null; // null when the registry omits it → app shows no
                             // banner (FAIL-OPEN: old worker / fork / offline mock)
}

/** Advisory app-update gate, authored in league-profiles.json `client` and echoed
 *  here (internal `_`-prefixed keys stripped on the wire — see worker/src/client.js).
 *  Comparison is by versionCode (the CI run_number baked into the APK), NEVER the
 *  semver name. ABSENT block / null fields MUST read as "no requirement". */
export interface ClientGate {
  minVersionCode?: number;         // below → persistent "no longer supported" bar
  recommendedVersionCode?: number; // [min, rec) → dismissible "update available"
  latestVersionName?: string;      // '0.3.1' — banner copy only
  downloadUrl?: string;            // GitHub Releases (sideloaded APK: signal + link)
}

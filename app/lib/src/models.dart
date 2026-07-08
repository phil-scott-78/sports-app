// Dart mirror of schema/canonical.ts (+ catalog/standings). Hand-written,
// tolerant fromJson — missing fields never throw. Keep field names aligned with
// the worker's output (worker/src/normalize.js).

// ---- parse helpers ----------------------------------------------------------
int? _int(dynamic v) => v is int
    ? v
    : (v is num ? v.toInt() : (v is String ? int.tryParse(v) : null));
num? _num(dynamic v) => v is num ? v : (v is String ? num.tryParse(v) : null);
String _str(dynamic v) => v == null ? '' : v.toString();
String? _strOrNull(dynamic v) => v?.toString();
bool _bool(dynamic v) => v == true;
List<dynamic> _list(dynamic v) => v is List ? v : const [];
Map<String, dynamic> _map(dynamic v) => v is Map
    ? v.map((k, val) => MapEntry(k.toString(), val))
    : <String, dynamic>{};

// ---- scores response --------------------------------------------------------
class ScoresResponse {
  final String sport, league, leagueId, leagueName;
  final Season season;

  /// ESPN's reference "sports day" (YYYY-MM-DD), ET-bucketed. Used as the anchor
  /// for the Scores tab's Yesterday/Upcoming offsets — it doesn't roll at local
  /// midnight, so anchoring to it (not `DateTime.now()`) keeps the three day
  /// modes from overlapping in the post-midnight window.
  final String? day;
  final DateTime? updated;
  final bool anyLive;

  /// Soonest scheduled kickoff in this slate (epoch ms), or null when nothing is
  /// scheduled. The worker surfaces this (worker/src/normalize.js) so the client
  /// can tighten its idle poll near kickoff — otherwise the idle→live flip is
  /// hidden for a full idle window at the most-watched moment. See [kickoffSoonMs].
  final int? nextStartMs;

  /// Authoritative game days ('YYYYMMDD', ET) lifted from the SAME scoreboard
  /// payload (worker leagues[0].calendar) — present only for "day"-type leagues
  /// (NBA/NHL/MLB/soccer), empty for gridiron/golf/F1. When non-empty the
  /// league-detail Schedule strip dims/auto-focuses from this instead of a
  /// separate range fetch. See [SeasonWindow].
  final List<String> calendarDays;

  /// The league's season window (start/end), from leagues[0].season — anchors the
  /// offseason "Returns …" focus when no game days are in view.
  final SeasonWindow? seasonWindow;
  final List<SportEvent> events;

  ScoresResponse({
    required this.sport,
    required this.league,
    required this.leagueId,
    required this.leagueName,
    required this.season,
    this.day,
    required this.updated,
    required this.anyLive,
    this.nextStartMs,
    this.calendarDays = const [],
    this.seasonWindow,
    required this.events,
  });

  factory ScoresResponse.fromJson(Map<String, dynamic> j) => ScoresResponse(
        sport: _str(j['sport']),
        league: _str(j['league']),
        leagueId: _str(j['leagueId']),
        leagueName: _str(j['leagueName']),
        season: Season.fromJson(_map(j['season'])),
        day: _strOrNull(j['day']),
        updated: DateTime.tryParse(_str(j['updated']))?.toLocal(),
        anyLive: _bool(j['anyLive']),
        nextStartMs: _int(j['nextStartMs']),
        calendarDays:
            _list(j['calendarDays']).map(_str).toList(growable: false),
        seasonWindow: j['seasonWindow'] == null
            ? null
            : SeasonWindow.fromJson(_map(j['seasonWindow'])),
        events: _list(j['events'])
            .map((e) => SportEvent.fromJson(_map(e)))
            .toList(growable: false),
      );
}

/// A league's season window (leagues[0].season). Both ends optional/tolerant.
class SeasonWindow {
  final DateTime? start, end;
  SeasonWindow({this.start, this.end});
  factory SeasonWindow.fromJson(Map<String, dynamic> j) => SeasonWindow(
        start: DateTime.tryParse(_str(j['startDate']))?.toLocal(),
        end: DateTime.tryParse(_str(j['endDate']))?.toLocal(),
      );
}

class Season {
  final int? year, type;
  final String? slug, displayName;
  Season({this.year, this.type, this.slug, this.displayName});
  factory Season.fromJson(Map<String, dynamic> j) => Season(
        year: _int(j['year']),
        type: _int(j['type']),
        slug: _strOrNull(j['slug']),
        displayName: _strOrNull(j['displayName']),
      );
}

class SportEvent {
  final String id, name, shortName;
  final DateTime? start;
  final bool neutralSite;
  final Venue? venue;
  final Circuit? circuit; // racing only — the §2.9 Circuit tab join
  final List<String> broadcasts;
  final List<String> notes;
  final String? weekLabel; // 'Week 5' / 'Round 15' (gridiron/rugby, regular season)
  final Weather? weather; // outdoor venues only
  final EventLinks links;
  final List<Competition> competitions;

  /// When this event is a single tennis match exploded out of its parent
  /// tournament ([matches]), the id of that parent tournament event — so game
  /// detail can re-resolve the live match inside the freshest tournament slate.
  /// Null for ordinary (already one-competition) events.
  final String? tournamentId;

  SportEvent({
    required this.id,
    required this.name,
    required this.shortName,
    required this.start,
    required this.neutralSite,
    required this.venue,
    this.circuit,
    required this.broadcasts,
    required this.notes,
    this.weekLabel,
    this.weather,
    required this.links,
    required this.competitions,
    this.tournamentId,
  });

  /// The competition to foreground. Most events have exactly one; a racing weekend
  /// has several (ESPN orders them FP1/FP2/FP3/Qual/Race) — surface the live session,
  /// else the Race, else the first, so the card never headlines practice. A tennis
  /// tournament also nests many competitions, but the UI routes those through
  /// [isTournamentOfMatches] → [matches] (one card per match) rather than `main`.
  Competition? get main {
    if (competitions.isEmpty) return null;
    if (competitions.length > 1) {
      for (final c in competitions) {
        if (c.status.live) return c;
      }
      for (final c in competitions) {
        if ((c.label ?? '').toLowerCase() == 'race') return c;
      }
    }
    return competitions.first;
  }

  /// A tennis-style event: a whole tournament nesting many independent, set-based
  /// head-to-head matches (singles = athlete, doubles = pair). Discriminator-
  /// driven, never sport name: volleyball is set-based too but team-vs-team
  /// (competitorKind `team`), and MMA/boxing is round-based — both fall out here,
  /// so neither is mistaken for a tournament. Routes the Scores list to a calm
  /// per-tournament summary row that drills into [matches] instead of collapsing
  /// the whole draw onto one (fight-card-shaped) detail screen.
  bool get isTournamentOfMatches =>
      competitions.length > 1 &&
      competitions.every((c) =>
          c.layout == 'headToHead' &&
          c.competitorKind != 'team' &&
          c.periods.unit == 'set');

  /// This tournament's matches, one single-competition [SportEvent] per match —
  /// the design's "one card per match". Each keeps the real ESPN match id (so
  /// rows/detail are uniquely keyed) and the parent [tournamentId] (so a live
  /// match re-resolves inside the freshest tournament slate).
  List<SportEvent> get matches =>
      [for (final c in competitions) withCompetition(c)];

  /// A shallow copy carrying a single competition — explodes one match out of a
  /// tennis tournament. Re-ids to the match (unique) and records the parent
  /// tournament id in [tournamentId].
  SportEvent withCompetition(Competition c) => SportEvent(
        id: c.id,
        tournamentId: id,
        name: name,
        shortName: shortName,
        start: start,
        neutralSite: neutralSite,
        venue: venue,
        circuit: circuit,
        broadcasts: broadcasts,
        notes: notes,
        weekLabel: weekLabel,
        weather: weather,
        links: links,
        competitions: [c],
      );

  factory SportEvent.fromJson(Map<String, dynamic> j) => SportEvent(
        id: _str(j['id']),
        name: _str(j['name']),
        shortName: _str(j['shortName']),
        start: DateTime.tryParse(_str(j['start']))?.toLocal(),
        neutralSite: _bool(j['neutralSite']),
        venue: j['venue'] == null ? null : Venue.fromJson(_map(j['venue'])),
        circuit: j['circuit'] == null ? null : Circuit.fromJson(_map(j['circuit'])),
        broadcasts: _list(j['broadcasts']).map(_str).toList(growable: false),
        notes: _list(j['notes']).map(_str).toList(growable: false),
        weekLabel: _strOrNull(j['weekLabel']),
        weather:
            j['weather'] == null ? null : Weather.fromJson(_map(j['weather'])),
        links: EventLinks.fromJson(_map(j['links'])),
        competitions: _list(j['competitions'])
            .map((c) => Competition.fromJson(_map(c)))
            .toList(growable: false),
        tournamentId: _strOrNull(j['tournamentId']),
      );
}

class Venue {
  /// CORE venues/{id} join id (scoreboard competitions[].venue.id) — gates the
  /// §2.9 Venue tab. Null when ESPN ships no venue id (e.g. racing).
  final String? id;
  final String name;
  final String? city, country;
  final bool indoor;
  Venue({this.id, required this.name, this.city, this.country, this.indoor = false});
  factory Venue.fromJson(Map<String, dynamic> j) => Venue(
        id: _strOrNull(j['id']),
        name: _str(j['name']),
        city: _strOrNull(j['city']),
        country: _strOrNull(j['country']),
        indoor: _bool(j['indoor']),
      );
  String get location =>
      [if (city != null) city, if (country != null) country].join(', ');
}

/// Racing circuit join (scoreboard events[].circuit) — gates the §2.9 Circuit
/// tab (CORE circuits/{id}). Present for racing only; every field tolerant.
class Circuit {
  final String? id, fullName, city, country;
  Circuit({this.id, this.fullName, this.city, this.country});
  factory Circuit.fromJson(Map<String, dynamic> j) => Circuit(
        id: _strOrNull(j['id']),
        fullName: _strOrNull(j['fullName']),
        city: _strOrNull(j['city']),
        country: _strOrNull(j['country']),
      );
}

/// Outdoor-game weather (emitted only for non-indoor venues).
class Weather {
  final num? temperature;
  final String? condition;
  Weather({this.temperature, this.condition});
  factory Weather.fromJson(Map<String, dynamic> j) => Weather(
        temperature: _num(j['temperature']),
        condition: _strOrNull(j['condition']),
      );

  /// '77° · Cloudy' — temp and/or sky, whichever is present.
  String get summary => [
        if (temperature != null) '${temperature!.round()}°',
        if (condition != null && condition!.isNotEmpty) condition,
      ].join(' · ');
}

class EventLinks {
  final String? web, box;
  EventLinks({this.web, this.box});
  factory EventLinks.fromJson(Map<String, dynamic> j) =>
      EventLinks(web: _strOrNull(j['web']), box: _strOrNull(j['box']));
}

// ---- Venue & Circuit facts (the §2.9 detail tab; core venues/{id} · circuits/{id})

/// A rel-tagged CDN asset — a venue photo or a circuit track-map diagram.
class VenueImage {
  final String href;
  final List<String> rel;
  VenueImage({required this.href, this.rel = const []});
  factory VenueImage.fromJson(Map<String, dynamic> j) => VenueImage(
        href: _str(j['href']),
        rel: _list(j['rel']).map(_str).toList(growable: false),
      );
}

/// A parsed measurement string like `"7.004 km"` → value + unit + display.
class Measure {
  final num? value;
  final String? unit;
  final String display;
  Measure({this.value, this.unit, required this.display});
  factory Measure.fromJson(Map<String, dynamic> j) => Measure(
        value: _num(j['value']),
        unit: _strOrNull(j['unit']),
        display: _str(j['display']),
      );
}

/// F1 lap record: time + year + (best-effort resolved) driver identity.
class LapRecord {
  final String? time;
  final int? year;
  final String? driverName, driverHeadshot;
  LapRecord({this.time, this.year, this.driverName, this.driverHeadshot});
  factory LapRecord.fromJson(Map<String, dynamic> j) {
    final d = _map(j['driver']);
    return LapRecord(
      time: _strOrNull(j['time']),
      year: _int(j['year']),
      driverName: _strOrNull(d['name']),
      driverHeadshot: _strOrNull(d['headshot']),
    );
  }
}

/// Stadium facts for the Venue tab — lazy `core venues/{id}` (join on the
/// scoreboard `competitions[].venue.id`). NO capacity/opened (NOT OBSERVED).
/// `length`/`turns` are only present for non-F1 racing venues (ovals).
class VenueFacts {
  final String id, name;
  final String? city, state, country, address1, photo;
  final List<VenueImage> images;
  final String? surface; // 'grass' | 'turf'
  final String? roof; // 'open' | 'indoor'
  final num? length; // non-F1 racing track length (miles)
  final int? turns;
  VenueFacts({
    required this.id,
    required this.name,
    this.city,
    this.state,
    this.country,
    this.address1,
    this.photo,
    this.images = const [],
    this.surface,
    this.roof,
    this.length,
    this.turns,
  });
  factory VenueFacts.fromJson(Map<String, dynamic> j) => VenueFacts(
        id: _str(j['id']),
        name: _str(j['name']),
        city: _strOrNull(j['city']),
        state: _strOrNull(j['state']),
        country: _strOrNull(j['country']),
        address1: _strOrNull(j['address1']),
        photo: _strOrNull(j['photo']),
        images: _list(j['images'])
            .map((e) => VenueImage.fromJson(_map(e)))
            .toList(growable: false),
        surface: _strOrNull(j['surface']),
        roof: _strOrNull(j['roof']),
        length: _num(j['length']),
        turns: _int(j['turns']),
      );

  /// 'Chicago, IL' — city then state/country, whichever is present.
  String get location => [
        if (city != null && city!.isNotEmpty) city,
        if (state != null && state!.isNotEmpty) state
        else if (country != null && country!.isNotEmpty) country,
      ].join(', ');
}

/// F1 circuit facts for the Circuit tab — lazy `core circuits/{id}` (join on the
/// scoreboard `events[].circuit.id`). The happy path: every fact 100% for F1.
class CircuitFacts {
  final String id, name;
  final String? city, country, diagram, direction;
  final List<VenueImage> diagrams;
  final int? established, laps, turns;
  final Measure? length, distance;
  final LapRecord? fastestLap;
  CircuitFacts({
    required this.id,
    required this.name,
    this.city,
    this.country,
    this.diagram,
    this.direction,
    this.diagrams = const [],
    this.established,
    this.laps,
    this.turns,
    this.length,
    this.distance,
    this.fastestLap,
  });
  factory CircuitFacts.fromJson(Map<String, dynamic> j) => CircuitFacts(
        id: _str(j['id']),
        name: _str(j['name']),
        city: _strOrNull(j['city']),
        country: _strOrNull(j['country']),
        diagram: _strOrNull(j['diagram']),
        direction: _strOrNull(j['direction']),
        diagrams: _list(j['diagrams'])
            .map((e) => VenueImage.fromJson(_map(e)))
            .toList(growable: false),
        established: _int(j['established']),
        laps: _int(j['laps']),
        turns: _int(j['turns']),
        length: j['length'] is Map ? Measure.fromJson(_map(j['length'])) : null,
        distance: j['distance'] is Map ? Measure.fromJson(_map(j['distance'])) : null,
        fastestLap:
            j['fastestLap'] is Map ? LapRecord.fromJson(_map(j['fastestLap'])) : null,
      );

  /// 'Stavelot, Belgium' — city then country.
  String get location => [
        if (city != null && city!.isNotEmpty) city,
        if (country != null && country!.isNotEmpty) country,
      ].join(', ');
}

// ---- Athlete / player profile (§2.6; core athletes/{id} + statistics + eventlog)

/// One stat cell — shared by season totals and per-game lines.
class AthleteStat {
  final String name, displayValue;
  final String? abbreviation, displayName, shortDisplayName;
  final num? value;
  AthleteStat({
    required this.name,
    required this.displayValue,
    this.abbreviation,
    this.displayName,
    this.shortDisplayName,
    this.value,
  });
  factory AthleteStat.fromJson(Map<String, dynamic> j) => AthleteStat(
        name: _str(j['name']),
        displayValue: _str(j['displayValue']),
        abbreviation: _strOrNull(j['abbreviation']),
        displayName: _strOrNull(j['displayName']),
        shortDisplayName: _strOrNull(j['shortDisplayName']),
        value: _num(j['value']),
      );
}

/// A stat category (Pitching/Fielding, Offensive/Defensive/General). Keyed by
/// `name`; the app picks the headline cells per league — never by sport name.
class AthleteStatCategory {
  final String name;
  final String? displayName;
  final List<AthleteStat> stats;
  AthleteStatCategory({required this.name, this.displayName, this.stats = const []});
  factory AthleteStatCategory.fromJson(Map<String, dynamic> j) => AthleteStatCategory(
        name: _str(j['name']),
        displayName: _strOrNull(j['displayName']),
        stats: _list(j['stats'])
            .map((e) => AthleteStat.fromJson(_map(e)))
            .toList(growable: false),
      );
}

/// One row of the last-N game log (eventlog item, $ref-resolved).
class AthleteGameRow {
  final String eventId;
  final String? date, name, shortName, teamId;
  final List<AthleteStatCategory> stats;
  AthleteGameRow({
    required this.eventId,
    this.date,
    this.name,
    this.shortName,
    this.teamId,
    this.stats = const [],
  });
  factory AthleteGameRow.fromJson(Map<String, dynamic> j) => AthleteGameRow(
        eventId: _str(j['eventId']),
        date: _strOrNull(j['date']),
        name: _strOrNull(j['name']),
        shortName: _strOrNull(j['shortName']),
        teamId: _strOrNull(j['teamId']),
        stats: _list(j['stats'])
            .map((e) => AthleteStatCategory.fromJson(_map(e)))
            .toList(growable: false),
      );
}

/// The athlete's team block, resolved from team.$ref.
class AthleteTeam {
  final String id, name;
  final String? abbr, color, logo, logoDark;
  AthleteTeam({
    required this.id,
    required this.name,
    this.abbr,
    this.color,
    this.logo,
    this.logoDark,
  });
  factory AthleteTeam.fromJson(Map<String, dynamic> j) => AthleteTeam(
        id: _str(j['id']),
        name: _str(j['name']),
        abbr: _strOrNull(j['abbr']),
        color: _strOrNull(j['color']),
        logo: _strOrNull(j['logo']),
        logoDark: _strOrNull(j['logoDark']),
      );
}

/// A player profile — the lazy, fanned-out §2.6 "Player rows" feed for the Phase 5
/// player page. Identity always present; `stats`/`lastGames`/`team` are best-effort
/// (a partial, identity-only profile is valid).
class AthleteProfile {
  final String id, league, name;
  final String? shortName, jersey, position, headshot, height, weight;
  final int? age;
  final AthleteTeam? team;
  final List<AthleteStatCategory> stats;
  final List<AthleteGameRow> lastGames;
  AthleteProfile({
    required this.id,
    required this.league,
    required this.name,
    this.shortName,
    this.jersey,
    this.position,
    this.headshot,
    this.height,
    this.weight,
    this.age,
    this.team,
    this.stats = const [],
    this.lastGames = const [],
  });
  factory AthleteProfile.fromJson(Map<String, dynamic> j) => AthleteProfile(
        id: _str(j['id']),
        league: _str(j['league']),
        name: _str(j['name']),
        shortName: _strOrNull(j['shortName']),
        jersey: _strOrNull(j['jersey']),
        position: _strOrNull(j['position']),
        headshot: _strOrNull(j['headshot']),
        height: _strOrNull(j['height']),
        weight: _strOrNull(j['weight']),
        age: _int(j['age']),
        team: j['team'] is Map ? AthleteTeam.fromJson(_map(j['team'])) : null,
        stats: _list(j['stats'])
            .map((e) => AthleteStatCategory.fromJson(_map(e)))
            .toList(growable: false),
        lastGames: _list(j['lastGames'])
            .map((e) => AthleteGameRow.fromJson(_map(e)))
            .toList(growable: false),
      );
}

class Competition {
  final String id, layout, scoreKind, competitorKind;
  final String? label; // racing session (FP1/Qual/Race)
  final Status status;
  final Periods periods;
  final String? decision;
  final List<Competitor> competitors;
  final Method? method;
  final CompetitionMeta? meta;
  final Situation? situation; // live "what's happening now" strip
  final List<ScoringEvent> events; // cheap goal/card timeline (soccer/rugby)
  // ---- cheap-tier passthroughs (scoreboard, 2026-07) ----
  final int? attendance;
  final String? headline; // one-line ESPN recap/preview (a single calm line)
  final bool conferenceGame; // college conference matchup
  final bool wasSuspended; // MLB: suspended earlier, later resumed
  final String? broadcast; // cheap TV/stream label ('MLB.TV/TBS', 'ESPN')
  final Odds? odds; // pre-game betting line (inline scoreboard or core enrichment)

  Competition({
    required this.id,
    required this.layout,
    required this.scoreKind,
    required this.competitorKind,
    required this.status,
    required this.periods,
    required this.decision,
    required this.competitors,
    required this.method,
    required this.meta,
    this.situation,
    this.events = const [],
    this.label,
    this.attendance,
    this.headline,
    this.conferenceGame = false,
    this.wasSuspended = false,
    this.broadcast,
    this.odds,
  });

  bool get isField => layout == 'field';

  /// A copy with a replaced [situation] — used by the game-detail screen to fold
  /// the detail-open core situation over the cheap scoreboard one without mutating
  /// the shared feed model. Everything else is carried through by reference.
  Competition withSituation(Situation? s) => Competition(
        id: id,
        layout: layout,
        scoreKind: scoreKind,
        competitorKind: competitorKind,
        status: status,
        periods: periods,
        decision: decision,
        competitors: competitors,
        method: method,
        meta: meta,
        situation: s,
        events: events,
        label: label,
        attendance: attendance,
        headline: headline,
        conferenceGame: conferenceGame,
        wasSuspended: wasSuspended,
        broadcast: broadcast,
        odds: odds,
      );

  Competitor? competitorByHome(String homeAway) {
    for (final c in competitors) {
      if (c.homeAway == homeAway) return c;
    }
    return null;
  }

  Competitor? get home => competitorByHome('home');
  Competitor? get away => competitorByHome('away');

  factory Competition.fromJson(Map<String, dynamic> j) => Competition(
        id: _str(j['id']),
        label: _strOrNull(j['label']),
        layout: _str(j['layout']),
        scoreKind: _str(j['scoreKind']),
        competitorKind: _str(j['competitorKind']),
        status: Status.fromJson(_map(j['status'])),
        periods: Periods.fromJson(_map(j['periods'])),
        decision: _strOrNull(j['decision']),
        competitors: _list(j['competitors'])
            .map((c) => Competitor.fromJson(_map(c)))
            .toList(growable: false),
        method: j['method'] == null ? null : Method.fromJson(_map(j['method'])),
        meta: j['meta'] == null
            ? null
            : CompetitionMeta.fromJson(_map(j['meta'])),
        situation: j['situation'] == null
            ? null
            : Situation.fromJson(_map(j['situation'])),
        events: _list(j['events'])
            .map((e) => ScoringEvent.fromJson(_map(e)))
            .toList(growable: false),
        attendance: _int(j['attendance']),
        headline: _strOrNull(j['headline']),
        conferenceGame: _bool(j['conferenceGame']),
        wasSuspended: _bool(j['wasSuspended']),
        broadcast: _strOrNull(j['broadcast']),
        odds: j['odds'] == null ? null : Odds.fromJson(_map(j['odds'])),
      );

  /// Red cards by side, derived from the cheap [events] timeline — drives the
  /// card's "man down" glyph. Empty map when none.
  Map<String, int> get redCardsBySide {
    final out = <String, int>{};
    for (final e in events) {
      if (e.type == 'red-card' && e.team != null) {
        out[e.team!] = (out[e.team!] ?? 0) + 1;
      }
    }
    return out;
  }
}

/// Pre-game betting line (canonical Odds). Spread/total come cheap off the inline
/// scoreboard odds[]; the per-team moneyline is added when the detail screen
/// enriches from the core competition-odds list. All fields optional — render
/// only what's present, hide the block cleanly when nothing is.
class Odds {
  final String? details; // 'SEA -3.5' favorite + line summary
  final num? spread; // signed point spread
  final num? overUnder; // game total
  final num? homeMoneyline, awayMoneyline, drawMoneyline;
  final String? provider; // 'DraftKings'
  const Odds({
    this.details,
    this.spread,
    this.overUnder,
    this.homeMoneyline,
    this.awayMoneyline,
    this.drawMoneyline,
    this.provider,
  });
  factory Odds.fromJson(Map<String, dynamic> j) => Odds(
        details: _strOrNull(j['details']),
        spread: _num(j['spread']),
        overUnder: _num(j['overUnder']),
        homeMoneyline: _num(j['homeMoneyline']),
        awayMoneyline: _num(j['awayMoneyline']),
        drawMoneyline: _num(j['drawMoneyline']),
        provider: _strOrNull(j['provider']),
      );

  bool get hasMoneyline =>
      homeMoneyline != null || awayMoneyline != null || drawMoneyline != null;

  /// American-odds string for a moneyline number (+150 / -110).
  static String? moneyline(num? v) =>
      v == null ? null : (v > 0 ? '+${v.toInt()}' : '${v.toInt()}');
}

/// One normalized timeline event (goal / card / try) from the cheap scoreboard
/// `competition.details[]`. Mirrors canonical ScoringEvent.
class ScoringEvent {
  final String type; // goal | own-goal | penalty-goal | yellow-card | red-card | score | …
  final String? team; // 'home' | 'away'
  final String? clock; // "45'+2'"
  final int? period;
  final String? athlete; // scorer / booked player short name
  final String? detail; // ESPN type text ('Goal', 'Yellow Card')
  final num? scoreValue;
  final bool ownGoal, penalty, redCard;
  ScoringEvent({
    required this.type,
    this.team,
    this.clock,
    this.period,
    this.athlete,
    this.detail,
    this.scoreValue,
    this.ownGoal = false,
    this.penalty = false,
    this.redCard = false,
  });
  factory ScoringEvent.fromJson(Map<String, dynamic> j) {
    final flags = _map(j['flags']);
    return ScoringEvent(
      type: _str(j['type']),
      team: _strOrNull(j['team']),
      clock: _strOrNull(j['clock']),
      period: _int(j['period']),
      athlete: _strOrNull(j['athlete']),
      detail: _strOrNull(j['detail']),
      scoreValue: _num(j['scoreValue']),
      ownGoal: _bool(flags['ownGoal']),
      penalty: _bool(flags['penalty']),
      redCard: _bool(flags['redCard']),
    );
  }

  bool get isGoal =>
      type == 'goal' || type == 'own-goal' || type == 'penalty-goal';
  bool get isCard => type == 'yellow-card' || type == 'red-card';
}

/// Live game situation — sport-agnostic union, only present keys are set.
class Situation {
  // baseball
  final int? balls, strikes, outs;
  final bool? onFirst, onSecond, onThird;
  final String? pitcher, batter, outsText;
  final String? pitcherLine, batterLine; // live matchup lines ('0.2 IP, 0 ER' / '1-3')
  // gridiron
  final int? down, distance, homeTimeouts, awayTimeouts, yardLine;
  final String? downDistanceText, possession;
  final bool? isRedZone;
  // basketball (core: bonus state per side, 'NONE' | 'ONE' | 'DOUBLE')
  final String? homeBonus, awayBonus;
  // hockey (cheap: scoreboard situation)
  final bool? powerPlay, emptyNet;
  final String? strength; // 'power-play' | 'short-handed' | 'even-strength' | 'empty-net'
  final String? strengthTeam; // competitor id of the side on the man advantage
  // any sport
  final String? lastPlay;
  // basketball CHEAP win prob (0-100 int) — home side; absent for other sports.
  final int? homeWinPct;
  Situation({
    this.balls,
    this.strikes,
    this.outs,
    this.onFirst,
    this.onSecond,
    this.onThird,
    this.pitcher,
    this.batter,
    this.pitcherLine,
    this.batterLine,
    this.outsText,
    this.down,
    this.distance,
    this.homeTimeouts,
    this.awayTimeouts,
    this.yardLine,
    this.downDistanceText,
    this.possession,
    this.isRedZone,
    this.homeBonus,
    this.awayBonus,
    this.powerPlay,
    this.emptyNet,
    this.strength,
    this.strengthTeam,
    this.lastPlay,
    this.homeWinPct,
  });
  factory Situation.fromJson(Map<String, dynamic> j) => Situation(
        balls: _int(j['balls']),
        strikes: _int(j['strikes']),
        outs: _int(j['outs']),
        onFirst: j['onFirst'] is bool ? j['onFirst'] as bool : null,
        onSecond: j['onSecond'] is bool ? j['onSecond'] as bool : null,
        onThird: j['onThird'] is bool ? j['onThird'] as bool : null,
        pitcher: _strOrNull(j['pitcher']),
        batter: _strOrNull(j['batter']),
        pitcherLine: _strOrNull(j['pitcherLine']),
        batterLine: _strOrNull(j['batterLine']),
        outsText: _strOrNull(j['outsText']),
        down: _int(j['down']),
        distance: _int(j['distance']),
        homeTimeouts: _int(j['homeTimeouts']),
        awayTimeouts: _int(j['awayTimeouts']),
        yardLine: _int(j['yardLine']),
        downDistanceText: _strOrNull(j['downDistanceText']),
        possession: _strOrNull(j['possession']),
        isRedZone: j['isRedZone'] is bool ? j['isRedZone'] as bool : null,
        homeBonus: _strOrNull(j['homeBonus']),
        awayBonus: _strOrNull(j['awayBonus']),
        powerPlay: j['powerPlay'] is bool ? j['powerPlay'] as bool : null,
        emptyNet: j['emptyNet'] is bool ? j['emptyNet'] as bool : null,
        strength: _strOrNull(j['strength']),
        strengthTeam: _strOrNull(j['strengthTeam']),
        lastPlay: _strOrNull(j['lastPlay']),
        homeWinPct: _int(j['homeWinPct']),
      );

  /// Overlay a [core] situation (from the detail-open core fetch) onto this
  /// scoreboard situation: any non-null field of [core] wins, everything else is
  /// kept. Used by the game-detail screen so the richer core state (gridiron
  /// down/distance, basketball bonus/timeouts, hockey power play) upgrades the
  /// cheap glance in place. Null [core] returns this unchanged.
  Situation mergedWith(Situation? core) {
    if (core == null) return this;
    return Situation(
      balls: core.balls ?? balls,
      strikes: core.strikes ?? strikes,
      outs: core.outs ?? outs,
      onFirst: core.onFirst ?? onFirst,
      onSecond: core.onSecond ?? onSecond,
      onThird: core.onThird ?? onThird,
      pitcher: core.pitcher ?? pitcher,
      batter: core.batter ?? batter,
      pitcherLine: core.pitcherLine ?? pitcherLine,
      batterLine: core.batterLine ?? batterLine,
      outsText: core.outsText ?? outsText,
      down: core.down ?? down,
      distance: core.distance ?? distance,
      homeTimeouts: core.homeTimeouts ?? homeTimeouts,
      awayTimeouts: core.awayTimeouts ?? awayTimeouts,
      yardLine: core.yardLine ?? yardLine,
      downDistanceText: core.downDistanceText ?? downDistanceText,
      possession: core.possession ?? possession,
      isRedZone: core.isRedZone ?? isRedZone,
      homeBonus: core.homeBonus ?? homeBonus,
      awayBonus: core.awayBonus ?? awayBonus,
      powerPlay: core.powerPlay ?? powerPlay,
      emptyNet: core.emptyNet ?? emptyNet,
      strength: core.strength ?? strength,
      strengthTeam: core.strengthTeam ?? strengthTeam,
      lastPlay: core.lastPlay ?? lastPlay,
      homeWinPct: core.homeWinPct ?? homeWinPct,
    );
  }

  bool get hasBaseball => balls != null || strikes != null || outs != null;
  bool get hasGridiron => downDistanceText != null || down != null;

  /// A side is (or isn't) in the bonus — the basketball core-situation flourish.
  /// 'NONE' means not in bonus; any other value ('ONE'/'DOUBLE') is in bonus.
  bool _inBonus(String? s) => s != null && s.toUpperCase() != 'NONE';
  bool get homeInBonus => _inBonus(homeBonus);
  bool get awayInBonus => _inBonus(awayBonus);

  /// Basketball core state worth a card: a bonus reading for either side, or the
  /// per-side timeout counts the scoreboard doesn't carry.
  bool get hasBonus => homeBonus != null || awayBonus != null;

  /// A side has the man advantage (hockey): an explicit power-play flag, or a
  /// non-even strength label that isn't just an empty net.
  bool get hasPowerPlay =>
      powerPlay == true ||
      (strength != null &&
          strength != 'even-strength' &&
          strength != 'empty-net');
}

class Status {
  final String phase, periodLabel, espnName, detail;
  final String? shortDetail, altDetail, clock;
  final bool live, ended;
  final int period;

  Status({
    required this.phase,
    required this.live,
    required this.ended,
    required this.period,
    required this.periodLabel,
    required this.espnName,
    required this.detail,
    this.shortDetail,
    this.altDetail,
    this.clock,
  });

  bool get isScheduled => phase == 'scheduled';
  bool get isFinal => phase == 'final';

  factory Status.fromJson(Map<String, dynamic> j) => Status(
        phase: _str(j['phase']),
        live: _bool(j['live']),
        ended: _bool(j['ended']),
        period: _int(j['period']) ?? 0,
        periodLabel: _str(j['periodLabel']),
        espnName: _str(j['espnName']),
        detail: _str(j['detail']),
        shortDetail: _strOrNull(j['shortDetail']),
        altDetail: _strOrNull(j['altDetail']),
        clock: _strOrNull(j['clock']),
      );
}

class Periods {
  final String unit;
  final int regulation, played;
  final bool isOvertime;
  final int? lengthMin;
  Periods({
    required this.unit,
    required this.regulation,
    required this.played,
    required this.isOvertime,
    this.lengthMin,
  });
  factory Periods.fromJson(Map<String, dynamic> j) => Periods(
        unit: _str(j['unit']),
        regulation: _int(j['regulation']) ?? 0,
        played: _int(j['played']) ?? 0,
        isOvertime: _bool(j['isOvertime']),
        lengthMin: _int(j['lengthMin']),
      );
}

class Competitor {
  final String kind, id, displayName;
  final String? shortName,
      abbreviation,
      logo,
      logoDark,
      color,
      altColor,
      homeAway;
  final int? order, startOrder, rank, seed;
  final bool? winner;
  final Score? score;
  final List<PeriodScore> periodScores;
  final List<Athlete> athletes;
  final List<TeamRecord> records;
  final num? shootoutScore;
  final String? aggregateScore;
  final bool? advance;
  // cheap-tier context already in the scoreboard
  final Map<String, String> stats; // team stat line, keyed by ESPN abbr
  final List<Leader> leaders;
  final List<Probable> probables;
  final int? hits, errors; // baseball R/H/E
  final String? form; // soccer/rugby recent form 'WLWWW'
  final Vehicle? vehicle; // racing
  final bool? serving; // tennis/volleyball: this competitor is serving

  Competitor({
    required this.kind,
    required this.id,
    required this.displayName,
    this.shortName,
    this.abbreviation,
    this.logo,
    this.logoDark,
    this.color,
    this.altColor,
    this.homeAway,
    this.order,
    this.startOrder,
    this.rank,
    this.seed,
    this.winner,
    this.score,
    required this.periodScores,
    required this.athletes,
    required this.records,
    this.shootoutScore,
    this.aggregateScore,
    this.advance,
    this.stats = const {},
    this.leaders = const [],
    this.probables = const [],
    this.hits,
    this.errors,
    this.form,
    this.vehicle,
    this.serving,
  });

  bool get isWinner => winner == true;
  String get label => abbreviation ?? shortName ?? displayName;
  String? get recordSummary => records.isEmpty ? null : records.first.summary;

  factory Competitor.fromJson(Map<String, dynamic> j) => Competitor(
        kind: _str(j['kind']),
        id: _str(j['id']),
        displayName: _str(j['displayName']),
        shortName: _strOrNull(j['shortName']),
        abbreviation: _strOrNull(j['abbreviation']),
        logo: _strOrNull(j['logo']),
        logoDark: _strOrNull(j['logoDark']),
        color: _strOrNull(j['color']),
        altColor: _strOrNull(j['altColor']),
        homeAway: _strOrNull(j['homeAway']),
        order: _int(j['order']),
        startOrder: _int(j['startOrder']),
        rank: _int(j['rank']),
        seed: _int(j['seed']),
        winner: j['winner'] is bool ? j['winner'] as bool : null,
        score: j['score'] == null ? null : Score.fromJson(_map(j['score'])),
        periodScores: _list(j['periodScores'])
            .map((p) => PeriodScore.fromJson(_map(p)))
            .toList(growable: false),
        athletes: _list(j['athletes'])
            .map((a) => Athlete.fromJson(_map(a)))
            .toList(growable: false),
        records: _list(j['records'])
            .map((r) => TeamRecord.fromJson(_map(r)))
            .toList(growable: false),
        shootoutScore: _num(j['shootoutScore']),
        aggregateScore: _strOrNull(j['aggregateScore']),
        advance: j['advance'] is bool ? j['advance'] as bool : null,
        stats: _map(j['stats']).map((k, v) => MapEntry(k, _str(v))),
        leaders: _list(j['leaders'])
            .map((l) => Leader.fromJson(_map(l)))
            .toList(growable: false),
        probables: _list(j['probables'])
            .map((p) => Probable.fromJson(_map(p)))
            .toList(growable: false),
        hits: _int(j['hits']),
        errors: _int(j['errors']),
        form: _strOrNull(j['form']),
        vehicle:
            j['vehicle'] == null ? null : Vehicle.fromJson(_map(j['vehicle'])),
        serving: j['serving'] is bool ? j['serving'] as bool : null,
      );

  /// Baseball R/H/E availability.
  bool get hasRHE => hits != null || errors != null;
}

class Vehicle {
  final String? number, manufacturer, team, owner, sponsor;
  Vehicle(
      {this.number, this.manufacturer, this.team, this.owner, this.sponsor});
  factory Vehicle.fromJson(Map<String, dynamic> j) => Vehicle(
        number: _strOrNull(j['number']),
        manufacturer: _strOrNull(j['manufacturer']),
        team: _strOrNull(j['team']),
        owner: _strOrNull(j['owner']),
        sponsor: _strOrNull(j['sponsor']),
      );
}

class Leader {
  final String name, label;
  final String? display, athlete;
  Leader({required this.name, required this.label, this.display, this.athlete});
  factory Leader.fromJson(Map<String, dynamic> j) => Leader(
        name: _str(j['name']),
        label: _str(j['label']),
        display: _strOrNull(j['display']),
        athlete: _strOrNull(j['athlete']),
      );
}

class Probable {
  final String role, athlete;
  final String? record; // MLB '(5-4, 3.30)'
  final bool confirmed; // NHL goalie locked (vs projected)
  Probable({
    required this.role,
    required this.athlete,
    this.record,
    this.confirmed = false,
  });
  factory Probable.fromJson(Map<String, dynamic> j) => Probable(
        role: _str(j['role']),
        athlete: _str(j['athlete']),
        record: _strOrNull(j['record']),
        confirmed: _bool(j['confirmed']),
      );
}

class Score {
  final String display;
  final num? value, toPar, strokes;
  Score({required this.display, this.value, this.toPar, this.strokes});
  factory Score.fromJson(Map<String, dynamic> j) => Score(
        display: _str(j['display']),
        value: _num(j['value']),
        toPar: _num(j['toPar']),
        strokes: _num(j['strokes']),
      );
}

class PeriodScore {
  final int period;
  final num? value;
  final String display;
  final num? tiebreak;
  final bool? setWinner; // tennis: did this competitor win the set
  final CricketScore? cricket; // cricket per-innings authoritative numbers
  final int? holesPlayed; // golf: holes completed in this round (THRU)
  PeriodScore({
    required this.period,
    required this.value,
    required this.display,
    this.tiebreak,
    this.setWinner,
    this.cricket,
    this.holesPlayed,
  });
  factory PeriodScore.fromJson(Map<String, dynamic> j) => PeriodScore(
        period: _int(j['period']) ?? 0,
        value: _num(j['value']),
        display: _str(j['display']),
        tiebreak: _num(j['tiebreak']),
        setWinner: j['setWinner'] is bool ? j['setWinner'] as bool : null,
        cricket: j['cricket'] == null
            ? null
            : CricketScore.fromJson(_map(j['cricket'])),
        holesPlayed: _int(j['holesPlayed']),
      );
}

class CricketScore {
  final num? runs, wickets, overs, target;
  final bool? isBatting, declared, allOut;
  final String? reason;
  CricketScore({
    this.runs,
    this.wickets,
    this.overs,
    this.target,
    this.isBatting,
    this.declared,
    this.allOut,
    this.reason,
  });
  factory CricketScore.fromJson(Map<String, dynamic> j) => CricketScore(
        runs: _num(j['runs']),
        wickets: _num(j['wickets']),
        overs: _num(j['overs']),
        target: _num(j['target']),
        isBatting: j['isBatting'] is bool ? j['isBatting'] as bool : null,
        declared: j['declared'] is bool ? j['declared'] as bool : null,
        allOut: j['allOut'] is bool ? j['allOut'] as bool : null,
        reason: _strOrNull(j['reason']),
      );

  /// '161/5' — runs/wickets, the way a fan reads a cricket innings.
  String get rw => '${runs ?? 0}/${wickets ?? 0}';
}

class Athlete {
  final String id, name;
  final String? jersey, country, headshot, position;
  Athlete({
    required this.id,
    required this.name,
    this.jersey,
    this.country,
    this.headshot,
    this.position,
  });
  factory Athlete.fromJson(Map<String, dynamic> j) => Athlete(
        id: _str(j['id']),
        name: _str(j['name']),
        jersey: _strOrNull(j['jersey']),
        country: _strOrNull(j['country']),
        headshot: _strOrNull(j['headshot']),
        position: _strOrNull(j['position']),
      );
}

class TeamRecord {
  final String type, summary;
  TeamRecord({required this.type, required this.summary});
  factory TeamRecord.fromJson(Map<String, dynamic> j) =>
      TeamRecord(type: _str(j['type']), summary: _str(j['summary']));
}

class Method {
  final String kind;
  final String? detail, target, finishTime;
  final int? finishRound;
  Method({
    required this.kind,
    this.detail,
    this.target,
    this.finishRound,
    this.finishTime,
  });
  factory Method.fromJson(Map<String, dynamic> j) => Method(
        kind: _str(j['kind']),
        detail: _strOrNull(j['detail']),
        target: _strOrNull(j['target']),
        finishRound: _int(j['finishRound']),
        finishTime: _strOrNull(j['finishTime']),
      );
  String get summary => [
        kind,
        if (detail != null) detail,
        if (finishRound != null) 'R$finishRound',
      ].join(' · ');
}

class CompetitionMeta {
  final String? round,
      seriesSummary,
      cardSegment,
      flag,
      cricketClass,
      cricketSummary;
  final bool? featured, hadPlayoff;
  final SeriesInfo? series; // structured playoff series → pip row
  final GolfMeta? golf; // cut line / major / rounds (core-enriched by the worker)
  CompetitionMeta({
    this.round,
    this.seriesSummary,
    this.cardSegment,
    this.flag,
    this.cricketClass,
    this.cricketSummary,
    this.featured,
    this.hadPlayoff,
    this.series,
    this.golf,
  });
  factory CompetitionMeta.fromJson(Map<String, dynamic> j) => CompetitionMeta(
        round: _strOrNull(j['round']),
        seriesSummary: _strOrNull(j['seriesSummary']),
        cardSegment: _strOrNull(j['cardSegment']),
        flag: _strOrNull(j['flag']),
        cricketClass: _strOrNull(j['cricketClass']),
        cricketSummary: _strOrNull(j['cricketSummary']),
        featured: j['featured'] is bool ? j['featured'] as bool : null,
        hadPlayoff: j['hadPlayoff'] is bool ? j['hadPlayoff'] as bool : null,
        series:
            j['series'] == null ? null : SeriesInfo.fromJson(_map(j['series'])),
        golf: j['golf'] == null ? null : GolfMeta.fromJson(_map(j['golf'])),
      );
}

/// Golf tournament meta (canonical meta.golf) — best-effort enrichment from the
/// core tournament resource; absent when the worker's core fetch failed.
class GolfMeta {
  final int numberOfRounds;
  final int? currentRound, cutRound, cutCount;
  final num? cutScore; // to-par cut line, e.g. -3
  final bool major;
  final String? scoringSystem; // 'Medal' | 'Teamstroke'
  GolfMeta({
    required this.numberOfRounds,
    this.currentRound,
    this.cutRound,
    this.cutCount,
    this.cutScore,
    this.major = false,
    this.scoringSystem,
  });
  factory GolfMeta.fromJson(Map<String, dynamic> j) => GolfMeta(
        numberOfRounds: _int(j['numberOfRounds']) ?? 4,
        currentRound: _int(j['currentRound']),
        cutRound: _int(j['cutRound']),
        cutCount: _int(j['cutCount']),
        cutScore: _num(j['cutScore']),
        major: _bool(j['major']),
        scoringSystem: _strOrNull(j['scoringSystem']),
      );

  /// Has a cut at all? cutRound 0 = signature/no-cut event.
  bool get hasCut => (cutRound ?? 0) > 0;

  /// 'Cut −3 · 79 made' — the one-line leaderboard caption; null when no cut
  /// or the line isn't known yet (before the cut round completes).
  String? get cutLine {
    if (!hasCut || cutScore == null) return null;
    final s = cutScore!;
    final scoreTxt = s == 0 ? 'E' : (s > 0 ? '+$s' : '−${s.abs()}');
    final made = cutCount != null ? ' · $cutCount made' : '';
    return 'Cut $scoreTxt$made';
  }
}

/// Structured best-of-N playoff series (NBA/NHL/MLB-playoff). `wins(id)` reads a
/// competitor's win count by id; `gamesToWin` is the clinch number (best-of-N).
class SeriesInfo {
  final String? type;
  final int? total;
  final bool completed;
  final List<({String id, int wins})> competitors;
  SeriesInfo({
    this.type,
    this.total,
    this.completed = false,
    required this.competitors,
  });
  factory SeriesInfo.fromJson(Map<String, dynamic> j) => SeriesInfo(
        type: _strOrNull(j['type']),
        total: _int(j['total']),
        completed: _bool(j['completed']),
        competitors: _list(j['competitors'])
            .map((c) {
              final m = _map(c);
              return (id: _str(m['id']), wins: _int(m['wins']) ?? 0);
            })
            .toList(growable: false),
      );

  int wins(String id) {
    for (final c in competitors) {
      if (c.id == id) return c.wins;
    }
    return 0;
  }

  /// Games needed to clinch — the majority floor(total/2)+1 of a best-of-N, else
  /// the max wins seen. (For odd totals floor(total/2)+1 == ceil(total/2).)
  int get gamesToWin {
    if (total != null && total! > 0) return (total! ~/ 2) + 1;
    return maxWins == 0 ? 1 : maxWins;
  }

  int get maxWins => competitors.fold<int>(0, (m, c) => c.wins > m ? c.wins : m);

  /// Total games decided so far (sum of both sides' wins).
  int get gamesPlayed => competitors.fold<int>(0, (s, c) => s + c.wins);

  /// Derived series game number (§Part I.6): sum(wins)+1 — only while the series
  /// is unfinished; null once a side has clinched.
  int? get gameNumber => completed ? null : gamesPlayed + 1;

  /// The leader can win the series with a win in this game (§Part I.6): one win
  /// short of the majority, and the series isn't already decided. In a scores row
  /// the two competitors ARE the series teams, so "leader plays today" holds.
  bool get canClinch =>
      !completed && total != null && total! > 0 && maxWins + 1 == gamesToWin;

  bool get isPlayoff => type == 'playoff' && competitors.length >= 2;
}

// ---- catalog ----------------------------------------------------------------
class CatalogSport {
  final String sport;
  final List<CatalogLeague> leagues;
  CatalogSport({required this.sport, required this.leagues});
  factory CatalogSport.fromJson(Map<String, dynamic> j) => CatalogSport(
        sport: _str(j['sport']),
        leagues: _list(j['leagues'])
            .map((l) => CatalogLeague.fromJson(_map(l)))
            .toList(growable: false),
      );
}

class CatalogLeague {
  final String key, league, name;
  final String? abbr, region, priority, leagueId;

  /// Whether ESPN's /teams returns a roster (drives the favorites picker). False
  /// for individual sports (golf/tennis/MMA/NASCAR); true for team sports + F1.
  /// Defaults true so an older worker (no flag) hides nothing.
  final bool hasTeams;

  /// Which /v1/rankings feed this league has ('polls' | 'tour' | 'divisions'),
  /// null when none — the league page shows a rankings panel only when set.
  final String? rankings;

  /// The competitor kind ('team' | 'athlete' | 'pair'). Gates the team page —
  /// only 'team' leagues have a /teamdetail worth opening. Defaults to 'team' so
  /// an older worker (no field) keeps the existing team-nav behavior.
  final String competitorKind;
  CatalogLeague({
    required this.key,
    required this.league,
    required this.name,
    this.abbr,
    this.region,
    this.priority,
    this.leagueId,
    this.hasTeams = true,
    this.rankings,
    this.competitorKind = 'team',
  });
  factory CatalogLeague.fromJson(Map<String, dynamic> j) => CatalogLeague(
        key: _str(j['key']),
        league: _str(j['league']),
        name: _str(j['name']),
        abbr: _strOrNull(j['abbr']),
        region: _strOrNull(j['region']),
        priority: _strOrNull(j['priority']),
        leagueId: _strOrNull(j['leagueId']),
        hasTeams: j['hasTeams'] != false,
        rankings: _strOrNull(j['rankings']),
        competitorKind: _strOrNull(j['competitorKind']) ?? 'team',
      );

  /// Whether a team in this league has an openable detail page.
  bool get hasTeamPage => competitorKind == 'team';
}

// ---- overview (Leagues season-pulse) ----------------------------------------
/// One league's at-a-glance state for the Leagues list. `state` is one of
/// live | today | upcoming | recent | offseason | unknown; `detail` is a short
/// human caption ("Live now", "Tomorrow", "Returns Aug 6"). Computed by the
/// worker (see worker/src/overview.js) so the app stays a thin renderer.
class LeagueStateInfo {
  final String key, state, detail;
  final bool live;
  LeagueStateInfo(
      {required this.key,
      required this.state,
      required this.detail,
      required this.live});
  factory LeagueStateInfo.fromJson(Map<String, dynamic> j) => LeagueStateInfo(
        key: _str(j['key']),
        state: _str(j['state']),
        detail: _str(j['detail']),
        live: _bool(j['live']),
      );
}

// ---- standings --------------------------------------------------------------
class Standings {
  final String league;
  final int? season;

  /// Per-family preferred columns (ordered ESPN stat key + display label), from the
  /// worker/registry. Empty → render with the generic heuristic.
  final List<StandingColumn> columns;
  final List<StandingsGroup> groups;
  Standings(
      {required this.league,
      this.season,
      this.columns = const [],
      required this.groups});
  factory Standings.fromJson(Map<String, dynamic> j) => Standings(
        league: _str(j['league']),
        season: _int(j['season']),
        columns: _list(j['columns'])
            .map((c) => StandingColumn.fromJson(_map(c)))
            .toList(growable: false),
        groups: _list(j['groups'])
            .map((g) => StandingsGroup.fromJson(_map(g)))
            .toList(growable: false),
      );
}

class StandingColumn {
  final String key, label;
  StandingColumn({required this.key, required this.label});
  factory StandingColumn.fromJson(Map<String, dynamic> j) =>
      StandingColumn(key: _str(j['key']), label: _str(j['label']));
}

class StandingsGroup {
  final String name;
  final List<StandingsRow> rows;
  StandingsGroup({required this.name, required this.rows});
  factory StandingsGroup.fromJson(Map<String, dynamic> j) => StandingsGroup(
        name: _str(j['name']),
        rows: _list(j['rows'])
            .map((r) => StandingsRow.fromJson(_map(r)))
            .toList(growable: false),
      );
}

class StandingsRow {
  final StandingsTeam team;
  final int? rank;
  final Map<String, String> stats;

  /// Qualification band (soccer only): the coloured cut-line + tag. Null when
  /// ESPN carries no note for this row.
  final StandingsNote? note;
  StandingsRow({required this.team, this.rank, required this.stats, this.note});
  factory StandingsRow.fromJson(Map<String, dynamic> j) => StandingsRow(
        team: StandingsTeam.fromJson(_map(j['team'])),
        rank: _int(j['rank']),
        stats: _map(j['stats']).map((k, v) => MapEntry(k, _str(v))),
        note: j['note'] == null ? null : StandingsNote.fromJson(_map(j['note'])),
      );
}

/// A soccer qualification band on a standings row: an ESPN hex [color] cut-line
/// swatch + a [description] tag ('Champions League' / 'Relegation'). Both
/// tolerant — either may be absent.
class StandingsNote {
  final String? color, description;
  StandingsNote({this.color, this.description});
  factory StandingsNote.fromJson(Map<String, dynamic> j) => StandingsNote(
        color: _strOrNull(j['color']),
        description: _strOrNull(j['description']),
      );
}

class StandingsTeam {
  final String id, name;
  final String? abbr, logo, logoDark;
  StandingsTeam(
      {required this.id,
      required this.name,
      this.abbr,
      this.logo,
      this.logoDark});
  factory StandingsTeam.fromJson(Map<String, dynamic> j) => StandingsTeam(
        id: _str(j['id']),
        name: _str(j['name']),
        abbr: _strOrNull(j['abbr']),
        logo: _strOrNull(j['logo']),
        logoDark: _strOrNull(j['logoDark']),
      );
}

/// A followed league's fetched scores (or an error), for the home feed.
class LeagueFeed {
  final String key;
  final ScoresResponse? scores;
  final String? error;
  LeagueFeed(this.key, this.scores, {this.error});
}

// ---- favorite teams ---------------------------------------------------------
/// A lightweight team reference for the favorites picker (/v1/teams).
class TeamRef {
  final String id, displayName;
  final String? abbreviation, logo, logoDark, color;
  TeamRef({
    required this.id,
    required this.displayName,
    this.abbreviation,
    this.logo,
    this.logoDark,
    this.color,
  });
  factory TeamRef.fromJson(Map<String, dynamic> j) => TeamRef(
        id: _str(j['id']),
        displayName: _str(j['displayName']),
        abbreviation: _strOrNull(j['abbreviation']),
        logo: _strOrNull(j['logo']),
        logoDark: _strOrNull(j['logoDark']),
        color: _strOrNull(j['color']),
      );
}

/// The team-identity block of a [TeamCard] / [TeamDetail] (name, crest, record,
/// and — new — a season standing line like '2nd in AL East').
class TeamCardTeam {
  final String id, displayName;
  final String? abbreviation, logo, logoDark, color, record, standingSummary;
  TeamCardTeam({
    required this.id,
    required this.displayName,
    this.abbreviation,
    this.logo,
    this.logoDark,
    this.color,
    this.record,
    this.standingSummary,
  });
  factory TeamCardTeam.fromJson(Map<String, dynamic> j) => TeamCardTeam(
        id: _str(j['id']),
        displayName: _str(j['displayName']),
        abbreviation: _strOrNull(j['abbreviation']),
        logo: _strOrNull(j['logo']),
        logoDark: _strOrNull(j['logoDark']),
        color: _strOrNull(j['color']),
        record: _strOrNull(j['record']),
        standingSummary: _strOrNull(j['standingSummary']),
      );
}

/// One favorite team's card (/v1/team): live game if any, else last + next.
/// The three event slots reuse the canonical [SportEvent] the scores feed uses.
class TeamCard {
  final String league, sport, leagueName;
  final TeamCardTeam team;
  final SportEvent? live, last, next;
  final bool anyLive;
  TeamCard({
    required this.league,
    required this.sport,
    required this.leagueName,
    required this.team,
    this.live,
    this.last,
    this.next,
    required this.anyLive,
  });

  /// The event the card should foreground: live first, else last result, else next.
  SportEvent? get primary => live ?? last ?? next;

  factory TeamCard.fromJson(Map<String, dynamic> j) {
    SportEvent? ev(dynamic v) =>
        v == null ? null : SportEvent.fromJson(_map(v));
    return TeamCard(
      league: _str(j['league']),
      sport: _str(j['sport']),
      leagueName: _str(j['leagueName']),
      team: TeamCardTeam.fromJson(_map(j['team'])),
      live: ev(j['live']),
      last: ev(j['last']),
      next: ev(j['next']),
      anyLive: _bool(j['anyLive']),
    );
  }
}

/// A persisted favorite team. Carries cached name/crest so a chip renders before
/// the card resolves; scoped by (league, teamId) since team ids repeat across
/// leagues. Stored as one JSON entry per [favoriteTeamsProvider] string-list slot.
class FavoriteTeam {
  final String league, teamId, name;
  final String? abbr, logo;

  /// Cached identity color (hex) — v2 renders teams as color bars, so rows can
  /// paint before any card resolves.
  final String? color;
  const FavoriteTeam({
    required this.league,
    required this.teamId,
    required this.name,
    this.abbr,
    this.logo,
    this.color,
  });

  /// Stable composite key for dedupe / membership.
  String get id => '$league#$teamId';

  Map<String, dynamic> toJson() => {
        'league': league,
        'teamId': teamId,
        'name': name,
        if (abbr != null) 'abbr': abbr,
        if (logo != null) 'logo': logo,
        if (color != null) 'color': color,
      };
  factory FavoriteTeam.fromJson(Map<String, dynamic> j) => FavoriteTeam(
        league: _str(j['league']),
        teamId: _str(j['teamId']),
        name: _str(j['name']),
        abbr: _strOrNull(j['abbr']),
        logo: _strOrNull(j['logo']),
        color: _strOrNull(j['color']),
      );
}

/// A favorite's fetched card (or an error), for the Scores Favorites section.
/// Mirrors [LeagueFeed]: a failed team degrades to an error, never breaks the row.
class FavoriteTeamFeed {
  final FavoriteTeam fav;
  final TeamCard? card;
  final String? error;
  FavoriteTeamFeed(this.fav, this.card, {this.error});
}

// ---- team detail (the rich team page) ---------------------------------------
/// The team page payload (/v1/teamdetail): identity + full-season schedule +
/// roster + season stats + the team's standings group. Every section is
/// best-effort — a missing roster/stats/standing renders nothing.
class TeamDetail {
  final String league, sport, leagueName;
  final TeamCardTeam team;
  final List<SportEvent> schedule; // start-ascending
  final List<RosterGroup> roster;
  final List<TeamStatGroup> stats;
  final TeamStanding? standing;
  TeamDetail({
    required this.league,
    required this.sport,
    required this.leagueName,
    required this.team,
    this.schedule = const [],
    this.roster = const [],
    this.stats = const [],
    this.standing,
  });
  factory TeamDetail.fromJson(Map<String, dynamic> j) => TeamDetail(
        league: _str(j['league']),
        sport: _str(j['sport']),
        leagueName: _str(j['leagueName']),
        team: TeamCardTeam.fromJson(_map(j['team'])),
        schedule: _list(j['schedule'])
            .map((e) => SportEvent.fromJson(_map(e)))
            .toList(growable: false),
        roster: _list(j['roster'])
            .map((g) => RosterGroup.fromJson(_map(g)))
            .toList(growable: false),
        stats: _list(j['stats'])
            .map((g) => TeamStatGroup.fromJson(_map(g)))
            .toList(growable: false),
        standing: j['standing'] == null
            ? null
            : TeamStanding.fromJson(_map(j['standing'])),
      );
}

class RosterGroup {
  final String name;
  final List<RosterAthlete> athletes;
  RosterGroup({required this.name, this.athletes = const []});
  factory RosterGroup.fromJson(Map<String, dynamic> j) => RosterGroup(
        name: _str(j['name']),
        athletes: _list(j['athletes'])
            .map((a) => RosterAthlete.fromJson(_map(a)))
            .toList(growable: false),
      );
}

class RosterAthlete {
  final String id, name;
  final String? jersey, position, headshot;
  RosterAthlete({
    required this.id,
    required this.name,
    this.jersey,
    this.position,
    this.headshot,
  });
  factory RosterAthlete.fromJson(Map<String, dynamic> j) => RosterAthlete(
        id: _str(j['id']),
        name: _str(j['name']),
        jersey: _strOrNull(j['jersey']),
        position: _strOrNull(j['position']),
        headshot: _strOrNull(j['headshot']),
      );
}

class TeamStatGroup {
  final String name;
  final List<TeamStatItem> stats;
  TeamStatGroup({required this.name, this.stats = const []});
  factory TeamStatGroup.fromJson(Map<String, dynamic> j) => TeamStatGroup(
        name: _str(j['name']),
        stats: _list(j['stats'])
            .map((s) => TeamStatItem.fromJson(_map(s)))
            .toList(growable: false),
      );
}

class TeamStatItem {
  final String name, label, value;
  final String? abbr;
  final int? rank;
  TeamStatItem({
    required this.name,
    required this.label,
    required this.value,
    this.abbr,
    this.rank,
  });
  factory TeamStatItem.fromJson(Map<String, dynamic> j) => TeamStatItem(
        name: _str(j['name']),
        label: _str(j['label']),
        value: _str(j['value']),
        abbr: _strOrNull(j['abbr']),
        rank: _int(j['rank']),
      );
}

/// The team's own standings group (reuses [StandingsRow] + [StandingColumn] so
/// the team page and the standings page render the same table shape).
class TeamStanding {
  final String groupName;
  final List<StandingColumn> columns;
  final List<StandingsRow> rows;
  TeamStanding({
    required this.groupName,
    this.columns = const [],
    this.rows = const [],
  });
  factory TeamStanding.fromJson(Map<String, dynamic> j) => TeamStanding(
        groupName: _str(j['groupName']),
        columns: _list(j['columns'])
            .map((c) => StandingColumn.fromJson(_map(c)))
            .toList(growable: false),
        rows: _list(j['rows'])
            .map((r) => StandingsRow.fromJson(_map(r)))
            .toList(growable: false),
      );
}

/// A team's SEASON leaders (§2.6 TEAM LEADERS row): the top player per stat
/// category. CORE-tier + lazy (team-page open), fanned-out — a category with no
/// resolvable athlete is dropped upstream, so `categories` is already display-ready.
class TeamSeasonLeaders {
  final String league, teamId;
  final List<TeamLeader> categories;
  TeamSeasonLeaders({
    required this.league,
    required this.teamId,
    this.categories = const [],
  });
  factory TeamSeasonLeaders.fromJson(Map<String, dynamic> j) => TeamSeasonLeaders(
        league: _str(j['league']),
        teamId: _str(j['teamId']),
        categories: _list(j['categories'])
            .map((c) => TeamLeader.fromJson(_map(c)))
            .toList(growable: false),
      );
}

class TeamLeader {
  final String name, label, athleteId, athlete, displayValue;
  final String? position, headshot;
  TeamLeader({
    required this.name,
    required this.label,
    required this.athleteId,
    required this.athlete,
    required this.displayValue,
    this.position,
    this.headshot,
  });
  factory TeamLeader.fromJson(Map<String, dynamic> j) => TeamLeader(
        name: _str(j['name']),
        label: _str(j['label']),
        athleteId: _str(j['athleteId']),
        athlete: _str(j['athlete']),
        displayValue: _str(j['displayValue']),
        position: _strOrNull(j['position']),
        headshot: _strOrNull(j['headshot']),
      );
}

/// The rich per-match tennis resource — ESPN's core `events/{id}/competitions/
/// {cid}` (the tennis drill-in). The site `/summary` is dead for tennis, but the
/// core competition carries the match's identity: draw type, round + court, and
/// a ready-made result note ("Korneeva bt Shubladze 2-6 7-6 (7-2) 6-3"). Stats /
/// head-to-head / probabilities all 404, so this is a header, not a box score.
/// Best-effort — every field is nullable and the detail degrades to the cheap
/// set grid when the fetch fails (offline mock, or a live 404).
class TennisMatchInfo {
  final String? drawType; // "Women's Singles" / "Men's Doubles" / "Mixed Doubles"
  final String? round; // "Quarterfinal" / "Qualifying 1st Round"
  final String? roundAbbr; // "QF" / "Q1ST"
  final String? court; // "Court 2 Roehampton"
  final String? resultLine; // the human recap note (winner bt loser, full score)
  TennisMatchInfo({
    this.drawType,
    this.round,
    this.roundAbbr,
    this.court,
    this.resultLine,
  });

  bool get isEmpty =>
      drawType == null &&
      round == null &&
      court == null &&
      resultLine == null;

  /// Whether there's identity to show (draw/round/court) beyond the result note.
  bool get hasContext => drawType != null || round != null || court != null;

  /// The 'Quarterfinal · Court 2 Roehampton' caption under the draw-type label.
  String? get contextLine {
    final parts = [if (round != null) round!, if (court != null) court!];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  factory TennisMatchInfo.fromJson(Map<String, dynamic> j) => TennisMatchInfo(
        drawType: _strOrNull(j['drawType']),
        round: _strOrNull(j['round']),
        roundAbbr: _strOrNull(j['roundAbbr']),
        court: _strOrNull(j['court']),
        resultLine: _strOrNull(j['resultLine']),
      );
}

// ---- game summary (rich tier) -----------------------------------------------
class GameSummary {
  final String eventId;
  final bool live;
  final List<TeamStatRow> teamStats;
  final List<BoxGroup> boxGroups;
  final List<SummaryPlay> scoringPlays; // condensed scoring feed (default view)
  final PeriodLines? periodLines;
  final List<Lineup> lineups;
  // ---- enrichments that ride the same /summary payload (zero extra fetch) ----
  final List<SummaryPlay> plays; // FULL play-by-play (expand-to-view); [] when absent
  final SeasonSeries? seasonSeries;
  final List<SideForm> recentForm;
  final List<TeamInjuries> injuries;
  final WinProbability? winProbability;
  // ---- 2026-07 additions ----
  final int? attendance; // gameInfo.attendance
  final List<Official> officials; // referee/umpires (capped upstream)
  final List<DriveSummary> drives; // gridiron per-drive rows ([] elsewhere)
  final List<CricketInningsCard> cricketInnings; // the real cricket scorecard
  final List<BoutResult> bouts; // MMA structured results (core-built)
  final List<MatchEvent> timeline; // soccer curated event feed ([] elsewhere)
  final List<AtBat> atBats; // baseball at-bats w/ pitch sequences ([] elsewhere) (§3e)
  // Detail-open CORE situation, merged into the summary payload by api.dart (NOT
  // from normalizeSummary): football down/distance, basketball bonus/timeouts,
  // hockey power play. Null off the poll/for sports without a core situation.
  final Situation? situation;
  GameSummary({
    required this.eventId,
    required this.live,
    required this.teamStats,
    required this.boxGroups,
    required this.scoringPlays,
    required this.periodLines,
    required this.lineups,
    this.plays = const [],
    this.seasonSeries,
    this.recentForm = const [],
    this.injuries = const [],
    this.winProbability,
    this.attendance,
    this.officials = const [],
    this.drives = const [],
    this.cricketInnings = const [],
    this.bouts = const [],
    this.timeline = const [],
    this.atBats = const [],
    this.situation,
  });
  factory GameSummary.fromJson(Map<String, dynamic> j) => GameSummary(
        eventId: _str(j['eventId']),
        live: _bool(j['live']),
        teamStats: _list(j['teamStats'])
            .map((r) => TeamStatRow.fromJson(_map(r)))
            .toList(growable: false),
        boxGroups: _list(j['boxGroups'])
            .map((g) => BoxGroup.fromJson(_map(g)))
            .toList(growable: false),
        scoringPlays: _list(j['scoringPlays'])
            .map((p) => SummaryPlay.fromJson(_map(p)))
            .toList(growable: false),
        periodLines: j['periodLines'] == null
            ? null
            : PeriodLines.fromJson(_map(j['periodLines'])),
        lineups: _list(j['lineups'])
            .map((l) => Lineup.fromJson(_map(l)))
            .toList(growable: false),
        plays: _list(j['plays'])
            .map((p) => SummaryPlay.fromJson(_map(p)))
            .toList(growable: false),
        seasonSeries: j['seasonSeries'] == null
            ? null
            : SeasonSeries.fromJson(_map(j['seasonSeries'])),
        recentForm: _list(j['recentForm'])
            .map((f) => SideForm.fromJson(_map(f)))
            .toList(growable: false),
        injuries: _list(j['injuries'])
            .map((t) => TeamInjuries.fromJson(_map(t)))
            .toList(growable: false),
        winProbability: j['winProbability'] == null
            ? null
            : WinProbability.fromJson(_map(j['winProbability'])),
        attendance: _int(j['attendance']),
        officials: _list(j['officials'])
            .map((o) => Official.fromJson(_map(o)))
            .toList(growable: false),
        drives: _list(j['drives'])
            .map((d) => DriveSummary.fromJson(_map(d)))
            .toList(growable: false),
        cricketInnings: _list(j['cricketInnings'])
            .map((c) => CricketInningsCard.fromJson(_map(c)))
            .toList(growable: false),
        bouts: _list(j['bouts'])
            .map((b) => BoutResult.fromJson(_map(b)))
            .toList(growable: false),
        timeline: _list(j['timeline'])
            .map((e) => MatchEvent.fromJson(_map(e)))
            .toList(growable: false),
        atBats: _list(j['atBats'])
            .map((a) => AtBat.fromJson(_map(a)))
            .toList(growable: false),
        situation: j['situation'] == null
            ? null
            : Situation.fromJson(_map(j['situation'])),
      );

  bool get isEmpty =>
      teamStats.isEmpty &&
      boxGroups.isEmpty &&
      scoringPlays.isEmpty &&
      lineups.isEmpty &&
      periodLines == null &&
      // enrichments count too: a summary with only win-prob/series/injuries/PBP
      // must still render the rich section (else those would be silently dropped).
      plays.isEmpty &&
      seasonSeries == null &&
      recentForm.isEmpty &&
      injuries.isEmpty &&
      winProbability == null &&
      drives.isEmpty &&
      cricketInnings.isEmpty &&
      bouts.isEmpty &&
      atBats.isEmpty &&
      situation == null;

  /// The structured result for one bout (MMA detail is per-bout; the summary is
  /// per-card) — matched by the bout's Competition.id.
  BoutResult? boutFor(String competitionId) {
    for (final b in bouts) {
      if (b.id == competitionId) return b;
    }
    return null;
  }

  /// Side form by 'home'/'away', for quick lookup in the detail header.
  SideForm? formFor(String side) {
    for (final f in recentForm) {
      if (f.side == side) return f;
    }
    return null;
  }

  TeamInjuries? injuriesFor(String side) {
    for (final t in injuries) {
      if (t.side == side) return t;
    }
    return null;
  }
}

/// A match official (summary gameInfo) — 'João Pinheiro · Referee'.
class Official {
  final String name;
  final String? role;
  Official({required this.name, this.role});
  factory Official.fromJson(Map<String, dynamic> j) => Official(
        name: _str(j['name']),
        role: _strOrNull(j['role']),
      );
}

/// One gridiron drive (compact glance row; the plays live in [GameSummary.plays]).
class DriveSummary {
  final String? side, teamAbbr, description, result;
  final bool isScore;
  final int? yards, playCount;

  /// §5b: the drive's quarter (its first play's period) — the feed groups drives
  /// into per-quarter cards; the elapsed clock ('2:44') for the stat strip; the
  /// running score after the drive; and the slim per-drive plays for the All-view
  /// tap-to-expand. All null/empty for older payloads.
  final int? period;
  final String? timeElapsed;
  final num? awayScore, homeScore;
  final List<DrivePlay> plays;
  DriveSummary({
    this.side,
    this.teamAbbr,
    this.description,
    this.result,
    this.isScore = false,
    this.yards,
    this.playCount,
    this.period,
    this.timeElapsed,
    this.awayScore,
    this.homeScore,
    this.plays = const [],
  });
  factory DriveSummary.fromJson(Map<String, dynamic> j) => DriveSummary(
        side: _strOrNull(j['side']),
        teamAbbr: _strOrNull(j['teamAbbr']),
        description: _strOrNull(j['description']),
        result: _strOrNull(j['result']),
        isScore: _bool(j['isScore']),
        yards: _int(j['yards']),
        playCount: _int(j['playCount']),
        period: _int(j['period']),
        timeElapsed: _strOrNull(j['timeElapsed']),
        awayScore: _num(j['awayScore']),
        homeScore: _num(j['homeScore']),
        plays: _list(j['plays'])
            .map((e) => DrivePlay.fromJson(_map(e)))
            .toList(growable: false),
      );
}

/// One play inside a drive — the §5b All-view disclosure rows behind a drive.
class DrivePlay {
  final String text;
  final String? clock;
  final bool scoring;
  DrivePlay({required this.text, this.clock, this.scoring = false});
  factory DrivePlay.fromJson(Map<String, dynamic> j) => DrivePlay(
        text: _str(j['text']),
        clock: _strOrNull(j['clock']),
        scoring: _bool(j['scoring']),
      );
}

/// One baseball at-bat (§3e): a condensed row in the All-plays view that expands
/// to its [pitches]. [text] is the batting result (empty while [live]); [batter]
/// (resolved short name) rides only the live, pre-expanded at-bat. [outs]/[away]/
/// [home] are the state AFTER the at-bat. Pitching-change rows are not at-bats.
class AtBat {
  final int? period;
  final String? half, side, teamAbbr, batter;
  final String text;
  final bool scoring, live;
  final int? outs, balls, strikes;
  final num? away, home;
  final List<Pitch> pitches;
  AtBat({
    this.period,
    this.half,
    this.side,
    this.teamAbbr,
    this.batter,
    this.text = '',
    this.scoring = false,
    this.live = false,
    this.outs,
    this.balls,
    this.strikes,
    this.away,
    this.home,
    this.pitches = const [],
  });
  factory AtBat.fromJson(Map<String, dynamic> j) => AtBat(
        period: _int(j['period']),
        half: _strOrNull(j['half']),
        side: _strOrNull(j['side']),
        teamAbbr: _strOrNull(j['teamAbbr']),
        batter: _strOrNull(j['batter']),
        text: _str(j['text']),
        scoring: _bool(j['scoring']),
        live: _bool(j['live']),
        outs: _int(j['outs']),
        balls: _int(j['balls']),
        strikes: _int(j['strikes']),
        away: _num(j['away']),
        home: _num(j['home']),
        pitches: _list(j['pitches'])
            .map((p) => Pitch.fromJson(_map(p)))
            .toList(growable: false),
      );
}

/// One pitch inside an [AtBat]. [r] classifies the result for the §2 muted glyph
/// dot (ball / strike / foul / inplay / other); [text] is the pitch outcome with
/// the 'Pitch N :' prefix stripped ('Strike 1 Swinging'); [velo] is MPH.
class Pitch {
  final String r;
  final String text;
  final num? velo;
  Pitch({this.r = 'other', this.text = '', this.velo});
  factory Pitch.fromJson(Map<String, dynamic> j) => Pitch(
        r: _str(j['r']).isEmpty ? 'other' : _str(j['r']),
        text: _str(j['text']),
        velo: _num(j['velo']),
      );
}

/// One innings of the cricket scorecard: the batting side's figures + the
/// opposing bowling figures. All values are pre-formatted strings.
class CricketInningsCard {
  final int innings;
  final String battingTeam;
  final String? total, extras, bowlingTeam;
  final List<CricketBatRow> batting;
  final List<CricketBowlRow> bowling;
  CricketInningsCard({
    required this.innings,
    required this.battingTeam,
    this.total,
    this.extras,
    this.bowlingTeam,
    this.batting = const [],
    this.bowling = const [],
  });
  factory CricketInningsCard.fromJson(Map<String, dynamic> j) =>
      CricketInningsCard(
        innings: _int(j['innings']) ?? 0,
        battingTeam: _str(j['battingTeam']),
        total: _strOrNull(j['total']),
        extras: _strOrNull(j['extras']),
        bowlingTeam: _strOrNull(j['bowlingTeam']),
        batting: _list(j['batting'])
            .map((r) => CricketBatRow.fromJson(_map(r)))
            .toList(growable: false),
        bowling: _list(j['bowling'])
            .map((r) => CricketBowlRow.fromJson(_map(r)))
            .toList(growable: false),
      );
}

class CricketBatRow {
  final String name;
  final String? dismissal, runs, balls, fours, sixes;
  CricketBatRow({
    required this.name,
    this.dismissal,
    this.runs,
    this.balls,
    this.fours,
    this.sixes,
  });
  factory CricketBatRow.fromJson(Map<String, dynamic> j) => CricketBatRow(
        name: _str(j['name']),
        dismissal: _strOrNull(j['dismissal']),
        runs: _strOrNull(j['runs']),
        balls: _strOrNull(j['balls']),
        fours: _strOrNull(j['fours']),
        sixes: _strOrNull(j['sixes']),
      );
}

class CricketBowlRow {
  final String name;
  final String? overs, maidens, runs, wickets, economy;
  CricketBowlRow({
    required this.name,
    this.overs,
    this.maidens,
    this.runs,
    this.wickets,
    this.economy,
  });
  factory CricketBowlRow.fromJson(Map<String, dynamic> j) => CricketBowlRow(
        name: _str(j['name']),
        overs: _strOrNull(j['overs']),
        maidens: _strOrNull(j['maidens']),
        runs: _strOrNull(j['runs']),
        wickets: _strOrNull(j['wickets']),
        economy: _strOrNull(j['economy']),
      );
}

/// One bout's structured result (MMA). `id` matches the bout Competition.id.
class BoutResult {
  final String id;
  final String? result, shortResult, clock;
  final int? round;
  final List<BoutJudge> judges; // decisions only
  BoutResult({
    required this.id,
    this.result,
    this.shortResult,
    this.clock,
    this.round,
    this.judges = const [],
  });
  factory BoutResult.fromJson(Map<String, dynamic> j) => BoutResult(
        id: _str(j['id']),
        result: _strOrNull(j['result']),
        shortResult: _strOrNull(j['shortResult']),
        clock: _strOrNull(j['clock']),
        round: _int(j['round']),
        judges: _list(j['judges'])
            .map((x) => BoutJudge.fromJson(_map(x)))
            .toList(growable: false),
      );
}

/// One competitor's judge totals ([totals] aligned per judge across both corners).
class BoutJudge {
  final String competitorId;
  final int? total;
  final List<int> totals;
  BoutJudge({required this.competitorId, this.total, this.totals = const []});
  factory BoutJudge.fromJson(Map<String, dynamic> j) => BoutJudge(
        competitorId: _str(j['competitorId']),
        total: _int(j['total']),
        totals: _list(j['totals'])
            .map(_int)
            .whereType<int>()
            .toList(growable: false),
      );
}

/// Season head-to-head series ('Series tied 1-1').
class SeasonSeries {
  final String summary;
  final String? score, title;
  SeasonSeries({required this.summary, this.score, this.title});
  factory SeasonSeries.fromJson(Map<String, dynamic> j) => SeasonSeries(
        summary: _str(j['summary']),
        score: _strOrNull(j['score']),
        title: _strOrNull(j['title']),
      );
}

/// One side's last-5 form ('WLWWL', newest last).
class SideForm {
  final String? side, abbr;
  final String form;
  SideForm({this.side, this.abbr, required this.form});
  factory SideForm.fromJson(Map<String, dynamic> j) => SideForm(
        side: _strOrNull(j['side']),
        abbr: _strOrNull(j['abbr']),
        form: _str(j['form']),
      );
}

/// One side's "key absences" list (structured; news comments dropped upstream).
class TeamInjuries {
  final String? side, abbr;
  final List<InjuryItem> items;
  TeamInjuries({this.side, this.abbr, required this.items});
  factory TeamInjuries.fromJson(Map<String, dynamic> j) => TeamInjuries(
        side: _strOrNull(j['side']),
        abbr: _strOrNull(j['abbr']),
        items: _list(j['items'])
            .map((i) => InjuryItem.fromJson(_map(i)))
            .toList(growable: false),
      );
}

class InjuryItem {
  final String name, status;
  final String? pos, detail, returnDate;
  InjuryItem({
    required this.name,
    required this.status,
    this.pos,
    this.detail,
    this.returnDate,
  });
  factory InjuryItem.fromJson(Map<String, dynamic> j) => InjuryItem(
        name: _str(j['name']),
        status: _str(j['status']),
        pos: _strOrNull(j['pos']),
        detail: _strOrNull(j['detail']),
        returnDate: _strOrNull(j['returnDate']),
      );

  /// 'Out · Knee' — status and body part, whichever present.
  String get line =>
      [status, if (detail != null && detail!.isNotEmpty) detail].join(' · ');
}

/// Current/final win probability (percentages 0-100). ESPN analytic, not a bet.
class WinProbability {
  final int home, away;
  final int? tie;
  WinProbability({required this.home, required this.away, this.tie});
  factory WinProbability.fromJson(Map<String, dynamic> j) => WinProbability(
        home: _int(j['home']) ?? 0,
        away: _int(j['away']) ?? 0,
        tie: _int(j['tie']),
      );
}

class TeamStatRow {
  final String label;
  final String? away, home;
  TeamStatRow({required this.label, this.away, this.home});
  factory TeamStatRow.fromJson(Map<String, dynamic> j) => TeamStatRow(
      label: _str(j['label']),
      away: _strOrNull(j['away']),
      home: _strOrNull(j['home']));
}

class BoxGroup {
  final String title;
  final List<String> columns;
  final List<BoxTeam> teams;
  BoxGroup({required this.title, required this.columns, required this.teams});
  factory BoxGroup.fromJson(Map<String, dynamic> j) => BoxGroup(
        title: _str(j['title']),
        columns: _list(j['columns']).map(_str).toList(growable: false),
        teams: _list(j['teams'])
            .map((t) => BoxTeam.fromJson(_map(t)))
            .toList(growable: false),
      );
}

class BoxTeam {
  final String? side, abbr;
  final List<BoxRow> rows;
  BoxTeam({this.side, this.abbr, required this.rows});
  factory BoxTeam.fromJson(Map<String, dynamic> j) => BoxTeam(
        side: _strOrNull(j['side']),
        abbr: _strOrNull(j['abbr']),
        rows: _list(j['rows'])
            .map((r) => BoxRow.fromJson(_map(r)))
            .toList(growable: false),
      );
}

class BoxRow {
  /// CORE athletes/{id} join — non-null makes the row tap through to the player
  /// page. Null where ESPN ships no athlete id (the row stays inert).
  final String? id;
  final String name;
  final String? pos;
  final List<String> stats;

  /// Baseball only: `false` marks a substitute (the app indents the row), `true`
  /// a starter, null where ESPN ships no starter flag (§3d).
  final bool? starter;

  /// The athlete's lineup note ('a-walked for Thomas in the 7th') — the
  /// substitution footnote. Null when absent.
  final String? note;
  BoxRow(
      {this.id,
      required this.name,
      this.pos,
      required this.stats,
      this.starter,
      this.note});
  factory BoxRow.fromJson(Map<String, dynamic> j) => BoxRow(
        id: _strOrNull(j['id']),
        name: _str(j['name']),
        pos: _strOrNull(j['pos']),
        stats: _list(j['stats']).map(_str).toList(growable: false),
        starter: j['starter'] is bool ? j['starter'] as bool : null,
        note: _strOrNull(j['note']),
      );
}

class SummaryPlay {
  final int? period;

  /// Baseball half-inning ('top'|'bottom') from ESPN `period.type` — lets the
  /// feed group scoring/all plays by (period, half), so a 4-run bottom doesn't
  /// merge into the top of the same inning (§3c). Null for every other sport.
  final String? half;
  final String? periodLabel, clock, side, teamAbbr, type;

  /// The play's first participant (basketball), resolved to a name via the
  /// boxscore — the feed bolds it. Null when there's no participant or the id
  /// isn't in the box (the row then renders entirely dim) (§4b).
  final String? actor;
  final String text;
  final num? away, home;

  /// Whether this row is an actual score. Only meaningful in the condensed
  /// scoringPlays feed, where soccer's key events also carry cards/subs; the
  /// Recap "Scoring" card filters on it. Absent ⇒ true (every non-soccer
  /// scoring-play row is a score, and old cached payloads must not regress).
  final bool scoring;

  SummaryPlay({
    this.period,
    this.half,
    this.periodLabel,
    this.clock,
    this.side,
    this.teamAbbr,
    this.type,
    this.actor,
    required this.text,
    this.away,
    this.home,
    this.scoring = true,
  });
  factory SummaryPlay.fromJson(Map<String, dynamic> j) => SummaryPlay(
        period: _int(j['period']),
        half: _strOrNull(j['half']),
        periodLabel: _strOrNull(j['periodLabel']),
        clock: _strOrNull(j['clock']),
        side: _strOrNull(j['side']),
        teamAbbr: _strOrNull(j['teamAbbr']),
        type: _strOrNull(j['type']),
        actor: _strOrNull(j['actor']),
        text: _str(j['text']),
        away: _num(j['away']),
        home: _num(j['home']),
        scoring: j.containsKey('scoring') ? _bool(j['scoring']) : true,
      );
}

/// One row in the soccer curated event feed (worker `timeline` → the design's
/// Timeline tab). Goals / cards / subs (+ VAR) with the scorer & assist — or the
/// sub's on & off — already split out by the worker; the running score is derived
/// by the UI (ESPN leaves it undefined on key events).
class MatchEvent {
  final int? t; // minutes incl. stoppage, for ordering only (soccer)
  final int? period;
  final String? periodLabel; // group header ('2nd Half', '3rd Quarter', 'Bottom 6th')
  final String kind; // goal | own-goal | penalty-goal | penalty-missed |
  //                    yellow-card | red-card | substitution | var  (soccer),
  //                    or score | play  (generic play-by-play), or other
  final String? clock, side, teamAbbr, athlete, assist, text;
  final bool scoring;
  final num? scoreAway, scoreHome; // carried running score (generic feeds)
  const MatchEvent({
    required this.kind,
    this.t,
    this.period,
    this.periodLabel,
    this.clock,
    this.side,
    this.teamAbbr,
    this.athlete,
    this.assist,
    this.text,
    this.scoring = false,
    this.scoreAway,
    this.scoreHome,
  });
  factory MatchEvent.fromJson(Map<String, dynamic> j) => MatchEvent(
        kind: _str(j['kind']),
        t: _int(j['t']),
        period: _int(j['period']),
        periodLabel: _strOrNull(j['periodLabel']),
        clock: _strOrNull(j['clock']),
        side: _strOrNull(j['side']),
        teamAbbr: _strOrNull(j['teamAbbr']),
        athlete: _strOrNull(j['athlete']),
        assist: _strOrNull(j['assist']),
        text: _strOrNull(j['text']),
        scoring: _bool(j['scoring']),
      );

  /// Cheap fallback: the scoreboard timeline ([ScoringEvent] — goals + cards
  /// only) projected into the same shape, so the Timeline tab renders instantly
  /// off the scores payload before the rich /summary (subs, assists) arrives, and
  /// for sports whose summary ships no key-event feed.
  factory MatchEvent.fromScoringEvent(ScoringEvent e, {String? teamAbbr}) =>
      MatchEvent(
        kind: e.type,
        clock: e.clock,
        period: e.period,
        side: e.team,
        teamAbbr: teamAbbr,
        athlete: e.athlete,
        text: e.detail,
        scoring: e.isGoal,
      );

  /// A generic play-by-play row ([SummaryPlay]) projected into the same feed —
  /// so every sport's action list shares one grammar. The running score ESPN
  /// carries per play rides through as [scoreAway]/[scoreHome].
  factory MatchEvent.fromSummaryPlay(SummaryPlay p) => MatchEvent(
        kind: p.scoring ? 'score' : 'play',
        period: p.period,
        periodLabel: p.periodLabel,
        clock: p.clock,
        side: p.side,
        teamAbbr: p.teamAbbr,
        athlete: p.actor, // basketball actor (§4b) — the feed bolds it when present
        text: p.text,
        scoring: p.scoring,
        scoreAway: p.away,
        scoreHome: p.home,
      );

  bool get isGoal =>
      kind == 'goal' || kind == 'own-goal' || kind == 'penalty-goal';
  bool get isCard => kind == 'yellow-card' || kind == 'red-card';
  bool get isSub => kind == 'substitution';
  bool get isScoring => scoring || isGoal || kind == 'score';
}

class PeriodLines {
  final String unit;
  final List<String> labels;
  final SidePeriods away, home;
  PeriodLines(
      {required this.unit,
      required this.labels,
      required this.away,
      required this.home});
  factory PeriodLines.fromJson(Map<String, dynamic> j) => PeriodLines(
        unit: _str(j['unit']),
        labels: _list(j['labels']).map(_str).toList(growable: false),
        away: SidePeriods.fromJson(_map(j['away'])),
        home: SidePeriods.fromJson(_map(j['home'])),
      );
}

class SidePeriods {
  final String? abbr, total;
  final List<String> values;
  SidePeriods({this.abbr, this.total, required this.values});
  factory SidePeriods.fromJson(Map<String, dynamic> j) => SidePeriods(
        abbr: _strOrNull(j['abbr']),
        total: _strOrNull(j['total']),
        values: _list(j['values']).map(_str).toList(growable: false),
      );
}

class Lineup {
  final String? side, abbr, formation;
  final List<LineupPlayer> starters, bench;
  Lineup(
      {this.side,
      this.abbr,
      this.formation,
      required this.starters,
      required this.bench});
  factory Lineup.fromJson(Map<String, dynamic> j) => Lineup(
        side: _strOrNull(j['side']),
        abbr: _strOrNull(j['abbr']),
        formation: _strOrNull(j['formation']),
        starters: _list(j['starters'])
            .map((p) => LineupPlayer.fromJson(_map(p)))
            .toList(growable: false),
        bench: _list(j['bench'])
            .map((p) => LineupPlayer.fromJson(_map(p)))
            .toList(growable: false),
      );
}

class LineupPlayer {
  /// CORE athletes/{id} join — non-null makes the row tap through to the player
  /// page. Null where ESPN ships no athlete id (the row stays inert).
  final String? id;
  final String name;
  final String? pos, jersey;
  LineupPlayer({this.id, required this.name, this.pos, this.jersey});
  factory LineupPlayer.fromJson(Map<String, dynamic> j) => LineupPlayer(
        id: _strOrNull(j['id']),
        name: _str(j['name']),
        pos: _strOrNull(j['pos']),
        jersey: _strOrNull(j['jersey']),
      );
}

// ---- rankings (college polls) -----------------------------------------------
/// College Top-25 polls (/v1/rankings). AP first, then Coaches/CFP. Empty `polls`
/// for pro leagues / offseason. Distinct from the inline per-team poll rank.
class RankingsResponse {
  final String league;
  final List<Poll> polls;
  RankingsResponse({required this.league, required this.polls});
  factory RankingsResponse.fromJson(Map<String, dynamic> j) => RankingsResponse(
        league: _str(j['league']),
        polls: _list(j['polls'])
            .map((p) => Poll.fromJson(_map(p)))
            .toList(growable: false),
      );
}

class Poll {
  final String name, shortName;
  final String? occurrence;
  final List<RankEntry> ranks;
  Poll({
    required this.name,
    required this.shortName,
    this.occurrence,
    required this.ranks,
  });
  factory Poll.fromJson(Map<String, dynamic> j) => Poll(
        name: _str(j['name']),
        shortName: _str(j['shortName']),
        occurrence: _strOrNull(j['occurrence']),
        ranks: _list(j['ranks'])
            .map((r) => RankEntry.fromJson(_map(r)))
            .toList(growable: false),
      );
}

class RankEntry {
  final int? current, previous, points;
  final String? trend, record;
  final bool champion; // MMA: belt holder (hasAccolade)
  final RankTeam? team; // college polls
  final RankAthlete? athlete; // tennis tours / UFC divisions
  RankEntry({
    this.current,
    this.previous,
    this.points,
    this.trend,
    this.record,
    this.champion = false,
    this.team,
    this.athlete,
  });
  factory RankEntry.fromJson(Map<String, dynamic> j) => RankEntry(
        current: _int(j['current']),
        previous: _int(j['previous']),
        points: _int(j['points']),
        trend: _strOrNull(j['trend']),
        record: _strOrNull(j['record']),
        champion: _bool(j['champion']),
        team: j['team'] == null ? null : RankTeam.fromJson(_map(j['team'])),
        athlete: j['athlete'] == null
            ? null
            : RankAthlete.fromJson(_map(j['athlete'])),
      );

  /// Display name regardless of entity kind.
  String get name => team?.name ?? athlete?.name ?? '';

  /// 'up' / 'down' / 'flat' from the pre-rendered trend, for the arrow glyph.
  String get trendDir {
    final t = trend ?? '';
    if (t.startsWith('+')) return 'up';
    if (t.startsWith('-') && t.length > 1) return 'down';
    return 'flat';
  }
}

class RankAthlete {
  final String id, name;
  final String? country, headshot;
  RankAthlete({required this.id, required this.name, this.country, this.headshot});
  factory RankAthlete.fromJson(Map<String, dynamic> j) => RankAthlete(
        id: _str(j['id']),
        name: _str(j['name']),
        country: _strOrNull(j['country']),
        headshot: _strOrNull(j['headshot']),
      );
}

class RankTeam {
  final String id, name;
  final String? abbr, logo, logoDark, color;
  RankTeam({
    required this.id,
    required this.name,
    this.abbr,
    this.logo,
    this.logoDark,
    this.color,
  });
  factory RankTeam.fromJson(Map<String, dynamic> j) => RankTeam(
        id: _str(j['id']),
        name: _str(j['name']),
        abbr: _strOrNull(j['abbr']),
        logo: _strOrNull(j['logo']),
        logoDark: _strOrNull(j['logoDark']),
        color: _strOrNull(j['color']),
      );
}

// ---- golf player scorecard ----------------------------------------------------
/// Hole-by-hole detail for one leaderboard row
/// (GET /v1/scorecard/{league}/{eventId}/{playerId}).
class GolfScorecard {
  final String league, eventId;
  final ScorecardPlayer player;
  final List<ScorecardRound> rounds;
  final List<ScorecardStat> stats; // small curated tournament stat line
  GolfScorecard({
    required this.league,
    required this.eventId,
    required this.player,
    this.rounds = const [],
    this.stats = const [],
  });
  factory GolfScorecard.fromJson(Map<String, dynamic> j) {
    final p = _map(j['player']);
    return GolfScorecard(
      league: _str(j['league']),
      eventId: _str(j['eventId']),
      player: ScorecardPlayer(
        id: _str(p['id']),
        name: _str(p['name']),
        headshot: _strOrNull(p['headshot']),
        country: _strOrNull(p['country']),
      ),
      rounds: _list(j['rounds'])
          .map((r) => ScorecardRound.fromJson(_map(r)))
          .toList(growable: false),
      stats: _list(j['stats'])
          .map((s) => ScorecardStat.fromJson(_map(s)))
          .toList(growable: false),
    );
  }
}

class ScorecardPlayer {
  final String id, name;
  final String? headshot, country;
  ScorecardPlayer(
      {required this.id, required this.name, this.headshot, this.country});
}

class ScorecardStat {
  final String name, label, value;
  ScorecardStat({required this.name, required this.label, required this.value});
  factory ScorecardStat.fromJson(Map<String, dynamic> j) => ScorecardStat(
        name: _str(j['name']),
        label: _str(j['label']),
        value: _str(j['value']),
      );
}

class ScorecardRound {
  final int round;
  final int? strokes, outScore, inScore, startTee, groupNumber, currentPosition;
  final String? toPar, teeTime; // teeTime = ISO, present pre-round
  final List<ScorecardHole> holes; // [] pre-round
  ScorecardRound({
    required this.round,
    this.strokes,
    this.outScore,
    this.inScore,
    this.startTee,
    this.groupNumber,
    this.currentPosition,
    this.toPar,
    this.teeTime,
    this.holes = const [],
  });
  factory ScorecardRound.fromJson(Map<String, dynamic> j) => ScorecardRound(
        round: _int(j['round']) ?? 0,
        strokes: _int(j['strokes']),
        outScore: _int(j['outScore']),
        inScore: _int(j['inScore']),
        startTee: _int(j['startTee']),
        groupNumber: _int(j['groupNumber']),
        currentPosition: _int(j['currentPosition']),
        toPar: _strOrNull(j['toPar']),
        teeTime: _strOrNull(j['teeTime']),
        holes: _list(j['holes'])
            .map((h) => ScorecardHole.fromJson(_map(h)))
            .toList(growable: false),
      );

  bool get played => holes.isNotEmpty;
  DateTime? get teeTimeLocal =>
      teeTime == null ? null : DateTime.tryParse(teeTime!)?.toLocal();
}

class ScorecardHole {
  final int hole;
  final int? par, strokes;
  final String? scoreType; // 'EAGLE' | 'BIRDIE' | 'PAR' | 'BOGEY' | …
  ScorecardHole({required this.hole, this.par, this.strokes, this.scoreType});
  factory ScorecardHole.fromJson(Map<String, dynamic> j) => ScorecardHole(
        hole: _int(j['hole']) ?? 0,
        par: _int(j['par']),
        strokes: _int(j['strokes']),
        scoreType: _strOrNull(j['scoreType']),
      );

  /// strokes − par, for coloring; null when either is unknown.
  int? get delta =>
      (strokes != null && par != null) ? strokes! - par! : null;
}

// ---- health + client-version gate ------------------------------------------
/// The advisory update gate the worker echoes onto `/v1/health` from the registry
/// (`schema/league-profiles.json` → `client`). Comparison is by [versionCode]
/// (monotonic — the CI run number), NEVER the semver name.
///
/// Every field is nullable on purpose: an ABSENT `client` block (an old worker, a
/// fork, or the offline mock) parses to all-null, and the gate logic treats null
/// as "no requirement" → no banner (fail-open). It must never read as version 0.
class ClientGate {
  /// Below this, the build is unsupported → a persistent banner.
  final int? minVersionCode;

  /// Below this (but at/above [minVersionCode]), a dismissible nudge.
  final int? recommendedVersionCode;

  /// Human-facing latest version (e.g. '0.3.1'), for the banner copy.
  final String? latestVersionName;

  /// Where to get the new build — a sideloaded APK can't self-update, so this is
  /// the GitHub Releases page.
  final String? downloadUrl;

  const ClientGate({
    this.minVersionCode,
    this.recommendedVersionCode,
    this.latestVersionName,
    this.downloadUrl,
  });

  factory ClientGate.fromJson(Map<String, dynamic> j) => ClientGate(
        minVersionCode: _int(j['minVersionCode']),
        recommendedVersionCode: _int(j['recommendedVersionCode']),
        latestVersionName: _strOrNull(j['latestVersionName']),
        downloadUrl: _strOrNull(j['downloadUrl']),
      );
}

/// `/v1/health` payload. [client] is null when the worker omits the gate.
class HealthInfo {
  final bool ok;
  final int leagues;
  final ClientGate? client;

  const HealthInfo({required this.ok, required this.leagues, this.client});

  factory HealthInfo.fromJson(Map<String, dynamic> j) => HealthInfo(
        ok: _bool(j['ok']),
        leagues: _int(j['leagues']) ?? 0,
        client: j['client'] is Map ? ClientGate.fromJson(_map(j['client'])) : null,
      );
}

// ---- tournament (§2.7) --------------------------------------------------------
/// One canonical shape for the four tournament grammars (canonical.ts
/// §Tournament): group tables + knockout scroller (World Cup), a full
/// single-elim draw (Wimbledon), a seeded region bracket (March Madness), and
/// double-elim pools + a championship series (CWS). Everything below [title] is
/// optional-by-default — render what is present.
class TournamentResponse {
  final String league, title;
  final String? subtitle;
  final List<TournamentGroup> groups;
  final List<TournamentRound> rounds;
  final List<TournamentPool> pools;
  final TournamentSeries? series;
  TournamentResponse({
    required this.league,
    required this.title,
    this.subtitle,
    this.groups = const [],
    this.rounds = const [],
    this.pools = const [],
    this.series,
  });
  factory TournamentResponse.fromJson(Map<String, dynamic> j) => TournamentResponse(
        league: _str(j['league']),
        title: _str(j['title']),
        subtitle: _strOrNull(j['subtitle']),
        groups: _list(j['groups'])
            .map((g) => TournamentGroup.fromJson(_map(g)))
            .toList(growable: false),
        rounds: _list(j['rounds'])
            .map((r) => TournamentRound.fromJson(_map(r)))
            .toList(growable: false),
        pools: _list(j['pools'])
            .map((p) => TournamentPool.fromJson(_map(p)))
            .toList(growable: false),
        series: j['series'] is Map ? TournamentSeries.fromJson(_map(j['series'])) : null,
      );

  bool get isEmpty =>
      groups.isEmpty && rounds.isEmpty && pools.isEmpty && series == null;
}

/// A round-robin group table — rows are EXACTLY [StandingsRow] (incl. the soccer
/// qualification [StandingsRow.note]), so the standings renderer draws them.
class TournamentGroup {
  final String label;
  final List<StandingsRow> rows;
  TournamentGroup({required this.label, required this.rows});
  factory TournamentGroup.fromJson(Map<String, dynamic> j) => TournamentGroup(
        label: _str(j['label']),
        rows: _list(j['rows'])
            .map((r) => StandingsRow.fromJson(_map(r)))
            .toList(growable: false),
      );
}

/// One elimination round. [round] is the canonical key ('roundOf16' |
/// 'quarterfinal' | 'semifinal' | 'thirdPlace' | 'final' | 'group' |
/// 'qualifying' | ...) or null for an unrecognized pass-through label.
class TournamentRound {
  final String? round;
  final String label;
  final List<TournamentMatchup> matchups;
  TournamentRound({this.round, required this.label, required this.matchups});
  factory TournamentRound.fromJson(Map<String, dynamic> j) => TournamentRound(
        round: _strOrNull(j['round']),
        label: _str(j['label']),
        matchups: _list(j['matchups'])
            .map((m) => TournamentMatchup.fromJson(_map(m)))
            .toList(growable: false),
      );
}

class TournamentMatchup {
  final String eventId;
  final String? competitionId; // tennis: match id under the tournament event
  final DateTime? date;
  final String phase;
  final bool live;
  final String? note; // 'Switzerland advance 4-3 on penalties'
  final int? gameNumber;
  final String? bracket; // region / group tag ('East', 'Group A')
  final String? advancesTo; // forward link when derivable (spec §2.7 gap otherwise)
  final List<TournamentSide> competitors;
  TournamentMatchup({
    required this.eventId,
    this.competitionId,
    this.date,
    required this.phase,
    this.live = false,
    this.note,
    this.gameNumber,
    this.bracket,
    this.advancesTo,
    required this.competitors,
  });
  factory TournamentMatchup.fromJson(Map<String, dynamic> j) => TournamentMatchup(
        eventId: _str(j['eventId']),
        competitionId: _strOrNull(j['competitionId']),
        date: DateTime.tryParse(_str(j['date']))?.toLocal(),
        phase: _str(j['phase']),
        live: _bool(j['live']),
        note: _strOrNull(j['note']),
        gameNumber: _int(j['gameNumber']),
        bracket: _strOrNull(j['bracket']),
        advancesTo: _strOrNull(j['advancesTo']),
        competitors: _list(j['competitors'])
            .map((c) => TournamentSide.fromJson(_map(c)))
            .toList(growable: false),
      );

  /// The id [advancesTo] points at (competitionId when set, else eventId).
  String get ref => competitionId ?? eventId;
}

class TournamentSide {
  final String id, name;
  final String? shortName, abbr, homeAway;
  final int? seed; // tennis only (curatedRank IS the seed there; 99 omitted)
  final bool winner;
  final String? score; // display score; absent while scheduled
  final int? shootout; // soccer pens
  final List<TournamentSet> sets; // tennis per-set games won
  TournamentSide({
    required this.id,
    required this.name,
    this.shortName,
    this.abbr,
    this.homeAway,
    this.seed,
    this.winner = false,
    this.score,
    this.shootout,
    this.sets = const [],
  });
  factory TournamentSide.fromJson(Map<String, dynamic> j) => TournamentSide(
        id: _str(j['id']),
        name: _str(j['name']),
        shortName: _strOrNull(j['shortName']),
        abbr: _strOrNull(j['abbr']),
        homeAway: _strOrNull(j['homeAway']),
        seed: _int(j['seed']),
        winner: _bool(j['winner']),
        score: _strOrNull(j['score']),
        shootout: _int(j['shootout']),
        sets: _list(j['sets'])
            .map((s) => TournamentSet.fromJson(_map(s)))
            .toList(growable: false),
      );

  /// A pre-created draw slot ESPN hasn't filled yet (negative/empty id).
  bool get isTbd => id.isEmpty || id.startsWith('-');
}

class TournamentSet {
  final int? value, tiebreak;
  final bool? winner;
  TournamentSet({this.value, this.tiebreak, this.winner});
  factory TournamentSet.fromJson(Map<String, dynamic> j) => TournamentSet(
        value: _int(j['value']),
        tiebreak: _int(j['tiebreak']),
        winner: j['winner'] is bool ? j['winner'] as bool : null,
      );
}

/// A double-elim pool table (CWS) — reconstructed, see canonical.ts.
class TournamentPool {
  final String label;
  final List<TournamentPoolRow> rows;
  TournamentPool({required this.label, required this.rows});
  factory TournamentPool.fromJson(Map<String, dynamic> j) => TournamentPool(
        label: _str(j['label']),
        rows: _list(j['rows'])
            .map((r) => TournamentPoolRow.fromJson(_map(r)))
            .toList(growable: false),
      );
}

class TournamentPoolRow {
  final String teamId, teamName;
  final String? teamAbbr;
  final int w, l;
  final String status; // 'advances' | 'eliminated' | 'alive'
  TournamentPoolRow({
    required this.teamId,
    required this.teamName,
    this.teamAbbr,
    required this.w,
    required this.l,
    required this.status,
  });
  factory TournamentPoolRow.fromJson(Map<String, dynamic> j) {
    final t = _map(j['team']);
    return TournamentPoolRow(
      teamId: _str(t['id']),
      teamName: _str(t['name']),
      teamAbbr: _strOrNull(t['abbr']),
      w: _int(j['w']) ?? 0,
      l: _int(j['l']) ?? 0,
      status: _str(j['status']),
    );
  }
}

/// Championship best-of-N (scoreboard `series` block; latest game's state).
class TournamentSeries {
  final String? title;
  final int? total;
  final bool completed;
  final List<TournamentSeriesSide> competitors;
  final List<TournamentSeriesGame> games;
  TournamentSeries({
    this.title,
    this.total,
    this.completed = false,
    this.competitors = const [],
    this.games = const [],
  });
  factory TournamentSeries.fromJson(Map<String, dynamic> j) => TournamentSeries(
        title: _strOrNull(j['title']),
        total: _int(j['total']),
        completed: _bool(j['completed']),
        competitors: _list(j['competitors'])
            .map((c) => TournamentSeriesSide.fromJson(_map(c)))
            .toList(growable: false),
        games: _list(j['games'])
            .map((g) => TournamentSeriesGame.fromJson(_map(g)))
            .toList(growable: false),
      );
}

class TournamentSeriesSide {
  final String id;
  final String? name, abbr;
  final int wins;
  TournamentSeriesSide({required this.id, this.name, this.abbr, this.wins = 0});
  factory TournamentSeriesSide.fromJson(Map<String, dynamic> j) => TournamentSeriesSide(
        id: _str(j['id']),
        name: _strOrNull(j['name']),
        abbr: _strOrNull(j['abbr']),
        wins: _int(j['wins']) ?? 0,
      );
}

class TournamentSeriesGame {
  final String eventId;
  final DateTime? date;
  final String phase;
  final int? gameNumber;
  final List<TournamentSeriesGameSide> sides;
  TournamentSeriesGame({
    required this.eventId,
    this.date,
    required this.phase,
    this.gameNumber,
    this.sides = const [],
  });
  factory TournamentSeriesGame.fromJson(Map<String, dynamic> j) => TournamentSeriesGame(
        eventId: _str(j['eventId']),
        date: DateTime.tryParse(_str(j['date']))?.toLocal(),
        phase: _str(j['phase']),
        gameNumber: _int(j['gameNumber']),
        sides: _list(j['sides'])
            .map((s) => TournamentSeriesGameSide.fromJson(_map(s)))
            .toList(growable: false),
      );
}

class TournamentSeriesGameSide {
  final String id;
  final String? abbr, score;
  final bool winner;
  TournamentSeriesGameSide({required this.id, this.abbr, this.score, this.winner = false});
  factory TournamentSeriesGameSide.fromJson(Map<String, dynamic> j) =>
      TournamentSeriesGameSide(
        id: _str(j['id']),
        abbr: _strOrNull(j['abbr']),
        score: _strOrNull(j['score']),
        winner: _bool(j['winner']),
      );
}

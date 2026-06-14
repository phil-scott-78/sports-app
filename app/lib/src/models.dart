// Dart mirror of schema/canonical.ts (+ catalog/standings). Hand-written,
// tolerant fromJson — missing fields never throw. Keep field names aligned with
// the worker's output (worker/src/normalize.js).

// ---- parse helpers ----------------------------------------------------------
int? _int(dynamic v) =>
    v is int ? v : (v is num ? v.toInt() : (v is String ? int.tryParse(v) : null));
num? _num(dynamic v) => v is num ? v : (v is String ? num.tryParse(v) : null);
String _str(dynamic v) => v == null ? '' : v.toString();
String? _strOrNull(dynamic v) => v?.toString();
bool _bool(dynamic v) => v == true;
List<dynamic> _list(dynamic v) => v is List ? v : const [];
Map<String, dynamic> _map(dynamic v) =>
    v is Map ? v.map((k, val) => MapEntry(k.toString(), val)) : <String, dynamic>{};

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
        events: _list(j['events'])
            .map((e) => SportEvent.fromJson(_map(e)))
            .toList(growable: false),
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
  final List<String> broadcasts;
  final List<String> notes;
  final EventLinks links;
  final List<Competition> competitions;

  SportEvent({
    required this.id,
    required this.name,
    required this.shortName,
    required this.start,
    required this.neutralSite,
    required this.venue,
    required this.broadcasts,
    required this.notes,
    required this.links,
    required this.competitions,
  });

  /// The primary competition (most sports have exactly one; F1 has several).
  Competition? get main => competitions.isEmpty ? null : competitions.first;

  factory SportEvent.fromJson(Map<String, dynamic> j) => SportEvent(
        id: _str(j['id']),
        name: _str(j['name']),
        shortName: _str(j['shortName']),
        start: DateTime.tryParse(_str(j['start']))?.toLocal(),
        neutralSite: _bool(j['neutralSite']),
        venue: j['venue'] == null ? null : Venue.fromJson(_map(j['venue'])),
        broadcasts:
            _list(j['broadcasts']).map(_str).toList(growable: false),
        notes: _list(j['notes']).map(_str).toList(growable: false),
        links: EventLinks.fromJson(_map(j['links'])),
        competitions: _list(j['competitions'])
            .map((c) => Competition.fromJson(_map(c)))
            .toList(growable: false),
      );
}

class Venue {
  final String name;
  final String? city, country;
  final bool indoor;
  Venue({required this.name, this.city, this.country, this.indoor = false});
  factory Venue.fromJson(Map<String, dynamic> j) => Venue(
        name: _str(j['name']),
        city: _strOrNull(j['city']),
        country: _strOrNull(j['country']),
        indoor: _bool(j['indoor']),
      );
  String get location =>
      [if (city != null) city, if (country != null) country].join(', ');
}

class EventLinks {
  final String? web, box;
  EventLinks({this.web, this.box});
  factory EventLinks.fromJson(Map<String, dynamic> j) =>
      EventLinks(web: _strOrNull(j['web']), box: _strOrNull(j['box']));
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
    this.label,
  });

  bool get isField => layout == 'field';
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
        meta: j['meta'] == null ? null : CompetitionMeta.fromJson(_map(j['meta'])),
        situation: j['situation'] == null ? null : Situation.fromJson(_map(j['situation'])),
      );
}

/// Live game situation — sport-agnostic union, only present keys are set.
class Situation {
  // baseball
  final int? balls, strikes, outs;
  final bool? onFirst, onSecond, onThird;
  final String? pitcher, batter, outsText;
  // gridiron
  final int? down, distance, homeTimeouts, awayTimeouts;
  final String? downDistanceText, possession;
  final bool? isRedZone;
  // any sport
  final String? lastPlay;
  Situation({
    this.balls,
    this.strikes,
    this.outs,
    this.onFirst,
    this.onSecond,
    this.onThird,
    this.pitcher,
    this.batter,
    this.outsText,
    this.down,
    this.distance,
    this.homeTimeouts,
    this.awayTimeouts,
    this.downDistanceText,
    this.possession,
    this.isRedZone,
    this.lastPlay,
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
        outsText: _strOrNull(j['outsText']),
        down: _int(j['down']),
        distance: _int(j['distance']),
        homeTimeouts: _int(j['homeTimeouts']),
        awayTimeouts: _int(j['awayTimeouts']),
        downDistanceText: _strOrNull(j['downDistanceText']),
        possession: _strOrNull(j['possession']),
        isRedZone: j['isRedZone'] is bool ? j['isRedZone'] as bool : null,
        lastPlay: _strOrNull(j['lastPlay']),
      );
  bool get hasBaseball => balls != null || strikes != null || outs != null;
  bool get hasGridiron => downDistanceText != null || down != null;
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
  final String? shortName, abbreviation, logo, logoDark, color, altColor, homeAway;
  final int? order, startOrder, rank, seed;
  final bool? winner;
  final Score? score;
  final List<PeriodScore> periodScores;
  final List<Athlete> athletes;
  final List<TeamRecord> records;
  final num? shootoutScore;
  final String? aggregateScore;
  final bool? advance;
  // cheap-tier context already in the scoreboard (see DISPLAY-SPEC.md)
  final Map<String, String> stats; // team stat line, keyed by ESPN abbr
  final List<Leader> leaders;
  final List<Probable> probables;
  final int? hits, errors; // baseball R/H/E
  final String? form; // soccer/rugby recent form 'WLWWW'
  final Vehicle? vehicle; // racing

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
  });

  bool get isWinner => winner == true;
  String get label =>
      abbreviation ?? shortName ?? displayName;
  String? get recordSummary =>
      records.isEmpty ? null : records.first.summary;

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
        vehicle: j['vehicle'] == null ? null : Vehicle.fromJson(_map(j['vehicle'])),
      );

  /// Baseball R/H/E availability.
  bool get hasRHE => hits != null || errors != null;
}

class Vehicle {
  final String? number, manufacturer, team, owner, sponsor;
  Vehicle({this.number, this.manufacturer, this.team, this.owner, this.sponsor});
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
  Probable({required this.role, required this.athlete});
  factory Probable.fromJson(Map<String, dynamic> j) =>
      Probable(role: _str(j['role']), athlete: _str(j['athlete']));
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
        cricket: j['cricket'] == null ? null : CricketScore.fromJson(_map(j['cricket'])),
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
  final String? round, seriesSummary, cardSegment, flag, cricketClass, cricketSummary;
  final bool? featured, hadPlayoff;
  CompetitionMeta({
    this.round,
    this.seriesSummary,
    this.cardSegment,
    this.flag,
    this.cricketClass,
    this.cricketSummary,
    this.featured,
    this.hadPlayoff,
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
      );
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
  CatalogLeague({
    required this.key,
    required this.league,
    required this.name,
    this.abbr,
    this.region,
    this.priority,
    this.leagueId,
  });
  factory CatalogLeague.fromJson(Map<String, dynamic> j) => CatalogLeague(
        key: _str(j['key']),
        league: _str(j['league']),
        name: _str(j['name']),
        abbr: _strOrNull(j['abbr']),
        region: _strOrNull(j['region']),
        priority: _strOrNull(j['priority']),
        leagueId: _strOrNull(j['leagueId']),
      );
}

// ---- overview (Leagues season-pulse) ----------------------------------------
/// One league's at-a-glance state for the Leagues list. `state` is one of
/// live | today | upcoming | recent | offseason | unknown; `detail` is a short
/// human caption ("Live now", "Tomorrow", "Returns Aug 6"). Computed by the
/// worker (see worker/src/overview.js) so the app stays a thin renderer.
class LeagueStateInfo {
  final String key, state, detail;
  final bool live;
  LeagueStateInfo({required this.key, required this.state, required this.detail, required this.live});
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
  final List<StandingsGroup> groups;
  Standings({required this.league, this.season, required this.groups});
  factory Standings.fromJson(Map<String, dynamic> j) => Standings(
        league: _str(j['league']),
        season: _int(j['season']),
        groups: _list(j['groups'])
            .map((g) => StandingsGroup.fromJson(_map(g)))
            .toList(growable: false),
      );
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
  StandingsRow({required this.team, this.rank, required this.stats});
  factory StandingsRow.fromJson(Map<String, dynamic> j) => StandingsRow(
        team: StandingsTeam.fromJson(_map(j['team'])),
        rank: _int(j['rank']),
        stats: _map(j['stats'])
            .map((k, v) => MapEntry(k, _str(v))),
      );
}

class StandingsTeam {
  final String id, name;
  final String? abbr, logo, logoDark;
  StandingsTeam({required this.id, required this.name, this.abbr, this.logo, this.logoDark});
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

/// The team-identity block of a [TeamCard] (name, crest, record).
class TeamCardTeam {
  final String id, displayName;
  final String? abbreviation, logo, logoDark, color, record;
  TeamCardTeam({
    required this.id,
    required this.displayName,
    this.abbreviation,
    this.logo,
    this.logoDark,
    this.color,
    this.record,
  });
  factory TeamCardTeam.fromJson(Map<String, dynamic> j) => TeamCardTeam(
        id: _str(j['id']),
        displayName: _str(j['displayName']),
        abbreviation: _strOrNull(j['abbreviation']),
        logo: _strOrNull(j['logo']),
        logoDark: _strOrNull(j['logoDark']),
        color: _strOrNull(j['color']),
        record: _strOrNull(j['record']),
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
    SportEvent? ev(dynamic v) => v == null ? null : SportEvent.fromJson(_map(v));
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
  const FavoriteTeam({
    required this.league,
    required this.teamId,
    required this.name,
    this.abbr,
    this.logo,
  });

  /// Stable composite key for dedupe / membership.
  String get id => '$league#$teamId';

  Map<String, dynamic> toJson() => {
        'league': league,
        'teamId': teamId,
        'name': name,
        if (abbr != null) 'abbr': abbr,
        if (logo != null) 'logo': logo,
      };
  factory FavoriteTeam.fromJson(Map<String, dynamic> j) => FavoriteTeam(
        league: _str(j['league']),
        teamId: _str(j['teamId']),
        name: _str(j['name']),
        abbr: _strOrNull(j['abbr']),
        logo: _strOrNull(j['logo']),
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

// ---- game summary (rich tier) -----------------------------------------------
class GameSummary {
  final String eventId;
  final bool live;
  final List<TeamStatRow> teamStats;
  final List<BoxGroup> boxGroups;
  final List<SummaryPlay> scoringPlays;
  final PeriodLines? periodLines;
  final List<Lineup> lineups;
  GameSummary({
    required this.eventId,
    required this.live,
    required this.teamStats,
    required this.boxGroups,
    required this.scoringPlays,
    required this.periodLines,
    required this.lineups,
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
        periodLines: j['periodLines'] == null ? null : PeriodLines.fromJson(_map(j['periodLines'])),
        lineups: _list(j['lineups'])
            .map((l) => Lineup.fromJson(_map(l)))
            .toList(growable: false),
      );

  bool get isEmpty =>
      teamStats.isEmpty &&
      boxGroups.isEmpty &&
      scoringPlays.isEmpty &&
      lineups.isEmpty &&
      periodLines == null;
}

class TeamStatRow {
  final String label;
  final String? away, home;
  TeamStatRow({required this.label, this.away, this.home});
  factory TeamStatRow.fromJson(Map<String, dynamic> j) =>
      TeamStatRow(label: _str(j['label']), away: _strOrNull(j['away']), home: _strOrNull(j['home']));
}

class BoxGroup {
  final String title;
  final List<String> columns;
  final List<BoxTeam> teams;
  BoxGroup({required this.title, required this.columns, required this.teams});
  factory BoxGroup.fromJson(Map<String, dynamic> j) => BoxGroup(
        title: _str(j['title']),
        columns: _list(j['columns']).map(_str).toList(growable: false),
        teams: _list(j['teams']).map((t) => BoxTeam.fromJson(_map(t))).toList(growable: false),
      );
}

class BoxTeam {
  final String? side, abbr;
  final List<BoxRow> rows;
  BoxTeam({this.side, this.abbr, required this.rows});
  factory BoxTeam.fromJson(Map<String, dynamic> j) => BoxTeam(
        side: _strOrNull(j['side']),
        abbr: _strOrNull(j['abbr']),
        rows: _list(j['rows']).map((r) => BoxRow.fromJson(_map(r))).toList(growable: false),
      );
}

class BoxRow {
  final String name;
  final String? pos;
  final List<String> stats;
  BoxRow({required this.name, this.pos, required this.stats});
  factory BoxRow.fromJson(Map<String, dynamic> j) => BoxRow(
        name: _str(j['name']),
        pos: _strOrNull(j['pos']),
        stats: _list(j['stats']).map(_str).toList(growable: false),
      );
}

class SummaryPlay {
  final int? period;
  final String? periodLabel, clock, side, teamAbbr, type;
  final String text;
  final num? away, home;
  SummaryPlay({
    this.period,
    this.periodLabel,
    this.clock,
    this.side,
    this.teamAbbr,
    this.type,
    required this.text,
    this.away,
    this.home,
  });
  factory SummaryPlay.fromJson(Map<String, dynamic> j) => SummaryPlay(
        period: _int(j['period']),
        periodLabel: _strOrNull(j['periodLabel']),
        clock: _strOrNull(j['clock']),
        side: _strOrNull(j['side']),
        teamAbbr: _strOrNull(j['teamAbbr']),
        type: _strOrNull(j['type']),
        text: _str(j['text']),
        away: _num(j['away']),
        home: _num(j['home']),
      );
}

class PeriodLines {
  final String unit;
  final List<String> labels;
  final SidePeriods away, home;
  PeriodLines({required this.unit, required this.labels, required this.away, required this.home});
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
  Lineup({this.side, this.abbr, this.formation, required this.starters, required this.bench});
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
  final String name;
  final String? pos, jersey;
  LineupPlayer({required this.name, this.pos, this.jersey});
  factory LineupPlayer.fromJson(Map<String, dynamic> j) => LineupPlayer(
        name: _str(j['name']),
        pos: _strOrNull(j['pos']),
        jersey: _strOrNull(j['jersey']),
      );
}

// A session-lived team-IDENTITY cache — the one primitive every screen calls
// for a team's color/logo/tricode (SCORES-APP-BUILD-SPEC §3.1).
//
// WHY: standings and summary payloads OMIT team color, and standings needs the
// join to paint its rows; tournament sides carry only an id. ESPN DOES ship
// color + logo on the cheap scoreboard and on /teams, so we warm a
// `teamId -> {logo, logoDark, color, altColor, abbreviation}` map from every
// normalized scoreboard/teams payload that flows through the data layer, then
// let color-less screens (standings rows, bracket bars, avatars) join by id.
//
// This layer is PURE (no Flutter, no theme) — it stores raw ESPN hex strings and
// CDN URLs; UI consumers convert hex → a legible Color via util.teamColorOf. The
// warm-up is a passive side effect hung off api.dart AFTER normalization (never
// inside the pure normalizers), so a cache miss simply means a neutral fallback,
// never a wrong render.

/// One team's cached identity. Every field optional — a source (e.g. /teams)
/// may carry no altColor, a scoreboard may carry no logoDark until derived.
class TeamIdentity {
  final String? logo, logoDark, color, altColor, abbreviation;
  const TeamIdentity({
    this.logo,
    this.logoDark,
    this.color,
    this.altColor,
    this.abbreviation,
  });

  bool get hasColor => color != null && color!.isNotEmpty;
}

/// Derive the dark-background logo variant from a standard ESPN team logo URL
/// (`…/i/teamlogos/…/500/…` → `…/500-dark/…`), per the §3.1 spec note. Null when
/// the URL isn't the recognizable 500-px team-logo shape. Consumers still fall
/// back to the light logo on a 404 (Image.errorBuilder).
String? deriveLogoDark(String? logo) =>
    (logo != null && logo.contains('/i/teamlogos/') && logo.contains('/500/'))
        ? logo.replaceFirst('/500/', '/500-dark/')
        : null;

/// The process-wide identity cache. A plain singleton (not Riverpod) so any
/// widget can read it synchronously — `IdentityCache.instance[teamId]`.
class IdentityCache {
  IdentityCache._();
  static final IdentityCache instance = IdentityCache._();

  final Map<String, TeamIdentity> _by = {};

  /// Lookup by team id — null when the cache hasn't seen this team yet.
  TeamIdentity? operator [](String? id) =>
      (id == null || id.isEmpty) ? null : _by[id];

  int get length => _by.length;

  /// Test-only reset (the cache is process-lived; tests warm it in isolation).
  void clear() => _by.clear();

  /// Merge one team's identity in. Only NON-EMPTY incoming fields are written,
  /// so a color-less source (standings/rankings) can add a logo without erasing
  /// a color an earlier scoreboard already supplied — and vice-versa. logoDark
  /// is derived from the light logo when the source didn't ship one.
  void put(
    String? id, {
    String? logo,
    String? logoDark,
    String? color,
    String? altColor,
    String? abbreviation,
  }) {
    if (id == null || id.isEmpty) return;
    final prev = _by[id];
    String? keep(String? incoming, String? old) =>
        (incoming != null && incoming.isNotEmpty) ? incoming : old;
    final nextLogo = keep(logo, prev?.logo);
    _by[id] = TeamIdentity(
      logo: nextLogo,
      logoDark: keep(logoDark, prev?.logoDark) ?? deriveLogoDark(nextLogo),
      color: keep(color, prev?.color),
      altColor: keep(altColor, prev?.altColor),
      abbreviation: keep(abbreviation, prev?.abbreviation),
    );
  }

  /// Warm from a normalized scoreboard map (the [normalizeScoreboard] output):
  /// events[].competitions[].competitors[]. Only `team`-kind competitors carry a
  /// club identity — athletes (golf/tennis/mma/racing) and doubles pairs are
  /// skipped (they have neither a club logo nor a color; §3.1).
  void warmScoreboard(dynamic payload) {
    if (payload is! Map) return;
    final events = payload['events'];
    if (events is! List) return;
    for (final ev in events) {
      final comps = (ev is Map) ? ev['competitions'] : null;
      if (comps is! List) continue;
      for (final comp in comps) {
        final cs = (comp is Map) ? comp['competitors'] : null;
        if (cs is! List) continue;
        for (final c in cs) {
          _warmCompetitor(c);
        }
      }
    }
  }

  void _warmCompetitor(dynamic c) {
    if (c is! Map) return;
    // Only club-shaped competitors have joinable identity. `kind` is per
    // competitor in the canonical shape; when absent, fall back to accepting
    // anything that actually carries a color/logo.
    final kind = c['kind'];
    if (kind is String && kind != 'team') return;
    final color = c['color'], logo = c['logo'];
    if (kind == null && (color == null || color == '') && (logo == null || logo == '')) {
      return;
    }
    put(
      c['id']?.toString(),
      logo: _s(c['logo']),
      logoDark: _s(c['logoDark']),
      color: _s(c['color']),
      altColor: _s(c['altColor']),
      abbreviation: _s(c['abbreviation']),
    );
  }

  /// Warm from a normalized /teams list (the [normalizeTeams] output): each entry
  /// carries id + abbreviation + logo/logoDark + color (no altColor).
  void warmTeams(dynamic teams) {
    if (teams is! List) return;
    for (final t in teams) {
      if (t is! Map) continue;
      put(
        t['id']?.toString(),
        logo: _s(t['logo']),
        logoDark: _s(t['logoDark']),
        color: _s(t['color']),
        altColor: _s(t['altColor']),
        abbreviation: _s(t['abbreviation']),
      );
    }
  }

  static String? _s(dynamic v) {
    if (v == null) return null;
    final s = v.toString();
    return s.isEmpty ? null : s;
  }
}

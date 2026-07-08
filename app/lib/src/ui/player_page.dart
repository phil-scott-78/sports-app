import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import '../util.dart';
import 'widgets.dart';

/// Open a player's overview page (design 11e). Mirrors [openTeamPage] /
/// [openLeaguePage]. `name`/`color` seed the identity block before the CORE
/// fan-out resolves (so a tap from a leaders/roster row renders instantly), and
/// `teamId` lets the data layer read the denser roster row.
void openPlayerPage(
  BuildContext context,
  String league, {
  required String athleteId,
  String? teamId,
  String? name,
  String? color,
}) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => PlayerPage(
      league: league,
      athleteId: athleteId,
      teamId: teamId,
      name: name,
      color: color,
    ),
  ));
}

/// The player overview (design 11e): a compact 'PLAYER' bar, a headshot +
/// identity block, then two data-gated cards — the SEASON per-game grid and the
/// LAST-N game log. An identity-only profile (no stats/games) renders the
/// identity and nothing else, cleanly. No follow/star yet (the header keeps a
/// slot for it).
class PlayerPage extends ConsumerWidget {
  final String league, athleteId;
  final String? teamId, name, color;
  const PlayerPage({
    super.key,
    required this.league,
    required this.athleteId,
    this.teamId,
    this.name,
    this.color,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (league: league, athleteId: athleteId, teamId: teamId);
    final async = ref.watch(athleteProfileProvider(key));
    final profile = async.valueOrNull;
    // Seed identity so the block paints before / regardless of the fetch.
    final seedColor = teamColorOf(profile?.team?.color ?? color);

    return Scaffold(
      appBar: overviewBar(context, 'PLAYER'),
      body: switch (async) {
        AsyncError() when profile == null && name == null => const Padding(
            padding: EdgeInsets.all(T.pageMargin),
            child: HintCard('Couldn’t load this player.'),
          ),
        AsyncLoading() when profile == null && name == null => const Padding(
            padding: EdgeInsets.only(top: 100),
            child: Center(child: CircularProgressIndicator(color: T.gold)),
          ),
        _ => _body(profile, seedColor),
      },
    );
  }

  Widget _body(AthleteProfile? p, Color color) {
    final displayName = p?.name ?? name ?? athleteId;
    final season = _selectStats(p?.stats ?? const [], _seasonPriority, 8);
    final games = p?.lastGames ?? const [];
    return ListView(
      padding: const EdgeInsets.only(bottom: T.scrollBottom),
      children: [
        _Identity(profile: p, displayName: displayName, color: color),
        if (season.isNotEmpty) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: T.pageMargin),
            child: _PerGameCard(stats: season),
          ),
        ],
        if (games.isNotEmpty) ...[
          const SizedBox(height: T.gapCard),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: T.pageMargin),
            child: _GameLogCard(profile: p!, games: games),
          ),
        ],
      ],
    );
  }
}

/// Headshot + name + 'color · #jersey · position · team' line (11e). Every
/// sub-field is presence-gated so an identity-only seed still reads cleanly.
class _Identity extends StatelessWidget {
  final AthleteProfile? profile;
  final String displayName;
  final Color color;
  const _Identity({
    required this.profile,
    required this.displayName,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final sub = <Widget>[];
    void dot() {
      if (sub.isNotEmpty) {
        sub.add(const Text('·', style: TextStyle(fontSize: 12.5, color: T.textFaint)));
      }
    }

    if (p?.jersey != null && p!.jersey!.isNotEmpty) {
      dot();
      sub.add(Text('#${p.jersey}',
          style: const TextStyle(
              fontSize: 12.5, fontWeight: FontWeight.w600, color: T.text)));
    }
    if (p?.position != null && p!.position!.isNotEmpty) {
      dot();
      sub.add(Text(p.position!, style: T.caption));
    }
    if (p?.team?.name != null && p!.team!.name.isNotEmpty) {
      dot();
      sub.add(Flexible(
          child: Text(p.team!.name,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: T.caption)));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(T.pageMargin, 8, T.pageMargin, 12),
      child: Row(children: [
        LogoAvatar(
            url: p?.headshot, initials: initialsOf(displayName), color: color, size: 92),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(displayName.toUpperCase(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontFamily: 'BarlowCondensed',
                    fontWeight: FontWeight.w700,
                    fontSize: 30,
                    height: 0.95,
                    color: T.text)),
            const SizedBox(height: 6),
            Row(children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(3)),
              ),
              Expanded(
                child: Row(children: [
                  for (var i = 0; i < sub.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    sub[i],
                  ],
                ]),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// SEASON · PER GAME (11e): a 4-column grid of Barlow-26 values over faint
/// letterspaced labels. Column headers come from each stat's abbreviation — the
/// exact stat set is whatever the sport serves (see gap #21: per-game stat names
/// are inferred, so the selection is a cross-sport priority list, never a
/// per-sport branch).
class _PerGameCard extends StatelessWidget {
  final List<AthleteStat> stats;
  const _PerGameCard({required this.stats});

  @override
  Widget build(BuildContext context) => V2Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const CardLabel('Season · Per game'),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 14,
            crossAxisSpacing: 4,
            childAspectRatio: 1.55,
            children: [for (final s in stats) _cell(s)],
          ),
        ]),
      );

  Widget _cell(AthleteStat s) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.displayValue,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontFamily: 'BarlowCondensed',
                fontWeight: FontWeight.w700,
                fontSize: 26,
                height: 1.0,
                color: T.text,
                fontFeatures: [FontFeature.tabularFigures()])),
        const SizedBox(height: 4),
        Text(_label(s).toUpperCase(), maxLines: 1, style: T.captionFaint),
      ]);
}

/// LAST N GAMES (11e): OPP + up to three per-game stat columns (RESULT omitted —
/// the eventlog row carries no win/loss and resolving each event's winner is an
/// extra N fetches the data layer doesn't do). The first stat column is the
/// primary (Barlow-15/700); the rest recede to dim.
class _GameLogCard extends StatelessWidget {
  final AthleteProfile profile;
  final List<AthleteGameRow> games;
  const _GameLogCard({required this.profile, required this.games});

  @override
  Widget build(BuildContext context) {
    // Column set from the first game that serves stats (so headers align).
    final template = games.firstWhere((g) => g.stats.isNotEmpty,
        orElse: () => games.first);
    final cols = _selectStats(template.stats, _gamePriority, 3);
    return V2Card(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CardLabel('Last ${games.length} games'),
        const SizedBox(height: 4),
        _header(cols),
        for (final g in games) _row(g, cols),
      ]),
    );
  }

  Widget _header(List<AthleteStat> cols) => Container(
        padding: const EdgeInsets.only(top: 8, bottom: 7),
        decoration:
            const BoxDecoration(border: Border(bottom: BorderSide(color: T.border))),
        child: Row(children: [
          const Expanded(child: Text('OPP', style: T.cardLabelFaint)),
          for (var i = 0; i < cols.length; i++)
            SizedBox(
              width: 40,
              child: Text(_label(cols[i]).toUpperCase(),
                  textAlign: TextAlign.right,
                  style: i == 0
                      ? T.cardLabelFaint.copyWith(color: T.text)
                      : T.cardLabelFaint),
            ),
        ]),
      );

  Widget _row(AthleteGameRow g, List<AthleteStat> cols) {
    // per-game cell values, keyed by the template column's stat name.
    String cell(String name) {
      for (final c in g.stats) {
        for (final s in c.stats) {
          if (s.name == name) return s.displayValue;
        }
      }
      return '—';
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: T.rowVPad),
      decoration:
          const BoxDecoration(border: Border(top: BorderSide(color: T.divider))),
      child: Row(children: [
        Expanded(
          child: Text(_opp(g),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: T.listText.copyWith(fontWeight: FontWeight.w600)),
        ),
        for (var i = 0; i < cols.length; i++)
          SizedBox(
            width: 40,
            child: Text(cell(cols[i].name),
                textAlign: TextAlign.right,
                style: i == 0
                    ? const TextStyle(
                        fontFamily: 'BarlowCondensed',
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: T.text,
                        fontFeatures: [FontFeature.tabularFigures()])
                    : T.statLine.copyWith(color: T.textDim)),
          ),
      ]),
    );
  }

  /// 'vs NY' / '@ TOR' from the row's `shortName` ('DAL @ NY') + the player's
  /// team abbreviation, else the raw shortName.
  String _opp(AthleteGameRow g) {
    final sn = g.shortName ?? g.name;
    final abbr = profile.team?.abbr;
    if (sn != null && abbr != null && sn.contains(' @ ')) {
      final parts = sn.split(' @ ');
      if (parts.length == 2) {
        final away = parts[0].trim(), home = parts[1].trim();
        if (away == abbr) return '@ $home';
        if (home == abbr) return 'vs $away';
      }
    }
    return sn ?? '';
  }
}

// ---- shared identity chrome (also used by the team page) --------------------

/// A compact sub-page bar: back chevron + a centered small-caps label
/// ('TEAM' / 'CLUB' / 'PLAYER'). The big shouted name lives in the identity
/// block below, per the overview grammar — so this bar stays a quiet marker.
PreferredSizeWidget overviewBar(BuildContext context, String label,
        {Widget? trailing}) =>
    AppBar(
      backgroundColor: T.bg,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded,
            size: 18, color: T.textDim),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: Text(label.toUpperCase(),
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: T.textDim)),
      actions: trailing != null ? [trailing] : null,
    );

/// A circular network logo/headshot with a [TintedAvatar] fallback: the avatar
/// paints first (initials on a team-tinted disc) and the network image covers
/// it once it loads; on a load error the avatar simply stays.
class LogoAvatar extends StatelessWidget {
  final String? url;
  final String initials;
  final Color color;
  final double size;
  const LogoAvatar({
    super.key,
    required this.url,
    required this.initials,
    required this.color,
    this.size = 80,
  });

  @override
  Widget build(BuildContext context) {
    final avatar = TintedAvatar(initials, color, size: size);
    if (url == null || url!.isEmpty) return ClipOval(child: avatar);
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(fit: StackFit.expand, children: [
          avatar,
          Image.network(url!,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => const SizedBox.shrink()),
        ]),
      ),
    );
  }
}

/// First+last initial (or the single leading letter) for an avatar fallback.
String initialsOf(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
}

// ---- data-driven stat selection ---------------------------------------------

/// A cell's short label: abbreviation → shortDisplayName → name. Always from the
/// DATA, never a hardcoded header string.
String _label(AthleteStat s) =>
    (s.abbreviation != null && s.abbreviation!.isNotEmpty)
        ? s.abbreviation!
        : (s.shortDisplayName != null && s.shortDisplayName!.isNotEmpty)
            ? s.shortDisplayName!
            : s.name;

/// Pick up to [cap] stat cells from the flattened categories, in a cross-sport
/// priority order (per-game / rate headline stats), then fill any remaining
/// slots with whatever else the sport serves (skipping per-48 duplicates).
/// Dispatch is by stat NAME + structure, never by sport name. Deduped by label.
List<AthleteStat> _selectStats(
    List<AthleteStatCategory> cats, List<String> priority, int cap) {
  final flat = <String, AthleteStat>{};
  for (final c in cats) {
    for (final s in c.stats) {
      flat.putIfAbsent(s.name, () => s);
    }
  }
  final out = <AthleteStat>[];
  final seen = <String>{};
  bool take(AthleteStat s) {
    final k = _label(s).toLowerCase();
    if (!seen.add(k)) return false;
    out.add(s);
    return true;
  }

  for (final name in priority) {
    final s = flat[name];
    if (s != null) take(s);
    if (out.length >= cap) return out;
  }
  // Fallback fill: the sport isn't (fully) covered by the priority list — append
  // remaining cells in category order, skipping the per-48 rate duplicates.
  for (final c in cats) {
    for (final s in c.stats) {
      if (out.length >= cap) return out;
      if (s.name.contains('48')) continue;
      take(s);
    }
  }
  return out;
}

/// Cross-sport per-game / rate headline stats for the SEASON grid, by ESPN stat
/// `name`. A union across sports applied generically (first present wins).
const _seasonPriority = <String>[
  // basketball
  'avgPoints', 'avgRebounds', 'avgAssists', 'avgSteals', 'avgBlocks',
  'fieldGoalPct', 'threePointFieldGoalPct', 'threePointPct', 'freeThrowPct',
  'avgMinutes',
  // baseball — batting
  'avg', 'homeRuns', 'RBIs', 'runs', 'hits', 'onBasePlusSlugging',
  'stolenBases', 'onBasePct', 'sluggingPct',
  // baseball — pitching
  'ERA', 'wins', 'losses', 'strikeouts', 'WHIP', 'saves', 'inningsPitched',
  // hockey
  'goals', 'assists', 'points', 'plusMinus', 'savePct', 'goalsAgainstAverage',
  // football
  'passingYards', 'passingTouchdowns', 'completionPct', 'QBRating',
  'rushingYards', 'rushingTouchdowns', 'receivingYards', 'receptions',
  'receivingTouchdowns', 'totalTackles', 'sacks', 'interceptions',
  // soccer
  'appearances', 'shotsTotal', 'foulsCommitted', 'yellowCards',
];

/// Cross-sport raw single-game headline stats for the LAST-N game columns.
const _gamePriority = <String>[
  'points', 'rebounds', 'assists', 'steals', 'blocks', // basketball
  'hits', 'homeRuns', 'RBIs', 'runs', 'stolenBases', // baseball — batting
  'strikeouts', 'inningsPitched', 'earnedRuns', // baseball — pitching
  'goals', 'assists', 'points', 'saves', // hockey / soccer
  'passingYards', 'rushingYards', 'receivingYards', 'receptions',
  'totalTackles', 'sacks', // football
];

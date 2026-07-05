import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import '../util.dart';
import 'widgets.dart';

/// Long-press a game row → follow either team, or the league. The design's
/// "add from anywhere" gesture (turn 8b).
void showGameFollowSheet(
  BuildContext context, {
  required String league,
  String? leagueName,
  required Competition comp,
}) {
  final teams = comp.competitors.where((c) => c.kind == 'team').toList();
  _showSheet(context, league: league, leagueName: leagueName, teams: [
    for (final c in teams)
      (
        teamId: c.id,
        name: c.displayName,
        abbr: c.abbreviation ?? c.label,
        color: teamColor(c),
        colorHex: c.color,
        record: c.recordSummary,
      ),
  ]);
}

/// Long-press a favorite hero card → manage that one team.
void showTeamFollowSheet(
  BuildContext context, {
  required String league,
  required String teamId,
  required String name,
  String? abbr,
  String? subtitle,
}) {
  _showSheet(context, league: league, leagueName: subtitle, teams: [
    (
      teamId: teamId,
      name: name,
      abbr: abbr ?? name,
      color: T.outline,
      colorHex: null,
      record: null,
    ),
  ]);
}

typedef _SheetTeam = ({
  String teamId,
  String name,
  String abbr,
  Color color,
  String? colorHex,
  String? record,
});

void _showSheet(
  BuildContext context, {
  required String league,
  String? leagueName,
  required List<_SheetTeam> teams,
}) {
  showModalBottomSheet<void>(
    context: context,
    barrierColor: const Color(0x73080A0D),
    builder: (_) => _FollowSheet(
        league: league, leagueName: leagueName, teams: teams),
  );
}

class _FollowSheet extends ConsumerWidget {
  final String league;
  final String? leagueName;
  final List<_SheetTeam> teams;
  const _FollowSheet({
    required this.league,
    required this.leagueName,
    required this.teams,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favs = ref.watch(favoriteTeamsProvider.notifier);
    ref.watch(favoriteTeamsProvider); // rebuild on toggle
    final followed = ref.watch(followedProvider).contains(league);
    final displayLeague = leagueName ?? league.split('/').last.toUpperCase();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: T.outline, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            if (teams.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.only(bottom: 14),
                decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: T.border))),
                child: Row(children: [
                  CrestCircle(abbr: teams.first.abbr, color: teams.first.color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(teams.first.name,
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: T.text)),
                          if (teams.first.record != null)
                            Text(teams.first.record!, style: T.caption),
                        ]),
                  ),
                ]),
              ),
            ],
            for (final t in teams)
              _SheetRow(
                icon: favs.contains(league, t.teamId)
                    ? const Icon(Icons.star_rounded, color: T.gold, size: 22)
                    : const Icon(Icons.star_border_rounded,
                        color: T.textDim, size: 22),
                title: favs.contains(league, t.teamId)
                    ? 'Remove ${_short(t.name)} from favorites'
                    : 'Add ${_short(t.name)} to favorites',
                subtitle: 'Pinned card on your home feed',
                emphasized: !favs.contains(league, t.teamId),
                onTap: () {
                  favs.toggle(FavoriteTeam(
                    league: league,
                    teamId: t.teamId,
                    name: t.name,
                    abbr: t.abbr,
                    color: t.colorHex,
                  ));
                },
              ),
            _SheetRow(
              icon: Icon(
                followed ? Icons.check_circle_rounded : Icons.add_circle_outline,
                color: followed ? T.gold : T.textDim,
                size: 22,
              ),
              title: followed
                  ? 'Following $displayLeague'
                  : 'Follow $displayLeague',
              subtitle: followed
                  ? 'Tap to remove its section from your feed'
                  : 'Its games get a section in your feed',
              divider: false,
              onTap: () => ref.read(followedProvider.notifier).toggle(league),
            ),
          ],
        ),
      ),
    );
  }

  String _short(String name) {
    final parts = name.split(' ');
    return parts.isEmpty ? name : parts.last;
  }
}

class _SheetRow extends StatelessWidget {
  final Widget icon;
  final String title;
  final String? subtitle;
  final bool emphasized;
  final bool divider;
  final VoidCallback onTap;
  const _SheetRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.emphasized = false,
    this.divider = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () {
          onTap();
          Navigator.of(context).pop();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: divider
              ? const BoxDecoration(
                  border: Border(bottom: BorderSide(color: T.divider)))
              : null,
          child: Row(children: [
            SizedBox(width: 22, height: 22, child: Center(child: icon)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              emphasized ? FontWeight.w600 : FontWeight.w400,
                          color: T.text)),
                  if (subtitle != null) Text(subtitle!, style: T.caption),
                ],
              ),
            ),
          ]),
        ),
      );
}

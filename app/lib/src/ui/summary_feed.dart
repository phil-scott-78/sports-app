import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import 'widgets.dart';

/// Scoring timeline — the at-a-glance "how did we get here" story.
///
/// Consecutive plays are grouped by period; each group leads with a small muted
/// header pulled from the first play (periodLabel, else 'Period N'). Rows stay
/// compact: clock, team chip, the play text, and the running away-home score.
class ScoringFeed extends StatelessWidget {
  final List<SummaryPlay> plays;
  const ScoringFeed({super.key, required this.plays});

  @override
  Widget build(BuildContext context) {
    if (plays.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;

    final children = <Widget>[];
    int? lastPeriod;
    var firstGroup = true;
    for (final p in plays) {
      if (p.period != lastPeriod) {
        lastPeriod = p.period;
        final label = (p.periodLabel != null && p.periodLabel!.isNotEmpty)
            ? p.periodLabel!
            : 'Period ${p.period ?? ''}'.trim();
        children.add(Padding(
          padding: EdgeInsets.only(top: firstGroup ? 0 : 12, bottom: 4),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
        ));
        firstGroup = false;
      }
      children.add(_playRow(context, p));
    }

    return DetailPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _playRow(BuildContext context, SummaryPlay p) {
    final cs = Theme.of(context).colorScheme;
    final hasScore = p.away != null && p.home != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Text(
              p.clock ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: numStyle(size: 12, color: cs.onSurfaceVariant),
            ),
          ),
          SizedBox(
            width: 34,
            child: Text(
              p.teamAbbr ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
              ),
            ),
          ),
          Expanded(
            child: Text(
              p.text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: cs.onSurface),
            ),
          ),
          if (hasScore) ...[
            const SizedBox(width: 8),
            Text('${p.away}-${p.home}', style: numStyle(size: 13, weight: FontWeight.w800)),
          ],
        ],
      ),
    );
  }
}

/// Team sheets — starters and bench, stacked away-then-home.
///
/// Each lineup is its own panel: an abbr + formation header, the starting XI as
/// jersey/name/position rows, and (when present) a dimmed bench list beneath a
/// small muted 'Bench' label.
class LineupsView extends StatelessWidget {
  final List<Lineup> lineups;
  const LineupsView({super.key, required this.lineups});

  @override
  Widget build(BuildContext context) {
    if (lineups.isEmpty) return const SizedBox.shrink();

    // away before home when sides are known; otherwise keep input order.
    final ordered = [...lineups];
    if (ordered.every((l) => l.side != null)) {
      ordered.sort((a, b) {
        int rank(String? s) => s == 'away' ? 0 : (s == 'home' ? 1 : 2);
        return rank(a.side).compareTo(rank(b.side));
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < ordered.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _lineupPanel(context, ordered[i]),
        ],
      ],
    );
  }

  Widget _lineupPanel(BuildContext context, Lineup lineup) {
    final cs = Theme.of(context).colorScheme;
    final hasFormation = lineup.formation != null && lineup.formation!.isNotEmpty;
    return DetailPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                lineup.abbr ?? '',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
              if (hasFormation) ...[
                const SizedBox(width: 8),
                Text(
                  lineup.formation!,
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          for (final pl in lineup.starters) _playerRow(context, pl),
          if (lineup.bench.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Bench',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            for (final pl in lineup.bench) _playerRow(context, pl, dim: true),
          ],
        ],
      ),
    );
  }

  Widget _playerRow(BuildContext context, LineupPlayer pl, {bool dim = false}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              pl.jersey ?? '',
              maxLines: 1,
              style: numStyle(size: 13, color: cs.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              pl.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                color: dim ? cs.onSurfaceVariant : cs.onSurface,
              ),
            ),
          ),
          if (pl.pos != null && pl.pos!.isNotEmpty)
            SizedBox(
              width: 30,
              child: Text(
                pl.pos!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

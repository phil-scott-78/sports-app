import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import 'widgets.dart';

/// Scoring timeline — the at-a-glance "how did we get here" story, rendered as a
/// **center spine**: home events read down the left, away down the right, around
/// a vertical rail with a node per play (the design's sport-agnostic timeline).
///
/// Plays are grouped by period (a centered chip per transition). Each node is the
/// sport's glyph in a gold ring for a score, a danger square for a card, a swap
/// for a substitution. When [nowLabel] is set (a live game) a "LIVE · {clock}"
/// marker leads the rail. Falls back to a compact single rail when no play
/// carries a `side` (so non-sided feeds still read cleanly).
class ScoringFeed extends StatelessWidget {
  final List<SummaryPlay> plays;
  final String? sport;
  final String? nowLabel;
  const ScoringFeed({super.key, required this.plays, this.sport, this.nowLabel});

  @override
  Widget build(BuildContext context) {
    if (plays.isEmpty) return const SizedBox.shrink();
    final hasSides = plays.any((p) => p.side == 'home' || p.side == 'away');
    return DetailPanel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: hasSides ? _spine(context) : _singleRail(context),
    );
  }

  // ---- center spine -------------------------------------------------------
  Widget _spine(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = <Widget>[];

    if (nowLabel != null && nowLabel!.isNotEmpty) rows.add(_nowMarker(context));

    int? lastPeriod;
    var first = true;
    for (final p in plays) {
      if (p.period != lastPeriod) {
        lastPeriod = p.period;
        final label = (p.periodLabel != null && p.periodLabel!.isNotEmpty)
            ? p.periodLabel!
            : 'Period ${p.period ?? ''}'.trim();
        if (label.isNotEmpty) rows.add(_periodChip(context, label, top: first ? 2 : 10));
      }
      rows.add(_event(context, p));
      first = false;
    }

    return Stack(
      children: [
        // The spine itself, behind the rows; nodes/chips cut it with the card fill.
        Positioned(
          top: 0,
          bottom: 0,
          left: 0,
          right: 0,
          child: Center(
            child: Container(width: 2, color: cs.surfaceContainerHighest),
          ),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
      ],
    );
  }

  Widget _periodChip(BuildContext context, String label, {required double top}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: 6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _nowMarker(BuildContext context) {
    final live = BinanceColors.of(context).live;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          decoration: BoxDecoration(
            color: live.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            LiveDot(color: live),
            const SizedBox(width: 6),
            Text('LIVE · $nowLabel',
                style: TextStyle(
                    fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: live)),
          ]),
        ),
      ),
    );
  }

  Widget _event(BuildContext context, SummaryPlay p) {
    final isHome = p.side == 'home';
    final content = _sideContent(context, p, isHome);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: isHome ? content : const SizedBox.shrink()),
          SizedBox(width: 46, child: _node(context, p)),
          Expanded(child: !isHome ? content : const SizedBox.shrink()),
        ],
      ),
    );
  }

  Widget _sideContent(BuildContext context, SummaryPlay p, bool isHome) {
    final cs = Theme.of(context).colorScheme;
    final kind = _kind(p);
    // The team tag stays neutral — gold is reserved for the score node ring, and
    // the spine side (home left / away right) already tells the teams apart. A
    // disciplinary card is the one tag that earns colour (red). Without this,
    // baseball — where *every* play is a score — painted both teams gold.
    final tagColor = kind == _Kind.card ? BinanceColors.of(context).danger : cs.onSurfaceVariant;
    final align = isHome ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final ta = isHome ? TextAlign.right : TextAlign.left;
    final hasScore = p.away != null && p.home != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(isHome ? 0 : 6, 0, isHome ? 6 : 0, 0),
      child: Column(
        crossAxisAlignment: align,
        children: [
          if ((p.teamAbbr ?? '').isNotEmpty)
            Text(p.teamAbbr!,
                style: TextStyle(
                    fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.3, color: tagColor)),
          const SizedBox(height: 2),
          Text(p.text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: ta,
              style: TextStyle(fontSize: 12.5, height: 1.35, color: cs.onSurface)),
          if (hasScore) ...[
            const SizedBox(height: 2),
            Text('${p.away}–${p.home}',
                style: numStyle(size: 11, weight: FontWeight.w800, color: cs.onSurface)),
          ],
        ],
      ),
    );
  }

  Widget _node(BuildContext context, SummaryPlay p) {
    final cs = Theme.of(context).colorScheme;
    final ext = BinanceColors.of(context);
    final kind = _kind(p);
    final Color ring = switch (kind) {
      _Kind.score => ext.victor,
      _Kind.card => ext.danger,
      _ => cs.outline,
    };
    final IconData icon = switch (kind) {
      _Kind.score => sportIcon(sport ?? ''),
      _Kind.sub => Icons.swap_horiz,
      _Kind.card => Icons.square,
    };
    final Color iconColor = switch (kind) {
      _Kind.score => ext.victor,
      _Kind.card => ext.danger,
      _ => cs.onSurfaceVariant,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if ((p.clock ?? '').isNotEmpty)
          Container(
            color: cs.surfaceContainerLow,
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Text(p.clock!,
                maxLines: 1,
                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
          ),
        const SizedBox(height: 2),
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            shape: BoxShape.circle,
            border: Border.all(color: ring, width: 2),
          ),
          child: Icon(icon, size: kind == _Kind.card ? 11 : 15, color: iconColor),
        ),
      ],
    );
  }

  _Kind _kind(SummaryPlay p) {
    final t = (p.type ?? '').toLowerCase();
    if (t.contains('card') || t.contains('yellow') || t.contains('red') || t.contains('penalty card')) {
      return _Kind.card;
    }
    if (t.contains('sub')) return _Kind.sub;
    // The scoring feed is scoring plays — default to a score node (the gold ring).
    return _Kind.score;
  }

  // ---- single-rail fallback (no sides) -----------------------------------
  Widget _singleRail(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final children = <Widget>[];
    if (nowLabel != null && nowLabel!.isNotEmpty) children.add(_nowMarker(context));
    int? lastPeriod;
    var firstGroup = nowLabel == null || nowLabel!.isEmpty;
    for (final p in plays) {
      if (p.period != lastPeriod) {
        lastPeriod = p.period;
        final label = (p.periodLabel != null && p.periodLabel!.isNotEmpty)
            ? p.periodLabel!
            : 'Period ${p.period ?? ''}'.trim();
        children.add(Padding(
          padding: EdgeInsets.only(top: firstGroup ? 0 : 12, bottom: 4),
          child: Text(label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
        ));
        firstGroup = false;
      }
      children.add(_railRow(context, p));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  Widget _railRow(BuildContext context, SummaryPlay p) {
    final cs = Theme.of(context).colorScheme;
    final hasScore = p.away != null && p.home != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Text(p.clock ?? '',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: numStyle(size: 12, color: cs.onSurfaceVariant)),
          ),
          SizedBox(
            width: 34,
            child: Text(p.teamAbbr ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: cs.onSurface)),
          ),
          Expanded(
            child: Text(p.text,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: cs.onSurface)),
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

enum _Kind { score, card, sub }

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

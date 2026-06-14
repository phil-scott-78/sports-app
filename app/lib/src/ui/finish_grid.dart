import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import 'widgets.dart';

/// Auto-racing finishing-order grid for a multi-session event (practices,
/// qualifying, race). A chip row up top switches sessions; the grid below
/// lists the field in finishing order — POS / DRIVER / CONSTRUCTOR / STATUS.
///
/// Graceful degradation: the CONSTRUCTOR column is dropped entirely when no
/// competitor in the session carries any manufacturer/team text.
class FinishGrid extends StatefulWidget {
  final List<Competition> sessions;
  const FinishGrid({super.key, required this.sessions});

  @override
  State<FinishGrid> createState() => _FinishGridState();
}

class _FinishGridState extends State<FinishGrid> {
  late int _selected;

  @override
  void initState() {
    super.initState();
    _selected = _defaultIndex(widget.sessions);
  }

  @override
  void didUpdateWidget(FinishGrid old) {
    super.didUpdateWidget(old);
    // Keep the selection valid if the session list shrinks underneath us.
    if (_selected >= widget.sessions.length) {
      _selected = _defaultIndex(widget.sessions);
    }
  }

  // Prefer the race, else the last session (qualifying/practice fall-through).
  static int _defaultIndex(List<Competition> sessions) {
    for (var i = 0; i < sessions.length; i++) {
      final label = sessions[i].label;
      if (label != null && label.toLowerCase().contains('race')) return i;
    }
    return sessions.isEmpty ? 0 : sessions.length - 1;
  }

  String _sessionLabel(int i) {
    final label = widget.sessions[i].label;
    return (label != null && label.isNotEmpty) ? label : 'Session ${i + 1}';
  }

  @override
  Widget build(BuildContext context) {
    final sessions = widget.sessions;
    if (sessions.isEmpty) return const SizedBox.shrink();
    final index = _selected.clamp(0, sessions.length - 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < sessions.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(_sessionLabel(i)),
                    selected: i == index,
                    onSelected: (_) => setState(() => _selected = i),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Grid(comp: sessions[index]),
      ],
    );
  }
}

/// The finishing-order table for a single session.
class _Grid extends StatelessWidget {
  final Competition comp;
  const _Grid({required this.comp});

  static String _constructor(Competitor c) {
    final v = c.vehicle;
    if (v == null) return '';
    return v.manufacturer ?? v.team ?? '';
  }

  static String _status(Competitor c, Competition comp) {
    final s = c.score?.display;
    if (s != null && s.isNotEmpty) return s;
    final short = comp.status.shortDetail;
    if (short != null && short.isNotEmpty) return short;
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = BinanceColors.of(context).accent;

    // Finishing order: ascending, nulls last. Cap the field for safety.
    final rows = [...comp.competitors]
      ..sort((a, b) {
        final ao = a.order, bo = b.order;
        if (ao == null && bo == null) return 0;
        if (ao == null) return 1;
        if (bo == null) return -1;
        return ao.compareTo(bo);
      });
    final field = rows.take(120).toList();
    final hasConstructor = field.any((c) => _constructor(c).isNotEmpty);

    Widget headCell(String text,
            {double? width, bool expand = false, TextAlign align = TextAlign.left}) {
      final label = Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: align,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
      );
      if (expand) return Expanded(child: label);
      return SizedBox(width: width, child: label);
    }

    Widget dataRow(Competitor c) {
      final isWinner = c.order == 1 || c.winner == true;
      final pos = c.order?.toString() ?? '-';
      final name = c.displayName;
      final constructor = _constructor(c);
      final status = _status(c, comp);

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            // POS — frozen left, bold for the winner.
            SizedBox(
              width: 30,
              child: Text(
                pos,
                maxLines: 1,
                style: numStyle(
                  size: 14,
                  weight: c.order == 1 ? FontWeight.w800 : FontWeight.w500,
                  color: cs.onSurface,
                ),
              ),
            ),
            // DRIVER — fills remaining space, podium accent for the winner.
            Expanded(
              child: Row(
                children: [
                  if (isWinner) ...[
                    Icon(Icons.emoji_events, size: 14, color: accent),
                    const SizedBox(width: 5),
                  ],
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isWinner ? FontWeight.w700 : FontWeight.w500,
                        color: isWinner ? accent : cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // CONSTRUCTOR — muted, omitted entirely when the field has none.
            if (hasConstructor)
              SizedBox(
                width: 90,
                child: Text(
                  constructor,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
              ),
            // STATUS — muted, right-aligned gap/time/state.
            SizedBox(
              width: 64,
              child: Text(
                status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: numStyle(size: 13, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }

    return DetailPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Column labels.
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              children: [
                headCell('POS', width: 30),
                headCell('DRIVER', expand: true),
                if (hasConstructor) headCell('CONSTRUCTOR', width: 90),
                headCell('STATUS', width: 64, align: TextAlign.right),
              ],
            ),
          ),
          Divider(height: 12, color: cs.outlineVariant.withValues(alpha: 0.4)),
          for (final c in field) dataRow(c),
        ],
      ),
    );
  }
}

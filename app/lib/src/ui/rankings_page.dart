import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import 'widgets.dart';

/// The college Top-25 for a league-detail page (AP / Coaches / CFP). A read-only,
/// fixed-length list — distinct from the inline per-team rank on game rows. One
/// poll at a time (AP default); a chip row switches polls when there's more than
/// one. Lazy + long-TTL via [rankingsProvider]; empty polls render nothing.
class RankingsView extends ConsumerStatefulWidget {
  final String league;
  const RankingsView({super.key, required this.league});
  @override
  ConsumerState<RankingsView> createState() => _RankingsViewState();
}

class _RankingsViewState extends ConsumerState<RankingsView> {
  int _poll = 0;

  @override
  Widget build(BuildContext context) {
    return ref.watch(rankingsProvider(widget.league)).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            const SizedBox(height: 80),
            ErrorView(
                message: '$e',
                onRetry: () => ref.invalidate(rankingsProvider(widget.league))),
          ]),
          data: (r) {
            if (r.polls.isEmpty) {
              return const EmptyState(
                icon: Icons.format_list_numbered,
                title: 'No rankings',
                subtitle: 'Polls appear during the season.',
              );
            }
            final idx = _poll.clamp(0, r.polls.length - 1);
            final poll = r.polls[idx];
            return RefreshIndicator(
              onRefresh: () =>
                  ref.refresh(rankingsProvider(widget.league).future),
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: poll.ranks.length + 1,
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return _Head(
                      polls: r.polls,
                      selected: idx,
                      onSelect: (p) => setState(() => _poll = p),
                    );
                  }
                  return _RankRow(entry: poll.ranks[i - 1]);
                },
              ),
            );
          },
        );
  }
}

class _Head extends StatelessWidget {
  final List<Poll> polls;
  final int selected;
  final ValueChanged<int> onSelect;
  const _Head(
      {required this.polls, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final occ = polls[selected].occurrence;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (polls.length > 1)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                for (var i = 0; i < polls.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(polls[i].shortName),
                      selected: i == selected,
                      onSelected: (_) => onSelect(i),
                    ),
                  ),
              ],
            ),
          ),
        if (occ != null && occ.isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(16, polls.length > 1 ? 4 : 14, 16, 6),
            child: Text(occ,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant)),
          ),
      ],
    );
  }
}

class _RankRow extends StatelessWidget {
  final RankEntry entry;
  const _RankRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ext = BinanceColors.of(context);
    final t = entry.team;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              entry.current?.toString() ?? '–',
              textAlign: TextAlign.center,
              style: numStyle(size: 16, weight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 8),
          Crest(url: t.logo, darkUrl: t.logoDark, fallback: t.abbr ?? t.name, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Text(t.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          if (entry.record != null) ...[
            Text(entry.record!,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            const SizedBox(width: 10),
          ],
          _Trend(entry: entry, up: ext.victor),
        ],
      ),
    );
  }
}

/// The pre-rendered ESPN trend ('+8' / '-2' / '-') as a small arrow + delta.
class _Trend extends StatelessWidget {
  final RankEntry entry;
  final Color up;
  const _Trend({required this.entry, required this.up});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dir = entry.trendDir;
    if (dir == 'flat') {
      return SizedBox(
          width: 34,
          child: Text('—',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)));
    }
    final isUp = dir == 'up';
    final col = isUp ? up : cs.error;
    return SizedBox(
      width: 34,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Icon(isUp ? Icons.arrow_drop_up : Icons.arrow_drop_down,
              size: 18, color: col),
          Text(entry.trend!.replaceAll(RegExp(r'[+\-]'), ''),
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: col)),
        ],
      ),
    );
  }
}

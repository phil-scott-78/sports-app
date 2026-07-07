import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import '../util.dart';
import 'explore_page.dart';
import 'hero_card.dart';
import 'league_card.dart';
import 'league_page.dart';
import 'poll.dart';
import 'settings_page.dart';
import 'widgets.dart';

/// The home feed: TODAY header, stacked favorite hero cards, then one dense
/// section per followed league.
class ScoresPage extends ConsumerStatefulWidget {
  const ScoresPage({super.key});
  @override
  ConsumerState<ScoresPage> createState() => _ScoresPageState();
}

class _ScoresPageState extends ConsumerState<ScoresPage> with LifecyclePoll {
  @override
  void initState() {
    super.initState();
    attachPoll();
    WidgetsBinding.instance.addPostFrameCallback((_) => repace());
  }

  @override
  void dispose() {
    detachPoll();
    super.dispose();
  }

  /// Whether the date strip is popped down.
  bool _showStrip = false;

  @override
  Duration? pollInterval() {
    if (ref.read(tabIndexProvider) != 0) return null;
    // A picked past/future day is a static slate — don't poll it. (Pull-to-refresh
    // still works for a manual refresh.)
    if (ref.read(homeDateProvider) != null) return null;
    final feeds = ref.read(feedProvider).valueOrNull;
    final favs = ref.read(favoritesFeedProvider).valueOrNull;
    final anyLive = (feeds ?? []).any((f) => f.scores?.anyLive == true) ||
        (favs ?? []).any((f) => f.card?.anyLive == true);
    if (anyLive) return AppConfig.refreshLive;
    final soon = (feeds ?? [])
        .any((f) => kickoffSoonMs(f.scores?.nextStartMs));
    if (soon) return AppConfig.refreshNearKickoff;
    return AppConfig.refreshIdle;
  }

  @override
  void onPoll() {
    ref.invalidate(feedProvider);
    ref.invalidate(favoritesFeedProvider);
  }

  @override
  void onForeground() => onPoll();

  @override
  Widget build(BuildContext context) {
    // Re-pace whenever the data (live state), active tab, or picked day changes.
    ref.listen(feedProvider, (_, __) => repace());
    ref.listen(tabIndexProvider, (_, __) => repace());
    ref.listen(homeDateProvider, (_, __) => repace());

    final date = ref.watch(homeDateProvider);
    final dated = date != null;
    final feeds = ref.watch(feedProvider);
    final favs = ref.watch(favoritesFeedProvider);

    return RefreshIndicator(
      color: T.gold,
      backgroundColor: T.surface,
      onRefresh: () async {
        onPoll();
        await ref.read(feedProvider.future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: T.scrollBottom),
        children: [
          _DateHeader(
            date: date,
            expanded: _showStrip,
            onToggle: () => setState(() => _showStrip = !_showStrip),
            onPick: (d) {
              ref.read(homeDateProvider.notifier).state = d;
              setState(() => _showStrip = false);
            },
          ),
          // The favorite hero cards are now-anchored (live/last/next), so they'd
          // be misleading on a past/future slate — hide them when a day is picked.
          if (!dated)
            ...switch (favs) {
              AsyncData(:final value) => [
                  for (final f in value)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                          T.pageMargin, T.gapCard, T.pageMargin, 0),
                      child: FavoriteHeroCard(f),
                    ),
                ],
              _ => const <Widget>[],
            },
          ...switch (feeds) {
            AsyncData(:final value) => _leagueSections(value, date),
            AsyncError(:final error) => [_feedError('$error')],
            _ => [
                if (feeds.valueOrNull == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 120),
                    child: Center(
                        child: CircularProgressIndicator(color: T.gold)),
                  ),
              ],
          },
        ],
      ),
    );
  }

  List<Widget> _leagueSections(List<LeagueFeed> feeds, String? date) {
    final out = <Widget>[];
    for (final f in feeds) {
      final scores = f.scores;
      if (scores == null) {
        out.add(_leagueErrorSection(f));
        continue;
      }
      if (scores.events.isEmpty) continue;
      out.add(_SectionHeader(league: f.key, scores: scores));
      out.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: T.pageMargin),
        child: LeagueEventsCard(league: f.key, scores: scores, date: date),
      ));
    }
    if (out.isEmpty) {
      out.add(Padding(
        padding: const EdgeInsets.fromLTRB(T.pageMargin, 22, T.pageMargin, 0),
        child: HintCard(date != null
            ? 'No games on this day in your leagues.'
            : 'No games today in your leagues.\nManage what you follow in the Following tab.'),
      ));
    }
    return out;
  }

  Widget _leagueErrorSection(LeagueFeed f) => Padding(
        padding: const EdgeInsets.fromLTRB(T.pageMargin, 22, T.pageMargin, 0),
        child: V2Card(
          radius: T.rowCardRadius,
          padding: const EdgeInsets.all(14),
          child: Text('${f.key} — couldn’t load',
              style: T.caption.copyWith(color: T.textFaint)),
        ),
      );

  Widget _feedError(String message) => Padding(
        padding: const EdgeInsets.fromLTRB(T.pageMargin, 22, T.pageMargin, 0),
        child: HintCard(message),
      );
}

/// The home header: a tappable date title ('TODAY' / 'YESTERDAY' / a weekday)
/// that pops down a horizontal date strip, a gold "BACK TO TODAY" pill when a
/// non-today day is showing, and the Explore + Settings buttons.
class _DateHeader extends StatelessWidget {
  final String? date; // null = today
  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<String?> onPick;
  const _DateHeader({
    required this.date,
    required this.expanded,
    required this.onToggle,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final selected = parseYmd(date) ?? DateTime.now();
    final isToday = date == null;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(T.pageMargin, 14, T.pageMargin, 0),
        child: Row(children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggle,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(dayTitle(selected),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: T.pageTitle),
                      ),
                      const SizedBox(width: 6),
                      AnimatedRotation(
                        turns: expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(Icons.keyboard_arrow_down_rounded,
                            size: 22, color: T.textDim),
                      ),
                    ]),
                    const SizedBox(height: 3),
                    Text(todayLabel(selected), style: T.caption),
                  ]),
            ),
          ),
          if (!isToday) ...[
            _BackToTodayPill(onTap: () => onPick(null)),
            const SizedBox(width: 10),
          ],
          _CircleButton(
            icon: Icons.search_rounded,
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ExplorePage())),
          ),
          const SizedBox(width: 10),
          _CircleButton(
            icon: Icons.settings_outlined,
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsPage())),
          ),
        ]),
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: expanded
            ? _DateStrip(selected: selected, onPick: onPick)
            : const SizedBox(width: double.infinity),
      ),
    ]);
  }
}

/// The gold pill that snaps the feed back to today.
class _BackToTodayPill extends StatelessWidget {
  final VoidCallback onTap;
  const _BackToTodayPill({required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: T.gold.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(100),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.today_rounded, size: 13, color: T.gold),
            SizedBox(width: 5),
            Text('BACK TO TODAY',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: T.gold)),
          ]),
        ),
      );
}

/// Horizontal day chips (~2 weeks back … 1 week ahead). The selected chip is
/// inverted (light on dark) like [ChipNav]; today carries a gold ring. Scrolls
/// to the selection on open.
class _DateStrip extends StatefulWidget {
  final DateTime selected;
  final ValueChanged<String?> onPick;
  const _DateStrip({required this.selected, required this.onPick});

  @override
  State<_DateStrip> createState() => _DateStripState();
}

class _DateStripState extends State<_DateStrip> {
  static const _back = 14, _ahead = 7;
  static const _itemW = 52.0, _gap = 8.0;
  late final List<DateTime> _days;
  late final ScrollController _ctrl;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final base = DateTime(now.year, now.month, now.day);
    _days = [for (var i = -_back; i <= _ahead; i++) base.add(Duration(days: i))];
    final sel = _days.indexWhere((d) => sameDay(d, widget.selected));
    // Land the selection roughly one-third from the left.
    final offset = sel < 0 ? 0.0 : (sel * (_itemW + _gap) - 120).clamp(0.0, 4000.0);
    _ctrl = ScrollController(initialScrollOffset: offset);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return SizedBox(
      height: 76,
      child: ListView.separated(
        controller: _ctrl,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(T.pageMargin, 14, T.pageMargin, 10),
        itemCount: _days.length,
        separatorBuilder: (_, __) => const SizedBox(width: _gap),
        itemBuilder: (_, i) {
          final d = _days[i];
          final isToday = sameDay(d, now);
          return _DayChip(
            key: ValueKey('daychip-${ymd(d)}'),
            day: d,
            width: _itemW,
            selected: sameDay(d, widget.selected),
            isToday: isToday,
            // today picks null (parameterless URL → shared hot cache).
            onTap: () => widget.onPick(isToday ? null : ymd(d)),
          );
        },
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  final DateTime day;
  final double width;
  final bool selected, isToday;
  final VoidCallback onTap;
  const _DayChip({
    super.key,
    required this.day,
    required this.width,
    required this.selected,
    required this.isToday,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: width,
          decoration: BoxDecoration(
            color: selected ? T.invertedBg : T.surface,
            borderRadius: BorderRadius.circular(14),
            border: isToday && !selected
                ? Border.all(color: T.gold, width: 1.5)
                : null,
          ),
          alignment: Alignment.center,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(weekdayAbbrev(day),
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: selected ? T.invertedLabel : T.textFaint)),
            const SizedBox(height: 4),
            Text('${day.day}',
                style: TextStyle(
                    fontFamily: 'BarlowCondensed',
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    height: 1.0,
                    color: selected ? T.invertedText : T.text)),
          ]),
        ),
      );
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration:
              const BoxDecoration(color: T.surface, shape: BoxShape.circle),
          child: Icon(icon, size: 18, color: T.textDim),
        ),
      );
}

class _SectionHeader extends StatelessWidget {
  final String league;
  final ScoresResponse scores;
  const _SectionHeader({required this.league, required this.scores});

  @override
  Widget build(BuildContext context) {
    var title = scores.leagueName.toUpperCase();
    // Tack the round onto tournament headers ('WORLD CUP · ROUND OF 16').
    final rounds = scores.events
        .map((e) => e.main?.meta?.round)
        .whereType<String>()
        .toSet();
    if (rounds.length == 1) title = '$title · ${rounds.first.toUpperCase()}';
    return InkWell(
      // The header taps through to the full league page.
      onTap: () =>
          openLeaguePage(context, league, name: scores.leagueName),
      child: Padding(
        padding: T.sectionHeaderPad,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.sectionTitle),
            ),
            Text(
                '${scores.events.length} game${scores.events.length == 1 ? '' : 's'}',
                style: T.captionFaint),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded,
                size: 16, color: T.textFaint),
          ],
        ),
      ),
    );
  }
}


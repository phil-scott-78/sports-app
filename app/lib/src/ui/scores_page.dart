import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
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
import 'today_page.dart';
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
    final feeds = ref.read(mergedFeedProvider).valueOrNull;
    final favs = ref.read(favoritesFeedProvider).valueOrNull;
    final bigs = ref.read(bigGamesProvider).valueOrNull;
    // Liveness that only the poll can refresh: favorite hero cards (teamCard)
    // and BIG GAMES rows are never push-fed.
    final pollOnlyLive = (favs ?? []).any((f) => f.card?.anyLive == true) ||
        (bigs ?? []).any((b) => b.event.main?.status.live == true);
    final liveLeagues = [
      for (final f in feeds ?? const <LeagueFeed>[])
        if (f.scores?.anyLive == true) f.key
    ];
    if (pollOnlyLive || liveLeagues.isNotEmpty) {
      // Demote to the slow reconciliation cadence when EVERY live league is
      // push-fed and healthy — the scores flip via FastCast, the poll is only
      // the safety net. Any push gap snaps back to the fast poll.
      final demoted = !pollOnlyLive &&
          liveLeagues.every((k) {
            final s = ref.read(liveSlateProvider(k));
            return s.hasValue && !s.hasError;
          });
      return demoted ? AppConfig.refreshReconcile : AppConfig.refreshLive;
    }
    final soon = (feeds ?? [])
        .any((f) => kickoffSoonMs(f.scores?.nextStartMs));
    if (soon) return AppConfig.refreshNearKickoff;
    return AppConfig.refreshIdle;
  }

  @override
  void onPoll() {
    ref.invalidate(feedProvider);
    ref.invalidate(favoritesFeedProvider);
    // Cheap re-scan: the ttl-60 scoreboard cache absorbs most of it.
    ref.invalidate(bigGamesProvider);
  }

  @override
  void onForeground() => onPoll();

  @override
  Widget build(BuildContext context) {
    // Re-pace whenever the data (live state / push health), active tab, or
    // picked day changes. Listening on the MERGED feed covers both poll rounds
    // and push transitions; repace keeps the running timer when the cadence is
    // unchanged, so ~1/s push rebuilds can't starve the reconciliation tick.
    ref.listen(mergedFeedProvider, (_, __) => repace());
    ref.listen(bigGamesProvider, (_, __) => repace());
    ref.listen(tabIndexProvider, (_, __) => repace());
    ref.listen(homeDateProvider, (_, __) => repace());

    final date = ref.watch(homeDateProvider);
    final dated = date != null;
    final feeds = ref.watch(mergedFeedProvider);
    final favs = ref.watch(favoritesFeedProvider);
    final fresh = ref.watch(feedFreshnessProvider);

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
          // The dim "Updated …" line — shown ONLY when a poll failed and the
          // slate is being served from cache (stale-while-revalidate), never
          // during normal operation.
          if (fresh.stale) _StaleLine(lastUpdated: fresh.lastUpdated),
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
          // Today's marquee games from flagship leagues you DON'T follow —
          // absent on an ordinary day, and now-anchored like the hero cards,
          // so hidden on a picked past/future day.
          if (!dated) ..._bigGamesSection(),
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
          // The one way from the home feed to EVERYTHING on today (followed or
          // not). Today-only, and only once the feed itself has painted.
          if (!dated && feeds.valueOrNull != null) _AllGamesRow(),
        ],
      ),
    );
  }

  /// The BIG GAMES section: today's marquee games (playoffs, finals, ranked
  /// matchups — see marquee.dart) from flagship leagues you don't follow, as
  /// one dense card of cross-league rows, each tagged with its league/stakes.
  /// Renders nothing on an ordinary day, while loading, and on failure — the
  /// section earns its place or doesn't exist.
  List<Widget> _bigGamesSection() {
    final bigs = ref.watch(bigGamesProvider).valueOrNull ?? const [];
    if (bigs.isEmpty) return const [];
    return [
      const Padding(
        padding: T.sectionHeaderPad,
        child: Text('BIG GAMES', style: T.sectionTitle),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: T.pageMargin),
        child: Container(
          decoration: BoxDecoration(
            color: T.surface,
            borderRadius: BorderRadius.circular(T.rowCardRadius),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (var i = 0; i < bigs.length; i++)
              LeagueEventRow(
                league: bigs[i].league,
                event: bigs[i].event,
                divider: i > 0,
                tagLine: bigs[i].tagLine,
              ),
          ]),
        ),
      ),
    ];
  }

  /// The followed-league sections. An empty slate is a VALID offseason/no-games
  /// state, not an error: the section header stays (with a terse "No games"), so
  /// the feed never silently drops a league you follow. When the whole day is
  /// empty, an [_EmptyDayHint] offers the nearest day with games.
  List<Widget> _leagueSections(List<LeagueFeed> feeds, String? date) {
    final out = <Widget>[];
    for (final f in feeds) {
      final scores = f.scores;
      if (scores == null) {
        out.add(_leagueErrorSection(f));
        continue;
      }
      // Header always renders (empty leagues keep their place; the header shows
      // "No games" instead of "See all N").
      out.add(_SectionHeader(league: f.key, scores: scores));
      if (scores.events.isNotEmpty) {
        out.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: T.pageMargin),
          child: LeagueEventsCard(league: f.key, scores: scores, date: date),
        ));
      }
    }
    final anyGames = feeds.any((f) => f.scores?.events.isNotEmpty ?? false);
    final anyError = feeds.any((f) => f.scores == null);
    // A wholly empty day (no games, nothing errored) gets the nearest-day hint.
    if (!anyGames && !anyError) out.add(_EmptyDayHint(date: date));
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

/// The quiet foot-of-feed row into [TodayPage] — every league on today,
/// followed or not. A plain surface row (not gold/dashed: it's a standing
/// destination, not a "nothing here" hint).
class _AllGamesRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(T.pageMargin, 22, T.pageMargin, 0),
        child: InkWell(
          borderRadius: BorderRadius.circular(T.rowCardRadius),
          onTap: () => openTodayPage(context),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: T.surface,
              borderRadius: BorderRadius.circular(T.rowCardRadius),
            ),
            child: const Row(children: [
              Expanded(child: Text('All games today', style: T.rowText)),
              Icon(Icons.chevron_right_rounded, size: 16, color: T.textFaint),
            ]),
          ),
        ),
      );
}

/// The dim "Updated 5:04 PM" line under the header — the stale/offline marker.
/// Rendered only when the feed is being served from cache after a failed poll.
class _StaleLine extends StatelessWidget {
  final DateTime? lastUpdated;
  const _StaleLine({required this.lastUpdated});

  @override
  Widget build(BuildContext context) {
    final when =
        lastUpdated == null ? '' : ' · Updated ${DateFormat.jm().format(lastUpdated!)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(T.pageMargin, 8, T.pageMargin, 0),
      child: Row(children: [
        const Icon(Icons.cloud_off_rounded, size: 13, color: T.textFaint),
        const SizedBox(width: 6),
        Text('Offline$when', style: T.captionFaint),
      ]),
    );
  }
}

/// The whole-day-empty footer. When the coverage scan (or the cheap
/// `calendarDays` hint) knows a nearby day with games it offers a tappable
/// "Next games <weekday>" that moves the date strip to that day; otherwise the
/// calm generic copy.
class _EmptyDayHint extends ConsumerWidget {
  final String? date;
  const _EmptyDayHint({required this.date});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = <String>{...?ref.watch(homeCoverageProvider).valueOrNull};
    for (final f in ref.watch(feedProvider).valueOrNull ?? const <LeagueFeed>[]) {
      days.addAll(f.scores?.calendarDays ?? const []);
    }
    final from = parseYmd(date) ?? DateTime.now();
    final nearest = _nearestGameDay(days, from);
    if (nearest != null) {
      final d = parseYmd(nearest)!;
      final f0 = DateTime(from.year, from.month, from.day);
      final future = !DateTime(d.year, d.month, d.day).isBefore(f0);
      final label =
          '${future ? 'Next games' : 'Last games'} ${DateFormat.E().format(d)}';
      return Padding(
        padding: const EdgeInsets.fromLTRB(T.pageMargin, 22, T.pageMargin, 0),
        child: _NextGamesHint(
          label: label,
          onTap: () => ref.read(homeDateProvider.notifier).state = nearest,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(T.pageMargin, 22, T.pageMargin, 0),
      child: HintCard(date != null
          ? 'No games on this day in your leagues.'
          : 'No games today in your leagues.\nManage what you follow in the Following tab.'),
    );
  }
}

/// The nearest 'YYYYMMDD' in [days] other than [from], preferring the soonest
/// future day, else the most-recent past day. Null when [days] is empty.
String? _nearestGameDay(Set<String> days, DateTime from) {
  final f0 = DateTime(from.year, from.month, from.day);
  DateTime? best;
  var bestRank = 1 << 30;
  for (final s in days) {
    final d = parseYmd(s);
    if (d == null) continue;
    final delta = DateTime(d.year, d.month, d.day).difference(f0).inDays;
    if (delta == 0) continue;
    // Future days rank 1..; past days rank higher (further = larger), so any
    // future day beats any past day and the nearest within each side wins.
    final rank = delta > 0 ? delta : 1000 - delta;
    if (rank < bestRank) {
      bestRank = rank;
      best = d;
    }
  }
  return best == null ? null : ymd(best);
}

/// The tappable "Next games <weekday>" pill — gold to read as an action, dashed
/// to read as "nothing here yet, go there".
class _NextGamesHint extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _NextGamesHint({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: DashedBox(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: T.gold)),
              const SizedBox(width: 5),
              const Icon(Icons.chevron_right_rounded, size: 16, color: T.gold),
            ]),
          ),
        ),
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
class _DateStrip extends ConsumerStatefulWidget {
  final DateTime selected;
  final ValueChanged<String?> onPick;
  const _DateStrip({required this.selected, required this.onPick});

  @override
  ConsumerState<_DateStrip> createState() => _DateStripState();
}

class _DateStripState extends ConsumerState<_DateStrip> {
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
    // The authoritative range scan (null while it lands / if it never does).
    final scanned = ref.watch(homeCoverageProvider).valueOrNull;
    // The cheap immediate hint: each followed league's game-day calendar (present
    // for day-type leagues, empty for gridiron/golf/F1). Dots render from this at
    // once, then the scan refines (and is the ONLY thing that can dim a day).
    final hint = <String>{};
    for (final f in ref.watch(feedProvider).valueOrNull ?? const <LeagueFeed>[]) {
      hint.addAll(f.scores?.calendarDays ?? const []);
    }
    // null = unknown (don't dim, don't dot); true = has games; false = empty.
    bool? coverageFor(String key) {
      if (scanned != null) return scanned.contains(key) || hint.contains(key);
      return hint.contains(key) ? true : null;
    }

    return SizedBox(
      height: 84,
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
            hasGames: coverageFor(ymd(d)),
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

  /// Per-day coverage: null = unknown (scan not landed), true = has games,
  /// false = proven empty. Drives the has-games dot + the empty-day dimming.
  final bool? hasGames;
  final VoidCallback onTap;
  const _DayChip({
    super.key,
    required this.day,
    required this.width,
    required this.selected,
    required this.isToday,
    required this.hasGames,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Dim only a PROVEN-empty day; an unknown day stays full so the strip never
    // flashes grey before the scan lands.
    final empty = hasGames == false;
    final numColor = selected
        ? T.invertedText
        : (empty ? T.textFaint : T.text);
    // The has-games dot: gold on today, otherwise a quiet neutral; nothing when
    // empty or unknown (the dimmed number carries "empty").
    final dotColor = hasGames == true
        ? (selected ? T.invertedLabel : (isToday ? T.gold : T.textDim))
        : Colors.transparent;
    return GestureDetector(
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
                  color: numColor)),
          const SizedBox(height: 5),
          // Fixed 5px slot → the dot's presence/absence never reflows the chip.
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
        ]),
      ),
    );
  }
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
    final empty = scores.events.isEmpty;
    var title = scores.leagueName.toUpperCase();
    // Tack the round onto tournament headers ('WORLD CUP · ROUND OF 16').
    final rounds = scores.events
        .map((e) => e.main?.meta?.round)
        .whereType<String>()
        .toSet();
    if (rounds.length == 1) title = '$title · ${rounds.first.toUpperCase()}';
    return InkWell(
      // The header taps through to the full league page (standings/schedule are
      // still worth a look even on an empty day).
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
            // Empty slate → a terse "No games" instead of "See all N"; the header
            // stays so a followed league never silently vanishes.
            if (empty)
              const Text('No games', style: T.captionFaint)
            else ...[
              Text('See all ${scores.events.length}', style: T.captionFaint),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded,
                  size: 16, color: T.textFaint),
            ],
          ],
        ),
      ),
    );
  }
}


import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import 'favorite_team_card.dart';
import 'game_detail_page.dart';
import 'widgets.dart';

class ScoresPage extends ConsumerStatefulWidget {
  const ScoresPage({super.key});
  @override
  ConsumerState<ScoresPage> createState() => _ScoresPageState();
}

class _ScoresPageState extends ConsumerState<ScoresPage> with WidgetsBindingObserver {
  Timer? _timer;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _schedule(AppConfig.refreshIdle);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      // Catch up only when Scores is the visible tab; otherwise the tab-switch
      // listener handles the refetch on return (don't fetch behind other tabs).
      if (ref.read(tabIndexProvider) == 0) _refreshAll();
      _repace();
    } else {
      _timer?.cancel(); // don't poll in the background (battery)
    }
  }

  void _schedule(Duration d) {
    _timer?.cancel();
    _timer = Timer.periodic(d, (_) => _refreshAll());
  }

  /// Refresh both the league feed and the favorites feed — they share the poll
  /// beat and the foreground/tab catch-ups.
  void _refreshAll() {
    ref.invalidate(feedProvider);
    ref.invalidate(favoritesFeedProvider);
  }

  /// Anchor the date strip / Yesterday-Upcoming math to ESPN's reported sports
  /// day, captured from a *Today* feed (only Today's slate carries ESPN's current
  /// `day`; an explicit-date fetch echoes the requested date instead).
  void _captureEspnToday(List<LeagueFeed>? feeds) {
    if (feeds == null || ref.read(dateModeProvider) != ScoreDate.today) return;
    for (final f in feeds) {
      final d = f.scores?.day;
      if (d == null || d.isEmpty) continue;
      final parsed = DateTime.tryParse(d);
      if (parsed == null) continue;
      final dateOnly = DateTime(parsed.year, parsed.month, parsed.day);
      if (ref.read(espnTodayProvider) != dateOnly) {
        ref.read(espnTodayProvider.notifier).state = dateOnly;
      }
      return;
    }
  }

  /// Single source of truth for the poll cadence: only the foregrounded, on-tab,
  /// "Today" slate ticks (live → 15s, else 60s); everything else cancels the
  /// timer. Gating on [_foreground] here is what stops an in-flight fetch that
  /// resolves *after* the app is backgrounded from re-arming a rogue timer.
  void _repace({bool? live}) {
    if (!_foreground ||
        ref.read(tabIndexProvider) != 0 ||
        ref.read(dateModeProvider) != ScoreDate.today) {
      _timer?.cancel();
      return;
    }
    final feedLive = ref.read(feedProvider).valueOrNull?.any((f) => f.scores?.anyLive == true) ?? false;
    final favLive = ref.read(favoritesFeedProvider).valueOrNull?.any((f) => f.card?.anyLive == true) ?? false;
    final isLive = live ?? (feedLive || favLive);
    _schedule(isLive ? AppConfig.refreshLive : AppConfig.refreshIdle);
  }

  @override
  Widget build(BuildContext context) {
    final configured = ref.watch(settingsProvider.select((s) => s.baseUrl)).trim().isNotEmpty;
    // Watched (not just listened) so the app bar re-sizes when Upcoming reveals
    // its date strip and hides it again on the other days.
    final mode = ref.watch(dateModeProvider);

    // Re-pace polling once a fetch settles: fast when anything is live. Skip the
    // intermediate loading emission (it carries the stale previous value and
    // would needlessly re-anchor the timer's countdown on every refresh).
    ref.listen<AsyncValue<List<LeagueFeed>>>(feedProvider, (_, next) {
      if (next.isLoading) return;
      _captureEspnToday(next.valueOrNull);
      _repace(); // re-reads both feed + favorites for the live decision
    });
    ref.listen<AsyncValue<List<FavoriteTeamFeed>>>(favoritesFeedProvider, (_, next) {
      if (next.isLoading) return;
      _repace();
    });

    // Switching day re-paces (the feed refetches on its own, since it watches
    // the mode); only Today keeps a timer running.
    ref.listen<ScoreDate>(dateModeProvider, (_, __) => _repace());

    // Pause polling while the user is on another tab (IndexedStack keeps this
    // page mounted); catch up and resume on return.
    ref.listen<int>(tabIndexProvider, (_, next) {
      if (next == 0) _refreshAll();
      _repace();
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scores'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refreshAll,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: configured ? _DateModeBar(showStrip: mode == ScoreDate.upcoming) : null,
      ),
      body: !configured
          ? const SetupPrompt()
          : RefreshIndicator(
              onRefresh: () => Future.wait([
                ref.refresh(feedProvider.future),
                ref.refresh(favoritesFeedProvider.future),
              ]),
              child: ref.watch(feedProvider).when(
                    loading: () => const _LoadingList(),
                    error: (e, _) => ListView(children: [
                      const SizedBox(height: 120),
                      ErrorView(message: '$e', onRetry: () => ref.invalidate(feedProvider)),
                    ]),
                    data: (feeds) => _FeedList(feeds: feeds),
                  ),
            ),
    );
  }
}

const double _kStripHeight = 58;

/// Yesterday / Today / Upcoming switcher pinned under the app bar. A calm
/// segmented control — the selected day gets a faint pill + bold label rather
/// than the brand yellow, which stays reserved for winner/value moments. When
/// [showStrip] is set (Upcoming is active) a compact date strip is revealed
/// underneath; the bar grows to make room for it.
class _DateModeBar extends ConsumerWidget implements PreferredSizeWidget {
  final bool showStrip;
  const _DateModeBar({required this.showStrip});

  @override
  Size get preferredSize => Size.fromHeight(showStrip ? 46 + _kStripHeight : 46);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(dateModeProvider);
    final cs = Theme.of(context).colorScheme;

    Widget seg(String label, ScoreDate value) {
      final selected = mode == value;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => ref.read(dateModeProvider.notifier).state = value,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
            padding: const EdgeInsets.symmetric(vertical: 7),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? cs.surfaceContainerHighest : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? cs.onSurface : cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: Row(children: [
            seg('Yesterday', ScoreDate.yesterday),
            seg('Today', ScoreDate.today),
            seg('Upcoming', ScoreDate.upcoming),
          ]),
        ),
        if (showStrip) const _UpcomingDateStrip(),
      ],
    );
  }
}

/// A compact, swipeable row of upcoming days revealed under the segmented
/// control when Upcoming is active. Picking a day fetches just that date (rather
/// than a week-long list) — calm and glanceable, à la Apple Sports. The selected
/// day wears the same faint pill the segmented control uses; brand yellow stays
/// reserved for winner/value moments. Days run tomorrow → +[AppConfig.upcomingDays].
class _UpcomingDateStrip extends ConsumerWidget {
  const _UpcomingDateStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offset = ref.watch(upcomingOffsetProvider);
    final now = DateTime.now();
    // Anchor the strip to ESPN's sports day (when known) so "tomorrow" is the day
    // after ESPN's today, not the device's — they diverge in the post-midnight
    // window, which otherwise shoves the whole strip a day forward.
    final today = ref.watch(espnTodayProvider) ?? DateTime(now.year, now.month, now.day);
    return SizedBox(
      height: _kStripHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        itemCount: AppConfig.upcomingDays,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final dayOffset = i + 1; // 1 = tomorrow
          return DateChip(
            date: today.add(Duration(days: dayOffset)),
            selected: dayOffset == offset,
            isToday: false, // the Upcoming strip is future-only (starts tomorrow)
            onTap: () {
              if (dayOffset == ref.read(upcomingOffsetProvider)) return;
              ref.read(upcomingOffsetProvider.notifier).state = dayOffset;
            },
          );
        },
      ),
    );
  }
}

class _LoadingList extends StatelessWidget {
  const _LoadingList();
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator());
}

class _FeedList extends ConsumerWidget {
  final List<LeagueFeed> feeds;
  const _FeedList({required this.feeds});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasFavs = ref.watch(favoriteTeamsProvider).isNotEmpty;

    if (feeds.isEmpty && !hasFavs) {
      return ListView(children: const [
        SizedBox(height: 100),
        EmptyState(
          icon: Icons.star_outline,
          title: 'No leagues followed',
          subtitle: 'Add some from the Leagues tab.',
        ),
      ]);
    }

    final noGames = switch (ref.watch(dateModeProvider)) {
      ScoreDate.yesterday => 'No games yesterday',
      ScoreDate.today => 'No games today',
      ScoreDate.upcoming => 'No upcoming games',
    };

    final children = <Widget>[];

    // Favorites pinned at the top — "my teams now", constant across the date tabs.
    if (hasFavs) {
      children.add(const _SectionHeader(title: 'Favorites'));
      final async = ref.watch(favoritesFeedProvider);
      final favData = async.valueOrNull;
      if (favData == null && async.isLoading) {
        children.add(const _InfoTile(icon: Icons.hourglass_empty, text: 'Loading favorites…'));
      } else if (favData == null && async.hasError) {
        children.add(_InfoTile(icon: Icons.error_outline, text: '${async.error}'));
      } else {
        for (final f in favData ?? const <FavoriteTeamFeed>[]) {
          children.add(Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: FavoriteTeamCard(feed: f),
          ));
        }
      }
    }

    for (final feed in feeds) {
      final name = feed.scores?.leagueName.isNotEmpty == true
          ? feed.scores!.leagueName
          : feed.key;
      children.add(_SectionHeader(title: name));
      if (feed.error != null) {
        children.add(_InfoTile(icon: Icons.error_outline, text: feed.error!));
      } else {
        final events = [...(feed.scores?.events ?? <SportEvent>[])]..sort(_byStatusThenTime);
        if (events.isEmpty) {
          children.add(_InfoTile(icon: Icons.event_busy_outlined, text: noGames));
        } else {
          for (final ev in events) {
            children.add(Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: GameCard(
                event: ev,
                sport: feed.scores!.sport,
                leagueKey: feed.key,
                leagueName: name,
              ),
            ));
          }
        }
      }
    }
    children.add(const SizedBox(height: 12));
    return ListView(physics: const AlwaysScrollableScrollPhysics(), children: children);
  }
}

int _statusRank(SportEvent e) {
  switch (e.main?.status.phase) {
    case 'live':
      return 0;
    case 'scheduled':
      return 1;
    case 'final':
      return 3;
    default:
      return 2;
  }
}

int _byStatusThenTime(SportEvent a, SportEvent b) {
  final r = _statusRank(a) - _statusRank(b);
  if (r != 0) return r;
  final ta = a.start, tb = b.start;
  if (ta != null && tb != null) return ta.compareTo(tb);
  return 0;
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      );
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoTile({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(children: [
        Icon(icon, size: 18, color: cs.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13))),
      ]),
    );
  }
}

// ---- game card --------------------------------------------------------------
class GameCard extends StatelessWidget {
  final SportEvent event;
  final String sport;
  final String leagueKey;
  final String leagueName;
  const GameCard({super.key, required this.event, required this.sport, required this.leagueKey, required this.leagueName});

  @override
  Widget build(BuildContext context) {
    final comp = event.main;
    if (comp == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: BinanceColors.of(context).cardBorder, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      // A subtle winner-color wash on final cards (borrowed from Apple Sports).
      // `Ink` paints the gradient *into* the Material, so the InkWell's tap
      // ripple still renders on top of it (a DecoratedBox child would mute the
      // splash). Null gradient → plain surface for non-final/field/color-less.
      child: Ink(
        decoration: BoxDecoration(gradient: _cardGradient(context, comp)),
        child: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => GameDetailPage(event: event, sport: sport, leagueKey: leagueKey, leagueName: leagueName),
          )),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: comp.isField ? _field(context, comp) : _match(context, comp),
          ),
        ),
      ),
    );
  }

  /// Apple-Sports head-to-head row: each team is a crest with its name in small
  /// print underneath, pinned to the outer edge; the two big scores hug a
  /// centered status/time. One renderer, no per-sport branching — the
  /// discriminators (`scoreKind`, winner flags) decide what each slot reads.
  Widget _match(BuildContext context, Competition comp) {
    final a = comp.home ?? (comp.competitors.isNotEmpty ? comp.competitors[0] : null);
    final b = comp.away ?? (comp.competitors.length > 1 ? comp.competitors[1] : null);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: a == null ? const SizedBox() : _teamBlock(context, comp, a, alignEnd: false)),
        _scoreCluster(context, comp, a, b),
        Expanded(child: b == null ? const SizedBox() : _teamBlock(context, comp, b, alignEnd: true)),
      ],
    );
  }

  /// Outer team column: crest on top, short name in small print under it, record
  /// only on the upcoming slate (Apple shows it just for not-yet-played games).
  /// [alignEnd] mirrors the block for the right-hand team so its crest sits on
  /// the outer edge.
  Widget _teamBlock(BuildContext context, Competition comp, Competitor c, {required bool alignEnd}) {
    final cs = Theme.of(context).colorScheme;
    final dim = comp.status.isFinal && c.winner == false;
    final name = c.shortName?.isNotEmpty == true ? c.shortName! : c.displayName;
    final align = alignEnd ? TextAlign.right : TextAlign.left;
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Crest(url: c.logo, darkUrl: c.logoDark, fallback: c.abbreviation ?? c.displayName, size: 36),
        const SizedBox(height: 6),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: align,
          style: TextStyle(
            fontSize: 13,
            fontWeight: c.isWinner ? FontWeight.w700 : FontWeight.w600,
            color: dim ? cs.onSurfaceVariant : cs.onSurface,
          ),
        ),
        if (c.recordSummary != null && comp.status.isScheduled)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              c.recordSummary!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: align,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ),
      ],
    );
  }

  /// The centre column: big left score · status/time · big right score. The
  /// scores flank a status that stays put so the whole list reads as aligned
  /// columns down the slate.
  Widget _scoreCluster(BuildContext context, Competition comp, Competitor? a, Competitor? b) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (a != null) _score(context, comp, a),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 78),
          child: _centerStatus(context, comp),
        ),
        const SizedBox(width: 8),
        if (b != null) _score(context, comp, b),
      ],
    );
  }

  Widget _score(BuildContext context, Competition comp, Competitor c) {
    final cs = Theme.of(context).colorScheme;
    if (comp.scoreKind == 'none') {
      // MMA and friends: a winner check, never a number.
      return c.isWinner
          ? Icon(Icons.check_circle, size: 22, color: BinanceColors.of(context).accent)
          : const SizedBox(width: 22);
    }
    final s = c.score?.display ?? '';
    if (s.isEmpty) return const SizedBox.shrink(); // scheduled → the time carries the row
    final dim = comp.status.isFinal && c.winner == false;
    return Text(
      s,
      style: numStyle(
        size: 28,
        weight: c.isWinner ? FontWeight.w800 : FontWeight.w700,
        color: dim ? cs.onSurfaceVariant : cs.onSurface,
      ),
    );
  }

  /// Centred status: a live game keeps the brand's pulsing red dot beside a
  /// high-contrast clock; final/scheduled sit muted. OT/PENS/AGG/DRAW tags tuck
  /// underneath.
  Widget _centerStatus(BuildContext context, Competition comp) {
    final cs = Theme.of(context).colorScheme;
    final live = comp.status.live;
    final badge = _decisionBadge(comp);
    final label = Text(
      statusLabel(comp.status, event.start),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 12.5,
        height: 1.15,
        fontWeight: FontWeight.w600,
        color: live ? cs.onSurface : cs.onSurfaceVariant,
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (live)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              LiveDot(color: cs.error),
              const SizedBox(width: 5),
              Flexible(child: label),
            ],
          )
        else
          label,
        if (badge != null) ...[
          const SizedBox(height: 4),
          _Badge(text: badge),
        ],
      ],
    );
  }

  Widget _field(BuildContext context, Competition comp) {
    final cs = Theme.of(context).colorScheme;
    final leader = comp.competitors.isNotEmpty ? comp.competitors.first : null;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(event.shortName.isNotEmpty ? event.shortName : event.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              if (leader != null)
                Text(
                  'Leader: ${leader.displayName}${leader.score?.display.isNotEmpty == true ? '  ${leader.score!.display}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
              Text('${comp.competitors.length} competitors',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        StatusChip(status: comp.status, startTime: event.start),
      ],
    );
  }

  String? _decisionBadge(Competition comp) {
    switch (comp.decision) {
      case 'overtime':
        return comp.status.altDetail ?? 'OT';
      case 'shootout':
        return 'PENS';
      case 'aggregate':
        return 'AGG';
      case 'draw':
        return 'DRAW';
      case 'method':
        return comp.method?.kind;
      default:
        return null;
    }
  }
}

class _Badge extends StatelessWidget {
  final String text;
  const _Badge({required this.text});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Neutral label — OT / PENS / AGG / DRAW are context tags, not brand moments,
    // so they stay muted; yellow is reserved for winner/value emphasis.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
            color: cs.onSurfaceVariant,
          )),
    );
  }
}

// ---- team-color card wash ---------------------------------------------------
/// A very subtle team-color gradient, reserved for **final** head-to-head cards
/// — the "result is in" moment. It washes only from the winning team's side
/// (home tints the top-left, away the bottom-right, matching their crests'
/// positions); a draw with no single winner tints from both corners. Low alpha
/// so it reads as a sheen, not a fill. Returns null for field sports, any
/// non-final game, and when the relevant team(s) expose no usable color (then
/// the card stays the plain Binance surface).
Gradient? _cardGradient(BuildContext context, Competition comp) {
  if (comp.isField || !comp.status.isFinal) return null;
  final a = comp.home ?? (comp.competitors.isNotEmpty ? comp.competitors.first : null);
  final b = comp.away ?? (comp.competitors.length > 1 ? comp.competitors[1] : null);
  final dark = Theme.of(context).brightness == Brightness.dark;
  final alpha = dark ? 0.16 : 0.10;

  final aWins = a?.winner == true;
  final bWins = b?.winner == true;

  // A clear single winner → wash only from that team's corner, fading to the
  // neutral surface across the card.
  if (aWins != bWins) {
    final winner = aWins ? a : b;
    final c = _tintColor(winner?.color, winner?.altColor, dark);
    if (c == null) return null;
    final tint = c.withValues(alpha: alpha);
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: aWins ? [tint, Colors.transparent] : [Colors.transparent, tint],
      stops: aWins ? const [0.0, 0.65] : const [0.35, 1.0],
    );
  }

  // A draw (or no winner flagged) → tint from both corners, neutral centre.
  final ca = _tintColor(a?.color, a?.altColor, dark);
  final cb = _tintColor(b?.color, b?.altColor, dark);
  if (ca == null && cb == null) return null;
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      (ca ?? cb)!.withValues(alpha: alpha),
      Colors.transparent,
      (cb ?? ca)!.withValues(alpha: alpha),
    ],
    stops: const [0.0, 0.5, 1.0],
  );
}

/// Pick a tintable color, preferring the alternate when the primary is too near
/// the canvas to register (a black primary on dark, a white one on light).
Color? _tintColor(String? primary, String? alt, bool dark) {
  final p = _hexColor(primary);
  final a = _hexColor(alt);
  if (p == null) return a;
  if (a != null) {
    final l = p.computeLuminance();
    if (dark && l < 0.04) return a; // near-black vanishes on the dark canvas
    if (!dark && l > 0.96) return a; // near-white vanishes on the light canvas
  }
  return p;
}

/// Parse an ESPN hex color ("1d428a" or "#1d428a"); null if unparseable.
Color? _hexColor(String? hex) {
  if (hex == null) return null;
  var h = hex.replaceFirst('#', '').trim();
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

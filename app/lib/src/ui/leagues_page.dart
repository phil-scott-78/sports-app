import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import 'league_detail_page.dart';
import 'poll.dart';
import 'widgets.dart';

/// Which slice of the (now ~245-league) registry the Leagues tab shows.
enum _Tier { popular, active, all }

extension on _Tier {
  String get label => switch (this) {
        _Tier.popular => 'Default',
        _Tier.active => 'Active',
        _Tier.all => 'All',
      };
}

/// A league state counts as "active" (worth showing in the Active tier) when it's
/// in-season — anything but the dormant offseason / not-yet-loaded.
bool _isActive(String? state) =>
    state != null && state != 'offseason' && state != 'unknown';

class LeaguesPage extends ConsumerStatefulWidget {
  const LeaguesPage({super.key});

  @override
  ConsumerState<LeaguesPage> createState() => _LeaguesPageState();
}

class _LeaguesPageState extends ConsumerState<LeaguesPage> with LifecyclePoll {
  bool _onTop = true; // false while a league detail is pushed over the shell
  _Tier _tier = _Tier.popular; // Default lands

  @override
  void initState() {
    super.initState();
    attachPoll();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) repace();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Depend on the modal scope so this re-paces when a league detail is pushed
    // over / popped off the shell (pollInterval()'s gate alone wouldn't).
    _onTop = ModalRoute.of(context)?.isCurrent ?? true;
    repace();
  }

  @override
  void dispose() {
    detachPoll();
    super.dispose();
  }

  // The season pulse is coarse and server-cached (5m TTL); refresh it on a slow
  // beat while the Leagues tab is the foregrounded, top-of-stack view, and once
  // on return to the tab. No point polling faster than the cache turns over.
  @override
  Duration? pollInterval() {
    if (!mounted || !_onTop) return null; // a league detail is pushed on top
    if (ref.read(tabIndexProvider) != 1) return null; // only when Leagues is active
    if (ref.read(settingsProvider).baseUrl.trim().isEmpty) return null;
    return const Duration(minutes: 5);
  }

  /// Refresh the pulse provider(s) the current tier reads (plus the pinned set).
  void _refreshPulse() {
    ref.invalidate(pinnedOverviewProvider);
    ref.invalidate(
        _tier == _Tier.active ? activeOverviewProvider : popularOverviewProvider);
  }

  @override
  void onPoll() => _refreshPulse();

  @override
  void onForeground() {
    if (ref.read(tabIndexProvider) == 1) _refreshPulse();
  }

  @override
  Widget build(BuildContext context) {
    final configured =
        ref.watch(settingsProvider.select((s) => s.baseUrl)).trim().isNotEmpty;

    // Refresh the pulse when returning to the Leagues tab, and re-pace polling.
    ref.listen<int>(tabIndexProvider, (_, next) {
      if (next == 1) _refreshPulse();
      repace();
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Leagues'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(catalogProvider);
              _refreshPulse();
            },
          ),
        ],
      ),
      body: !configured
          ? const SetupPrompt()
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<_Tier>(
                      segments: [
                        for (final t in _Tier.values)
                          ButtonSegment(value: t, label: Text(t.label)),
                      ],
                      selected: {_tier},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) {
                        setState(() => _tier = s.first);
                        repace();
                      },
                    ),
                  ),
                ),
                Expanded(child: _tierBody()),
              ],
            ),
    );
  }

  Widget _tierBody() {
    // Watch the pulse up-front so it loads in PARALLEL with the catalog (not only
    // after it resolves), and the row dots appear in one settle. `popular`+`pinned`
    // are always watched (cheap, and `all` reuses popular best-effort); `active`'s
    // two-page fetch is watched only on the Active tier so other tiers don't pay it.
    const empty = <String, LeagueStateInfo>{};
    final pinnedStates = ref.watch(pinnedOverviewProvider).valueOrNull ?? empty;
    final popularStates = ref.watch(popularOverviewProvider).valueOrNull ?? empty;

    return ref.watch(catalogProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorView(
              message: '$e', onRetry: () => ref.invalidate(catalogProvider)),
          data: (sports) {
            final pinned = ref.watch(pinnedLeaguesProvider);
            // Active is the one tier that must WAIT for its pulse (it filters by
            // state); Default/All render from the catalog immediately and gain
            // dots as the pulse settles.
            if (_tier == _Tier.active) {
              return ref.watch(activeOverviewProvider).when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => ErrorView(
                        message: '$e',
                        onRetry: () => ref.invalidate(activeOverviewProvider)),
                    data: (m) => _list(sports,
                        pinned: pinned, states: {...m, ...pinnedStates}),
                  );
            }
            return _list(sports,
                pinned: pinned, states: {...popularStates, ...pinnedStates});
          },
        );
  }

  Widget _list(
    List<CatalogSport> sports, {
    required List<String> pinned,
    required Map<String, LeagueStateInfo> states,
  }) {
    final followed = ref.watch(followedProvider);

    final byKey = <String, CatalogLeague>{};
    for (final s in sports) {
      for (final lg in s.leagues) {
        byKey[lg.key] = lg;
      }
    }

    final children = <Widget>[];

    // Pinned section (Default + Active): your followed + favorite-team leagues,
    // pinned to the top and removed from the sport groups below to avoid a dup.
    final pinnedShown =
        _tier == _Tier.all ? const <String>[] : pinned.where(byKey.containsKey).toList();
    final pinnedSet = pinnedShown.toSet();
    if (pinnedShown.isNotEmpty) {
      children.add(const SectionHeader('Pinned'));
      for (final k in pinnedShown) {
        children.add(_tile(byKey[k]!, states[k], followed));
      }
    }

    for (final s in sports) {
      final shown = <CatalogLeague>[];
      for (final lg in s.leagues) {
        if (pinnedSet.contains(lg.key)) continue;
        final include = switch (_tier) {
          _Tier.popular => lg.priority == 'v1',
          _Tier.active => (lg.priority == 'v1' || lg.priority == 'v2') &&
              _isActive(states[lg.key]?.state),
          _Tier.all => true,
        };
        if (include) shown.add(lg);
      }
      if (shown.isEmpty) continue;
      children.add(SectionHeader(sportLabel(s.sport)));
      for (final lg in shown) {
        children.add(_tile(lg, states[lg.key], followed));
      }
    }

    if (children.isEmpty) {
      return EmptyState(
        icon: _tier == _Tier.active
            ? Icons.nightlight_outlined
            : Icons.sports_outlined,
        title: _tier == _Tier.active ? 'Nothing active' : 'No leagues',
        subtitle: _tier == _Tier.active
            ? 'No followed or popular league has games right now.'
            : null,
      );
    }
    children.add(const SizedBox(height: kFloatingNavInset));
    return ListView(children: children);
  }

  Widget _tile(
      CatalogLeague lg, LeagueStateInfo? info, List<String> followed) {
    final isFollowed = followed.contains(lg.key);
    final subtitle = <String>[
      if (lg.region != null && lg.region!.isNotEmpty) lg.region!,
      if (info != null && info.detail.isNotEmpty) info.detail,
    ].join(' · ');
    return ListCard(
      child: ListTile(
        leading: _PulseDot(info?.state),
        title: Text(lg.name),
        subtitle: subtitle.isEmpty ? null : Text(subtitle),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => LeagueDetailPage(league: lg.key, name: lg.name),
        )),
        trailing: IconButton(
          tooltip: isFollowed ? 'Unfollow' : 'Follow',
          icon: Icon(isFollowed ? Icons.star : Icons.star_border,
              color: isFollowed ? BinanceColors.of(context).accent : null),
          onPressed: () => ref.read(followedProvider.notifier).toggle(lg.key),
        ),
      ),
    );
  }
}

/// The at-a-glance season-pulse dot. Colour + fill encode the state; the row's
/// caption ("Live now", "Tomorrow", "Returns Aug 6") carries the words. Live is
/// the one pulsing dot (reusing the live-score indicator); brand yellow is *not*
/// used here — it stays reserved for winner/value moments.
class _PulseDot extends StatelessWidget {
  final String? state;
  const _PulseDot(this.state);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ext = BinanceColors.of(context);
    // Distinct AND legible in both modes: a live red pulse; today a green fill;
    // upcoming a strong neutral fill; recent a muted fill; offseason a muted
    // hollow ring (dormant). `outline`/`outlineVariant` are hairline tokens —
    // near-invisible as a dot on the light canvas — so they're avoided here.
    // Unknown/not-yet-loaded shows no dot (the row reads as before the pulse).
    final Widget dot = switch (state) {
      'live' => LiveDot(color: cs.error),
      'today' => _circle(ext.up, filled: true),
      'upcoming' => _circle(cs.onSurface, filled: true),
      'recent' => _circle(cs.onSurfaceVariant, filled: true),
      'offseason' => _circle(cs.onSurfaceVariant, filled: false),
      _ => const SizedBox.shrink(),
    };
    // Fixed-width gutter so every title aligns regardless of dot style.
    return SizedBox(width: 12, child: Center(child: dot));
  }

  Widget _circle(Color c, {required bool filled}) => Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled ? c : Colors.transparent,
          border: filled ? null : Border.all(color: c, width: 1.5),
        ),
      );
}

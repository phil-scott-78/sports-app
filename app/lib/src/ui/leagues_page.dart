import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../theme.dart';
import 'league_detail_page.dart';
import 'poll.dart';
import 'widgets.dart';

class LeaguesPage extends ConsumerStatefulWidget {
  const LeaguesPage({super.key});

  @override
  ConsumerState<LeaguesPage> createState() => _LeaguesPageState();
}

class _LeaguesPageState extends ConsumerState<LeaguesPage> with LifecyclePoll {
  bool _onTop = true; // false while a league detail is pushed over the shell

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

  @override
  void onPoll() => ref.invalidate(overviewProvider);

  @override
  void onForeground() {
    if (ref.read(tabIndexProvider) == 1) ref.invalidate(overviewProvider);
  }

  @override
  Widget build(BuildContext context) {
    final configured = ref.watch(settingsProvider.select((s) => s.baseUrl)).trim().isNotEmpty;
    final followed = ref.watch(followedProvider);
    // The pulse is best-effort: if it hasn't loaded (or failed) the list still
    // renders, just without the state dot/caption.
    final states = ref.watch(overviewProvider).valueOrNull;

    // Refresh the pulse when returning to the Leagues tab, and re-pace polling.
    ref.listen<int>(tabIndexProvider, (_, next) {
      if (next == 1) ref.invalidate(overviewProvider);
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
              ref.invalidate(overviewProvider);
            },
          ),
        ],
      ),
      body: !configured
          ? const SetupPrompt()
          : ref.watch(catalogProvider).when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ErrorView(message: '$e', onRetry: () => ref.invalidate(catalogProvider)),
                data: (sports) {
                  final children = <Widget>[];
                  for (final s in sports) {
                    children.add(SectionHeader(sportLabel(s.sport)));
                    for (final lg in s.leagues) {
                      final isFollowed = followed.contains(lg.key);
                      final info = states?[lg.key];
                      final subtitle = <String>[
                        if (lg.region != null && lg.region!.isNotEmpty) lg.region!,
                        if (info != null && info.detail.isNotEmpty) info.detail,
                      ].join(' · ');
                      children.add(ListCard(
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
                      ));
                    }
                  }
                  return ListView(children: children);
                },
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


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../theme.dart';
import 'following_page.dart';
import 'scores_page.dart';
import 'standings_page.dart';

class ScoresV2App extends StatelessWidget {
  const ScoresV2App({super.key});

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: T.navBg,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
    return MaterialApp(
      title: 'Scores',
      debugShowCheckedModeBanner: false,
      theme: buildV2Theme(),
      home: const _Shell(),
    );
  }
}

/// Three tabs on an IndexedStack (state survives switching): Scores /
/// Standings / Following.
class _Shell extends ConsumerWidget {
  const _Shell();

  static const _tabs = [
    (icon: Icons.scoreboard_rounded, label: 'Scores'),
    (icon: Icons.format_list_numbered_rounded, label: 'Standings'),
    (icon: Icons.star_rounded, label: 'Following'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(tabIndexProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: tab,
          children: const [ScoresPage(), StandingsPage(), FollowingPage()],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: T.navBg,
          border: Border(top: BorderSide(color: T.divider)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
            child: Row(children: [
              for (var i = 0; i < _tabs.length; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () =>
                        ref.read(tabIndexProvider.notifier).state = i,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(_tabs[i].icon,
                          size: 22,
                          color: tab == i ? T.text : T.textFaint),
                      const SizedBox(height: 4),
                      Text(_tabs[i].label,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: tab == i
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: tab == i ? T.text : T.textFaint)),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

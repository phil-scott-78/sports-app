import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../theme.dart';
import 'scores_page.dart';
import 'leagues_page.dart';
import 'settings_page.dart';

/// Three tabs behind a floating label-pill nav (design "Nav B"): the active item
/// expands to a light fill showing its icon + label, the rest stay icon-only.
/// The body extends behind the pill (`extendBody`) so it floats over content.
/// Date browsing lives on Scores (the header date sheet), not a tab of its own.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  static const _pages = [ScoresPage(), LeaguesPage(), SettingsPage()];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(tabIndexProvider);
    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: index, children: _pages),
      bottomNavigationBar: FloatingNavBar(
        index: index,
        onChange: (i) => ref.read(tabIndexProvider.notifier).state = i,
      ),
    );
  }
}

/// Design "Nav B": a single rounded pill floating above the canvas. Inactive
/// items are icon-only; the active one expands to a light fill with its label.
class FloatingNavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChange;
  const FloatingNavBar({super.key, required this.index, required this.onChange});

  static const _items = [
    (icon: Icons.sports_score_outlined, active: Icons.sports_score, label: 'Scores'),
    (icon: Icons.emoji_events_outlined, active: Icons.emoji_events, label: 'Leagues'),
    (icon: Icons.settings_outlined, active: Icons.settings, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ext = BinanceColors.of(context);
    final bottom = MediaQuery.viewPaddingOf(context).bottom;

    return Container(
      // A soft scrim so list content fades into the canvas behind the pill.
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [cs.surface.withValues(alpha: 0), cs.surface],
          stops: const [0.0, 0.7],
        ),
      ),
      padding: EdgeInsets.only(left: 14, right: 14, top: 20, bottom: bottom + 12),
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: ext.cardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          children: [
            for (var i = 0; i < _items.length; i++)
              Expanded(
                flex: i == index ? 16 : 10,
                child: _NavItem(
                  icon: i == index ? _items[i].active : _items[i].icon,
                  label: _items[i].label,
                  selected: i == index,
                  onTap: () => onChange(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        height: 46,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: selected ? cs.onSurface : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 23, color: selected ? cs.surface : cs.onSurfaceVariant),
            if (selected) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.1,
                    color: cs.surface,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

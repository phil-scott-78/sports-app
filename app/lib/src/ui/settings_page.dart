import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import 'widgets.dart';
import 'favorite_teams_page.dart';
import 'manage_leagues_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const SectionHeader('Appearance'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('System')),
                ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (s) => notifier.setThemeMode(s.first),
            ),
          ),
          const Divider(height: 1),
          const SectionHeader('Content'),
          ListTile(
            leading: const Icon(Icons.emoji_events_outlined),
            title: const Text('Manage leagues'),
            subtitle: Text('${ref.watch(followedProvider).length} followed'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ManageLeaguesPage())),
          ),
          Builder(builder: (context) {
            final n = ref.watch(favoriteTeamsProvider).length;
            return ListTile(
              leading: const Icon(Icons.star_outline),
              title: const Text('Favorite teams'),
              subtitle: Text('$n favorite${n == 1 ? '' : 's'}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const FavoriteTeamsPage())),
            );
          }),
          const Divider(height: 1),
          const SectionHeader('About'),
          // The worker URL lives behind this row — tap it 6 times to edit it.
          const _AboutTile(),
          const SizedBox(height: kFloatingNavInset),
        ],
      ),
    );
  }
}

/// The About row — and the hidden worker-URL editor. The URL ships with a working
/// default ([AppConfig.defaultBaseUrl]), so it's tucked away here: tap the row 6
/// times to pop the edit dialog.
class _AboutTile extends ConsumerStatefulWidget {
  const _AboutTile();
  @override
  ConsumerState<_AboutTile> createState() => _AboutTileState();
}

class _AboutTileState extends ConsumerState<_AboutTile> {
  static const _tapsToReveal = 6;
  int _taps = 0;

  void _onTap() {
    _taps++;
    if (_taps >= _tapsToReveal) {
      _taps = 0;
      _editUrl();
    }
  }

  Future<void> _editUrl() async {
    final controller = TextEditingController(text: ref.read(settingsProvider).baseUrl);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Worker URL'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://sports-scores.you.workers.dev',
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(controller.text), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (result != null) ref.read(settingsProvider.notifier).setBaseUrl(result);
  }

  @override
  Widget build(BuildContext context) => ListTile(
        leading: const Icon(Icons.info_outline),
        title: const Text('Scores'),
        subtitle: const Text('A fast, calm, glanceable scores app.\nData via a self-hosted Cloudflare worker.'),
        onTap: _onTap,
      );
}

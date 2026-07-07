import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config.dart';
import '../providers.dart';
import '../theme.dart';
import '../version.dart';
import 'widgets.dart';

/// Minimal settings: the worker base URL (the only knob v2 needs) + about.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late final TextEditingController _url;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: ref.read(settingsProvider).baseUrl);
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  void _save() {
    ref.read(settingsProvider.notifier).setBaseUrl(_url.text);
    ref.invalidate(feedProvider);
    ref.invalidate(favoritesFeedProvider);
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Worker URL saved'),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: subpageBar(context, 'Settings'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            T.pageMargin, T.pageMargin, T.pageMargin, 28),
        children: [
          V2Card(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const CardLabel('Worker URL'),
              const SizedBox(height: 8),
              Text(
                'The Cloudflare worker this app reads scores from. '
                'Point it at your own deployment, or the offline mock '
                '(http://10.0.2.2:8787 on the Android emulator).',
                style: T.caption.copyWith(height: 1.5),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _url,
                style: const TextStyle(fontSize: 14, color: T.text),
                keyboardType: TextInputType.url,
                cursorColor: T.gold,
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  hintText: AppConfig.defaultBaseUrl,
                  hintStyle:
                      const TextStyle(fontSize: 14, color: T.textFaint),
                  filled: true,
                  fillColor: T.track,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                _Button(label: 'Save', primary: true, onTap: _save),
                const SizedBox(width: 10),
                _Button(
                  label: 'Reset default',
                  onTap: () {
                    _url.text = AppConfig.defaultBaseUrl;
                    _save();
                  },
                ),
              ]),
            ]),
          ),
          const SizedBox(height: 12),
          const V2Card(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CardLabel('About'),
              SizedBox(height: 8),
              Text(
                'Scores v2 · $kClientVersionName'
                '${kClientVersionCode > 0 ? ' ($kClientVersionCode)' : ''}',
                style: TextStyle(fontSize: 13, color: T.textDim),
              ),
              SizedBox(height: 4),
              Text(
                'Check a score in under two seconds, then get on with your day.',
                style: TextStyle(fontSize: 12, color: T.textFaint),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _Button extends StatelessWidget {
  final String label;
  final bool primary;
  final VoidCallback onTap;
  const _Button({required this.label, this.primary = false, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: primary ? T.invertedBg : null,
            border: primary ? null : Border.all(color: T.border, width: 1.5),
            borderRadius: BorderRadius.circular(100),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: primary ? T.invertedText : T.textDim)),
        ),
      );
}

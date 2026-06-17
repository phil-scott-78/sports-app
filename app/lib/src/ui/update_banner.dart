import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';

/// A thin, calm strip above the whole app advising an app update. Three tiers
/// (see [updateTierProvider]):
///  - hidden — current build, a dev build, or a gate-less/unreachable worker;
///  - SOFT — a dismissible "update available" nudge (below recommended), shown
///    once per release;
///  - HARD — a persistent "no longer supported" bar (below minimum).
///
/// A sideloaded APK can't self-update, so the worker can only signal + link:
/// tapping opens the GitHub Releases page in the browser. Renders nothing in the
/// common case, so it's free to leave mounted at the top of the app.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Single source of truth for "does this show" (shared with the app chrome so
    // it reserves space / status-bar inset only when visible — see app.dart).
    if (!ref.watch(bannerVisibleProvider)) return const SizedBox.shrink();
    final gate = ref.watch(healthProvider).valueOrNull?.client;
    if (gate == null) return const SizedBox.shrink(); // defensive (provider guards)
    return _Bar(tier: ref.watch(updateTierProvider), gate: gate);
  }
}

class _Bar extends ConsumerWidget {
  final UpdateTier tier;
  final ClientGate gate;
  const _Bar({required this.tier, required this.gate});

  Future<void> _openDownload() async {
    final url = gate.downloadUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final ext = BinanceColors.of(context);
    final isHard = tier == UpdateTier.hard;

    final latest = gate.latestVersionName;
    final message = isHard
        ? 'This version is no longer supported.'
        : latest != null && latest.isNotEmpty
            ? 'Update available — v$latest'
            : 'Update available';

    // Hard = a danger-tinted bar (a real signal); soft = quiet chrome.
    final bg = isHard
        ? Color.alphaBlend(ext.danger.withValues(alpha: 0.16), scheme.surface)
        : scheme.surfaceContainerHigh;
    final fg = isHard ? ext.danger : scheme.onSurface;

    // No SafeArea here — the app chrome (app.dart `_AppChrome`) wraps the banner
    // in a top SafeArea, which also zeroes the status-bar inset for the page below
    // so its AppBar doesn't pad for it twice.
    return Material(
      color: bg,
      child: InkWell(
        onTap: _openDownload,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.only(left: 16, right: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: scheme.outlineVariant, width: 1),
            ),
          ),
          child: Row(
            children: [
              Icon(
                isHard
                    ? Icons.warning_amber_rounded
                    : Icons.system_update_alt_rounded,
                size: 18,
                color: fg,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    fontFamily: kSans,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ),
              TextButton(
                onPressed: _openDownload,
                child: Text(isHard ? 'Update now' : 'Update'),
              ),
              if (!isHard)
                IconButton(
                  tooltip: 'Dismiss',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close_rounded,
                      size: 18, color: scheme.onSurfaceVariant),
                  onPressed: () {
                    final rec = gate.recommendedVersionCode;
                    if (rec != null) {
                      ref.read(dismissedUpdateProvider.notifier).dismiss(rec);
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The optional ON-DEVICE AI inning recap — one sentence about the half-inning
/// that just ended, written by the device's local model (Gemini Nano via the
/// ML Kit GenAI Prompt API on Android; see MainActivity.kt). Fully automatic:
/// used only when the platform reports the model AVAILABLE (already on the
/// device — this app never triggers a model download). Everywhere else — older
/// Android, web, tests, any failure — the deterministic line
/// (inning_recap.dart) stands; null here never surfaces an error.
///
/// One inference per (game, inning, half), coalesced + cached for the app's
/// lifetime — a 15s live poll must never re-ask about the same half-inning.
library;

import 'package:flutter/services.dart';

class RecapClient {
  static const _channel = MethodChannel('scores/recap');

  /// In-flight + settled recaps by cache key — overlapping rebuilds share one
  /// inference, and a settled half-inning is never re-requested.
  final _cache = <String, Future<String?>>{};

  /// Device-model availability, probed once per app run (it can't flip on
  /// mid-session without a download this app never starts).
  Future<bool>? _available;

  Future<bool> get available => _available ??= _probe();

  Future<bool> _probe() async {
    try {
      return await _channel.invokeMethod<bool>('available') ?? false;
    } catch (_) {
      return false; // MissingPluginException on web/tests, or any host error
    }
  }

  /// One-sentence recap of a completed half-inning, or null (no on-device
  /// model, inference failure — the deterministic line stands). [label] is the
  /// half's caption ('Top 5th · PIT'); [texts] the at-bat result lines in
  /// order.
  Future<String?> inningRecap({
    required String cacheKey,
    required String label,
    required List<String> texts,
  }) {
    if (texts.isEmpty) return Future.value(null);
    return _cache.putIfAbsent(
        cacheKey, () => _generate(label: label, texts: texts));
  }

  Future<String?> _generate({
    required String label,
    required List<String> texts,
  }) async {
    if (!await available) return null;
    final prompt = 'Summarize this baseball half-inning in exactly one short '
        'sentence (under 20 words) for a scores app: what happened — runs, '
        'big hits, escapes. Reply with only the sentence, plain text.\n\n'
        '$label — the at-bats, in order:\n'
        '${texts.map((t) => '- $t').join('\n')}';
    try {
      final t = await _channel
          .invokeMethod<String>('summarize', {'prompt': prompt});
      final line = t?.trim().replaceAll('\n', ' ');
      return (line != null && line.isNotEmpty) ? line : null;
    } catch (_) {
      return null;
    }
  }
}

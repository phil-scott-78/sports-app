import 'dart:async';
import 'package:flutter/widgets.dart';

/// Lifecycle-aware repeating poll for a [State]. Mix it in, then:
///   - call [attachPoll] in `initState` and [detachPoll] in `dispose`
///   - implement [pollInterval] (the cadence right now, or null to pause) and [onPoll]
///   - call [repace] whenever something that changes the cadence changes
///
/// The timer only ticks while the app is foregrounded; backgrounding cancels it
/// and resuming re-paces (after an optional [onForeground] catch-up). This
/// centralises the "don't let an in-flight resume re-arm a rogue timer" care the
/// Scores tab pioneered, so each polling screen stays a few lines. (The Scores
/// tab predates this and keeps its own bespoke version.)
mixin LifecyclePoll<T extends StatefulWidget> on State<T> {
  Timer? _pollTimer;
  bool pollForeground = true;
  WidgetsBindingObserver? _pollObserver;

  void attachPoll() {
    _pollObserver = _LifecycleProxy((fg) {
      pollForeground = fg;
      if (fg) onForeground();
      repace();
    });
    WidgetsBinding.instance.addObserver(_pollObserver!);
  }

  void detachPoll() {
    if (_pollObserver != null) WidgetsBinding.instance.removeObserver(_pollObserver!);
    _pollObserver = null;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// The desired cadence right now, or null to pause.
  Duration? pollInterval();

  /// Fired on each tick (foreground only).
  void onPoll();

  /// Catch-up hook when the app returns to the foreground. Default: no-op.
  void onForeground() {}

  /// (Re)arm or cancel the timer from [pollForeground] + [pollInterval]. Gating
  /// on [pollForeground]/[mounted] here is what stops a fetch that resolves
  /// *after* a background/dispose from re-arming a stray timer.
  void repace() {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (!pollForeground || !mounted) return;
    final d = pollInterval();
    if (d == null) return;
    _pollTimer = Timer.periodic(d, (_) => onPoll());
  }
}

class _LifecycleProxy extends WidgetsBindingObserver {
  final void Function(bool foreground) _onChange;
  _LifecycleProxy(this._onChange);
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _onChange(state == AppLifecycleState.resumed);
}

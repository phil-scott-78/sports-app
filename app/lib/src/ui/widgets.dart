import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../theme.dart';

/// Display name for a sport family key ('basketball' → 'Basketball', with a few
/// special cases). Shared by the Leagues list and the favorites/leagues pickers.
String sportLabel(String sport) {
  switch (sport) {
    case 'mma':
      return 'MMA';
    case 'rugby-league':
      return 'Rugby League';
    default:
      return sport.isEmpty ? sport : sport[0].toUpperCase() + sport.substring(1);
  }
}

/// Compact kickoff label for a scheduled game, derived from the event's own
/// start time. Today → just the clock ("7:00 PM"); other days get a day prefix
/// so the Upcoming slate reads clearly. This replaces ESPN's `shortDetail`,
/// which stamps a date even on games starting *today* (the bug we're fixing).
String scheduledLabel(DateTime start) {
  final s = start.toLocal();
  final time = DateFormat.jm().format(s); // "7:00 PM"
  // Whole calendar days between the two local midnights. Round (not truncate)
  // the elapsed hours so a 23h/25h daylight-saving day can't drop a day —
  // `Duration.inDays` would turn a spring-forward "tomorrow" (23h) into "today".
  final diff =
      (DateUtils.dateOnly(s).difference(DateUtils.dateOnly(DateTime.now())).inHours / 24).round();
  if (diff == 0) return time;
  if (diff == 1) return 'Tomorrow $time';
  if (diff == -1) return 'Yesterday $time';
  if (diff > 1 && diff < 7) return '${DateFormat.E().format(s)} $time'; // "Sat 7:00 PM"
  return '${DateFormat.MMMd().format(s)} $time'; // "Jun 20 7:00 PM"
}

/// Routes an ESPN crest through the "combiner" image resizer so the *server*
/// does a high-quality downscale to the exact pixels we display, returning a
/// right-sized PNG (alpha preserved). The raw crests are 500×500; downscaling
/// those on-device with bilinear filtering aliases badly on the thin white
/// strokes of the dark-mode variants — and ships ~10× the bytes. We clamp to
/// the 500px source so the combiner never upscales (which balloons the file).
/// Non-espncdn / non-crest URLs pass through untouched.
String espnSized(String url, int px) {
  final u = Uri.tryParse(url);
  if (u == null || !u.host.endsWith('espncdn.com') || !u.path.startsWith('/i/')) {
    return url;
  }
  final w = px > 500 ? 500 : px;
  return Uri.https('a.espncdn.com', '/combiner/i', {
    'img': u.path,
    'w': '$w',
    'h': '$w',
    'scale': 'crop',
    'cquality': '90',
    'format': 'png',
    'location': 'origin',
  }).toString();
}

/// Team crest / athlete headshot with a graceful initials fallback.
///
/// - Disk + memory cached (cached_network_image) so logos survive scrolls and
///   cold starts and aren't re-downloaded.
/// - Served pre-sized via [espnSized] (ESPN's server-side resizer) so the crest
///   arrives at display resolution instead of a 500×500 PNG downscaled on-device
///   — eliminating the dark-mode aliasing and cutting bandwidth ~10×.
/// - In dark mode prefers [darkUrl] (ESPN's white "dark" logo variant) and
///   falls back to [url] if that 404s (e.g. soccer has no dark variant).
class Crest extends StatelessWidget {
  final String? url;
  final String? darkUrl;
  final String fallback;
  final double size;
  const Crest({super.key, required this.url, this.darkUrl, required this.fallback, this.size = 28});

  @override
  Widget build(BuildContext context) {
    final initials = fallback.isEmpty
        ? '?'
        : fallback.substring(0, fallback.length < 3 ? fallback.length : 3).toUpperCase();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    final px = (size * (dpr > 3 ? 3 : dpr)).ceil();
    final hasLight = url != null && url!.isNotEmpty;
    final hasDark = darkUrl != null && darkUrl!.isNotEmpty;

    Widget box() => _box(context, initials);
    Widget net(String u, {Widget Function()? onError}) => CachedNetworkImage(
          imageUrl: u,
          width: size,
          height: size,
          fit: BoxFit.contain,
          memCacheWidth: px,
          memCacheHeight: px,
          filterQuality: FilterQuality.medium,
          fadeInDuration: const Duration(milliseconds: 120),
          placeholder: (_, __) => box(),
          errorWidget: (_, __, ___) => (onError ?? box)(),
        );

    final Widget child;
    if (isDark && hasDark) {
      // dark variant first; on 404 fall back to the light logo, then initials.
      child = net(espnSized(darkUrl!, px), onError: hasLight ? () => net(espnSized(url!, px)) : box);
    } else if (hasLight) {
      child = net(espnSized(url!, px));
    } else {
      return box();
    }
    return ClipRRect(borderRadius: BorderRadius.circular(6), child: child);
  }

  Widget _box(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: size * 0.34,
          fontWeight: FontWeight.w700,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// The one-line status text for a competition — "3rd 8:39" live, "Final",
/// or a clean kickoff time for a scheduled game. Shared by [StatusChip] and the
/// scores-list card so the two never drift. When [startTime] is present a
/// scheduled game is formatted from it (today → just the clock) instead of
/// ESPN's date-stamped label.
String statusLabel(Status status, DateTime? startTime) {
  if (status.live) {
    return status.periodLabel.isNotEmpty ? status.periodLabel : 'LIVE';
  }
  if (status.isFinal) {
    return status.shortDetail ?? (status.periodLabel.isNotEmpty ? status.periodLabel : 'Final');
  }
  if (status.isScheduled) {
    return startTime != null
        ? scheduledLabel(startTime)
        : (status.periodLabel.isNotEmpty ? status.periodLabel : 'Scheduled');
  }
  return status.shortDetail ?? (status.phase.isEmpty ? '—' : status.phase);
}

/// Status pill. Live games get a red-tinted pill with a pulsing dot (the one
/// place trading-down red earns its energy); final reads in strong body, a
/// scheduled tip-off in muted — text-color semantics over loud fills.
class StatusChip extends StatelessWidget {
  final Status status;

  /// When the game is scheduled, the kickoff is formatted from this instead of
  /// ESPN's date-stamped label (so today's games show just a time). Optional —
  /// falls back to the ESPN label when absent.
  final DateTime? startTime;
  const StatusChip({super.key, required this.status, this.startTime});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = statusLabel(status, startTime);
    // Live: red tint + red pulsing dot carry the signal, label stays high-
    // contrast body (red-on-red-tint clears AA in neither mode). Final reads in
    // body; everything else (scheduled/other) sits muted.
    final Color bg = status.live ? cs.errorContainer : cs.surfaceContainerHighest;
    final Color fg = (status.live || status.isFinal) ? cs.onSurface : cs.onSurfaceVariant;
    return Container(
      padding: EdgeInsets.fromLTRB(status.live ? 8 : 9, 4, 9, 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status.live) ...[
            LiveDot(color: cs.error),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: TextStyle(
              color: fg,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: status.live ? 0.3 : 0,
            ),
          ),
        ],
      ),
    );
  }
}

/// A softly pulsing live indicator dot with a faint glow.
class LiveDot extends StatefulWidget {
  final Color color;
  const LiveDot({super.key, required this.color});
  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = 0.45 + 0.55 * _c.value; // 0.45 → 1.0
        return Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: t),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.55 * t),
                blurRadius: 5 * t,
                spreadRadius: 0.5,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One day in a horizontal date strip: weekday over day-number, a faint pill
/// when selected. Shared by the Scores "Upcoming" strip and the league-detail
/// Schedule strip. [isToday] keeps today legible (full-contrast) even when it
/// isn't the selected day. A `FittedBox(scaleDown)` guards against vertical
/// overflow at large accessibility text scales (the strip lane is fixed-height).
class DateChip extends StatelessWidget {
  final DateTime date;
  final bool selected;
  final bool isToday;
  final VoidCallback onTap;
  const DateChip({
    super.key,
    required this.date,
    required this.selected,
    this.isToday = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = (selected || isToday) ? cs.onSurface : cs.onSurfaceVariant;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 48,
        margin: const EdgeInsets.symmetric(vertical: 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? cs.surfaceContainerHighest : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isToday ? 'TODAY' : DateFormat.E().format(date).toUpperCase(), // "SAT"
                style: TextStyle(
                  fontSize: 11,
                  height: 1.0, // pin leading so the chip's height is deterministic
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                  color: fg,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${date.day}',
                style: numStyle(
                  size: 16,
                  weight: (selected || isToday) ? FontWeight.w800 : FontWeight.w600,
                  color: fg,
                ).copyWith(height: 1.0),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rounded surface container used for every game-detail section.
class DetailPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  const DetailPanel({super.key, required this.child, this.padding});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        // Hairline borders read as a surface step, not an ink line — Binance.
        border: Border.all(color: BinanceColors.of(context).cardBorder, width: 1),
      ),
      child: child,
    );
  }
}

/// The one canonical group/section title for scrolling lists (Scores feed,
/// Leagues, the pickers, Settings groups). Small, bold, neutral `onSurface` —
/// NOT tracked or uppercase, NOT muted, NOT a display size. This is the single
/// source for the header `scores_page` once kept private as `_SectionHeader`;
/// reuse it everywhere instead of re-implementing a `Padding`+`Text` (which
/// drifts — five screens had crept to `(16,16,16,4)`). See DESIGN §Spacing.
class SectionHeader extends StatelessWidget {
  final String title;
  const SectionHeader(this.title, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      );
}

/// The flat-card surface recipe (the gold-standard `GameCard` / `DetailPanel`
/// look) wrapping a single list row, so list screens read like the Scores feed
/// instead of bare `ListTile`s on the scaffold floor: `surfaceContainerLow`
/// fill, 1px hairline, radius 12, no shadow. Cards inset 12 from the edge with
/// an 8px gap (the card gutter — see DESIGN §Spacing).
///
/// If the child is a `ListTile`, give the `ListTile` its own `onTap` and leave
/// [onTap] null (avoids a double ripple); pass [onTap] only for a non-
/// interactive child (e.g. a bare `Row`).
class ListCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry margin;
  const ListCard({
    super.key,
    required this.child,
    this.onTap,
    this.margin = const EdgeInsets.fromLTRB(12, 0, 12, 8),
  });
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: margin,
      child: Material(
        color: cs.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: BinanceColors.of(context).cardBorder, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: onTap == null ? child : InkWell(onTap: onTap, child: child),
      ),
    );
  }
}

/// Small muted, tracked label — the *column-header* / in-panel sub-label voice,
/// deliberately distinct from [SectionHeader]. Use it for column heads inside a
/// `DetailPanel` (box score, leaderboards), NOT for top-level list groups.
class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        // Keep the literal text (widget tests match on it); the tracked,
        // muted treatment carries the column-header voice.
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
}

/// Centered empty/placeholder state.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle, this.action});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle!, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// Shown across tabs until the worker URL is configured.
class SetupPrompt extends StatelessWidget {
  const SetupPrompt({super.key});
  @override
  Widget build(BuildContext context) => const EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Connect your scores worker',
        subtitle: 'Open the Settings tab and paste your Cloudflare worker URL, e.g.\nhttps://sports-scores.you.workers.dev',
      );
}

class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const ErrorView({super.key, required this.message, this.onRetry});
  @override
  Widget build(BuildContext context) => EmptyState(
        icon: Icons.error_outline,
        title: 'Couldn\'t load',
        subtitle: message,
        // The one functional action on the error state → the signature yellow
        // FilledButton (not .tonal grey). DESIGN §Components: scarce accent =
        // the single primary action on a screen.
        action: onRetry == null
            ? null
            : FilledButton(onPressed: onRetry, child: const Text('Retry')),
      );
}

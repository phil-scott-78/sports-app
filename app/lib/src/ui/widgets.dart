import 'dart:ui' show ImageFilter;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../theme.dart';

/// A Flutter Material icon for a sport family (the design's per-sport chips and
/// timeline nodes). Used by the Scores header chips and the center-spine timeline.
IconData sportIcon(String sport) {
  switch (sport) {
    case 'soccer':
      return Icons.sports_soccer;
    case 'baseball':
      return Icons.sports_baseball;
    case 'basketball':
      return Icons.sports_basketball;
    case 'hockey':
      return Icons.sports_hockey;
    case 'football':
      return Icons.sports_football;
    case 'golf':
      return Icons.sports_golf;
    case 'tennis':
      return Icons.sports_tennis;
    case 'mma':
      return Icons.sports_mma;
    case 'cricket':
      return Icons.sports_cricket;
    case 'racing':
      return Icons.sports_motorsports;
    case 'rugby':
    case 'rugby-league':
    case 'australian-football': // oval-ball field sport — closest Material glyph
      return Icons.sports_rugby;
    case 'volleyball':
      return Icons.sports_volleyball;
    case 'water-polo':
      return Icons.pool;
    case 'field-hockey':
      return Icons.sports_hockey;
    default:
      return Icons.sports; // incl. lacrosse (no Material glyph)
  }
}

/// Bottom padding the floating-pill nav ([FloatingNavBar]) needs scrolling lists
/// to leave so their last row clears the pill (the body extends behind it via
/// `Scaffold.extendBody`). Pill height + margin + home-indicator headroom.
const double kFloatingNavInset = 96;

/// Display name for a sport family key ('basketball' → 'Basketball', with a few
/// special cases). Shared by the Leagues list and the favorites/leagues pickers.
String sportLabel(String sport) {
  switch (sport) {
    case 'mma':
      return 'MMA';
    case 'rugby-league':
      return 'Rugby League';
    case 'australian-football':
      return 'Australian Football';
    case 'water-polo':
      return 'Water Polo';
    case 'field-hockey':
      return 'Field Hockey';
    default:
      return sport.isEmpty
          ? sport
          : sport[0].toUpperCase() + sport.substring(1);
  }
}

/// A quiet-day line in the sport's own voice — what an empty slate says on the
/// *today* view instead of a flat "No games today". Calm, not snark: the app's
/// personality is a knowing nod, one line, then out of the way.
String quietDayLine(String sport) {
  switch (sport) {
    case 'baseball':
      return 'Off day at the ballpark';
    case 'basketball':
      return 'Dark night at the arena';
    case 'hockey':
      return 'The ice is quiet tonight';
    case 'football':
      return 'No football today';
    case 'soccer':
      return 'Quiet day on the pitch';
    case 'golf':
      return 'No tee times today';
    case 'tennis':
      return 'The courts are quiet';
    case 'racing':
      return 'Engines are cold today';
    case 'mma':
      return 'No fights tonight';
    case 'cricket':
      return 'No play today';
    case 'rugby':
    case 'rugby-league':
      return 'No rugby today';
    default:
      return 'No games today';
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
  final diff = (DateUtils.dateOnly(s)
              .difference(DateUtils.dateOnly(DateTime.now()))
              .inHours /
          24)
      .round();
  if (diff == 0) return time;
  if (diff == 1) return 'Tomorrow $time';
  if (diff == -1) return 'Yesterday $time';
  if (diff > 1 && diff < 7) {
    return '${DateFormat.E().format(s)} $time'; // "Sat 7:00 PM"
  }
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
  if (u == null ||
      !u.host.endsWith('espncdn.com') ||
      !u.path.startsWith('/i/')) {
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

// ---- team-color winner wash -------------------------------------------------
/// Parse an ESPN hex color ("1d428a" or "#1d428a"); null if unparseable.
Color? teamHexColor(String? hex) {
  if (hex == null) return null;
  var h = hex.replaceFirst('#', '').trim();
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

/// Pick a tintable color, preferring the alternate when the primary is too near
/// the canvas to register (a black primary on dark, a white one on light).
Color? teamTint(String? primary, String? alt, bool dark) {
  final p = teamHexColor(primary);
  final a = teamHexColor(alt);
  if (p == null) return a;
  if (a != null) {
    final l = p.computeLuminance();
    if (dark && l < 0.04) return a; // near-black vanishes on the dark canvas
    if (!dark && l > 0.96) return a; // near-white vanishes on the light canvas
  }
  return p;
}

/// A very subtle team-color gradient, reserved for **final** head-to-head
/// competitions — the "result is in" moment. It washes from the winning team's
/// side (away tints the top-left, home the bottom-right, matching their crests'
/// positions); a draw with no single winner tints from both corners. Low alpha
/// so it reads as a sheen, not a fill. Returns null for field sports, any
/// non-final game, and when the relevant team(s) expose no usable color.
///
/// Shared by the scores [GameCard] wash and the game-detail hero so the two
/// never drift (winner emphasis stays team-color by design).
Gradient? winnerWashGradient(BuildContext context, Competition comp) {
  if (comp.isField || !comp.status.isFinal) return null;
  // a = away (top-left), b = home (bottom-right) — matches the away-first card/hero
  // layout so the wash tints from the winning team's actual on-screen corner.
  final a = comp.away ??
      (comp.competitors.isNotEmpty ? comp.competitors.first : null);
  final b =
      comp.home ?? (comp.competitors.length > 1 ? comp.competitors[1] : null);
  final dark = Theme.of(context).brightness == Brightness.dark;
  final alpha = dark ? 0.16 : 0.10;

  final aWins = a?.winner == true;
  final bWins = b?.winner == true;

  // A clear single winner → wash only from that team's corner.
  if (aWins != bWins) {
    final winner = aWins ? a : b;
    final c = teamTint(winner?.color, winner?.altColor, dark);
    if (c == null) return null;
    final tint = c.withValues(alpha: alpha);
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: aWins ? [tint, Colors.transparent] : [Colors.transparent, tint],
      stops: aWins ? const [0.0, 0.65] : const [0.35, 1.0],
    );
  }

  // A draw (or no winner flagged) → tint from both corners, neutral centre.
  final ca = teamTint(a?.color, a?.altColor, dark);
  final cb = teamTint(b?.color, b?.altColor, dark);
  if (ca == null && cb == null) return null;
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      (ca ?? cb)!.withValues(alpha: alpha),
      Colors.transparent,
      (cb ?? ca)!.withValues(alpha: alpha),
    ],
    stops: const [0.0, 0.5, 1.0],
  );
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
  const Crest(
      {super.key,
      required this.url,
      this.darkUrl,
      required this.fallback,
      this.size = 28});

  @override
  Widget build(BuildContext context) {
    final initials = fallback.isEmpty
        ? '?'
        : fallback
            .substring(0, fallback.length < 3 ? fallback.length : 3)
            .toUpperCase();
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
      child = net(espnSized(darkUrl!, px),
          onError: hasLight ? () => net(espnSized(url!, px)) : box);
    } else if (hasLight) {
      child = net(espnSized(url!, px));
    } else {
      return ExcludeSemantics(child: box());
    }
    // The crest is decorative — team identity is carried by the adjacent name
    // text everywhere a Crest renders, so keep the logo out of the a11y tree
    // rather than announcing an unlabeled image.
    return ExcludeSemantics(
      child: ClipRRect(borderRadius: BorderRadius.circular(6), child: child),
    );
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
    return status.shortDetail ??
        (status.periodLabel.isNotEmpty ? status.periodLabel : 'Final');
  }
  if (status.isScheduled) {
    return startTime != null
        ? scheduledLabel(startTime)
        : (status.periodLabel.isNotEmpty ? status.periodLabel : 'Scheduled');
  }
  return status.shortDetail ?? (status.phase.isEmpty ? '—' : status.phase);
}

/// Cricket's headline score, split for a slot built for "103". ESPN ships a
/// composite that is far too long to drop in raw — a chase carries its overs +
/// target ("161/5 (18/20 ov, target 156)"), a first-class innings stacks two
/// totals ("469 & 246/6d"), sometimes both ("263 & 44/1 (15 ov, target 453)").
/// We keep the runs/wickets line (both innings when present) and peel ESPN's
/// trailing parenthetical — "(overs[, target])", "(f/o)" — off it, surfacing just
/// the overs as a compact tempo tag. The full per-innings story (overs, target,
/// declared/all-out) lives in the Innings panel on the detail screen.
///
/// `runs` is '' only when there's no score yet (pre-innings) — callers dash it.
typedef CricketScoreParts = ({String runs, String? overs});

final RegExp _cricketOvers =
    RegExp(r'([\d.]+)\s*(?:/\s*\d+)?\s*ov', caseSensitive: false);

CricketScoreParts cricketScoreParts(Competitor c) {
  final raw = c.score?.display.trim() ?? '';
  if (raw.isEmpty) return (runs: '', overs: null);
  // Runs line = everything before ESPN's first parenthetical group; the
  // parenthetical only ever carries overs/target/follow-on context.
  final paren = raw.indexOf('(');
  final runs = (paren < 0 ? raw : raw.substring(0, paren)).trim();
  // Overs from ESPN's "(… ov)" tag: "18/20 ov" → 18, "99.3 ov" → 99.3. It always
  // sits in the parenthetical and reflects the *current* innings, so a two-innings
  // line surfaces just the live-innings overs (and a settled total carries none).
  final m = _cricketOvers.firstMatch(raw);
  return (
    runs: runs.isEmpty ? raw : runs,
    overs: m == null ? null : '${m.group(1)} ov'
  );
}

/// Status pill. Live games get a green-tinted pill with a pulsing dot (the
/// design's single live hue); final reads in strong body, a scheduled tip-off in
/// muted — text-color semantics over loud fills.
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
    final live = BinanceColors.of(context).live;
    final text = statusLabel(status, startTime);
    // Live: green tint + green pulsing dot carry the signal, label stays high-
    // contrast body. Final reads in body; everything else sits muted.
    final Color bg =
        status.live ? live.withValues(alpha: 0.14) : cs.surfaceContainerHighest;
    final Color fg =
        (status.live || status.isFinal) ? cs.onSurface : cs.onSurfaceVariant;
    return Container(
      padding: EdgeInsets.fromLTRB(status.live ? 8 : 9, 4, 9, 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status.live) ...[
            LiveDot(color: live),
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
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Honour reduce-motion: hold a steady dot instead of pulsing 60fps forever.
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
      _c.value = 1.0;
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary isolates this 60fps repaint into its own layer so it can't
    // dirty neighbouring widgets in the same card/chip.
    return RepaintBoundary(
      child: AnimatedBuilder(
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
      ),
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

  /// This day has no games (known from a range fetch) — faded back so populated
  /// days stand out. Still tappable. Never dims the selected day or today.
  final bool dimmed;
  final VoidCallback onTap;
  const DateChip({
    super.key,
    required this.date,
    required this.selected,
    this.isToday = false,
    this.dimmed = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = (selected || isToday) ? cs.onSurface : cs.onSurfaceVariant;
    final faded = dimmed && !selected && !isToday;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Opacity(
        opacity: faded ? 0.35 : 1,
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
                  isToday
                      ? 'TODAY'
                      : DateFormat.E().format(date).toUpperCase(), // "SAT"
                  style: TextStyle(
                    fontSize: 11,
                    height:
                        1.0, // pin leading so the chip's height is deterministic
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
                    weight: (selected || isToday)
                        ? FontWeight.w800
                        : FontWeight.w600,
                    color: fg,
                  ).copyWith(height: 1.0),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Presents [child] as a bottom sheet over a **dimmed + lightly blurred** scrim —
/// darker and softer than the stock `showModalBottomSheet` barrier (a flat
/// `black54`, no blur). Built on `showGeneralDialog` so the scrim's dim+blur fades
/// in independently while the panel slides up; the panel keeps the usual chrome
/// (rounded top, drag handle, surface fill, bottom safe-area) and dismisses on a
/// downward fling or a tap on the scrim. [child] supplies just the panel content
/// (sized to its own height).
Future<T?> showBlurredBottomSheet<T>({
  required BuildContext context,
  required Widget child,
  double blurSigma = 6,
  double dimOpacity = 0.66,
}) {
  final cs = Theme.of(context).colorScheme;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: false, // the scrim's GestureDetector owns dismissal
    barrierColor:
        Colors.transparent, // we paint the dim ourselves, under the blur
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (context, _, __) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(), // transparent top → the blurred scrim shows through
        GestureDetector(
          // Absorb stray taps on the panel (opaque) and fling-down to dismiss;
          // inner chip/strip gestures still win within their own bounds.
          behavior: HitTestBehavior.opaque,
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) > 250) {
              Navigator.of(context).maybePop();
            }
          },
          child: Material(
            color: cs.surface,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            clipBehavior: Clip.antiAlias,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child,
                ],
              ),
            ),
          ),
        ),
      ],
    ),
    transitionBuilder: (context, anim, _, page) {
      final t = Curves.easeOutCubic.transform(anim.value);
      return Stack(
        children: [
          // Dim + blur scrim, fading in; tap anywhere off the panel to dismiss.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
              child: BackdropFilter(
                filter: ImageFilter.blur(
                    sigmaX: blurSigma * t, sigmaY: blurSigma * t),
                child: ColoredBox(
                    color: Colors.black.withValues(alpha: dimOpacity * t)),
              ),
            ),
          ),
          // Panel slides up from the bottom edge.
          Positioned.fill(
            child: FractionalTranslation(
                translation: Offset(0, 1 - t), child: page),
          ),
        ],
      );
    },
  );
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
        border:
            Border.all(color: BinanceColors.of(context).cardBorder, width: 1),
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
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
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
          side:
              BorderSide(color: BinanceColors.of(context).cardBorder, width: 1),
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
  const EmptyState(
      {super.key,
      required this.icon,
      required this.title,
      this.subtitle,
      this.action});

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
            Text(title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant)),
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
        subtitle:
            'Open the Settings tab and paste your Cloudflare worker URL, e.g.\nhttps://sports-scores.you.workers.dev',
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

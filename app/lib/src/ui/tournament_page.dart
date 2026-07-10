import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config.dart';
import '../data/profiles.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import 'follow_sheet.dart';
import 'game_detail_page.dart';
import 'poll.dart';
import 'widgets.dart';

/// Open the tournament screen for a tennis draw drilled in from the Scores
/// list's per-tournament summary row. One ESPN "event" IS a whole tournament;
/// [event] carries its matches so matchup cards can tap into the set-grid
/// detail. Signature is preserved for the existing Scores-list callsite.
void openTournamentPage(BuildContext context, String league, SportEvent event,
    {String? date}) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => TournamentPage(
        league: league, initialEvent: event, date: date, name: event.name),
  ));
}

/// Open the tournament screen for a whole league (the league-page "Bracket"
/// affordance) — no seed event, the data layer resolves the current competition
/// from the profile's window.
void openLeagueTournamentPage(BuildContext context, String league,
    {String? name}) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => TournamentPage(league: league, name: name),
  ));
}

/// Whether a league is a candidate for the bracket/tournament view — a cheap
/// profile check (group tables or a windowed competition) so the league page
/// only fires the (heavier) tournament fetch for leagues that could have one.
/// Non-empty data is confirmed separately by watching the provider.
bool leagueHasTournamentView(String league) {
  try {
    final p = resolve(Registry.instance, league);
    return p['tournamentGroups'] == true || p['tournamentWindowDays'] != null;
  } catch (_) {
    return false;
  }
}

/// Provider key for a tournament fetch. All fields optional past [league] — the
/// data layer fills windows and default groupings itself.
typedef TournamentKey = ({
  String league,
  String? window,
  String? grouping,
  String? eventId,
});

final tournamentProvider =
    FutureProvider.autoDispose.family<TournamentResponse, TournamentKey>(
  (ref, k) => ref.watch(apiProvider).tournament(k.league,
      window: k.window, grouping: k.grouping, eventId: k.eventId),
);

/// The tournament screen: one constant shell (crest + title + chip strip) whose
/// body swaps between four bracket grammars on DATA PRESENCE (never tournament
/// name) — group tables (12a), a single-elim draw (12b), a seeded region
/// bracket (12c), and double-elim pools + a championship series (12d).
class TournamentPage extends ConsumerStatefulWidget {
  final String league;

  /// The tennis tournament event we were opened with (carries the per-match
  /// [SportEvent]s so matchup cards can tap into game detail). Null for the
  /// league-page affordance.
  final SportEvent? initialEvent;
  final String? name;
  final String? date;
  final String? grouping;
  const TournamentPage({
    super.key,
    required this.league,
    this.initialEvent,
    this.name,
    this.date,
    this.grouping,
  });

  @override
  ConsumerState<TournamentPage> createState() => _TournamentPageState();
}

class _TournamentPageState extends ConsumerState<TournamentPage>
    with LifecyclePoll {
  TournamentKey get _key => (
        league: widget.league,
        window: null,
        grouping: widget.grouping,
        eventId: widget.initialEvent?.id,
      );

  /// competitionId → per-match [SportEvent], so a tennis matchup card can open
  /// the set-grid detail. Empty for the league affordance (those events aren't
  /// loaded as SportEvents; their cards stay inert).
  late final Map<String, SportEvent> _matchLookup = {
    for (final m in widget.initialEvent?.matches ?? const <SportEvent>[])
      m.id: m,
  };

  @override
  void initState() {
    super.initState();
    attachPoll();
    WidgetsBinding.instance.addPostFrameCallback((_) => repace());
  }

  @override
  void dispose() {
    detachPoll();
    super.dispose();
  }

  @override
  Duration? pollInterval() {
    final t = ref.read(tournamentProvider(_key)).valueOrNull;
    if (t == null) return AppConfig.refreshIdle;
    final live = t.rounds.any((r) => r.matchups.any((m) => m.live));
    return live ? AppConfig.refreshLive : AppConfig.refreshIdle;
  }

  @override
  void onPoll() => ref.invalidate(tournamentProvider(_key));

  @override
  void onForeground() => onPoll();

  void _openMatch(TournamentMatchup m) {
    final ev = _matchLookup[m.competitionId] ?? _matchLookup[m.eventId];
    if (ev != null) {
      openGameDetail(context, widget.league, ev, date: widget.date);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(tournamentProvider(_key), (_, __) => repace());
    final async = ref.watch(tournamentProvider(_key));
    final fallbackTitle = widget.name ?? widget.league;

    return Scaffold(
      backgroundColor: T.bg,
      body: SafeArea(
        bottom: false,
        child: async.when(
          loading: () => _Shell(
            title: fallbackTitle,
            label: 'TOURNAMENT',
            body: const Expanded(
              child:
                  Center(child: CircularProgressIndicator(color: T.gold)),
            ),
          ),
          error: (_, __) => _Shell(
            title: fallbackTitle,
            label: 'TOURNAMENT',
            body: const Padding(
              padding: EdgeInsets.fromLTRB(
                  T.pageMargin, 24, T.pageMargin, 0),
              child: HintCard('Couldn’t load this bracket.'),
            ),
          ),
          data: (t) => t.isEmpty
              ? _Shell(
                  title: t.title.isNotEmpty ? t.title : fallbackTitle,
                  subtitle: t.subtitle,
                  label: 'TOURNAMENT',
                  body: const Padding(
                    padding: EdgeInsets.fromLTRB(
                        T.pageMargin, 24, T.pageMargin, 0),
                    child: HintCard('No bracket to show yet.'),
                  ),
                )
              : TournamentView(
                  response: t,
                  league: widget.league,
                  onTapMatchup: _matchLookup.isEmpty ? null : _openMatch,
                ),
        ),
      ),
    );
  }
}

// ─────────────────────────── the view (pure, testable) ───────────────────────
/// The tournament shell + body, driven purely by a [TournamentResponse]. Kept
/// provider-free so widget tests can pump it with a golden-built response.
class TournamentView extends StatefulWidget {
  final TournamentResponse response;

  /// The league key, enabling the long-press follow sheet on group/pool team
  /// rows. Null (widget tests) leaves the rows inert.
  final String? league;

  /// Tapped matchup → open its game detail. Null (or an unresolvable matchup)
  /// leaves the card inert.
  final void Function(TournamentMatchup)? onTapMatchup;
  const TournamentView(
      {super.key, required this.response, this.league, this.onTapMatchup});

  @override
  State<TournamentView> createState() => _TournamentViewState();
}

class _TournamentViewState extends State<TournamentView> {
  final _pageScroll = ScrollController();
  final _drawScroll = ScrollController();
  final _knockoutScroll = ScrollController();
  final _groupKeys = <String, GlobalKey>{};
  final _colKeys = <int, GlobalKey>{};
  int _chip = 0;
  String? _region;

  TournamentResponse get t => widget.response;

  @override
  void dispose() {
    _pageScroll.dispose();
    _drawScroll.dispose();
    _knockoutScroll.dispose();
    super.dispose();
  }

  // ---- shell classification ----
  bool get _hasGroups => t.groups.isNotEmpty;
  bool get _hasPoolsOrSeries => t.pools.isNotEmpty || t.series != null;
  bool get _hasSets =>
      t.rounds.any((r) => r.matchups.any((m) => m.competitors.any((c) => c.sets.isNotEmpty)));

  String get _label {
    if (_hasGroups || _hasPoolsOrSeries) return 'TOURNAMENT';
    if (_hasSets) return 'DRAW';
    return 'BRACKET';
  }

  @override
  Widget build(BuildContext context) {
    if (_hasGroups) return _groupsBody();
    if (_hasPoolsOrSeries) return _poolsBody();
    if (t.rounds.isNotEmpty) return _drawBody();
    // isEmpty is handled upstream; this only fires for an all-empty response.
    return _Shell(
      title: t.title,
      subtitle: t.subtitle,
      label: _label,
      body: const Padding(
        padding: EdgeInsets.fromLTRB(T.pageMargin, 24, T.pageMargin, 0),
        child: HintCard('No bracket to show yet.'),
      ),
    );
  }

  // ═══════════════ 12a · groups + knockout scroller ═══════════════
  Widget _groupsBody() {
    final knockout =
        t.rounds.where((r) => r.round != 'group').toList(growable: false);
    final qualTag = _qualTag();
    for (final g in t.groups) {
      _groupKeys.putIfAbsent(g.label, () => GlobalKey());
    }
    return _Shell(
      title: t.title,
      subtitle: t.subtitle,
      label: _label,
      chips: t.groups.length > 1
          ? _GroupChips(
              labels: [for (final g in t.groups) _groupChip(g.label)],
              selected: _chip,
              onTap: _jumpToGroup,
            )
          : null,
      body: Expanded(
        child: ListView(
          controller: _pageScroll,
          padding: const EdgeInsets.only(top: 12, bottom: T.scrollBottom),
          children: [
            for (final g in t.groups)
              Padding(
                key: _groupKeys[g.label],
                padding: const EdgeInsets.fromLTRB(
                    T.pageMargin, 0, T.pageMargin, T.gapCard),
                child: _GroupCard(
                    group: g, qualTag: qualTag, league: widget.league),
              ),
            if (knockout.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(T.pageMargin, 8, T.pageMargin, 10),
                child: Text('KNOCKOUT BRACKET', style: T.cardLabelFaint),
              ),
              SizedBox(
                height: 320,
                child: _RoundScroller(
                  rounds: knockout,
                  controller: _knockoutScroll,
                  cardWidth: 150,
                  onTapMatchup: widget.onTapMatchup,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 'Group A' → 'A'; a short non-'Group' label passes through; else first char.
  String _groupChip(String label) {
    final s = label.replaceFirst(RegExp(r'group\s*', caseSensitive: false), '').trim();
    if (s.isEmpty) return label.isEmpty ? '?' : label[0].toUpperCase();
    return (s.length <= 2 ? s : s[0]).toUpperCase();
  }

  void _jumpToGroup(int i) {
    setState(() => _chip = i);
    final key = _groupKeys[t.groups[i].label];
    final ctx = key?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 300),
          alignment: 0.05,
          curve: Curves.easeOut);
    }
  }

  /// The tag stamped on qualified group rows / the label of the first knockout
  /// round they advance to (e.g. 'R32'). Null when there's no knockout data.
  String? _qualTag() {
    for (final r in t.rounds) {
      if (r.round == 'group' || r.round == 'qualifying') continue;
      return _roundShort(r.round, r.label);
    }
    return null;
  }

  // ═══════════════ 12d · pools + championship series ═══════════════
  Widget _poolsBody() {
    return _Shell(
      title: t.title,
      subtitle: t.subtitle,
      label: _label,
      body: Expanded(
        child: ListView(
          controller: _pageScroll,
          padding: const EdgeInsets.fromLTRB(
              T.pageMargin, 12, T.pageMargin, T.scrollBottom),
          children: [
            for (final p in t.pools)
              Padding(
                padding: const EdgeInsets.only(bottom: T.gapCard),
                child: _PoolCard(pool: p, league: widget.league),
              ),
            if (t.series != null) _SeriesCard(series: t.series!),
          ],
        ),
      ),
    );
  }

  // ═══════════════ 12b / 12c · draw / seeded bracket columns ═══════════════
  Widget _drawBody() {
    // region buckets → region chips (12c). Distinct non-empty bracket tags.
    final regions = <String>[];
    for (final r in t.rounds) {
      for (final m in r.matchups) {
        final b = m.bracket;
        if (b != null && b.isNotEmpty && !regions.contains(b)) regions.add(b);
      }
    }
    final hasRegions = regions.length > 1;
    _region ??= hasRegions ? regions.first : null;

    var rounds = t.rounds;
    if (hasRegions && _region != null) {
      rounds = [
        for (final r in t.rounds)
          TournamentRound(
            round: r.round,
            label: r.label,
            matchups: r.matchups
                .where((m) => m.bracket == null || m.bracket == _region)
                .toList(growable: false),
          )
      ].where((r) => r.matchups.isNotEmpty).toList(growable: false);
    }

    Widget? chips;
    if (hasRegions) {
      chips = _PillChips(
        labels: regions,
        selected: regions.indexOf(_region!),
        onTap: (i) => setState(() => _region = regions[i]),
      );
    } else if (rounds.length > 1) {
      chips = _PillChips(
        labels: _roundChipLabels(rounds),
        selected: _chip.clamp(0, rounds.length - 1),
        onTap: _jumpToColumn,
      );
    }

    return _Shell(
      title: t.title,
      subtitle: t.subtitle,
      label: _label,
      chips: chips,
      body: Expanded(
        child: _RoundScroller(
          rounds: rounds,
          controller: _drawScroll,
          cardWidth: _hasSets ? 172 : 150,
          columnKeys: _colKeys,
          onTapMatchup: widget.onTapMatchup,
        ),
      ),
    );
  }

  void _jumpToColumn(int i) {
    setState(() => _chip = i);
    final ctx = _colKeys[i]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 300),
          alignment: 0.02,
          curve: Curves.easeOut);
    }
  }

  List<String> _roundChipLabels(List<TournamentRound> rounds) {
    var q = 0;
    return [
      for (final r in rounds)
        r.round == 'qualifying'
            ? 'Q${++q}'
            : _roundShort(r.round, r.label),
    ];
  }
}

// ═══════════════════════════ shell ═══════════════════════════
/// The constant tournament shell: back chevron + label header, a 64px circular
/// crest, the Barlow title + dim subtitle, an optional chip strip, then [body].
/// [body] is expected to be an [Expanded] (or fixed) child of the Column.
class _Shell extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String label;
  final Widget? chips;
  final Widget body;
  const _Shell({
    required this.title,
    required this.label,
    required this.body,
    this.subtitle,
    this.chips,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // label header row
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, T.pageMargin, 0),
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  size: 18, color: T.textDim),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Text(label.toUpperCase(),
                  style: T.cardLabel.copyWith(letterSpacing: 0.6)),
            ),
          ]),
        ),
        // crest + title
        Padding(
          padding: const EdgeInsets.fromLTRB(T.pageMargin, 8, T.pageMargin, 6),
          child: Row(children: [
            TintedAvatar(_initials(title), _idColor(title), size: 64),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title.toUpperCase(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: T.pageTitle.copyWith(height: 0.98)),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: T.caption),
                  ],
                ],
              ),
            ),
          ]),
        ),
        if (chips != null) ...[
          const SizedBox(height: 6),
          chips!,
        ],
        body,
      ],
    );
  }
}

// ═══════════════════════════ chip strips ═══════════════════════════
/// Group-letter chips — 36px rounded squares (12a). Selected is inverted.
class _GroupChips extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onTap;
  const _GroupChips(
      {required this.labels, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 36,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: T.pageMargin),
          itemCount: labels.length,
          separatorBuilder: (_, __) => const SizedBox(width: T.chipGap),
          itemBuilder: (_, i) {
            final on = i == selected;
            return GestureDetector(
              onTap: () => onTap(i),
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? T.invertedBg : null,
                  border: on ? null : Border.all(color: T.border, width: 1.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(labels[i],
                    style: TextStyle(
                        fontFamily: 'BarlowCondensed',
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: on ? T.invertedText : T.textDim)),
              ),
            );
          },
        ),
      );
}

/// Round / region pill chips (12b/12c). Selected is inverted.
class _PillChips extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onTap;
  const _PillChips(
      {required this.labels, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 34,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: T.pageMargin),
          itemCount: labels.length,
          separatorBuilder: (_, __) => const SizedBox(width: T.chipGap),
          itemBuilder: (_, i) {
            final on = i == selected;
            return GestureDetector(
              onTap: () => onTap(i),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 13),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? T.invertedBg : null,
                  border: on ? null : Border.all(color: T.border, width: 1.5),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(labels[i],
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                        color: on ? T.invertedText : T.textDim)),
              ),
            );
          },
        ),
      );
}

// ═══════════════════════════ 12a group table card ═══════════════════════════
class _GroupCard extends StatelessWidget {
  final TournamentGroup group;
  final String? qualTag;
  final String? league;
  const _GroupCard({required this.group, this.qualTag, this.league});

  @override
  Widget build(BuildContext context) {
    final rows = _ranked(group.rows);
    final cut = rows.where(_qualifies).length;
    return Container(
      decoration: BoxDecoration(
          color: T.surface, borderRadius: BorderRadius.circular(T.cardRadius)),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _header(),
        for (var i = 0; i < rows.length; i++) ...[
          if (i == cut && cut > 0 && cut < rows.length) _cutline(),
          _row(context, rows[i], i + 1, i < cut),
        ],
      ]),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(children: [
          const SizedBox(width: 18),
          Expanded(
              child: Text(group.label.toUpperCase(),
                  style: T.cardLabelFaint.copyWith(fontSize: 10))),
          _hCell('P'),
          _hCell('GD'),
          _hCell('PTS', bright: true),
          const SizedBox(width: 34),
        ]),
      );

  Widget _hCell(String s, {bool bright = false}) => SizedBox(
        width: s == 'GD' ? 30 : 24,
        child: Text(s,
            textAlign: TextAlign.right,
            style: bright
                ? T.cardLabelFaint.copyWith(fontSize: 10, color: T.text)
                : T.cardLabelFaint.copyWith(fontSize: 10)),
      );

  Widget _row(BuildContext context, StandingsRow r, int rank, bool qualified) {
    final band = _bandColor(r.note?.color);
    final gd = r.stats['pointDifferential'] ?? '';
    final body = Container(
      decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: T.divider))),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        SizedBox(
          width: 18,
          child: Text('$rank',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: qualified ? T.green : T.textDim)),
        ),
        if (band != null) ...[
          ColorBar(band, width: 5, height: 16),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(r.team.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: T.listText.copyWith(
                  fontWeight: qualified ? FontWeight.w700 : FontWeight.w400,
                  color: qualified ? T.text : T.textDim)),
        ),
        _cell(r.stats['gamesPlayed'] ?? '', width: 24, color: T.textDim),
        _cell(gd, width: 30, color: _signedColor(gd)),
        SizedBox(
          width: 24,
          child: Text(r.stats['points'] ?? '',
              textAlign: TextAlign.right, style: T.statLineStrong),
        ),
        SizedBox(
          width: 34,
          child: (qualified && qualTag != null)
              ? Text(qualTag!,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: T.green))
              : const SizedBox.shrink(),
        ),
      ]),
    );
    if (league == null || r.team.id.isEmpty) return body;
    return InkWell(
      onLongPress: () => showTeamFollowSheet(
        context,
        league: league!,
        teamId: r.team.id,
        name: r.team.name,
        abbr: r.team.abbr,
      ),
      child: body,
    );
  }

  Widget _cell(String v, {required double width, Color color = T.textDim}) =>
      SizedBox(
        width: width,
        child: Text(v,
            textAlign: TextAlign.center,
            style: T.statLine.copyWith(color: color)),
      );

  Widget _cutline() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: CustomPaint(
          size: const Size(double.infinity, 2),
          painter: _DashedGreenLine(),
        ),
      );

  bool _qualifies(StandingsRow r) {
    final d = r.note?.description?.toLowerCase() ?? '';
    return d.contains('advance') && !d.contains('best');
  }

  List<StandingsRow> _ranked(List<StandingsRow> rows) {
    if (!rows.any((r) => r.rank != null)) return rows;
    return List.of(rows)
      ..sort((a, b) => (a.rank ?? 1 << 20).compareTo(b.rank ?? 1 << 20));
  }
}

/// The dashed green qualification cut-line (§2.7).
class _DashedGreenLine extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const dash = 8.0, gap = 6.0;
    final paint = Paint()
      ..color = T.green.withValues(alpha: 0.55)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    var x = 0.0;
    final y = size.height / 2;
    while (x < size.width) {
      canvas.drawLine(
          Offset(x, y), Offset((x + dash).clamp(0, size.width), y), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_DashedGreenLine old) => false;
}

// ═══════════════════════════ round columns (12a knockout / 12b / 12c) ═══════════
/// A horizontal scroller of round columns, each a stack of matchup cards.
class _RoundScroller extends StatelessWidget {
  final List<TournamentRound> rounds;
  final ScrollController controller;
  final double cardWidth;
  final Map<int, GlobalKey>? columnKeys;
  final void Function(TournamentMatchup)? onTapMatchup;
  const _RoundScroller({
    required this.rounds,
    required this.controller,
    required this.cardWidth,
    this.columnKeys,
    this.onTapMatchup,
  });

  @override
  Widget build(BuildContext context) {
    if (rounds.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      controller: controller,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(T.pageMargin, 2, T.pageMargin, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rounds.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            _RoundColumn(
              key: columnKeys?.putIfAbsent(i, () => GlobalKey()),
              round: rounds[i],
              width: cardWidth,
              gold: i == rounds.length - 1,
              onTapMatchup: onTapMatchup,
            ),
          ],
        ],
      ),
    );
  }
}

class _RoundColumn extends StatelessWidget {
  final TournamentRound round;
  final double width;
  final bool gold;
  final void Function(TournamentMatchup)? onTapMatchup;
  const _RoundColumn({
    super.key,
    required this.round,
    required this.width,
    required this.gold,
    this.onTapMatchup,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(round.label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: T.cardLabelFaint.copyWith(
                    fontSize: 10,
                    color: gold ? T.gold : T.textFaint,
                    letterSpacing: 0.6)),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (var i = 0; i < round.matchups.length; i++)
                    Padding(
                      padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
                      child: _MatchupCard(
                        matchup: round.matchups[i],
                        gold: gold,
                        onTap: onTapMatchup,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One matchup card — two competitor rows. Renders a seed column when seeds are
/// present, set scores when sets are present, else a plain score / start-date.
class _MatchupCard extends StatelessWidget {
  final TournamentMatchup matchup;
  final bool gold;
  final void Function(TournamentMatchup)? onTap;
  const _MatchupCard({required this.matchup, this.gold = false, this.onTap});

  bool get _seeded => matchup.competitors.any((c) => c.seed != null);
  bool get _hasSets => matchup.competitors.any((c) => c.sets.isNotEmpty);

  /// Bar colors aligned to [cs], cache-preferred with the two-sided a11y guard.
  List<Color> _barColors(List<TournamentSide> cs) {
    final raw = [
      for (final s in cs) _sideColor(s.id, s.abbr ?? s.shortName ?? s.name),
    ];
    return cs.length == 2 ? _pairBars(raw[0], raw[1]) : raw;
  }

  @override
  Widget build(BuildContext context) {
    final cs = matchup.competitors;
    final winner = _winnerOf(cs);
    final barColors = _barColors(cs);
    final card = Container(
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(11),
        border: gold
            ? Border.all(color: T.gold.withValues(alpha: 0.3))
            : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < cs.length; i++) ...[
          if (i > 0)
            Container(
              height: 1,
              margin: const EdgeInsets.symmetric(vertical: 2),
              color: T.track,
            ),
          _sideRow(cs[i], winner, barColors[i]),
        ],
      ]),
    );
    final resolvable = onTap != null &&
        (matchup.competitionId != null || matchup.eventId.isNotEmpty);
    if (!resolvable) return card;
    return InkWell(
      borderRadius: BorderRadius.circular(11),
      onTap: () => onTap!(matchup),
      child: card,
    );
  }

  Widget _sideRow(TournamentSide s, TournamentSide? winner, Color barColor) {
    final win = s.winner;
    final dim = winner != null && !win;
    final nameColor = win ? T.text : (dim ? T.textFaint : T.text);
    final label = s.abbr ?? s.shortName ?? s.name;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        if (_seeded)
          SizedBox(
            width: 17,
            child: s.seed == null
                ? const SizedBox.shrink()
                : Container(
                    width: 15,
                    height: 15,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: win ? T.border : T.track,
                        borderRadius: BorderRadius.circular(4)),
                    child: Text('${s.seed}',
                        style: TextStyle(
                            fontFamily: 'BarlowCondensed',
                            fontWeight: FontWeight.w700,
                            fontSize: 9,
                            color: win ? T.textBody : T.textFaint)),
                  ),
          )
        else if (_hasSets)
          SizedBox(
            width: 16,
            child: Text(s.seed == null ? '' : '${s.seed}',
                style: TextStyle(
                    fontFamily: 'BarlowCondensed',
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                    color: win ? T.textDim : T.textFaint)),
          )
        else ...[
          ColorBar(barColor, width: 5, height: 14),
          const SizedBox(width: 8),
        ],
        Flexible(
          flex: _hasSets ? 3 : 1,
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: win ? FontWeight.w700 : FontWeight.w400,
                  color: nameColor)),
        ),
        const SizedBox(width: 6),
        // Tennis set lines vary in length (best-of-5 goes to 5 sets); a
        // right-aligned scale-down keeps them on one line without overflow,
        // while short scores/dates stay their natural size.
        if (_hasSets)
          Flexible(
            flex: 4,
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: _trailing(s, dim)),
            ),
          )
        else
          _trailing(s, dim),
      ]),
    );
  }

  Widget _trailing(TournamentSide s, bool dim) {
    if (_hasSets) {
      final txt = s.winner
          ? _setPairs(s, matchup.competitors)
          : _setSingles(s.sets);
      return Text(txt,
          maxLines: 1,
          style: TextStyle(
              fontSize: 11,
              color: s.winner ? T.textBody : T.textFaint,
              fontFeatures: const [FontFeature.tabularFigures()]));
    }
    // score, or start-time when scheduled with no score
    if (s.score != null && s.score!.isNotEmpty) {
      return Text(s.score!,
          style: TextStyle(
              fontFamily: 'BarlowCondensed',
              fontWeight: FontWeight.w700,
              fontSize: 14,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: dim ? T.textFaint : T.text));
    }
    if (matchup.phase == 'scheduled' && matchup.date != null) {
      return Text(_dayLabel(matchup.date!),
          style: const TextStyle(fontSize: 11, color: T.textFaint));
    }
    return const SizedBox.shrink();
  }
}

TournamentSide? _winnerOf(List<TournamentSide> cs) {
  for (final c in cs) {
    if (c.winner) return c;
  }
  return null;
}

// ═══════════════════════════ 12d pool card ═══════════════════════════
class _PoolCard extends StatelessWidget {
  final TournamentPool pool;
  final String? league;
  const _PoolCard({required this.pool, this.league});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: T.surface, borderRadius: BorderRadius.circular(T.cardRadius)),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(pool.label.toUpperCase(),
            style: T.cardLabelFaint.copyWith(
                fontSize: 11, letterSpacing: 0.8)),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: Text('TEAM', style: T.cardLabelFaint.copyWith(fontSize: 10))),
          SizedBox(
              width: 48,
              child: Text('W–L',
                  textAlign: TextAlign.center,
                  style: T.cardLabelFaint.copyWith(fontSize: 10))),
          SizedBox(
              width: 74,
              child: Text('STATUS',
                  textAlign: TextAlign.right,
                  style: T.cardLabelFaint.copyWith(fontSize: 10))),
        ]),
        const SizedBox(height: 3),
        for (var i = 0; i < pool.rows.length; i++)
          _row(context, pool.rows[i], top: i > 0),
      ]),
    );
  }

  Widget _row(BuildContext context, TournamentPoolRow r, {required bool top}) {
    final out = r.status == 'eliminated';
    final adv = r.status == 'advances';
    final body = Container(
      decoration: top
          ? const BoxDecoration(
              border: Border(top: BorderSide(color: T.divider)))
          : null,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        ColorBar(_sideColor(r.teamId, r.teamName), width: 5, height: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(r.teamName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: T.listText.copyWith(
                  fontWeight: adv ? FontWeight.w700 : FontWeight.w400,
                  color: out ? T.textFaint : (adv ? T.text : T.textDim))),
        ),
        SizedBox(
          width: 48,
          child: Text('${r.w}–${r.l}',
              textAlign: TextAlign.center,
              style: T.statLineStrong.copyWith(
                  fontSize: 14, color: out ? T.textFaint : T.text)),
        ),
        SizedBox(
          width: 74,
          child: Text(_statusLabel(r.status),
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: adv
                      ? T.green
                      : out
                          ? T.live
                          : T.textDim)),
        ),
      ]),
    );
    if (league == null || r.teamId.isEmpty) return body;
    return InkWell(
      onLongPress: () => showTeamFollowSheet(
        context,
        league: league!,
        teamId: r.teamId,
        name: r.teamName,
        color: _sideColor(r.teamId, r.teamName),
      ),
      child: body,
    );
  }

  static String _statusLabel(String s) => switch (s) {
        'advances' => 'ADVANCES',
        'eliminated' => 'OUT',
        _ => 'ALIVE',
      };
}

// ═══════════════════════════ 12d championship series card ═══════════════════════
class _SeriesCard extends StatelessWidget {
  final TournamentSeries series;
  const _SeriesCard({required this.series});

  @override
  Widget build(BuildContext context) {
    final a = series.competitors.isNotEmpty ? series.competitors[0] : null;
    final b = series.competitors.length > 1 ? series.competitors[1] : null;
    final title = series.title?.toUpperCase() ?? 'CHAMPIONSHIP';
    final bestOf = series.total != null ? ' · BEST OF ${series.total}' : '';
    return Container(
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(T.cardRadius),
        border: Border.all(color: T.gold.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$title$bestOf',
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: T.gold)),
        const SizedBox(height: 12),
        if (a != null && b != null) _matchup(a, b),
        if (series.games.isNotEmpty) ...[
          const SizedBox(height: 12),
          _gameChips(),
        ],
      ]),
    );
  }

  Widget _matchup(TournamentSeriesSide a, TournamentSeriesSide b) {
    final aWin = a.wins >= b.wins;
    final bars = _pairBars(
      _sideColor(a.id, a.abbr ?? a.name ?? ''),
      _sideColor(b.id, b.abbr ?? b.name ?? ''),
    );
    return Row(children: [
      ColorBar(bars[0], width: 8, height: 24, radius: 2),
      const SizedBox(width: 9),
      Text((a.abbr ?? a.name ?? '').toUpperCase(),
          style: T.heroName.copyWith(
              fontSize: 20, color: aWin ? T.text : T.textDim)),
      const Spacer(),
      Text('${a.wins}–${b.wins}',
          style: T.heroName.copyWith(fontSize: 22)),
      const Spacer(),
      Text((b.abbr ?? b.name ?? '').toUpperCase(),
          style: T.heroName.copyWith(
              fontSize: 20, color: !aWin ? T.text : T.textDim)),
      const SizedBox(width: 9),
      ColorBar(bars[1], width: 8, height: 24, radius: 2),
    ]);
  }

  Widget _gameChips() {
    return Row(children: [
      for (var i = 0; i < series.games.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(child: _chip(series.games[i])),
      ],
    ]);
  }

  Widget _chip(TournamentSeriesGame g) {
    final scheduled = g.phase == 'scheduled';
    final win = _winner(g);
    final body = scheduled
        ? (g.date != null ? _dayLabel(g.date!) : 'Upcoming')
        : win != null
            ? '${(win.abbr ?? '').toUpperCase()} ${_scoreline(g)}'
            : _scoreline(g);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: scheduled
            ? T.gold.withValues(alpha: 0.1)
            : const Color(0xFF1E232C),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(children: [
        Text('GAME ${g.gameNumber ?? '?'}',
            style: TextStyle(
                fontSize: 9,
                letterSpacing: 0.5,
                fontWeight: FontWeight.w600,
                color: scheduled ? T.gold : T.textFaint)),
        const SizedBox(height: 3),
        Text(body,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: scheduled ? T.gold : T.text,
                fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
    );
  }

  TournamentSeriesGameSide? _winner(TournamentSeriesGame g) {
    for (final s in g.sides) {
      if (s.winner) return s;
    }
    return null;
  }

  String _scoreline(TournamentSeriesGame g) =>
      g.sides.map((s) => s.score ?? '').where((s) => s.isNotEmpty).join('–');
}

// ═══════════════════════════ small helpers ═══════════════════════════
/// A stable, presentational identity color from a seed id — tournament data
/// carries no team colors, so bars derive a consistent hue (not real identity).
Color _idColor(String seed) {
  if (seed.isEmpty) return T.border;
  const palette = [
    Color(0xFF6CA7E0),
    Color(0xFFE5484D),
    Color(0xFF3FA96B),
    Color(0xFFE8B923),
    Color(0xFFB07AD6),
    Color(0xFF4EC0C0),
    Color(0xFFE0844A),
    Color(0xFF7BAFD4),
  ];
  var h = 0;
  for (final c in seed.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return palette[h % palette.length];
}

/// The bar color for a tournament side (§3.1): prefer the REAL identity color
/// from the assets cache when the side carries a team id, else the stable
/// presentational hash. Tournament payloads carry no colors, so this is how a
/// bracket bar gets a team's actual color when we've seen it on a scoreboard.
Color _sideColor(String id, String fallbackSeed) =>
    cachedTeamColor(id) ?? _idColor(id.isNotEmpty ? id : fallbackSeed);

/// Two side-bar colors with the §3.1 a11y guard: when the pair would read as one
/// identity (indistinguishable real colors, or a hash collision), BOTH fall back
/// to a neutral rail so the tricode label carries the distinction — never two
/// same-looking bars.
List<Color> _pairBars(Color a, Color b) =>
    colorsTooClose(a, b) ? const [T.outline, T.outline] : [a, b];

/// Up to three uppercase initials from a title ("FIFA World Cup" → "FWC").
String _initials(String title) {
  final words = title
      .split(RegExp(r'[\s·]+'))
      .where((w) => w.isNotEmpty && RegExp(r'[A-Za-z0-9]').hasMatch(w))
      .toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) {
    final w = words.first;
    return (w.length <= 3 ? w : w.substring(0, 3)).toUpperCase();
  }
  return words.take(3).map((w) => w[0]).join().toUpperCase();
}

/// Parse an ESPN band hex ('#81D6AC') to a Color; null when not a 6-digit hex.
Color? _bandColor(String? s) {
  if (s == null) return null;
  final h = s.replaceAll('#', '').trim();
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

Color _signedColor(String v) {
  if (RegExp(r'^\+').hasMatch(v)) return T.green;
  if (RegExp(r'^[-−]').hasMatch(v)) return T.live;
  return T.textDim;
}

/// A short round label from the canonical key, falling back to the raw label.
String _roundShort(String? key, String label) => switch (key) {
      'roundOf128' => 'R128',
      'roundOf64' => 'R64',
      'roundOf32' => 'R32',
      'roundOf16' => 'R16',
      'quarterfinal' => 'QF',
      'semifinal' => 'SF',
      'final' => 'Final',
      'thirdPlace' => '3rd',
      _ => label.length <= 6 ? label : label.substring(0, 6),
    };

/// 'Sat' / 'Jul 12' for a matchup date (winner-less scheduled slot).
String _dayLabel(DateTime d) {
  const wk = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final now = DateTime.now();
  final soon = d.difference(now).inDays.abs() < 6;
  if (soon) return wk[(d.weekday - 1) % 7];
  const mo = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${mo[d.month - 1]} ${d.day}';
}

/// Winner set line as 'w-l' pairs (with the losing tiebreak parenthesised):
/// zips the winner's per-set games against the loser's. Bright.
String _setPairs(TournamentSide winner, List<TournamentSide> all) {
  final loser = all.firstWhere((c) => !identical(c, winner),
      orElse: () => winner);
  final ws = winner.sets, ls = loser.sets;
  final n = ws.length < ls.length ? ws.length : ls.length;
  final parts = <String>[];
  for (var i = 0; i < n; i++) {
    final w = ws[i].value, l = ls[i].value;
    if (w == null || l == null) continue;
    final tb = ls[i].tiebreak ?? ws[i].tiebreak;
    parts.add(tb != null ? '$w-$l($tb)' : '$w-$l');
  }
  return parts.isEmpty ? _setSingles(ws) : parts.join(' ');
}

/// Loser / live set line — just the side's own per-set game counts. Dim.
String _setSingles(List<TournamentSet> sets) =>
    sets.map((s) => '${s.value ?? ''}').where((s) => s.isNotEmpty).join(' ');

// ─────────────────────────── round vocabulary ───────────────────────────
// Tennis draw rounds parsed from ESPN's round.displayName. Shared with the
// Scores list's per-tournament summary row (league_card.dart).

/// A sortable depth for a draw round — Final highest, qualifying below the main
/// draw. Used to order tournament sections and to pick a tournament's "furthest
/// round" for the summary row.
int tennisRoundRank(String? round) {
  final r = (round ?? '').toLowerCase();
  if (r.isEmpty) return 0;
  final qualifying = r.contains('qualif');
  int base;
  if (r.contains('final') && !r.contains('semi') && !r.contains('quarter')) {
    base = (r.contains('3rd') || r.contains('third')) ? 95 : 100;
  } else if (r.contains('semi')) {
    base = 90;
  } else if (r.contains('quarter')) {
    base = 80;
  } else {
    final ro = RegExp(r'round of (\d+)').firstMatch(r);
    if (ro != null) {
      // deeper "Round of N" = later round = lower depth (R16 > R32 > R64).
      final n = int.tryParse(ro.group(1)!) ?? 64;
      base = 78 - n ~/ 8; // R16→76, R32→74, R64→70, R128→62
    } else {
      final n = RegExp(r'(\d+)').firstMatch(r);
      base = 20 + (n != null ? (int.tryParse(n.group(1)!) ?? 0) : 0);
    }
  }
  // Qualifying always ranks below the main draw, but still ordered internally.
  return qualifying ? base - 200 : base;
}

/// A compact label for a draw round — "Final", "SF", "QF", "R16", "Qual".
/// Qualifying is checked first so "Qualifying Final" reads "Qual", not "Final".
String tennisRoundAbbr(String? round) {
  final r = (round ?? '').toLowerCase();
  if (r.isEmpty) return '';
  if (r.contains('qualif')) return 'Qual';
  if (r.contains('final') && !r.contains('semi') && !r.contains('quarter')) {
    return (r.contains('3rd') || r.contains('third')) ? '3rd Place' : 'Final';
  }
  if (r.contains('semi')) return 'SF';
  if (r.contains('quarter')) return 'QF';
  final ro = RegExp(r'round of (\d+)').firstMatch(r);
  if (ro != null) return 'R${ro.group(1)}';
  final n = RegExp(r'(\d+)').firstMatch(r);
  if (n != null) return 'R${n.group(1)}';
  return round!;
}

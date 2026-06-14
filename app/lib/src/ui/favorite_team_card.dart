import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import 'game_detail_page.dart';
import 'scores_page.dart' show GameCard;
import 'widgets.dart';

/// A favorite team's glanceable card for the top of the Scores tab.
///
/// - A LIVE game → the full [GameCard] (identical to the league feed).
/// - Otherwise → a compact card: team header, then the last result and the next
///   game, each tapping into the game detail.
/// - Offseason / error → a calm muted line.
class FavoriteTeamCard extends StatelessWidget {
  final FavoriteTeamFeed feed;
  const FavoriteTeamCard({super.key, required this.feed});

  @override
  Widget build(BuildContext context) {
    final card = feed.card;
    // Live: reuse the league GameCard wholesale.
    if (card?.live != null) {
      return GameCard(
        event: card!.live!,
        sport: card.sport,
        leagueKey: card.league,
        leagueName: card.leagueName,
      );
    }

    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: BinanceColors.of(context).cardBorder, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(14, 12, 14, card == null ? 12 : 8),
            child: _header(context),
          ),
          if (feed.error != null)
            _muted(context, 'Couldn\'t load')
          else if (card == null)
            _muted(context, 'Loading…')
          else ...[
            if (card.last != null) _gameRow(context, card, card.last!, isLast: true),
            if (card.next != null) _gameRow(context, card, card.next!, isLast: false),
            if (card.last == null && card.next == null)
              _muted(context, 'No recent or upcoming games'),
          ],
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = feed.card?.team;
    final name = t?.displayName ?? feed.fav.name;
    final logo = t?.logo ?? feed.fav.logo;
    final logoDark = t?.logoDark;
    final record = t?.record;
    return Row(
      children: [
        Crest(url: logo, darkUrl: logoDark, fallback: t?.abbreviation ?? feed.fav.abbr ?? name, size: 28),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        if (record != null && record.isNotEmpty)
          Text(record, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ],
    );
  }

  /// One "Last"/"Next" line. Tapping opens the game detail.
  Widget _gameRow(BuildContext context, TeamCard card, SportEvent ev, {required bool isLast}) {
    final cs = Theme.of(context).colorScheme;
    final ext = BinanceColors.of(context);
    final comp = ev.main;
    final fav = _favComp(comp, card.team.id);
    final opp = _opp(comp, fav);

    final oppName = opp == null ? '' : (opp.abbreviation ?? opp.shortName ?? opp.displayName);
    final vs = fav?.homeAway == 'away' ? '@' : 'vs';
    final oppText = oppName.isEmpty ? '' : '$vs $oppName';

    // The middle column: result + score for a finished game, or the kickoff time
    // for an upcoming one.
    final List<Widget> middle;
    if (isLast && comp != null) {
      final (letter, color) = _result(comp, fav, opp, cs, ext);
      middle = [
        Text(letter, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
        if (comp.scoreKind != 'none') ...[
          const SizedBox(width: 8),
          Text(
            '${fav?.score?.display ?? '–'}–${opp?.score?.display ?? '–'}',
            style: numStyle(size: 15, weight: FontWeight.w700, color: cs.onSurface),
          ),
        ],
      ];
    } else {
      middle = [
        Text(
          comp == null ? '' : statusLabel(comp.status, ev.start),
          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: cs.onSurface),
        ),
      ];
    }

    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => GameDetailPage(
          event: ev,
          sport: card.sport,
          leagueKey: card.league,
          leagueName: card.leagueName,
        ),
      )),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Text(isLast ? 'Last' : 'Next',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
            ),
            const SizedBox(width: 6),
            ...middle,
            const Spacer(),
            Flexible(
              child: Text(
                oppText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _muted(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Text(text, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
    );
  }

  /// The favorite's competitor within a competition (by id; abbr fallback).
  Competitor? _favComp(Competition? comp, String teamId) {
    if (comp == null) return null;
    for (final c in comp.competitors) {
      if (c.id == teamId) return c;
    }
    return comp.competitors.isNotEmpty ? comp.competitors.first : null;
  }

  Competitor? _opp(Competition? comp, Competitor? fav) {
    if (comp == null || fav == null) return null;
    for (final c in comp.competitors) {
      if (!identical(c, fav)) return c;
    }
    return null;
  }

  /// Result letter + color from the favorite's perspective: W (up), L (down),
  /// D for a draw, – when undecided.
  (String, Color) _result(Competition comp, Competitor? fav, Competitor? opp, ColorScheme cs, BinanceColors ext) {
    if (fav?.winner == true) return ('W', ext.formWin);
    if (opp?.winner == true) return ('L', ext.formLoss);
    if (comp.status.isFinal) return ('D', cs.onSurfaceVariant);
    return ('–', cs.onSurfaceVariant);
  }
}

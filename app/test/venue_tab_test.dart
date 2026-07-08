import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scores/src/models.dart';
import 'package:scores/src/providers.dart';
import 'package:scores/src/theme.dart';
import 'package:scores/src/ui/game_detail_page.dart';

/// Matches a bare [RichText] (a `_FactCell` value / the TONIGHT attendance) by
/// its flattened plain text — `find.text` only matches [Text]/[EditableText].
Finder richText(String s) => find.byWidgetPredicate(
    (w) => w is RichText && w.text.toPlainText() == s);

Widget wrap(Widget child, List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: buildV2Theme(),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(T.pageMargin),
            child: child,
          ),
        ),
      ),
    );

SportEvent stadiumEvent() => SportEvent.fromJson({
      'id': '1',
      'name': 'Brewers at Cubs',
      'shortName': 'MIL @ CHC',
      'venue': {'name': 'Wrigley Field', 'city': 'Chicago', 'indoor': false},
      'weather': {'temperature': 72, 'condition': 'Clear'},
      'competitions': [
        {
          'id': '1',
          'layout': 'headToHead',
          'scoreKind': 'numeric',
          'competitorKind': 'team',
          'attendance': 38551,
          'status': <String, dynamic>{},
          'periods': <String, dynamic>{},
        }
      ],
    });

SportEvent racingEvent() => SportEvent.fromJson({
      'id': '2',
      'name': 'Belgian Grand Prix',
      'shortName': 'Belgian GP',
      'competitions': [
        {
          'id': '2',
          'layout': 'field',
          'scoreKind': 'numeric',
          'competitorKind': 'athlete',
          'status': <String, dynamic>{},
          'periods': <String, dynamic>{},
        }
      ],
    });

void main() {
  // ── the gate: venue vs circuit vs hidden, by data presence (never sport) ──
  test('venueTabKind: circuit id → Circuit, venue id → Venue, neither → none',
      () {
    expect(venueTabKind(venueId: '43', circuitId: null), VenueTabKind.venue);
    expect(venueTabKind(venueId: null, circuitId: '616'), VenueTabKind.circuit);
    // circuit wins (a racing event also carries a circuit-derived venue).
    expect(venueTabKind(venueId: '43', circuitId: '616'), VenueTabKind.circuit);
    expect(venueTabKind(venueId: null, circuitId: null), VenueTabKind.none);
    // empty strings are treated as absent.
    expect(venueTabKind(venueId: '', circuitId: ''), VenueTabKind.none);
  });

  // ── VENUE fact grid (14a): served cells only, + the TONIGHT card ──
  testWidgets('VenueTab renders the fact grid + TONIGHT from facts + cheap data',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final event = stadiumEvent();
    final facts = VenueFacts.fromJson({
      'id': '43',
      'name': 'Wrigley Field',
      'city': 'Chicago',
      'state': 'IL',
      // a raster photo so Image.network (faked in tests) is exercised, not SVG.
      'photo': 'https://a.espncdn.com/i/venues/mlb/day/43.jpg',
      'surface': 'grass',
      'roof': 'open',
    });

    await tester.pumpWidget(wrap(
      VenueTab(
          league: 'baseball/mlb',
          event: event,
          comp: event.main!,
          venueId: '43'),
      [venueFactsProvider.overrideWith((ref, key) async => facts)],
    ));
    await tester.pump(); // resolve the facts future
    await tester.pump();

    // fact-cell labels (plain Text) prove each served cell renders…
    expect(find.text('SURFACE'), findsOneWidget);
    expect(find.text('ROOF'), findsOneWidget);
    expect(find.text('ATTENDANCE'), findsOneWidget);
    expect(find.text('WEATHER'), findsOneWidget);
    // …and their values (RichText) carry the derived strings.
    expect(richText('GRASS'), findsOneWidget);
    expect(richText('OPEN AIR'), findsOneWidget);
    expect(richText('38,551'), findsOneWidget);

    // address footer (city·state, upper-cased) + the TONIGHT card.
    expect(find.text('CHICAGO, IL'), findsOneWidget);
    expect(find.text('TONIGHT'), findsOneWidget);
    expect(find.text('72° · Clear'), findsOneWidget);
    expect(richText('38,551 ATT'), findsOneWidget);
  });

  testWidgets('VenueTab hides absent cells cleanly (no facts → no surface cell)',
      (tester) async {
    final event = stadiumEvent();
    await tester.pumpWidget(wrap(
      // no venueId → no facts fetch → surface/photo absent, cheap cells stay.
      VenueTab(league: 'baseball/mlb', event: event, comp: event.main!),
      const [],
    ));
    await tester.pump();

    expect(find.text('SURFACE'), findsNothing); // core-only, absent
    expect(find.text('ATTENDANCE'), findsOneWidget); // cheap, present
    expect(find.text('VENUE PHOTO'), findsOneWidget); // placeholder well
  });

  // ── CIRCUIT fact grid + lap record (13a) ──
  testWidgets('CircuitTab renders map footer, fact grid, and the lap record',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final event = racingEvent();
    final facts = CircuitFacts.fromJson({
      'id': '616',
      'name': 'Circuit de Spa-Francorchamps',
      'city': 'Stavelot',
      'country': 'Belgium',
      // raster so the Image.network path (faked) runs, not SvgPicture.network.
      'diagram': 'https://a.espncdn.com/i/venues/f1/circuit/257.jpg',
      'direction': 'Clockwise',
      'established': 1950,
      'length': {'display': '7.004 km', 'value': 7.004, 'unit': 'km'},
      'distance': {'display': '308.052 km', 'value': 308.052, 'unit': 'km'},
      'laps': 44,
      'turns': 19,
      'fastestLap': {
        'time': '1:44.701',
        'year': 2024,
        'driver': {'name': 'Sergio Pérez', 'headshot': ''},
      },
    });

    await tester.pumpWidget(wrap(
      CircuitTab(
          league: 'racing/f1',
          event: event,
          comp: event.main!,
          circuitId: '616'),
      [circuitFactsProvider.overrideWith((ref, key) async => facts)],
    ));
    await tester.pump();
    await tester.pump();

    // map footer
    expect(find.text('CLOCKWISE'), findsOneWidget);
    expect(find.text('Est. 1950'), findsOneWidget);

    // fact grid — labels + value/unit split
    expect(find.text('CIRCUIT LENGTH'), findsOneWidget);
    expect(find.text('RACE DISTANCE'), findsOneWidget);
    expect(find.text('LAPS'), findsOneWidget);
    expect(find.text('TURNS'), findsOneWidget);
    expect(richText('7.004 KM'), findsOneWidget);
    expect(richText('44'), findsOneWidget);
    expect(richText('19'), findsOneWidget);

    // lap record card
    expect(find.text('LAP RECORD'), findsOneWidget);
    expect(find.text('1:44.701'), findsOneWidget);
    expect(find.text('Sergio Pérez'), findsOneWidget);
    expect(find.text('2024'), findsOneWidget);
  });
}

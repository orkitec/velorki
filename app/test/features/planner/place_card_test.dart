import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/permissions/location_permission.dart';
import 'package:velorki/features/map/application/map_stops_controller.dart';
import 'package:velorki/features/map/data/map_preferences.dart';
import 'package:velorki/features/map/data/position_provider.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/domain/route_waypoints.dart';
import 'package:velorki/features/planner/presentation/planner_screen.dart';
import 'package:velorki/features/planner/presentation/route_format.dart';
import 'package:velorki/features/search/domain/search_result.dart';
import 'package:velorki/features/search/presentation/place_card.dart';
import 'package:velorki/features/search/presentation/search_field.dart';
import 'package:velorki/features/settings/data/units.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';
import '../assistant/support/fakes.dart';
import 'support/fakes.dart';
import 'support/pump.dart';

const LatLng _a = LatLng(48.0, 11.0);
const LatLng _b = LatLng(48.02, 11.0);
const LatLng _c = LatLng(48.04, 11.0);

/// Where the rider is, when the test says the position is known.
const LatLng _rider = LatLng(47.99, 11.0);

/// A cafe beside the first leg of a route through [_a], [_b] and [_c].
const SearchResult _cafe = SearchResult(
  name: 'Café Rad',
  position: LatLng(48.01, 11.001),
  city: 'Musterdorf',
  source: SearchSource.local,
  kind: SearchKind.poi,
  detail: 'cafe',
);

/// An unnamed tap, beside the last leg.
const SearchResult _tap = SearchResult(
  name: '',
  position: LatLng(48.03, 10.999),
  source: SearchSource.local,
  kind: SearchKind.poi,
  detail: 'drinking_water',
);

/// Overrides that make the rider's position known: [_rider].
final List<Override> _positionKnown = [
  locationPermissionGatewayProvider.overrideWithValue(
    const GrantedLocationPermission(),
  ),
  positionSourceProvider.overrideWithValue(const FixedPositionSource(_rider)),
];

/// The Plan tab with the stops [_cafe] and [_tap] drawn on its map.
Future<PlannerHarness> _pumpWithStops(
  WidgetTester tester, {
  bool positionKnown = true,
  Size surfaceSize = const Size(1000, 2000),
}) async {
  final h = await pumpScreen(
    tester,
    const PlannerScreen(),
    harness: PlannerHarness(backend: LineRoutingBackend()),
    surfaceSize: surfaceSize,
    extraOverrides: [
      mapStopsFinderProvider.overrideWithValue(
        (box, kinds, limit, {near}) async => const [_cafe, _tap],
      ),
      if (positionKnown) ..._positionKnown,
    ],
  );
  h.map
    ..zoom = 14
    ..visibleBounds = const BoundingBox(
      south: 47.98,
      west: 10.95,
      north: 48.06,
      east: 11.05,
    );
  await _container(tester)
      .read(mapStopsPreferencesProvider.notifier)
      .setShown(true);
  await tester.pump();
  await tester.pump(stopsDebounce * 2);
  await tester.pumpAndSettle();
  expect(h.map.stops, hasLength(2));
  return h;
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(PlannerScreen)));

/// Puts [points] into the plan and lets the route come.
Future<void> _plan(WidgetTester tester, List<LatLng> points) async {
  final planner = _container(tester).read(plannerControllerProvider.notifier);
  for (final p in points) {
    planner.addWaypoint(p);
  }
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

/// Taps [stop] on the map and lets its card come up.
Future<void> _tapStop(
  WidgetTester tester,
  PlannerHarness h,
  SearchResult stop,
) async {
  final index = h.map.stops.indexWhere((s) => s.position == stop.position);
  expect(index, isNonNegative);
  h.map.onStopTapped!(index);
  await tester.pumpAndSettle();
  expect(find.byType(PlaceCard), findsOneWidget);
}

/// Fails when a string on the card had to be cut to fit. Only the card's:
/// under it the planner's own sheet, in the test font, does not fit a phone
/// this narrow (see `expectNoClippedText`).
void _expectCardTextFits(WidgetTester tester) {
  final paragraphs = tester.renderObjectList<RenderParagraph>(
    _inCard(find.byType(RichText)),
  );
  expect(paragraphs, isNotEmpty);
  for (final paragraph in paragraphs) {
    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason: '"${paragraph.text.toPlainText()}" was cut off',
    );
  }
}

Finder _inCard(Finder finder) =>
    find.descendant(of: find.byType(PlaceCard), matching: finder);

List<LatLng> _positions(WidgetTester tester) =>
    _container(tester).read(plannerControllerProvider).positions;

String _distance(WidgetTester tester, double meters) =>
    formatDistance(l10n, _container(tester).read(unitSystemProvider), meters);

void main() {
  testWidgets('a stop on an empty plan: Route here plans from the rider', (
    tester,
  ) async {
    final h = await _pumpWithStops(tester);
    await _tapStop(tester, h, _cafe);

    // What it is, where, and how far from the rider; no route to be off.
    expect(_inCard(find.text('Café Rad')), findsOneWidget);
    expect(
      _inCard(find.text('${gazetteerPoiKindLabel(l10n, 'cafe')} · Musterdorf')),
      findsOneWidget,
    );
    expect(
      _inCard(
        find.text(
          l10n.placeCardFromYou(
            _distance(tester, haversineMeters(_rider, _cafe.position)),
          ),
        ),
      ),
      findsOneWidget,
    );
    expect(
      _inCard(find.textContaining(l10n.placeCardOffRoute('').trim())),
      findsNothing,
    );
    expect(h.map.searchPin, _cafe.position);
    expect(h.map.searchPinLabel, 'Café Rad');
    expect(
      _inCard(find.widgetWithText(FilledButton, l10n.placeCardRouteHere)),
      findsOneWidget,
    );
    expect(
      _inCard(find.widgetWithText(OutlinedButton, l10n.plannerSetAsStart)),
      findsOneWidget,
    );

    await tester.tap(find.text(l10n.placeCardRouteHere));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.byType(PlaceCard), findsNothing);
    expect(_positions(tester), [_rider, _cafe.position]);
    expect(h.map.waypoints.last.label, 'Café Rad');
    expect(h.map.searchPin, isNull);
  });

  testWidgets('a stop on an empty plan: Start here starts the plan there', (
    tester,
  ) async {
    final h = await _pumpWithStops(tester);
    await _tapStop(tester, h, _cafe);

    await tester.tap(find.text(l10n.plannerSetAsStart));
    await tester.pumpAndSettle();

    expect(find.byType(PlaceCard), findsNothing);
    expect(_positions(tester), [_cafe.position]);
    expect(h.map.waypoints.single.label, 'Café Rad');
    expect(h.map.searchPin, isNull);
  });

  testWidgets('a stop with only a start: Destination ends the plan there', (
    tester,
  ) async {
    final h = await _pumpWithStops(tester);
    await _plan(tester, [_a]);
    await _tapStop(tester, h, _cafe);

    expect(
      _inCard(find.widgetWithText(FilledButton, l10n.placeCardDestination)),
      findsOneWidget,
    );
    expect(_inCard(find.text(l10n.placeCardAddStop)), findsNothing);

    await tester.tap(find.text(l10n.placeCardDestination));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(_positions(tester), [_a, _cafe.position]);
    expect(h.map.searchPin, isNull);
  });

  testWidgets('a stop beside a route: Add as a stop takes it in where it '
      'lies, not at the end', (tester) async {
    final h = await _pumpWithStops(tester);
    await _plan(tester, [_a, _b, _c]);
    await _tapStop(tester, h, _cafe);

    // How far off the route it is, beside how far from the rider.
    final route = _container(tester).read(plannerControllerProvider).result!;
    final off = projectOnTrack(route.positions, _cafe.position).distanceM;
    expect(
      _inCard(
        find.textContaining(l10n.placeCardOffRoute(_distance(tester, off))),
      ),
      findsOneWidget,
    );
    expect(
      _inCard(find.widgetWithText(FilledButton, l10n.placeCardAddStop)),
      findsOneWidget,
    );
    expect(
      _inCard(find.widgetWithText(OutlinedButton, l10n.placeCardDestination)),
      findsOneWidget,
    );

    await tester.tap(find.text(l10n.placeCardAddStop));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(_positions(tester), [_a, _cafe.position, _b, _c]);
    expect(h.map.waypoints[1].label, 'Café Rad');
    expect(h.map.searchPin, isNull);
  });

  testWidgets('a stop beside a route: Destination appends it', (tester) async {
    final h = await _pumpWithStops(tester);
    await _plan(tester, [_a, _b, _c]);
    await _tapStop(tester, h, _cafe);

    await tester.tap(find.text(l10n.placeCardDestination));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(_positions(tester), [_a, _b, _c, _cafe.position]);
  });

  testWidgets('closed with its button, the card changes nothing', (
    tester,
  ) async {
    final h = await _pumpWithStops(tester);
    await _plan(tester, [_a, _b, _c]);
    final moves = h.map.calls.where((c) => c.method == 'moveTo').length;
    await _tapStop(tester, h, _tap);
    expect(h.map.searchPin, _tap.position);
    // Brought into view above the card, at the map's own zoom.
    final move = h.map.calls.where((c) => c.method == 'moveTo').toList();
    expect(move, hasLength(moves + 1));
    expect(move.last.arguments[0], _tap.position);
    expect(move.last.arguments[1], isNull);

    await tester.tap(find.byTooltip(l10n.placeCardClose));
    await tester.pumpAndSettle();

    expect(find.byType(PlaceCard), findsNothing);
    expect(h.map.searchPin, isNull);
    expect(_positions(tester), [_a, _b, _c]);
    // The search field was never part of it.
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      isEmpty,
    );
  });

  testWidgets('an unnamed stop is called what it is; with the position '
      'unknown, no distance from the rider', (tester) async {
    final h = await _pumpWithStops(tester, positionKnown: false);
    await _tapStop(tester, h, _tap);

    final kind = gazetteerPoiKindLabel(l10n, 'drinking_water')!;
    expect(_inCard(find.text(kind)), findsOneWidget);
    expect(h.map.searchPinLabel, kind);
    expect(
      _inCard(find.textContaining(l10n.placeCardFromYou('').trim())),
      findsNothing,
    );
    expect(
      _inCard(find.textContaining(l10n.placeCardOffRoute('').trim())),
      findsNothing,
    );
  });

  testWidgets('every line and button of the card fits on a 375x667 phone', (
    tester,
  ) async {
    final h = await _pumpWithStops(tester, surfaceSize: const Size(375, 667));
    await _plan(tester, [_a, _b, _c]);
    await _tapStop(tester, h, _cafe);

    expect(_inCard(find.text(l10n.placeCardAddStop)), findsOneWidget);
    expect(
      _inCard(find.textContaining(l10n.placeCardFromYou('').trim())),
      findsOneWidget,
    );
    _expectCardTextFits(tester);
    // Above the bottom edge, buttons and all.
    expect(
      tester.getBottomLeft(find.text(l10n.placeCardDestination)).dy,
      lessThan(667),
    );

    await tester.tap(find.byTooltip(l10n.placeCardClose));
    await tester.pumpAndSettle();

    _container(tester).read(plannerControllerProvider.notifier).clear();
    await tester.pumpAndSettle();
    await _tapStop(tester, h, _cafe);
    expect(_inCard(find.text(l10n.placeCardRouteHere)), findsOneWidget);
    _expectCardTextFits(tester);
  });
}

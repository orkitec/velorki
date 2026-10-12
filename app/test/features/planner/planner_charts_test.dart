import 'package:fl_chart/fl_chart.dart' show LineChart;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/integrations/common/data/relay_client_provider.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/domain/routing_options.dart';
import 'package:velorki/features/planner/domain/waypoint.dart';
import 'package:velorki/features/planner/presentation/elevation_profile_chart.dart';
import 'package:velorki/features/planner/presentation/planner_screen.dart';
import 'package:velorki/features/shared/presentation/metric_chart.dart';
import 'package:velorki/features/subscription/application/plus_access.dart';
import 'package:velorki/features/weather/application/route_weather_controller.dart';
import 'package:velorki/features/weather/data/dwd_route_forecast.dart';
import 'package:velorki/features/weather/domain/route_weather_state.dart';
import 'package:velorki/features/weather/presentation/route_weather_strip.dart';
import 'package:velorki/features/weather/presentation/route_colour_choice.dart';
import 'package:velorki/features/weather/presentation/weather_keys.dart';
import 'package:velorki/features/map/domain/map_controller.dart';
import 'package:velorki/core/geo/route_gradient.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';
import '../../support/chart_cursor.dart';
import '../../support/mock_relay.dart';
import 'support/fakes.dart';
import '../weather/support/weather_fixtures.dart';
import 'support/pump.dart';

const LatLng _start = LatLng(48, 11);

/// Ten kilometres due north, a point every 500 m.
final RouteResult _route = straightRoute(start: _start);

/// The forecast along [_route], whatever is asked.
class _Weather extends RouteWeatherController {
  @override
  AsyncValue<RouteWeatherState?> build(WeatherRoute route) =>
      AsyncData<RouteWeatherState?>(
        weatherAlong(_route, earliest: DateTime.utc(2026, 10, 11, 8)),
      );
}

/// The planner with [_route] planned, the forecast along it, and the
/// profile and the strip scrolled into view.
Future<PlannerHarness> _pump(WidgetTester tester) async {
  final h = await pumpScreen(
    tester,
    const PlannerScreen(),
    extraOverrides: [
      relayClientProvider.overrideWithValue(MockRelay().client()),
      plusAccessProvider.overrideWith((ref, feature) => PlusAccess.granted),
      routeWeatherControllerProvider.overrideWith2((_) => _Weather()),
    ],
  );
  ProviderScope.containerOf(tester.element(find.byType(PlannerScreen)))
      .read(plannerControllerProvider.notifier)
      .loadComputedRoute(
        result: _route,
        waypoints: [
          Waypoint(pos: _route.geometry.first.pos),
          Waypoint(pos: _route.geometry.last.pos),
        ],
        options: RoutingOptions(),
      );
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byType(RouteWeatherStrip));
  await tester.pumpAndSettle();
  return h;
}

Finder get _profile => find.descendant(
  of: find.byType(ElevationProfileChart),
  matching: find.byType(LineChart),
);

/// Where [share] of the way across the profile's plot is on screen.
Offset _onProfile(WidgetTester tester, double share) {
  final rect = tester.getRect(_profile);
  final chart = tester.widget<MetricChart>(find.byType(MetricChart));
  final left = rect.left + chart.leftReservedSize;
  return Offset(left + (rect.right - left) * share, rect.center.dy);
}

/// Where [share] of the way across the strip's plot is on screen.
Offset _onStrip(WidgetTester tester, double share) {
  final rect = tester.getRect(find.byType(RouteWeatherStrip));
  final left = rect.left + weatherStripLeftInset;
  return Offset(left + (rect.right - left) * share, rect.center.dy);
}

/// How far along [_route] [point] is, and how far off it.
({double along, double off}) _placeOf(LatLng point) => (
  along: haversineMeters(_start, LatLng(point.lat, _start.lon)),
  off: haversineMeters(point, LatLng(point.lat, _start.lon)),
);

Future<void> _pinch(WidgetTester tester, Offset centre) async {
  final a = await tester.createGesture();
  final b = await tester.createGesture();
  await a.down(centre - const Offset(50, 0));
  await b.down(centre + const Offset(50, 0));
  await tester.pump();
  for (var i = 0; i < 10; i++) {
    await a.moveBy(const Offset(-10, 0));
    await b.moveBy(const Offset(10, 0));
    await tester.pump();
  }
  await a.up();
  await b.up();
  await tester.pump(const Duration(milliseconds: 400));
}

/// The handle of the profile's cursor, and of the strip's.
Finder get _profileHandle => find.descendant(
  of: find.byType(ElevationProfileChart),
  matching: chartCursorHandles,
);
Finder get _stripHandle => find.descendant(
  of: find.byType(RouteWeatherStrip),
  matching: chartCursorHandles,
);

void main() {
  testWidgets('the route is coloured by its gradient from the start: on the '
      'map and under the profile, with the choice and its key under the '
      'profile; Off takes it off and the wind draws the wind', (tester) async {
    final h = await _pump(tester);
    List<MapCall> callsOf(String method) =>
        h.map.calls.where((c) => c.method == method).toList();

    // Flat ten kilometres: one grey stretch, on the map and on the chart.
    final drawn = callsOf('setRouteColours');
    expect(drawn, isNotEmpty);
    expect(
      (drawn.last.arguments.single! as List<ColouredSegment>).map(
        (s) => s.colour,
      ),
      [gradientClassColour(GradientClass.flat)],
    );
    List<({double start, double end, Color colour})> bands() => tester
        .widget<ElevationProfileChart>(find.byType(ElevationProfileChart))
        .bands;
    expect(bands(), hasLength(1));
    expect(bands().single.end, closeTo(10000, 1));

    // The choice and the key between the profile and the weather.
    final choice = find.byType(RouteColourChoice);
    expect(
      tester.getTopLeft(choice).dy,
      greaterThan(tester.getBottomLeft(find.byType(ElevationProfileChart)).dy),
    );
    expect(
      tester.getTopLeft(find.byType(GradientColourKey)).dy,
      greaterThan(tester.getBottomLeft(choice).dy),
    );
    expect(
      tester.getTopLeft(find.byType(RouteWeatherStrip)).dy,
      greaterThan(tester.getBottomLeft(find.byType(GradientColourKey)).dy),
    );

    Finder segment(String label) =>
        find.descendant(of: choice, matching: find.text(label));
    await tester.tap(segment(l10n.weatherOverlayOff));
    await tester.pumpAndSettle();
    expect(callsOf('clearRouteColours'), isNotEmpty);
    expect(bands(), isEmpty);
    expect(find.byType(GradientColourKey), findsNothing);

    await tester.tap(segment(l10n.weatherWind));
    await tester.pumpAndSettle();
    expect(callsOf('setRouteWind'), isNotEmpty);
    expect(bands(), isNotEmpty);
  });

  testWidgets('a tap on the profile puts the cursor and the rider badge on '
      'the route, a sweep moves both, and both stay once the finger has '
      'lifted', (tester) async {
    final h = await _pump(tester);
    expect(_profileHandle, findsNothing);

    await tester.tapAt(_onProfile(tester, 0.2));
    await tester.pump(const Duration(milliseconds: 400));
    var place = _placeOf(h.map.routeCursor!);
    expect(place.along, closeTo(2000, 20));
    expect(place.off, lessThan(1));
    expect(_profileHandle, findsOneWidget);

    final finger = await tester.startGesture(_onProfile(tester, 0.4));
    await tester.pump();
    for (final share in <double>[0.5, 0.6, 0.75]) {
      await finger.moveTo(_onProfile(tester, share));
      await tester.pump();
    }
    await finger.up();
    place = _placeOf(h.map.routeCursor!);
    expect(place.along, closeTo(7500, 20));
    expect(place.off, lessThan(1));

    await tester.pump(const Duration(seconds: 5));
    expect(h.map.routeCursor, isNotNull);
    expect(_placeOf(h.map.routeCursor!).along, closeTo(7500, 20));
    expect(_profileHandle, findsOneWidget);
  });

  testWidgets('the profile and the weather strip share one cursor', (
    tester,
  ) async {
    final h = await _pump(tester);

    await tester.tapAt(_onStrip(tester, 0.5));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_placeOf(h.map.routeCursor!).along, closeTo(5000, 20));
    expect(_profileHandle, findsOneWidget);
    expect(_stripHandle, findsOneWidget);
    expect(
      tester.getCenter(_profileHandle).dx,
      closeTo(tester.getCenter(_stripHandle).dx, 1),
    );

    // The profile's handle moves the strip's cursor with it.
    final perPixel =
        10000 / (_onProfile(tester, 1).dx - _onProfile(tester, 0).dx);
    await dragChartCursor(tester, const Offset(-50, 0), handle: _profileHandle);
    expect(
      _placeOf(h.map.routeCursor!).along,
      closeTo(5000 - 50 * perPixel, 30),
    );
    expect(
      tester.getCenter(_stripHandle).dx,
      closeTo(tester.getCenter(_profileHandle).dx, 1),
    );
  });

  testWidgets('zoomed, a drag on the profile pans both charts, the handle '
      'moves the cursor, and a pan past it takes it and the badge to the '
      'edge', (tester) async {
    final h = await _pump(tester);
    ElevationProfileChart profile() => tester.widget<ElevationProfileChart>(
      find.byType(ElevationProfileChart),
    );
    await _pinch(tester, _onProfile(tester, 0.5));
    final zoomed = profile().window!;

    await tester.tapAt(_onProfile(tester, 0.5));
    await tester.pump(const Duration(milliseconds: 400));
    final middle = (zoomed.start + zoomed.end) / 2;
    expect(_placeOf(h.map.routeCursor!).along, closeTo(middle, 20));

    // The handle moves the cursor a quarter of the way across.
    final quarter = (_onProfile(tester, 1).dx - _onProfile(tester, 0).dx) / 4;
    await dragChartCursor(tester, Offset(quarter, 0), handle: _profileHandle);
    expect(profile().window, zoomed, reason: 'the handle does not pan');
    final moved = middle + (zoomed.end - zoomed.start) / 4;
    expect(_placeOf(h.map.routeCursor!).along, closeTo(moved, 30));

    // A drag on the plot pans; dragged far enough right, the window leaves
    // the cursor behind it on the right, and it waits at the right edge.
    await tester.dragFrom(
      _onProfile(tester, 0.3) + const Offset(0, 20),
      Offset(quarter * 2, 0),
    );
    await tester.pump(const Duration(milliseconds: 400));
    final panned = profile().window!;
    expect(panned.start, lessThan(zoomed.start));
    expect(panned.end, lessThan(moved));
    expect(_placeOf(h.map.routeCursor!).along, closeTo(panned.end, 5));
    expect(
      tester.widget<RouteWeatherStrip>(find.byType(RouteWeatherStrip)).window,
      panned,
    );
  });

  testWidgets('a double tap on the handle hides the cursor on both charts '
      'and takes the badge off the map', (tester) async {
    final h = await _pump(tester);
    await tester.tapAt(_onProfile(tester, 0.3));
    await tester.pump(const Duration(milliseconds: 400));
    expect(h.map.routeCursor, isNotNull);

    await doubleTapChartCursor(tester, handle: _profileHandle);

    expect(h.map.routeCursor, isNull);
    expect(chartCursorHandles, findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('a vertical drag on the profile still goes to the sheet and '
      'puts no cursor down', (tester) async {
    final h = await _pump(tester);
    final before = tester.getRect(_profile).top;

    // Measured with the finger still down: let go, the sheet may settle
    // back on the detent it was on.
    final finger = await tester.startGesture(_onProfile(tester, 0.5));
    for (var i = 0; i < 10; i++) {
      await finger.moveBy(const Offset(0, 10));
      await tester.pump();
    }
    expect(tester.getRect(_profile).top, greaterThan(before + 50));
    await finger.up();
    await tester.pumpAndSettle();

    expect(h.map.routeCursor, isNull);
    expect(h.map.routeCursorCalls, isEmpty);
  });

  testWidgets('the zoom outlives the sheet moving to another height', (
    tester,
  ) async {
    await _pump(tester);
    ElevationProfileChart profile() => tester.widget<ElevationProfileChart>(
      find.byType(ElevationProfileChart),
    );
    await _pinch(tester, _onProfile(tester, 0.5));
    final zoomed = profile().window;
    expect(zoomed, isNotNull);

    final finger = await tester.startGesture(_onProfile(tester, 0.5));
    for (var i = 0; i < 30; i++) {
      await finger.moveBy(const Offset(0, 15));
      await tester.pump();
    }
    await finger.up();
    await tester.pumpAndSettle();

    expect(profile().window, zoomed);
  });

  testWidgets('a pinch on the profile zooms the strip to the same stretch, '
      'a pinch on the strip zooms the profile, and "Whole route" resets '
      'both', (tester) async {
    await _pump(tester);
    RouteWeatherStrip strip() =>
        tester.widget<RouteWeatherStrip>(find.byType(RouteWeatherStrip));
    ElevationProfileChart profile() => tester.widget<ElevationProfileChart>(
      find.byType(ElevationProfileChart),
    );

    await _pinch(tester, _onProfile(tester, 0.5));

    final window = profile().window;
    expect(window, isNotNull);
    expect(window!.end - window.start, lessThan(6000));
    expect(strip().window, window);
    final axis = tester.widget<LineChart>(_profile).data;
    expect(axis.minX, closeTo(window.start / 1000, 1e-9));
    expect(find.text(l10n.chartResetZoomRoute), findsOneWidget);

    await _pinch(tester, _onStrip(tester, 0.5));
    final narrower = strip().window!;
    expect(narrower.end - narrower.start, lessThan(window.end - window.start));
    expect(profile().window, narrower);

    await tester.tap(find.text(l10n.chartResetZoomRoute));
    await tester.pumpAndSettle();
    expect(profile().window, isNull);
    expect(strip().window, isNull);
  });

  testWidgets('without Plus the free forecast draws the wind on the route '
      'once the rider accepts it, with its source under the key', (
    tester,
  ) async {
    final free = FakeDwdClient();
    final h = await pumpScreen(
      tester,
      const PlannerScreen(),
      extraOverrides: [
        relayClientProvider.overrideWithValue(MockRelay().client()),
        plusAccessProvider.overrideWith((ref, feature) => PlusAccess.missing),
        dwdForecastClientProvider.overrideWithValue(free),
        weatherClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 10, 11, 8),
        ),
      ],
    );
    ProviderScope.containerOf(tester.element(find.byType(PlannerScreen)))
        .read(plannerControllerProvider.notifier)
        .loadComputedRoute(
          result: _route,
          waypoints: [
            Waypoint(pos: _route.geometry.first.pos),
            Waypoint(pos: _route.geometry.last.pos),
          ],
          options: RoutingOptions(),
        );
    await tester.pumpAndSettle();
    final wind = find.descendant(
      of: find.byType(RouteColourChoice),
      matching: find.text(l10n.weatherWind),
    );
    await tester.ensureVisible(wind);
    await tester.pumpAndSettle();
    await tester.tap(wind);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.weatherFreeForecastUse));
    await tester.pumpAndSettle();
    await tester.pump(weatherDebounce);
    await tester.pumpAndSettle();

    expect(free.requests, isNotEmpty);
    final drawn = h.map.calls.where((c) => c.method == 'setRouteWind');
    expect(drawn, isNotEmpty);
    final segments = drawn.last.arguments.single! as List<WindSegment>;
    expect(segments, isNotEmpty);
    expect(
      segments,
      everyElement(
        isA<WindSegment>().having(
          (s) => s.windClass,
          'class',
          WindClassOnMap.head,
        ),
      ),
    );
    expect(find.byType(FreeForecastSourceLine), findsOneWidget);
  });
}

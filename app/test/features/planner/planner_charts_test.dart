import 'package:fl_chart/fl_chart.dart' show LineChart;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/integrations/common/data/relay_client_provider.dart';
import 'package:velorki/features/map/application/route_cursor.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/domain/routing_options.dart';
import 'package:velorki/features/planner/domain/waypoint.dart';
import 'package:velorki/features/planner/presentation/elevation_profile_chart.dart';
import 'package:velorki/features/planner/presentation/planner_screen.dart';
import 'package:velorki/features/shared/presentation/metric_chart.dart';
import 'package:velorki/features/subscription/application/plus_access.dart';
import 'package:velorki/features/weather/application/route_weather_controller.dart';
import 'package:velorki/features/weather/domain/route_weather_state.dart';
import 'package:velorki/features/weather/presentation/route_weather_strip.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';
import '../../support/mock_relay.dart';
import '../weather/support/weather_fixtures.dart';
import 'support/pump.dart';

const LatLng _start = LatLng(48, 11);

/// Ten kilometres due north, a point every 500 m.
final RouteResult _route = straightRoute(start: _start);

/// The forecast along [_route], whatever is asked.
class _Weather extends RouteWeatherController {
  @override
  AsyncValue<RouteWeatherState?> build() => AsyncData<RouteWeatherState?>(
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
      routeWeatherControllerProvider.overrideWith(_Weather.new),
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

void main() {
  testWidgets('a finger on the profile puts the rider dot on the route, '
      'which follows the sweep and goes once the finger has lifted', (
    tester,
  ) async {
    final h = await _pump(tester);

    final finger = await tester.startGesture(_onProfile(tester, 0.2));
    await tester.pump();
    var place = _placeOf(h.map.routeCursor!);
    expect(place.along, closeTo(2000, 260));
    expect(place.off, lessThan(1));

    for (final share in <double>[0.4, 0.6, 0.75]) {
      await finger.moveTo(_onProfile(tester, share));
      await tester.pump();
    }
    place = _placeOf(h.map.routeCursor!);
    expect(place.along, closeTo(7500, 260));
    expect(place.off, lessThan(1));

    await finger.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(h.map.routeCursor, isNotNull, reason: 'it lingers a moment');
    await tester.pump(routeCursorLinger);
    expect(h.map.routeCursor, isNull);
  });

  testWidgets('a finger on the weather strip puts the dot there too', (
    tester,
  ) async {
    final h = await _pump(tester);

    await tester.tapAt(_onStrip(tester, 0.5));
    await tester.pump(const Duration(milliseconds: 400));
    final place = _placeOf(h.map.routeCursor!);
    expect(place.along, closeTo(5000, 20));
    expect(place.off, lessThan(1));
    await tester.pump(routeCursorLinger);
    expect(h.map.routeCursor, isNull);
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
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/app/shell_layout.dart';
import 'package:velorki/features/map/data/weather_fetcher.dart';
import 'package:velorki/features/map/data/weather_map_preferences.dart';
import 'package:velorki/features/map/domain/weather_map.dart';
import 'package:velorki/features/map/domain/wind_field.dart';
import 'package:velorki/features/map/presentation/map_controls.dart';
import 'package:velorki/features/map/presentation/weather_time_row.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/domain/routing_options.dart';
import 'package:velorki/features/planner/domain/waypoint.dart';
import 'package:velorki/features/planner/presentation/elevation_profile_chart.dart';
import 'package:velorki/features/shared/presentation/floating_bar.dart';
import 'package:velorki/features/weather/presentation/weather_keys.dart';
import 'package:velorki/features/recording/domain/recording_snapshot.dart';
import 'package:velorki/features/shared/presentation/docking_sheet.dart';
import 'package:velorki/features/shared/presentation/stat_tile.dart';
import 'package:velorki/features/weather/application/route_colouring.dart';
import 'package:velorki/features/weather/application/route_overlay.dart';
import 'package:velorki/features/weather/application/route_weather_controller.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';
import '../planner/support/fakes.dart';
import '../recording/support/pump.dart';

/// Never reaches the network: every service answers, with nothing.
class _QuietFetcher implements WeatherFetcher {
  @override
  Future<bool> probe(String url) async => true;

  @override
  Future<DateTime?> newestFrame(WeatherMapSource source) async => null;

  @override
  bool takeRefusal(String sourceId) => false;

  @override
  Future<Uint8List?> cloudImage(
    WeatherMapSource source,
    int region,
    WeatherFrame frame,
    DateTime now, {
    List<CloudFade> fades = const <CloudFade>[],
  }) async => null;

  @override
  Future<Uint8List?> cloudDetailImage(
    WeatherMapSource source,
    BoundingBox box,
    WeatherFrame frame,
    DateTime now, {
    List<CloudFade> fades = const <CloudFade>[],
  }) async => null;

  @override
  Future<Uint8List?> radarImage(
    WeatherMapSource source,
    BoundingBox box,
    WeatherFrame frame,
    DateTime now, {
    RadarStyle style = RadarStyle.soft,
    List<List<LatLng>> masks = const <List<LatLng>>[],
    List<RainCoverage> coverages = const <RainCoverage>[],
    String maskKey = '',
  }) async => null;

  @override
  Future<WindGrid?> windGrid(
    WeatherMapSource source,
    WindRequest request,
    WeatherFrame frame,
    DateTime now,
  ) async => null;
}

final List<Override> _quiet = <Override>[
  weatherFetcherProvider.overrideWithValue(_QuietFetcher()),
];

Finder get _row => find.descendant(
  of: find.byType(DockingSheetShell),
  matching: find.byType(Slider),
);

Future<void> _rain(WidgetTester tester, bool on) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(MapControls)),
  );
  await container.read(weatherMapPreferencesProvider.notifier).setRadar(on);
  await tester.pumpAndSettle();
}

/// Puts the test view at [size], at three pixels a point, without safe
/// areas.
Future<void> _screen(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = size * 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpAndSettle();
}

RecordingSnapshot _snapshot() => RecordingSnapshot(
  rideId: 'ride-1',
  status: RecordingStatus.active,
  startedAt: DateTime.utc(2026, 9, 12, 10),
  autoPaused: false,
  distanceM: 12345,
  elapsed: const Duration(minutes: 42, seconds: 7),
  moving: const Duration(minutes: 40),
  speedMps: 6,
  avgSpeedMps: 5,
  ascentM: 210,
  descentM: 190,
  lastPosition: const LatLng(48.1, 11.2),
  accuracyM: 4,
  pointCount: 120,
  newPoints: const [LatLng(48.0, 11.0), LatLng(48.1, 11.2)],
);

void main() {
  setUp(() => debugShellLayoutOverride = null);

  testWidgets('Plan: the time control at the top of the sheet, in view at '
      'rest, only with the rain on', (tester) async {
    const size = Size(402, 874);
    await _screen(tester, size);
    await pumpRecordingApp(
      tester,
      initialLocation: plannerRoute,
      surfaceSize: size,
      extraOverrides: _quiet,
    );
    await tester.pumpAndSettle();
    expect(_row, findsNothing);
    await _rain(tester, true);
    expect(_row, findsOneWidget);
    final sheet = tester.getRect(find.byType(DockingSheetShell));
    final slider = tester.getRect(_row);
    // Right under the header, inside the resting sheet, above the bar.
    final header = tester.getRect(find.text(l10n.plannerEmptyStateDetail));
    expect(slider.top, greaterThan(sheet.top));
    expect(slider.top, greaterThanOrEqualTo(header.bottom));
    expect(slider.top - header.bottom, lessThan(24));
    expect(slider.bottom, lessThan(size.height - 90));
    await _rain(tester, false);
    expect(_row, findsNothing);
  });

  testWidgets('Plan: with a route the time control is its departure, shown '
      'with the map\'s rain and wind off, whatever colours the route', (
    tester,
  ) async {
    const size = Size(402, 874);
    await _screen(tester, size);
    await pumpRecordingApp(
      tester,
      initialLocation: plannerRoute,
      surfaceSize: size,
      extraOverrides: [
        ..._quiet,
        weatherRouteGeometryProvider(plannerWeatherRoute)
            .overrideWithValue(<TrackPoint>[
              for (var d = 0.0; d <= 10000; d += 500)
                TrackPoint(destinationPoint(const LatLng(50, 8), 0, d)),
            ]),
      ],
    );
    await tester.pumpAndSettle();
    // The route's weather is shown for everyone: so is its departure.
    expect(_row, findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(weatherTimeLabelKey)).data,
      startsWith(l10n.mapWeatherLeaveNow),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MapControls)),
    );
    for (final overlay in [RouteOverlay.wind, RouteOverlay.gradient]) {
      await container.read(routeOverlayChoiceProvider.notifier).set(overlay);
      await tester.pumpAndSettle();
      expect(_row, findsOneWidget);
    }
    // The rain on: the control, still the departure.
    await _rain(tester, true);
    expect(_row, findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(weatherTimeLabelKey)).data,
      startsWith(l10n.mapWeatherLeaveNow),
    );
    // The free forecast's wait runs out.
    await tester.pump(weatherDebounce);
  });

  // With a route the sheet runs: the figures, the actions and Save, the
  // time control, the colour choice and its key, the profile, then the
  // rest; at rest the figures, the actions, Save and the time control are
  // in view above the bar, with the variants' chips too.
  for (final size in [
    const Size(402, 874),
    const Size(375, 667),
    const Size(360, 640),
  ]) {
    for (final variants in [false, true]) {
      testWidgets('Plan with a route at $size'
          '${variants ? ', with variants' : ''}: the sheet\'s order, and the '
          'time control in view at rest', (tester) async {
        await _screen(tester, size);
        final h = await pumpRecordingApp(
          tester,
          initialLocation: plannerRoute,
          surfaceSize: size,
          extraOverrides: _quiet,
        );
        await tester.pumpAndSettle();
        final container = ProviderScope.containerOf(
          tester.element(find.byType(MapControls)),
        );
        final route = syntheticRoute(lengthM: 10000);
        h.planner.backend.byAlternative[1] = syntheticRoute(lengthM: 11000);
        container
            .read(plannerControllerProvider.notifier)
            .loadComputedRoute(
              result: route,
              waypoints: [
                Waypoint(pos: route.geometry.first.pos),
                Waypoint(pos: route.geometry.last.pos),
              ],
              options: RoutingOptions(),
            );
        await tester.pumpAndSettle();
        if (variants) {
          await tester.tap(
            find.widgetWithText(LabeledIconButton, l10n.plannerVariants),
          );
          await tester.pumpAndSettle();
          expect(
            find.widgetWithText(ChoiceChip, l10n.plannerMainRoute),
            findsOneWidget,
          );
        }
        final save = find.widgetWithText(FilledButton, l10n.plannerSave);
        final order = [
          find.byType(StatRow).first,
          find.widgetWithText(LabeledIconButton, l10n.plannerUndo),
          save,
          _row,
          find.byType(SegmentedButton<RouteOverlay>),
          find.byType(RouteColourKey),
          find.byType(ElevationProfileChart),
        ];
        for (var i = 1; i < order.length; i++) {
          expect(
            tester.getRect(order[i]).top,
            greaterThanOrEqualTo(tester.getRect(order[i - 1]).bottom),
            reason: '${order[i]} under ${order[i - 1]}',
          );
        }
        // The time control right under Save.
        final control = find.ancestor(
          of: _row,
          matching: find.byType(WeatherTimeRow),
        );
        expect(
          tester.getRect(control).top - tester.getRect(save).bottom,
          lessThan(4),
        );
        // In view at rest: above the floating bar.
        final bar = tester.getRect(find.byType(FloatingBarShell)).top;
        expect(tester.getRect(_row).bottom, lessThanOrEqualTo(bar));
        // The free forecast's wait runs out.
        await tester.pump(weatherDebounce);
      });
    }
  }

  testWidgets('Record: the time control on the idle card, and under the '
      'figures during a ride', (tester) async {
    const size = Size(402, 874);
    await _screen(tester, size);
    final h = await pumpRecordingApp(
      tester,
      surfaceSize: size,
      extraOverrides: _quiet,
    );
    await tester.pumpAndSettle();
    expect(_row, findsNothing);
    await _rain(tester, true);
    expect(_row, findsOneWidget);
    expect(
      tester.getRect(_row).bottom,
      lessThan(size.height - 100),
      reason: 'in view at the resting height',
    );

    await emitSnapshot(tester, h, _snapshot());
    await tester.pumpAndSettle();
    expect(_row, findsOneWidget);
    final figures = tester.getRect(find.byType(StatRow).last);
    final slider = tester.getRect(_row);
    expect(slider.top, greaterThan(figures.bottom));
    // Still in view with the live sheet at rest.
    expect(slider.bottom, lessThan(size.height));
    await _rain(tester, false);
    expect(_row, findsNothing);
  });

  for (final size in [const Size(402, 874), const Size(874, 402)]) {
    testWidgets('the control column stays where it is with the rain on, at '
        '$size', (tester) async {
      if (size.width > size.height) {
        const channel = MethodChannel(ScreenSideChannel.channelName);
        final messenger = tester.binding.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(
          channel,
          (call) async => call.method == 'side' ? RailSide.right.name : null,
        );
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      }
      await _screen(tester, size);
      await pumpRecordingApp(
        tester,
        initialLocation: plannerRoute,
        surfaceSize: size,
        extraOverrides: _quiet,
        expectTextFits: false,
      );
      await tester.pumpAndSettle();
      final off = tester.getRect(find.byType(MapControls));
      await _rain(tester, true);
      expect(tester.getRect(find.byType(MapControls)), off);
      // No time control over the map.
      expect(
        find.descendant(
          of: find.byType(MapControls),
          matching: find.byType(Slider),
        ),
        findsNothing,
      );
      expect(find.byType(Slider), findsOneWidget);
      expect(find.byType(WeatherTimeRow), findsOneWidget);
    });
  }
}

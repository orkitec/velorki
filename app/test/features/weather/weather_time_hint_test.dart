import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/app/shell_layout.dart';
import 'package:velorki/features/integrations/common/data/relay_client_provider.dart';
import 'package:velorki/features/map/data/weather_fetcher.dart';
import 'package:velorki/features/map/data/weather_map_preferences.dart';
import 'package:velorki/features/map/domain/weather_map.dart';
import 'package:velorki/features/map/domain/wind_field.dart';
import 'package:velorki/features/map/presentation/map_controls.dart';
import 'package:velorki/features/shared/presentation/docking_sheet.dart';
import 'package:velorki/features/subscription/application/plus_access.dart';
import 'package:velorki/features/weather/application/route_colouring.dart';
import 'package:velorki/features/weather/application/route_overlay.dart';
import 'package:velorki/features/weather/application/route_weather_controller.dart';
import 'package:velorki/features/weather/application/weather_time_hint.dart';
import 'package:velorki/features/weather/presentation/weather_time_hint_dialog.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';
import '../../support/mock_relay.dart';
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

const Size _phone = Size(402, 874);

/// The Plan tab with a 10 km route, colouring and the map's weather as
/// [preferences] has them; with [plusMissing] a build with the relay whose
/// store says the rider has no Plus, else a build without the relay.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Map<String, Object> preferences = const <String, Object>{},
  bool route = true,
  bool plusMissing = false,
  String location = plannerRoute,
}) async {
  await tester.binding.setSurfaceSize(_phone);
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = _phone * 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await pumpRecordingApp(
    tester,
    initialLocation: location,
    surfaceSize: _phone,
    preferences: preferences,
    extraOverrides: <Override>[
      weatherFetcherProvider.overrideWithValue(_QuietFetcher()),
      relayClientProvider.overrideWithValue(
        plusMissing ? MockRelay().client() : null,
      ),
      if (plusMissing)
        plusAccessProvider.overrideWith((ref, _) => PlusAccess.missing),
      if (route)
        weatherRouteGeometryProvider(plannerWeatherRoute)
            .overrideWithValue(<TrackPoint>[
              for (var d = 0.0; d <= 10000; d += 500)
                TrackPoint(destinationPoint(const LatLng(50, 8), 0, d)),
            ]),
    ],
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(MapControls)));
}

Finder get _slider => find.descendant(
  of: find.byType(DockingSheetShell),
  matching: find.byType(Slider),
);

/// Drags the time control a few steps on and lets it go.
Future<void> _move(WidgetTester tester, {double by = 80}) async {
  await tester.drag(_slider, Offset(by, 0));
  await tester.pumpAndSettle();
}

Finder get _dialog => find.text(l10n.weatherTimeHintTitle);

/// Lets the free forecast's wait run out, so no timer outlives the test.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump(weatherDebounce);
  await tester.pumpAndSettle();
}

/// Colouring on and by the gradient, the map's rain and wind off.
const Map<String, Object> _gradient = <String, Object>{
  'weather.route_colouring_on': true,
  'weather.route_overlay': 'gradient',
};

void main() {
  setUp(() => debugShellLayoutOverride = ShellLayout.bottomBar);

  testWidgets('let go where nothing in view follows it, the time control '
      'says what it moves, once a run', (tester) async {
    final container = await _pump(tester, preferences: _gradient);
    expect(_slider, findsOneWidget);
    await _move(tester);
    expect(_dialog, findsOneWidget);
    expect(find.text(l10n.weatherTimeHintBody), findsOneWidget);
    for (final text in [
      l10n.weatherTimeHintRainRadar,
      l10n.weatherTimeHintWind,
      l10n.weatherTimeHintColourWind,
      l10n.weatherTimeHintColourRain,
      l10n.weatherTimeHintDontShowAgain,
    ]) {
      expect(find.text(text), findsOneWidget);
    }
    expectNoClippedText(tester);
    await tester.tap(find.text(l10n.weatherTimeHintClose));
    await tester.pumpAndSettle();
    expect(_dialog, findsNothing);
    // Nothing changed.
    expect(container.read(weatherMapPreferencesProvider).any, isFalse);
    expect(container.read(routeOverlayShownProvider), RouteOverlay.gradient);

    // Moved again in the same run: no dialog.
    await _move(tester, by: -80);
    expect(_dialog, findsNothing);
    await _settle(tester);
  });

  testWidgets('with the colouring off the surface, it shows too', (
    tester,
  ) async {
    await _pump(
      tester,
      preferences: const <String, Object>{
        'weather.route_colouring_on': false,
        'weather.route_overlay': 'surface',
      },
    );
    await _move(tester);
    expect(_dialog, findsOneWidget);
    await _settle(tester);
  });

  // A new ProviderScope pumped over the last keeps the last one's state, so
  // each case is a test of its own.
  for (final (name, preferences) in <(String, Map<String, Object>)>[
    ('the rain radar on', {..._gradient, 'map.weather.radar': true}),
    ('the wind on', {..._gradient, 'map.weather.wind': true}),
    (
      '"Don\'t show again" ticked in an earlier run',
      {..._gradient, 'weather.time_hint_never': true},
    ),
  ]) {
    testWidgets('not shown with $name', (tester) async {
      await _pump(tester, preferences: preferences);
      await _move(tester);
      expect(_dialog, findsNothing);
      await _settle(tester);
    });
  }

  testWidgets('not shown with the route coloured by the wind', (tester) async {
    final container = await _pump(tester, preferences: _gradient);
    await container
        .read(routeOverlayChoiceProvider.notifier)
        .set(RouteOverlay.wind);
    await tester.pumpAndSettle();
    expect(container.read(routeOverlayShownProvider), RouteOverlay.wind);
    await _move(tester);
    expect(_dialog, findsNothing);
    await _settle(tester);
  });

  testWidgets('not shown without a route, where the control is the map\'s', (
    tester,
  ) async {
    await _pump(
      tester,
      route: false,
      preferences: {..._gradient, 'map.weather.radar': true},
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MapControls)),
    );
    // The rain off again once the control is there: still no dialog.
    await _move(tester);
    await container
        .read(weatherMapPreferencesProvider.notifier)
        .setRadar(false);
    await tester.pumpAndSettle();
    expect(_dialog, findsNothing);
    await _settle(tester);
  });

  for (final (choice, on) in <(String, bool Function(WeatherMapSettings))>[
    (l10n.weatherTimeHintRainRadar, (s) => s.radar),
    (l10n.weatherTimeHintWind, (s) => s.wind),
  ]) {
    testWidgets('"$choice" switches the map\'s layer on', (tester) async {
      final container = await _pump(tester, preferences: _gradient);
      await _move(tester);
      await tester.tap(find.text(choice));
      await tester.pumpAndSettle();
      expect(_dialog, findsNothing);
      expect(on(container.read(weatherMapPreferencesProvider)), isTrue);
      await _settle(tester);
    });
  }

  for (final (choice, overlay) in <(String, RouteOverlay)>[
    (l10n.weatherTimeHintColourWind, RouteOverlay.wind),
    (l10n.weatherTimeHintColourRain, RouteOverlay.rain),
  ]) {
    testWidgets('"$choice" switches the colouring on, asking about the free '
        'forecast without Plus', (tester) async {
      final container = await _pump(
        tester,
        preferences: const <String, Object>{
          'weather.route_colouring_on': false,
          'weather.route_overlay': 'gradient',
        },
      );
      await _move(tester);
      await tester.tap(find.text(choice));
      await tester.pumpAndSettle();
      // The free forecast's dialog, as the choice under the route asks.
      expect(find.text(l10n.weatherFreeForecastTitle), findsOneWidget);
      await tester.tap(find.text(l10n.weatherFreeForecastUse));
      await tester.pumpAndSettle();
      expect(container.read(routeColouringOnProvider), isTrue);
      expect(container.read(routeOverlayShownProvider), overlay);
      await _settle(tester);
    });
  }

  testWidgets('without Plus, "Show rain radar" asks as the Layers sheet does', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      preferences: _gradient,
      plusMissing: true,
    );
    await _move(tester);
    await tester.tap(find.text(l10n.weatherTimeHintRainRadar));
    await tester.pumpAndSettle();
    expect(find.text(l10n.mapRainRadarPlusBody), findsOneWidget);
    await tester.tap(find.text(l10n.mapRainRadarPlusUseFree));
    await tester.pumpAndSettle();
    expect(container.read(weatherMapPreferencesProvider).radar, isTrue);
    await _settle(tester);
  });

  testWidgets('"Don\'t show again" is kept across launches', (tester) async {
    final container = await _pump(tester, preferences: _gradient);
    await _move(tester);
    await tester.tap(find.byKey(weatherTimeHintNeverKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.weatherTimeHintClose));
    await tester.pumpAndSettle();
    expect(
      container
          .read(sharedPreferencesProvider)
          .getBool('weather.time_hint_never'),
      isTrue,
    );
    // A new run.
    container.invalidate(weatherTimeHintProvider);
    expect(container.read(weatherTimeHintProvider), isFalse);
    await _move(tester, by: -80);
    expect(_dialog, findsNothing);
    await _settle(tester);
  });

  testWidgets('a new run without the box ticked shows it again', (
    tester,
  ) async {
    final container = await _pump(tester, preferences: _gradient);
    await _move(tester);
    await tester.tap(find.text(l10n.weatherTimeHintClose));
    await tester.pumpAndSettle();
    container.invalidate(weatherTimeHintProvider);
    await _move(tester, by: -80);
    expect(_dialog, findsOneWidget);
    await _settle(tester);
  });

  testWidgets('fits a small phone turned sideways, every choice in reach', (
    tester,
  ) async {
    const size = Size(667, 375);
    await tester.binding.setSurfaceSize(size);
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = size * 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    WeatherTimeHintAction? picked;
    await tester.pumpWidget(
      testApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => picked = await showWeatherTimeHintDialog(
                  context,
                  rainRadar: true,
                  wind: true,
                  onNever: (_) {},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expectNoClippedText(tester);
    final last = find.text(l10n.weatherTimeHintColourRain);
    await tester.ensureVisible(last);
    await tester.pumpAndSettle();
    await tester.tap(last);
    await tester.pumpAndSettle();
    expect(picked, WeatherTimeHintAction.colourByRain);
  });
}

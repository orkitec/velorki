import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/core/geo/route_gradient.dart';
import 'package:velorki/features/integrations/common/data/relay_client_provider.dart';
import 'package:velorki/features/map/domain/map_controller.dart';
import 'package:velorki/features/planner/domain/elevation_profile.dart';
import 'package:velorki/features/planner/presentation/elevation_profile_chart.dart';
import 'package:velorki/features/subscription/application/plus_access.dart';
import 'package:velorki/features/weather/application/free_route_weather.dart';
import 'package:velorki/features/weather/application/route_colouring.dart';
import 'package:velorki/features/weather/application/route_overlay.dart';
import 'package:velorki/features/weather/application/route_weather_controller.dart';
import 'package:velorki/features/weather/data/dwd_route_forecast.dart';
import 'package:velorki/features/weather/domain/route_sampling.dart';
import 'package:velorki/features/weather/domain/route_weather_state.dart';
import 'package:velorki/features/weather/presentation/route_colour_choice.dart';
import 'package:velorki/features/weather/presentation/weather_keys.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';
import '../../support/mock_relay.dart';
import 'support/weather_fixtures.dart';

final DateTime _earliest = DateTime.utc(2026, 10, 11, 8);

/// A 10 km route north: flat for 5 km, then 8 % up.
final List<TrackPoint> _geometry = <TrackPoint>[
  for (var d = 0.0; d <= 10000; d += 100)
    TrackPoint(
      destinationPoint(const LatLng(50, 8), 0, d),
      ele: 100 + (d > 5000 ? (d - 5000) * 0.08 : 0),
    ),
];

/// The weather on [_geometry]: a headwind all day, rain of [precip] mm.
RouteWeatherState _weather({double precip = 0}) {
  final route = straightRoute();
  final samples = sampleRoute(route, typicalSpeedKmh: 18);
  final cells = cellsFor(samples);
  final window = requestWindow(
    _earliest,
    samples.last.offset,
    sliderSpan: departureSpan,
  );
  return RouteWeatherState.evaluated(
    departure: _earliest,
    earliestDeparture: _earliest,
    window: window,
    forecast: uniformForecast(
      cells.cells.length,
      hours(window.from, window.hours, (t, _) => hour(t, precip: precip)),
    ),
    samples: samples,
    cells: cells,
  );
}

/// What the store says, changed by a test.
class _Access extends Notifier<PlusAccess> {
  @override
  PlusAccess build() => PlusAccess.unknown;

  void set(PlusAccess access) => state = access;
}

final NotifierProvider<_Access, PlusAccess> _access =
    NotifierProvider<_Access, PlusAccess>(_Access.new);

class _FakeWeather extends RouteWeatherController {
  _FakeWeather(this._initial);

  final AsyncValue<RouteWeatherState?> _initial;

  @override
  AsyncValue<RouteWeatherState?> build(WeatherRoute route) {
    ref.keepAlive();
    return _initial;
  }
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  PlusAccess access = PlusAccess.granted,
  bool withRelay = true,
  Map<String, Object> prefs = const <String, Object>{},
  AsyncValue<RouteWeatherState?>? weather,
  FakeDwdClient? free,
  PlusAccess Function(Ref ref)? accessOf,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final stored = await SharedPreferences.getInstance();
  final relay = MockRelay();
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              RouteElevationProfile(
                route: plannerWeatherRoute,
                samples: elevationProfile(_geometry),
              ),
            ],
          ),
        ),
      ),
      GoRoute(
        path: paywallRoute,
        builder: (_, _) => const Scaffold(body: Text('paywall')),
      ),
    ],
  );
  addTearDown(router.dispose);
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(stored),
      relayClientProvider.overrideWithValue(withRelay ? relay.client() : null),
      plusAccessProvider.overrideWith(
        (ref, feature) => accessOf?.call(ref) ?? access,
      ),
      weatherRouteGeometryProvider(plannerWeatherRoute)
          .overrideWithValue(_geometry),
      weatherRouteSpeedProvider(plannerWeatherRoute).overrideWithValue(18),
      dwdForecastClientProvider.overrideWithValue(free ?? FakeDwdClient()),
      weatherClockProvider.overrideWithValue(() => _earliest),
      routeWeatherControllerProvider.overrideWith2(
        (_) =>
            _FakeWeather(weather ?? AsyncData<RouteWeatherState?>(_weather())),
      ),
    ],
  );
  addTearDown(container.dispose);
  // A phone's width.
  await tester.binding.setSurfaceSize(const Size(360, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: testRouterApp(routerConfig: router),
    ),
  );
  await tester.pump();
  return container;
}

Finder _segment(String label) => find.descendant(
  of: find.byType(SegmentedButton<RouteOverlay>),
  matching: find.text(label),
);

RouteOverlay _selected(WidgetTester tester) => tester
    .widget<SegmentedButton<RouteOverlay>>(
      find.byType(SegmentedButton<RouteOverlay>),
    )
    .selected
    .single;

List<({double start, double end, Color colour})> _bands(WidgetTester tester) =>
    tester
        .widget<ElevationProfileChart>(find.byType(ElevationProfileChart))
        .bands;

void main() {
  testWidgets('with Plus: Off, Gradient, Wind and Rain under the profile, '
      'the gradient first; each colours the chart and has its key', (
    tester,
  ) async {
    final container = await _pump(tester);
    RouteOverlay chosen() => container.read(routeOverlayChoiceProvider);
    for (final label in [
      l10n.weatherOverlayOff,
      l10n.colourByGradient,
      l10n.weatherWind,
      l10n.weatherRain,
    ]) {
      expect(_segment(label), findsOneWidget);
    }
    expect(find.byIcon(Icons.lock_outline), findsNothing);
    // Under the chart.
    expect(
      tester.getTopLeft(find.byType(SegmentedButton<RouteOverlay>)).dy,
      greaterThan(tester.getBottomLeft(find.byType(ElevationProfileChart)).dy),
    );

    // The gradient by default: the chart in its colours, and its key.
    expect(chosen(), RouteOverlay.gradient);
    expect(_selected(tester), RouteOverlay.gradient);
    expect(_bands(tester).map((b) => b.colour), [
      Color(0xFF000000 | gradientClassColour(GradientClass.flat)),
      Color(0xFF000000 | gradientClassColour(GradientClass.steep)),
    ]);
    expect(find.byType(GradientColourKey), findsOneWidget);
    final data = tester.widget<LineChart>(find.byType(LineChart)).data;
    expect(data.lineBarsData.single.belowBarData.gradient, isNotNull);
    expectNoClippedText(tester);

    await tester.tap(_segment(l10n.weatherWind));
    await tester.pump();
    expect(chosen(), RouteOverlay.wind);
    expect(
      container
          .read(sharedPreferencesProvider)
          .getString('weather.route_overlay'),
      'wind',
    );
    expect(find.byType(WindColourKey), findsOneWidget);
    expect(find.byType(GradientColourKey), findsNothing);
    // The weather's fixture route is 10 km long, as this one is.
    expect(_bands(tester), isNotEmpty);

    // A dry ride: the key says so rather than show colours.
    await tester.tap(_segment(l10n.weatherRain));
    await tester.pump();
    expect(chosen(), RouteOverlay.rain);
    expect(find.text(l10n.weatherRainNoneOnRoute), findsOneWidget);
    expect(find.byType(RainColourKey), findsNothing);
    expect(_bands(tester), isEmpty);

    await tester.tap(_segment(l10n.weatherOverlayOff));
    await tester.pump();
    expect(chosen(), RouteOverlay.off);
    expect(_bands(tester), isEmpty);
    expect(find.byType(GradientColourKey), findsNothing);
    expect(find.byType(WindColourKey), findsNothing);
    final plain = tester.widget<LineChart>(find.byType(LineChart)).data;
    expect(plain.lineBarsData.single.belowBarData.gradient, isNull);
  });

  testWidgets('the rain key names the strengths while rain is on the way', (
    tester,
  ) async {
    await _pump(
      tester,
      weather: AsyncData<RouteWeatherState?>(_weather(precip: 3)),
    );
    await tester.tap(_segment(l10n.weatherRain));
    await tester.pump();
    expect(find.byType(RainColourKey), findsOneWidget);
    expect(find.text(l10n.weatherRainModerate), findsOneWidget);
  });

  testWidgets('no key and no bands while the weather is on its way', (
    tester,
  ) async {
    await _pump(
      tester,
      prefs: const <String, Object>{'weather.route_overlay': 'wind'},
      weather: const AsyncLoading<RouteWeatherState?>(),
    );
    expect(_selected(tester), RouteOverlay.wind);
    expect(find.byType(WindColourKey), findsNothing);
    expect(_bands(tester), isEmpty);
  });

  testWidgets('without Plus the first pick of the wind asks; the free '
      'forecast chosen colours the route from it and is not asked again', (
    tester,
  ) async {
    final free = FakeDwdClient();
    final container = await _pump(
      tester,
      access: PlusAccess.missing,
      free: free,
    );
    expect(find.byIcon(Icons.lock_outline), findsNothing);
    await tester.tap(_segment(l10n.weatherWind));
    await tester.pumpAndSettle();
    expect(find.text(l10n.weatherFreeForecastTitle), findsOneWidget);
    expect(find.text(l10n.weatherFreeForecastPlusBody), findsOneWidget);
    expect(container.read(routeOverlayChoiceProvider), RouteOverlay.gradient);

    await tester.tap(find.text(l10n.weatherFreeForecastUse));
    await tester.pumpAndSettle();
    expect(find.text(l10n.weatherFreeForecastTitle), findsNothing);
    expect(container.read(routeOverlayChoiceProvider), RouteOverlay.wind);
    expect(container.read(routeOverlayShownProvider), RouteOverlay.wind);
    expect(
      container
          .read(sharedPreferencesProvider)
          .getBool('weather.free_route_forecast'),
      isTrue,
    );
    // Asked once the route has stood still a moment.
    await tester.pump(weatherDebounce);
    await tester.pumpAndSettle();
    expect(free.requests, isNotEmpty);
    expect(
      container
          .read(routeColouringProvider(plannerWeatherRoute))
          .wind
          .map((r) => r.key),
      everyElement(WindClassOnMap.head),
    );
    expect(_bands(tester), isNotEmpty);
    expect(find.byType(WindColourKey), findsOneWidget);
    expect(find.byType(FreeForecastSourceLine), findsOneWidget);
    expect(
      find.text(l10n.weatherFreeForecastSource(dwdAttribution)),
      findsOneWidget,
    );
    expectNoClippedText(tester);

    // The rain: no question again.
    await tester.tap(_segment(l10n.weatherRain));
    await tester.pumpAndSettle();
    expect(find.text(l10n.weatherFreeForecastTitle), findsNothing);
    expect(container.read(routeOverlayChoiceProvider), RouteOverlay.rain);
    expect(find.text(l10n.weatherRainNoneOnRoute), findsOneWidget);
    expect(find.byType(FreeForecastSourceLine), findsOneWidget);

    // The source line shows what Plus is.
    await tester.tap(find.byType(FreeForecastSourceLine));
    await tester.pumpAndSettle();
    expect(find.text('paywall'), findsOneWidget);
  });

  testWidgets('a rider who accepted it before is not asked', (tester) async {
    final container = await _pump(
      tester,
      access: PlusAccess.missing,
      prefs: const <String, Object>{'weather.free_route_forecast': true},
    );
    await tester.tap(_segment(l10n.weatherRain));
    await tester.pumpAndSettle();
    expect(find.text(l10n.weatherFreeForecastTitle), findsNothing);
    expect(container.read(routeOverlayChoiceProvider), RouteOverlay.rain);
    await tester.pump(weatherDebounce);
  });

  testWidgets('"See Plus" shows the paywall and changes nothing', (
    tester,
  ) async {
    final container = await _pump(tester, access: PlusAccess.missing);
    await tester.tap(_segment(l10n.weatherWind));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.weatherFreeForecastSeePlus));
    await tester.pumpAndSettle();
    expect(find.text('paywall'), findsOneWidget);
    expect(container.read(routeOverlayChoiceProvider), RouteOverlay.gradient);
    expect(container.read(freeRouteForecastAcceptedProvider), isFalse);
  });

  testWidgets('dismissed, the dialog changes nothing and asks again', (
    tester,
  ) async {
    final container = await _pump(tester, access: PlusAccess.missing);
    await tester.tap(_segment(l10n.weatherRain));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.commonCancel));
    await tester.pumpAndSettle();
    expect(find.text(l10n.weatherFreeForecastTitle), findsNothing);
    expect(container.read(routeOverlayChoiceProvider), RouteOverlay.gradient);
    expect(container.read(freeRouteForecastAcceptedProvider), isFalse);
    expect(
      container
          .read(sharedPreferencesProvider)
          .getBool('weather.free_route_forecast'),
      isNull,
    );

    await tester.tap(_segment(l10n.weatherRain));
    await tester.pumpAndSettle();
    expect(find.text(l10n.weatherFreeForecastTitle), findsOneWidget);
  });

  testWidgets('with Plus no question and no free source line: the relay '
      'forecast colours the route', (tester) async {
    final free = FakeDwdClient();
    await _pump(tester, free: free);
    await tester.tap(_segment(l10n.weatherWind));
    await tester.pumpAndSettle();
    expect(find.text(l10n.weatherFreeForecastTitle), findsNothing);
    expect(find.byType(WindColourKey), findsOneWidget);
    expect(find.byType(FreeForecastSourceLine), findsNothing);
    await tester.pump(weatherDebounce);
    expect(free.requests, isEmpty);
  });

  testWidgets('without Plus a wind chosen before is shown as the gradient', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      access: PlusAccess.missing,
      prefs: const <String, Object>{'weather.route_overlay': 'wind'},
    );
    expect(container.read(routeOverlayChoiceProvider), RouteOverlay.wind);
    expect(container.read(routeOverlayShownProvider), RouteOverlay.gradient);
    expect(_selected(tester), RouteOverlay.gradient);
    expect(find.byType(GradientColourKey), findsOneWidget);
    expect(
      container.read(routeColouringProvider(plannerWeatherRoute)).wind,
      isEmpty,
    );
  });

  testWidgets('a build without the relay offers the wind and the rain from '
      'the free forecast, without Plus in the dialog or the source line', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      withRelay: false,
      free: FakeDwdClient(rain: 3),
    );
    expect(_segment(l10n.weatherWind), findsOneWidget);
    expect(_segment(l10n.weatherRain), findsOneWidget);
    await tester.tap(_segment(l10n.weatherRain));
    await tester.pumpAndSettle();
    expect(find.text(l10n.weatherFreeForecastTitle), findsOneWidget);
    expect(find.text(l10n.weatherFreeForecastSeePlus), findsNothing);
    expect(find.text(l10n.weatherFreeForecastPlusBody), findsNothing);
    await tester.tap(find.text(l10n.weatherFreeForecastUse));
    await tester.pumpAndSettle();
    await tester.pump(weatherDebounce);
    await tester.pumpAndSettle();
    expect(container.read(routeOverlayShownProvider), RouteOverlay.rain);
    expect(find.byType(RainColourKey), findsOneWidget);
    expect(_bands(tester), isNotEmpty);
    expect(find.byType(FreeForecastSourceLine), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets('while the store has not answered: no question, the free '
      'forecast at once, and the relay\'s once Plus is granted', (
    tester,
  ) async {
    final free = FakeDwdClient();
    final container = await _pump(
      tester,
      free: free,
      accessOf: (ref) => ref.watch(_access),
    );
    expect(_segment(l10n.weatherWind), findsOneWidget);
    await tester.tap(_segment(l10n.weatherWind));
    await tester.pumpAndSettle();
    expect(find.text(l10n.weatherFreeForecastTitle), findsNothing);
    expect(container.read(routeOverlayChoiceProvider), RouteOverlay.wind);
    expect(container.read(routeOverlayShownProvider), RouteOverlay.wind);
    await tester.pump(weatherDebounce);
    await tester.pumpAndSettle();
    expect(free.requests, isNotEmpty);
    expect(find.byType(FreeForecastSourceLine), findsOneWidget);

    container.read(_access.notifier).set(PlusAccess.granted);
    await tester.pumpAndSettle();
    expect(container.read(routeWeatherFromRelayProvider), isTrue);
    expect(find.byType(FreeForecastSourceLine), findsNothing);
    expect(find.byType(WindColourKey), findsOneWidget);
  });

  testWidgets('picked while the store had not answered, Plus missing keeps '
      'the choice and the free forecast, and never asks', (tester) async {
    final container = await _pump(
      tester,
      accessOf: (ref) => ref.watch(_access),
    );
    await tester.tap(_segment(l10n.weatherRain));
    await tester.pumpAndSettle();
    container.read(_access.notifier).set(PlusAccess.missing);
    await tester.pump(weatherDebounce);
    await tester.pumpAndSettle();
    expect(container.read(routeOverlayShownProvider), RouteOverlay.rain);
    expect(find.byType(FreeForecastSourceLine), findsOneWidget);
    await tester.tap(_segment(l10n.weatherWind));
    await tester.pumpAndSettle();
    expect(find.text(l10n.weatherFreeForecastTitle), findsNothing);
    expect(container.read(routeOverlayChoiceProvider), RouteOverlay.wind);
    await tester.pump(weatherDebounce);
  });

  testWidgets('the free forecast failing says so under the choice', (
    tester,
  ) async {
    await _pump(
      tester,
      access: PlusAccess.missing,
      prefs: const <String, Object>{
        'weather.free_route_forecast': true,
        'weather.route_overlay': 'wind',
      },
      free: FakeDwdClient(down: true),
    );
    await tester.pump(weatherDebounce);
    await tester.pumpAndSettle();
    expect(find.text(l10n.mapWeatherWindUnavailable), findsOneWidget);
    expect(_bands(tester), isEmpty);
    expect(find.byType(FreeForecastSourceLine), findsNothing);
  });

  test('the wind switch of before comes back as the wind', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'weather.wind_on_map': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    expect(container.read(routeOverlayChoiceProvider), RouteOverlay.wind);
  });
}

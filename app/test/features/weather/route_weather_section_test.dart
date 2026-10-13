import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/features/integrations/common/data/relay_client_provider.dart';
import 'package:velorki/features/map/data/weather_map_preferences.dart';
import 'package:velorki/features/map/domain/weather_map.dart';
import 'package:velorki/features/planner/presentation/route_format.dart';
import 'package:velorki/core/units/units.dart' show formatSpeed;
import 'package:velorki/features/settings/data/units.dart';
import 'package:velorki/features/subscription/application/plus_access.dart';
import 'package:velorki/features/weather/application/route_weather_controller.dart';
import 'package:velorki/features/weather/domain/route_sampling.dart';
import 'package:velorki/features/weather/domain/route_weather_state.dart';
import 'package:velorki/features/weather/presentation/route_weather_section.dart';
import 'package:velorki/features/weather/presentation/route_weather_strip.dart';
import 'package:velorki/features/weather/presentation/weather_keys.dart';
import 'package:velorki_api/velorki_api.dart';

import '../../support/app.dart';
import '../../support/mock_relay.dart';
import 'support/weather_fixtures.dart';

/// 08:00 UTC on the day of the test's clock.
final DateTime _earliest = DateTime.utc(2026, 10, 11, 8);

/// A forecast for a 10 km ride north at 18 km/h: a headwind from the north
/// all day, rain from 14:00 UTC, 12 °C rising by a degree an hour.
RouteWeatherState weatherState({
  DateTime? departure,
  int Function(int hour)? windDir,
  double Function(int hour)? precip,
  double? gust = 12,
}) {
  final samples = sampleRoute(straightRoute(), typicalSpeedKmh: 18);
  final cells = cellsFor(samples);
  final window = requestWindow(
    _earliest,
    samples.last.offset,
    sliderSpan: departureSpan,
  );
  final forecast = uniformForecast(
    cells.cells.length,
    hours(
      window.from,
      window.hours,
      (t, i) => hour(
        t,
        temp: 12.0 + i,
        windDir: windDir?.call(i) ?? 0,
        precip: precip?.call(i) ?? (t.hour >= 14 ? 2 : 0),
        gust: gust,
      ),
    ),
  );
  return RouteWeatherState.evaluated(
    departure: departure ?? _earliest,
    earliestDeparture: _earliest,
    window: window,
    forecast: forecast,
    samples: samples,
    cells: cells,
  );
}

/// What the section asked of the controller.
class _Asked {
  int retries = 0;
}

/// The controller, holding whatever the test gives it.
class _FakeWeather extends RouteWeatherController {
  _FakeWeather(this._initial, this._asked);

  final AsyncValue<RouteWeatherState?> _initial;
  final _Asked _asked;

  @override
  AsyncValue<RouteWeatherState?> build(WeatherRoute route) {
    // As the planner's own does: a tree pumped over this one leaves it be.
    ref.keepAlive();
    // As the real one does: the departure follows the time control.
    ref.listen(weatherRadarOffsetProvider, (_, offset) {
      final s = state.value!;
      state = AsyncData<RouteWeatherState?>(
        s.withDeparture(s.earliestDeparture.add(Duration(minutes: offset))),
      );
    });
    return _initial;
  }

  @override
  void retry() => _asked.retries++;
}

class _Pumped {
  _Pumped(this.container, this.weather, this.prefs);

  final ProviderContainer container;
  final _Asked weather;
  final SharedPreferences prefs;
}

Future<_Pumped> _pump(
  WidgetTester tester, {
  AsyncValue<RouteWeatherState?>? weather,
  PlusAccess access = PlusAccess.granted,
  bool withRelay = true,
  WeatherRoute route = plannerWeatherRoute,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final asked = _Asked();
  final fake = _FakeWeather(
    weather ?? AsyncData<RouteWeatherState?>(weatherState()),
    asked,
  );
  final relay = MockRelay();
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const SizedBox(key: Key('above'), height: 10),
              RouteWeatherSection(route: route),
              const SizedBox(key: Key('below'), height: 10),
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
      sharedPreferencesProvider.overrideWithValue(prefs),
      localeCountryProvider.overrideWithValue('DE'),
      relayClientProvider.overrideWithValue(withRelay ? relay.client() : null),
      plusAccessProvider.overrideWith((ref, feature) => access),
      routeWeatherControllerProvider.overrideWith2((_) => fake),
      weatherClockProvider.overrideWithValue(
        () => DateTime.utc(2026, 10, 11, 7, 50),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.binding.setSurfaceSize(const Size(400, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: testRouterApp(routerConfig: router),
    ),
  );
  await tester.pump();
  return _Pumped(container, asked, prefs);
}

double _gap(WidgetTester tester) =>
    tester.getTopLeft(find.byKey(const Key('below'))).dy -
    tester.getBottomLeft(find.byKey(const Key('above'))).dy;

void main() {
  testWidgets('a build without the relay shows nothing', (tester) async {
    await _pump(tester, withRelay: false);
    expect(_gap(tester), 0);
    expect(find.text(l10n.weatherTitle.toUpperCase()), findsNothing);
  });

  testWidgets('shows nothing while the store has not answered', (tester) async {
    await _pump(tester, access: PlusAccess.unknown);
    expect(_gap(tester), 0);
  });

  testWidgets('without Plus, a teaser leads to the paywall', (tester) async {
    await _pump(tester, access: PlusAccess.missing);
    expect(find.text(l10n.weatherTitle.toUpperCase()), findsOneWidget);
    expect(find.text(l10n.plusFeatureWeatherBody), findsOneWidget);
    expect(find.byType(RouteWeatherStrip), findsNothing);
    await tester.tap(find.text(l10n.plusSeeDetails));
    await tester.pumpAndSettle();
    expect(find.text('paywall'), findsOneWidget);
  });

  testWidgets('no route: nothing', (tester) async {
    await _pump(tester, weather: const AsyncData<RouteWeatherState?>(null));
    expect(_gap(tester), 0);
  });

  testWidgets('while loading, it holds the height the forecast will have', (
    tester,
  ) async {
    await _pump(tester, weather: const AsyncLoading<RouteWeatherState?>());
    expect(find.text(l10n.weatherTitle.toUpperCase()), findsOneWidget);
    expect(find.byType(RouteWeatherStrip), findsOneWidget);
    final loading = _gap(tester);
    expect(loading, greaterThan(weatherStripHeight));

    // A line of two lines: the test's font, a full em a letter, makes the
    // gusts' line three.
    await _pump(
      tester,
      weather: AsyncData<RouteWeatherState?>(weatherState(gust: null)),
    );
    expect(_gap(tester), loading);
  });

  testWidgets('a failure says why and asks again on Try again', (tester) async {
    final pumped = await _pump(
      tester,
      weather: AsyncError<RouteWeatherState?>(
        WeatherProblem(WeatherFailure.relay, (l10n) => l10n.weatherDry),
        StackTrace.empty,
      ),
    );
    expect(find.text(l10n.weatherDry), findsOneWidget);
    await tester.tap(find.text(l10n.weatherTryAgain));
    expect(pumped.weather.retries, 1);
  });

  testWidgets('the forecast: the line that sums it up, the strip with its '
      'rows named and its key, and the attribution', (tester) async {
    await _pump(tester);
    // Dry, the wind from the north on a route north, 12 °C at 08:00 and
    // 13 °C by the end at 08:33, gusts of 12 m/s.
    final line = [
      l10n.weatherDry,
      l10n.weatherMostlyHeadwind,
      l10n.weatherTemperatureRange(
        '12',
        formatTemperature(l10n, UnitSystem.metric, 13),
      ),
      l10n.weatherGusts(
        formatMeasure(l10n, formatSpeed(UnitSystem.metric, 12)),
      ),
    ].join(' · ');
    expect(find.text(line), findsOneWidget);
    expect(find.byType(RouteWeatherStrip), findsOneWidget);
    final strip = tester.widget<RouteWeatherStrip>(
      find.byType(RouteWeatherStrip),
    );
    expect(strip.rowLabels, (
      wind: l10n.weatherWind,
      rain: l10n.weatherRain,
      temperature: l10n.weatherTemperatureShort,
    ));
    // The key to the arrows' colours, under the strip.
    expect(find.byType(WindColourKey), findsOneWidget);
    for (final name in [
      l10n.weatherKeyHeadwind,
      l10n.weatherKeyCrosswind,
      l10n.weatherKeyTailwind,
    ]) {
      expect(find.text(name), findsOneWidget);
    }
    expect(
      tester.getTopLeft(find.byType(WindColourKey)).dy,
      greaterThan(tester.getBottomLeft(find.byType(RouteWeatherStrip)).dy),
    );
    expect(find.text(l10n.weatherAttribution('MET Norway')), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(RouteWeatherStrip)).label,
      contains(l10n.weatherDry),
    );
    expectNoClippedText(tester);
  });

  testWidgets('rain on the way leads the line, with when and where', (
    tester,
  ) async {
    // Rain from 08:00 UTC's next hour on: 3 mm/h from 09:00, interpolated
    // up from nothing at 08:00.
    await _pump(
      tester,
      weather: AsyncData<RouteWeatherState?>(
        weatherState(precip: (i) => i == 0 ? 0 : 3),
      ),
    );
    final text = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .firstWhere((t) => t.contains(' · '));
    final rainy = l10n.weatherRainLikelyFrom('', '').split(' ').first;
    expect(text, startsWith(rainy));
    expect(text, isNot(contains(l10n.weatherDry)));
  });

  testWidgets('the attribution opens the licences', (tester) async {
    await _pump(tester);
    await tester.tap(find.text(l10n.weatherAttribution('MET Norway')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.weatherSourcesTitle), findsOneWidget);
    expect(find.text(metno.licence), findsOneWidget);
    expect(find.text(metno.url), findsOneWidget);
  });

  testWidgets('on the Plan tab the departure is the time control over the '
      'map: the section says it, with no slider of its own', (tester) async {
    final pumped = await _pump(tester);
    expect(find.byType(Slider), findsNothing);
    final today = find.textContaining(l10n.weatherDepartureToday('').trim());
    expect(today, findsOneWidget);
    final before = tester.widget<Text>(today).data;
    pumped.container.read(weatherRadarOffsetProvider.notifier).set(60);
    await tester.pump();
    expect(tester.widget<Text>(today).data, isNot(before));
  });

  testWidgets('on a saved route\'s page a slider on the time control\'s '
      'steps sets the shared step when let go', (tester) async {
    final pumped = await _pump(tester, route: const SavedWeatherRoute('r1'));
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.value, 0);
    expect(slider.divisions, weatherRadarOffsets.length - 1);
    final index = weatherSliderIndexOf(60);
    slider.onChanged!(index.toDouble());
    await tester.pump();
    // Nothing set while the finger is down.
    expect(pumped.container.read(weatherRadarOffsetProvider), 0);
    expect(tester.widget<Slider>(find.byType(Slider)).value, index.toDouble());
    tester.widget<Slider>(find.byType(Slider)).onChangeEnd!(index.toDouble());
    await tester.pump();
    expect(pumped.container.read(weatherRadarOffsetProvider), 60);

    // Set elsewhere (the Plan tab's control), the slider follows.
    pumped.container.read(weatherRadarOffsetProvider.notifier).set(180);
    await tester.pump();
    expect(
      tester.widget<Slider>(find.byType(Slider)).value,
      weatherSliderIndexOf(180).toDouble(),
    );
  });

  testWidgets('Best time moves the time control to the best step, then says '
      'so', (tester) async {
    // Rain until 12:00 UTC, dry after: the best departure is the first dry
    // step.
    final pumped = await _pump(
      tester,
      weather: AsyncData<RouteWeatherState?>(
        weatherState(precip: (i) => i < 4 ? 3 : 0),
      ),
    );
    await tester.tap(find.text(l10n.weatherBestTime));
    await tester.pump();
    final step = pumped.container.read(weatherRadarOffsetProvider);
    expect(weatherRadarOffsets, contains(step));
    expect(step, greaterThan(180));
    expect(find.text(l10n.weatherBestTimeNow), findsOneWidget);
    final button = tester.widget<TextButton>(
      find.ancestor(
        of: find.text(l10n.weatherBestTimeNow),
        matching: find.byWidgetPredicate((w) => w is TextButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  test('the fixture is from MET Norway', () {
    expect(weatherState().summary.sources, const <WeatherSource>[metno]);
  });
}

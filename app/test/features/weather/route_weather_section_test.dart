import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/features/integrations/common/data/relay_client_provider.dart';
import 'package:velorki/features/planner/presentation/route_format.dart';
import 'package:velorki/features/settings/data/units.dart';
import 'package:velorki/features/subscription/application/plus_access.dart';
import 'package:velorki/features/weather/application/route_weather_controller.dart';
import 'package:velorki/features/weather/application/wind_on_map.dart';
import 'package:velorki/features/weather/domain/route_sampling.dart';
import 'package:velorki/features/weather/domain/route_weather_state.dart';
import 'package:velorki/features/weather/presentation/route_weather_section.dart';
import 'package:velorki/features/weather/presentation/route_weather_strip.dart';
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
        gust: 12,
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
  final List<DateTime> departures = <DateTime>[];
  int retries = 0;
}

/// The controller, holding whatever the test gives it.
class _FakeWeather extends RouteWeatherController {
  _FakeWeather(this._initial, this._asked);

  final AsyncValue<RouteWeatherState?> _initial;
  final _Asked _asked;

  @override
  AsyncValue<RouteWeatherState?> build() => _initial;

  @override
  void setDeparture(DateTime time) {
    _asked.departures.add(time);
    state = AsyncData<RouteWeatherState?>(state.value!.withDeparture(time));
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
            children: const [
              SizedBox(key: Key('above'), height: 10),
              RouteWeatherSection(),
              SizedBox(key: Key('below'), height: 10),
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
      routeWeatherControllerProvider.overrideWith(() => fake),
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

    await _pump(tester);
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

  testWidgets('the forecast: summary, strip and attribution', (tester) async {
    await _pump(tester);
    // 12 °C at 08:00, 13 °C by the end of the ride at 08:33.
    expect(
      find.text(
        l10n.weatherTemperatureRange(
          '12',
          formatTemperature(l10n, UnitSystem.metric, 13),
        ),
      ),
      findsOneWidget,
    );
    // The wind from the north, the route heading north: all of it ahead.
    expect(
      find.text(l10n.weatherHeadwind(formatPercent(l10n, 1))),
      findsOneWidget,
    );
    expect(find.text(l10n.weatherDry), findsOneWidget);
    expect(find.textContaining(l10n.weatherGusts('').trim()), findsOneWidget);
    expect(find.byType(RouteWeatherStrip), findsOneWidget);
    expect(find.text(l10n.weatherAttribution('MET Norway')), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(RouteWeatherStrip)).label,
      contains(l10n.weatherDry),
    );
    expectNoClippedText(tester);
  });

  testWidgets('the attribution opens the licences', (tester) async {
    await _pump(tester);
    await tester.tap(find.text(l10n.weatherAttribution('MET Norway')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.weatherSourcesTitle), findsOneWidget);
    expect(find.text(metno.licence), findsOneWidget);
    expect(find.text(metno.url), findsOneWidget);
  });

  testWidgets('the slider moves the departure in quarter hours', (
    tester,
  ) async {
    final pumped = await _pump(tester);
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.value, 0);
    expect(slider.divisions, 96);
    slider.onChanged!(4);
    await tester.pump();
    expect(pumped.weather.departures, [
      _earliest.add(const Duration(hours: 1)),
    ]);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 4);
  });

  testWidgets('Best time moves to the best departure, then says so', (
    tester,
  ) async {
    // Rain until 12:00 UTC, dry after: the best departure is the first dry
    // one.
    final pumped = await _pump(
      tester,
      weather: AsyncData<RouteWeatherState?>(
        weatherState(precip: (i) => i < 4 ? 3 : 0),
      ),
    );
    await tester.tap(find.text(l10n.weatherBestTime));
    await tester.pump();
    expect(pumped.weather.departures, hasLength(1));
    expect(
      pumped.weather.departures.single.isAfter(
        _earliest.add(const Duration(hours: 3)),
      ),
      isTrue,
    );
    expect(find.text(l10n.weatherBestTimeNow), findsOneWidget);
    final button = tester.widget<TextButton>(
      find.ancestor(
        of: find.text(l10n.weatherBestTimeNow),
        matching: find.byWidgetPredicate((w) => w is TextButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('the wind switch is remembered', (tester) async {
    final pumped = await _pump(tester);
    expect(pumped.container.read(windOnMapProvider), isFalse);
    await tester.tap(find.text(l10n.weatherWindOnMap));
    await tester.pump();
    expect(pumped.container.read(windOnMapProvider), isTrue);
    expect(pumped.prefs.getBool('weather.wind_on_map'), isTrue);
  });

  test('the fixture is from MET Norway', () {
    expect(weatherState().summary.sources, const <WeatherSource>[metno]);
  });
}

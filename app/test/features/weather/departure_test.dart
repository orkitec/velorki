import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/integrations/common/data/relay_client_provider.dart';
import 'package:velorki/features/map/data/weather_map_preferences.dart';
import 'package:velorki/features/map/domain/weather_map.dart';
import 'package:velorki/features/subscription/application/plus_access.dart';
import 'package:velorki/features/weather/application/free_route_weather.dart';
import 'package:velorki/features/weather/application/route_colouring.dart';
import 'package:velorki/features/weather/application/route_overlay.dart';
import 'package:velorki/features/weather/application/route_weather_controller.dart';
import 'package:velorki/features/weather/data/dwd_route_forecast.dart';
import 'package:velorki/features/weather/domain/route_sampling.dart';
import 'package:velorki/features/weather/domain/route_weather_state.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/mock_relay.dart';
import 'support/weather_fixtures.dart';

/// A 10 km route north, half an hour at 18 km/h.
final List<TrackPoint> _geometry = <TrackPoint>[
  for (var d = 0.0; d <= 10000; d += 100)
    TrackPoint(destinationPoint(const LatLng(50, 8), 0, d), ele: 100),
];

/// 07:50 UTC.
final DateTime _start = DateTime.utc(2026, 10, 11, 7, 50);

void main() {
  group('the free forecast departs when the time control says', () {
    Set<DateTime> windHours(FakeDwdClient client, int from) => {
      for (final (coverage, hour) in client.requests.skip(from))
        if (coverage == dwdWindCoverage) hour,
    };

    test('at now plus its step, each sample at the hour the rider is '
        'there; a drag asks nothing, and steps set in quick succession ask '
        'once', () {
      fakeAsync((async) {
        final client = FakeDwdClient();
        final container = ProviderContainer(
          overrides: [
            weatherRouteGeometryProvider(plannerWeatherRoute)
                .overrideWithValue(_geometry),
            weatherRouteSpeedProvider(plannerWeatherRoute)
                .overrideWithValue(18),
            dwdForecastClientProvider.overrideWithValue(client),
            weatherClockProvider.overrideWithValue(
              () => _start.add(async.elapsed),
            ),
          ],
        );
        final provider = freeRouteWeatherProvider(plannerWeatherRoute);
        container.listen(provider, (_, _) {});
        async.elapse(weatherDebounce);
        async.flushMicrotasks();
        expect(container.read(provider).value!.departure, _start);
        expect(windHours(client, 0), {
          DateTime.utc(2026, 10, 11, 7),
          DateTime.utc(2026, 10, 11, 8),
        });

        // Dragged over the steps: only the preview moves.
        final asked = client.requests.length;
        final preview = container.read(weatherRadarPreviewProvider.notifier);
        for (final step in weatherRadarOffsets.take(10)) {
          preview.set(step);
          async.elapse(const Duration(milliseconds: 100));
        }
        preview.set(null);
        async.elapse(weatherDebounce);
        async.flushMicrotasks();
        expect(client.requests, hasLength(asked));

        // Let go three times within the debounce: asked once, for the last.
        final offset = container.read(weatherRadarOffsetProvider.notifier);
        for (final step in [60, 120, 180]) {
          offset.set(step);
          async.elapse(const Duration(milliseconds: 300));
        }
        async.elapse(weatherDebounce);
        async.flushMicrotasks();
        // A few seconds on, the same minute: 10:50.
        final state = container.read(provider).value!;
        expect(state.earliestDeparture, _start);
        expect(state.departure, _start.add(const Duration(minutes: 180)));
        expect(windHours(client, asked), {
          DateTime.utc(2026, 10, 11, 10),
          DateTime.utc(2026, 10, 11, 11),
        });
        container.dispose();
      });
    });
  });

  test('the route keeps its colours while the free forecast loads for a '
      'new departure, and loses them for another line', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    fakeAsync((async) {
      final line = _Line();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          relayClientProvider.overrideWithValue(null),
          plusAccessProvider.overrideWith((ref, feature) => PlusAccess.missing),
          _line.overrideWith(() => line),
          weatherRouteGeometryProvider(plannerWeatherRoute)
              .overrideWith((ref) => ref.watch(_line)),
          weatherRouteSpeedProvider(plannerWeatherRoute).overrideWithValue(18),
          dwdForecastClientProvider.overrideWithValue(FakeDwdClient()),
          weatherClockProvider.overrideWithValue(
            () => _start.add(async.elapsed),
          ),
        ],
      );
      final empty = <bool>[];
      unawaited(
        container
            .read(routeOverlayChoiceProvider.notifier)
            .set(RouteOverlay.wind),
      );
      container.listen(
        routeColouringProvider(plannerWeatherRoute),
        (_, next) => empty.add(next.lines.wind.isEmpty),
        fireImmediately: true,
      );
      async.elapse(weatherDebounce);
      async.flushMicrotasks();
      expect(empty.last, isFalse);

      // A new departure: the map's segments never go empty on the way.
      empty.clear();
      container.read(weatherRadarOffsetProvider.notifier).set(180);
      for (var i = 0; i < 20; i++) {
        async.elapse(const Duration(milliseconds: 100));
        async.flushMicrotasks();
      }
      expect(empty, isNotEmpty);
      expect(empty, everyElement(isFalse));
      expect(
        container
            .read(routeColourWeatherProvider(plannerWeatherRoute))
            .value!
            .offsetMinutes,
        180,
      );

      // Another line, whose grids are not loaded: cleared until its own
      // forecast comes.
      empty.clear();
      line.set(<TrackPoint>[
        for (var d = 0.0; d <= 10000; d += 100)
          TrackPoint(destinationPoint(const LatLng(48, 11), 0, d), ele: 500),
      ]);
      async.elapse(const Duration(milliseconds: 100));
      async.flushMicrotasks();
      expect(empty, contains(isTrue));
      async.elapse(weatherDebounce);
      async.flushMicrotasks();
      expect(empty.last, isFalse);
      container.dispose();
    });
  });

  group('dragged, the route\'s colours follow the step under the finger', () {
    ProviderContainer open(
      FakeAsync async, {
      required SharedPreferences prefs,
      FakeDwdClient? client,
      RouteWeatherState? plus,
    }) {
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          relayClientProvider.overrideWithValue(
            plus == null ? null : MockRelay().client(),
          ),
          plusAccessProvider.overrideWith(
            (ref, feature) =>
                plus == null ? PlusAccess.missing : PlusAccess.granted,
          ),
          if (plus != null)
            routeWeatherControllerProvider.overrideWith2((_) => _Plus(plus)),
          weatherRouteGeometryProvider(plannerWeatherRoute)
              .overrideWithValue(_geometry),
          weatherRouteSpeedProvider(plannerWeatherRoute).overrideWithValue(18),
          dwdForecastClientProvider.overrideWithValue(
            client ?? FakeDwdClient(),
          ),
          weatherClockProvider.overrideWithValue(
            () => _start.add(async.elapsed),
          ),
        ],
      );
      unawaited(
        container
            .read(routeOverlayChoiceProvider.notifier)
            .set(RouteOverlay.wind),
      );
      container.listen(routeColouringProvider(plannerWeatherRoute), (_, _) {});
      return container;
    }

    RouteWeatherState? shown(ProviderContainer c) =>
        c.read(routeColourWeatherProvider(plannerWeatherRoute)).value;

    test('free: from the grids fetched ahead, nothing asked on the way; a '
        'step without them keeps the colours', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      fakeAsync((async) {
        // Nothing for the hours past six tomorrow morning.
        final client = FakeDwdClient(
          missing: (t) => t.isAfter(DateTime.utc(2026, 10, 12, 6)),
        );
        final container = open(async, prefs: prefs, client: client);
        async.elapse(weatherDebounce);
        async.flushMicrotasks();
        expect(shown(container)!.offsetMinutes, 0);
        // Fetched ahead: every hour the control reaches, and the ride.
        final ahead = {
          for (final (coverage, hour) in client.requests)
            if (coverage == dwdWindCoverage) hour,
        };
        expect(ahead, contains(DateTime.utc(2026, 10, 12, 8)));

        final asked = client.requests.length;
        final preview = container.read(weatherRadarPreviewProvider.notifier);
        for (final step in [15, 60, 180, 600]) {
          preview.set(step);
          async.flushMicrotasks();
          expect(shown(container)!.offsetMinutes, step);
          expect(
            container
                .read(routeColouringProvider(plannerWeatherRoute))
                .lines
                .wind,
            isNotEmpty,
          );
        }
        expect(client.requests, hasLength(asked));
        // A day ahead the grids did not come: the colours stay.
        preview.set(1440);
        async.flushMicrotasks();
        expect(shown(container)!.offsetMinutes, 600);
        expect(
          container.read(routeColouringProvider(plannerWeatherRoute)).isEmpty,
          isFalse,
        );
        container.dispose();
      });
    });

    test('Plus: evaluated on the phone for each step; a step past the '
        'answer keeps the colours', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final samples = sampleRoute(straightRoute(), typicalSpeedKmh: 18);
      final cells = cellsFor(samples);
      // Two hours of slider in the answer.
      final window = requestWindow(
        _start,
        samples.last.offset,
        sliderSpan: const Duration(hours: 2),
      );
      final plus = RouteWeatherState.evaluated(
        departure: _start,
        earliestDeparture: _start,
        window: window,
        forecast: uniformForecast(
          cells.cells.length,
          hours(window.from, window.hours, (t, _) => hour(t)),
        ),
        samples: samples,
        cells: cells,
      );
      fakeAsync((async) {
        final container = open(async, prefs: prefs, plus: plus);
        async.flushMicrotasks();
        final preview = container.read(weatherRadarPreviewProvider.notifier);
        preview.set(60);
        async.flushMicrotasks();
        expect(shown(container)!.offsetMinutes, 60);
        preview.set(600);
        async.flushMicrotasks();
        expect(shown(container)!.offsetMinutes, 60);
        preview.set(null);
        async.flushMicrotasks();
        expect(shown(container)!.offsetMinutes, 0);
        container.dispose();
      });
    });
  });

  group('the Plan tab\'s time control', () {
    Future<PlannerTimeControl> control({
      bool route = true,
      String overlay = 'gradient',
      PlusAccess access = PlusAccess.missing,
    }) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          relayClientProvider.overrideWithValue(MockRelay().client()),
          plusAccessProvider.overrideWith((ref, feature) => access),
          weatherRouteGeometryProvider(plannerWeatherRoute)
              .overrideWithValue(route ? _geometry : null),
        ],
      );
      addTearDown(container.dispose);
      // Picked in this launch, as the rider does.
      await container
          .read(routeOverlayChoiceProvider.notifier)
          .set(RouteOverlay.values.byName(overlay));
      return container.read(plannerTimeControlProvider);
    }

    test('is the map\'s alone without a route', () async {
      expect(
        await control(route: false, overlay: 'wind'),
        PlannerTimeControl.map,
      );
    });

    test(
      'with a route is its departure, shown whatever the layers, with '
      'Plus or without: the route\'s weather is shown for everyone',
      () async {
        expect(await control(), PlannerTimeControl.departureShown);
        expect(
          await control(overlay: 'wind'),
          PlannerTimeControl.departureShown,
        );
        expect(
          await control(overlay: 'rain'),
          PlannerTimeControl.departureShown,
        );
        expect(
          await control(access: PlusAccess.granted),
          PlannerTimeControl.departureShown,
        );
      },
    );
  });
}

/// The planned line, changed by a test.
class _Line extends Notifier<List<TrackPoint>?> {
  @override
  List<TrackPoint>? build() => _geometry;

  void set(List<TrackPoint> line) => state = line;
}

final NotifierProvider<_Line, List<TrackPoint>?> _line =
    NotifierProvider<_Line, List<TrackPoint>?>(_Line.new);

/// The relay's forecast, as if it had answered.
class _Plus extends RouteWeatherController {
  _Plus(this.weather);

  final RouteWeatherState weather;

  @override
  AsyncValue<RouteWeatherState?> build(WeatherRoute route) =>
      AsyncData<RouteWeatherState?>(weather);
}

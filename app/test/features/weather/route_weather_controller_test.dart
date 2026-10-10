import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/plus/plus_gate.dart';
import 'package:velorki/features/integrations/common/data/relay_client_provider.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/domain/planner_state.dart';
import 'package:velorki/features/weather/application/route_weather_controller.dart';
import 'package:velorki/features/weather/domain/route_weather_state.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';
import 'package:velorki_api/velorki_api.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/mock_relay.dart';
import '../../support/openapi_schema.dart';
import 'support/weather_fixtures.dart';

final AppLocalizations _l10n = lookupAppLocalizations(const Locale('en'));

final RouteResult _north = straightRoute();
final RouteResult _munich = straightRoute(start: const LatLng(48.1, 11.5));

/// The Plan tab, showing whatever route the test puts on it.
class _StubPlanner extends PlannerController {
  _StubPlanner(this.initial);

  final RouteResult? initial;

  @override
  PlannerState build() => PlannerState(route: AsyncData<RouteResult?>(initial));

  void show(RouteResult? route) =>
      state = state.copyWith(route: AsyncData<RouteResult?>(route));
}

/// An answer for every cell [request] asks about: [hourAt] for each hour.
Map<String, Object?> _answer(
  RecordedWeatherRequest request, {
  Map<String, Object?> Function(int i)? hourAt,
}) => {
  'cells': [
    for (final _ in request.cells)
      {
        'source': 'metno',
        'hours': [
          for (var i = 0; i < request.hours; i++)
            {
              't': weatherTime(request.from.add(Duration(hours: i))),
              'temp': 12,
              'wind': 5,
              'windDir': 0,
              'gust': null,
              'precip': 0,
              'precipProb': null,
              'cloud': null,
              ...?hourAt?.call(i),
            },
        ],
      },
  ],
  'sources': [metno.toJson()],
};

class _Harness {
  _Harness(this.async, {bool entitled = true, bool withRelay = true}) {
    container = ProviderContainer(
      overrides: [
        relayClientProvider.overrideWith((ref) {
          if (!withRelay) return null;
          final client = relay.client();
          ref.onDispose(client.close);
          return client;
        }),
        plannerControllerProvider.overrideWith(() => _StubPlanner(null)),
        weatherClockProvider.overrideWithValue(() => start.add(async.elapsed)),
      ],
    );
    container.read(plusEntitledProvider.notifier).value = entitled;
    container.listen(routeWeatherControllerProvider, (_, _) {});
  }

  final FakeAsync async;
  final MockRelay relay = MockRelay(schemas: OpenApi.load().check);
  late final ProviderContainer container;

  /// 07:50 UTC: the first departure is 08:00.
  static final DateTime start = DateTime.utc(2026, 10, 11, 7, 50);

  void show(RouteResult? route) =>
      (container.read(plannerControllerProvider.notifier) as _StubPlanner).show(
        route,
      );

  void entitle(bool entitled) =>
      container.read(plusEntitledProvider.notifier).value = entitled;

  AsyncValue<RouteWeatherState?> get state =>
      container.read(routeWeatherControllerProvider);

  RouteWeatherController get controller =>
      container.read(routeWeatherControllerProvider.notifier);

  void answerEveryCell({Duration delay = Duration.zero}) =>
      relay.replyWeather(WeatherReply.answering(_answer, delay: delay));

  void settle([Duration by = weatherDebounce]) {
    async.elapse(by);
    async.flushMicrotasks();
  }
}

void runFake(void Function(FakeAsync async) body) => fakeAsync((async) {
  body(async);
  async.flushTimers();
});

void main() {
  test('asks nothing for a rider without Velorki Plus', () {
    runFake((async) {
      final h = _Harness(async, entitled: false);
      h.show(_north);
      h.settle(const Duration(seconds: 5));
      expect(h.relay.weatherRequests, isEmpty);
      expect(h.state, const AsyncData<RouteWeatherState?>(null));
      h.container.dispose();
    });
  });

  test('asks nothing in a build without a relay', () {
    runFake((async) {
      final h = _Harness(async, withRelay: false);
      h.show(_north);
      h.settle(const Duration(seconds: 5));
      expect(h.state, const AsyncData<RouteWeatherState?>(null));
      h.container.dispose();
    });
  });

  test('asks a second after the route stops changing', () {
    runFake((async) {
      final h = _Harness(async);
      h.answerEveryCell();
      h.show(_munich);
      h.settle(const Duration(milliseconds: 600));
      h.show(_north);
      h.settle(const Duration(milliseconds: 999));
      expect(h.relay.weatherRequests, isEmpty);
      expect(h.state.isLoading, isTrue);
      h.settle(const Duration(milliseconds: 1));

      final request = h.relay.weatherRequests.single;
      expect(request.from, DateTime.utc(2026, 10, 11, 8));
      // 10 km at 18 km/h, 24 h of slider and the hour it ends in.
      expect(request.hours, 26);
      expect((request.cells.first['lat']! as num).toDouble(), 50);
      final state = h.state.value!;
      expect(state.departure, DateTime.utc(2026, 10, 11, 8));
      expect(state.weather.complete, isTrue);
      // A north wind, riding north.
      expect(state.summary.headwindShare, 1);
      expect(state.summary.sources, [metno]);
      h.container.dispose();
    });
  });

  test('keeps an answer for half an hour', () {
    runFake((async) {
      final h = _Harness(async);
      h
        ..answerEveryCell()
        ..answerEveryCell()
        ..answerEveryCell();
      h.show(_north);
      h.settle();
      h.show(_munich);
      h.settle();
      h.show(_north);
      h.settle();
      expect(h.relay.weatherRequests, hasLength(2));
      expect(h.state.value!.samples.first.position.lat, closeTo(50, 1e-9));

      h.settle(weatherCacheTtl);
      h.show(_munich);
      h.settle();
      expect(h.relay.weatherRequests, hasLength(3));
      h.container.dispose();
    });
  });

  test('moves the departure on the phone inside the hours fetched', () {
    runFake((async) {
      final h = _Harness(async);
      h
        ..answerEveryCell()
        ..answerEveryCell();
      h.show(_north);
      h.settle();
      final later = DateTime.utc(2026, 10, 11, 14, 30);
      h.controller.setDeparture(later);
      expect(h.relay.weatherRequests, hasLength(1));
      expect(h.state.value!.departure, later);
      expect(h.state.value!.weather.weather.first!.at, later);

      // A day later is outside them: asked for again, at once.
      final tomorrow = DateTime.utc(2026, 10, 12, 9);
      h.controller.setDeparture(tomorrow);
      expect(h.state.isLoading, isTrue);
      async.flushMicrotasks();
      expect(h.relay.weatherRequests, hasLength(2));
      expect(h.relay.weatherRequests.last.from, tomorrow);
      expect(h.state.value!.departure, tomorrow);
      h.container.dispose();
    });
  });

  test('drops an answer to a route that has changed since', () {
    runFake((async) {
      final h = _Harness(async);
      h.relay
        ..replyWeather(
          WeatherReply.answering(
            (r) => _answer(r, hourAt: (_) => {'temp': -5}),
            delay: const Duration(seconds: 5),
          ),
        )
        ..replyWeather(const WeatherReply.answering(_answer));
      h.show(_north);
      h.settle();
      expect(h.relay.weatherRequests, hasLength(1));
      h.show(_munich);
      h.settle(const Duration(seconds: 10));
      expect(h.relay.weatherRequests, hasLength(2));
      final state = h.state.value!;
      expect(state.samples.first.position.lat, closeTo(48.1, 1e-9));
      expect(state.summary.minTemp, 12);
      h.container.dispose();
    });
  });

  test('words a relay failure and clears it once Plus is bought', () {
    runFake((async) {
      final h = _Harness(async);
      h.relay.replyWeather(const WeatherReply.error(notEntitled));
      h.show(_north);
      h.settle();
      final problem = h.state.error! as WeatherProblem;
      expect(problem.failure, WeatherFailure.notEntitled);
      expect(problem.describe(_l10n), _l10n.relayPlusNeeded);

      h.entitle(false);
      expect(h.state, const AsyncData<RouteWeatherState?>(null));
      h.answerEveryCell();
      h.entitle(true);
      expect(h.state.isLoading, isTrue);
      h.settle();
      expect(h.state.value, isNotNull);
      h.container.dispose();
    });
  });

  test('maps rate limits and upstream failures', () {
    runFake((async) {
      final h = _Harness(async);
      h.relay
        ..replyWeather(const WeatherReply.error(rateLimited))
        ..replyWeather(const WeatherReply.error(upstreamError));
      h.show(_north);
      h.settle();
      final limited = h.state.error! as WeatherProblem;
      expect(limited.failure, WeatherFailure.rateLimited);
      expect(limited.retryAfterS, 6);
      expect(limited.describe(_l10n), _l10n.relayTooManyRequests);

      h.show(_munich);
      h.settle();
      final upstream = h.state.error! as WeatherProblem;
      expect(upstream.failure, WeatherFailure.relay);
      expect(upstream.describe(_l10n), _l10n.relayUpstreamFailed);
      h.container.dispose();
    });
  });

  test('clears the weather with the route', () {
    runFake((async) {
      final h = _Harness(async);
      h.answerEveryCell();
      h.show(_north);
      h.settle();
      expect(h.state.value, isNotNull);
      h.show(null);
      expect(h.state, const AsyncData<RouteWeatherState?>(null));
      h.container.dispose();
    });
  });

  test('suggests the departure that misses the rain', () {
    runFake((async) {
      final h = _Harness(async);
      h.relay.replyWeather(
        WeatherReply.answering(
          (r) =>
              _answer(r, hourAt: (i) => {'wind': 0, 'precip': i < 4 ? 3 : 0}),
        ),
      );
      h.show(_north);
      h.settle();
      expect(h.state.value!.summary.firstRainM, 0);
      expect(
        h.controller.suggestBestDeparture(),
        DateTime.utc(2026, 10, 11, 12),
      );
      h.container.dispose();
    });
  });

  test('scores nothing without a forecast', () {
    runFake((async) {
      final h = _Harness(async, entitled: false);
      expect(h.controller.suggestBestDeparture(), isNull);
      h.container.dispose();
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/weather/domain/route_sampling.dart';
import 'package:velorki/features/weather/domain/route_weather.dart';
import 'package:velorki_api/velorki_api.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/weather_fixtures.dart';

final DateTime _t0 = DateTime.utc(2026, 10, 11, 8);

/// A sample heading [bearing] at [distanceM], [offset] into the ride.
RouteWeatherSample _sample(
  double distanceM, {
  double bearing = 0,
  Duration offset = Duration.zero,
}) => RouteWeatherSample(
  distanceM: distanceM,
  position: const LatLng(50, 8),
  bearingDeg: bearing,
  offset: offset,
);

/// One cell answering [samples] with [hours].
RouteWeather _evaluate(
  List<RouteWeatherSample> samples,
  List<WeatherHour> hours, {
  DateTime? departure,
}) => evaluate(
  uniformForecast(1, hours),
  samples,
  List<int>.filled(samples.length, 0),
  departure ?? _t0,
);

void main() {
  group('windOnRoute', () {
    test('wind from the north is a headwind riding north', () {
      final w = windOnRoute(5, 0, 0);
      expect(w.headwind, closeTo(5, 1e-9));
      expect(w.crosswind, closeTo(0, 1e-9));
      expect(w.windClass, WindClass.headwind);
    });

    test('wind from the south is a tailwind riding north', () {
      final w = windOnRoute(5, 180, 0);
      expect(w.headwind, closeTo(-5, 1e-9));
      expect(w.windClass, WindClass.tailwind);
    });

    test('wind from the west is a crosswind riding north', () {
      final w = windOnRoute(5, 270, 0);
      expect(w.headwind, closeTo(0, 1e-9));
      expect(w.crosswind, closeTo(5, 1e-9));
      expect(w.windClass, WindClass.crosswind);
    });

    test('the sectors are 60° either side of ahead and behind', () {
      expect(windOnRoute(5, 59, 0).windClass, WindClass.headwind);
      expect(windOnRoute(5, 61, 0).windClass, WindClass.crosswind);
      expect(windOnRoute(5, 119, 0).windClass, WindClass.crosswind);
      expect(windOnRoute(5, 121, 0).windClass, WindClass.tailwind);
      // Across north: heading 350°, wind from 20°.
      expect(windOnRoute(5, 20, 350).windClass, WindClass.headwind);
    });

    test('a light air is calm from wherever', () {
      expect(windOnRoute(1.4, 0, 0).windClass, WindClass.calm);
      expect(windOnRoute(1.5, 0, 0).windClass, WindClass.headwind);
    });
  });

  group('evaluate', () {
    test('interpolates between the hours at the sample\'s time', () {
      final weather = _evaluate(
        [_sample(0, offset: const Duration(minutes: 30))],
        [
          hour(_t0, temp: 10, wind: 4, windDir: 350, precip: 0, gust: 6),
          hour(
            _t0.add(const Duration(hours: 1)),
            temp: 14,
            wind: 6,
            windDir: 10,
            precip: 1,
            gust: 10,
            precipProb: 40,
          ),
        ],
      );
      final w = weather.weather.single!;
      expect(w.at, _t0.add(const Duration(minutes: 30)));
      expect(w.temp, closeTo(12, 1e-9));
      expect(w.windMs, closeTo(5, 1e-9));
      // Along the short way across north, not back round through south.
      expect(w.windFromDeg, closeTo(0, 1e-9));
      expect(w.precipMm, closeTo(0.5, 1e-9));
      expect(w.gust, closeTo(8, 1e-9));
      // One side has no chance figure: the earlier hour's (none) stands.
      expect(w.precipProb, isNull);
      expect(w.headwindMs, closeTo(5, 1e-9));
    });

    test('departure moves every sample along the forecast', () {
      final hrs = hours(_t0, 4, (t, i) => hour(t, temp: 10.0 + i));
      final samples = [
        _sample(0),
        _sample(10000, offset: const Duration(hours: 1)),
      ];
      final early = _evaluate(samples, hrs);
      final late = _evaluate(
        samples,
        hrs,
        departure: _t0.add(const Duration(hours: 2)),
      );
      expect(early.weather.map((w) => w!.temp), [10, 11]);
      expect(late.weather.map((w) => w!.temp), [12, 13]);
    });

    test('a time outside the cell\'s hours, or no hours, is a gap', () {
      final samples = [
        _sample(0),
        _sample(10000, offset: const Duration(hours: 3)),
      ];
      final weather = _evaluate(samples, hours(_t0, 2));
      expect(weather.weather.first, isNotNull);
      expect(weather.weather.last, isNull);
      expect(weather.complete, isFalse);

      final before = _evaluate(
        samples,
        hours(_t0, 2),
        departure: _t0.subtract(const Duration(minutes: 1)),
      );
      expect(before.weather.first, isNull);

      final empty = evaluate(
        const WeatherForecast(
          cells: [WeatherCellForecast(source: null, hours: [])],
          sources: [],
        ),
        samples,
        const [0, 0],
        _t0,
      );
      expect(empty.weather, [null, null]);
      expect(empty.sources, isEmpty);
    });

    test('the last hour itself still has weather', () {
      final weather = _evaluate([
        _sample(0, offset: const Duration(hours: 1)),
      ], hours(_t0, 2));
      expect(weather.weather.single, isNotNull);
    });

    test('names only the sources that answered a sample', () {
      const other = WeatherSource(
        id: 'dwd',
        name: 'Deutscher Wetterdienst',
        url: 'https://www.dwd.de',
        licence: 'DWD',
      );
      final weather = evaluate(
        WeatherForecast(
          cells: [
            WeatherCellForecast(source: 'metno', hours: hours(_t0, 2)),
            WeatherCellForecast(source: 'dwd', hours: hours(_t0, 2)),
          ],
          sources: const [metno, other],
        ),
        [_sample(0)],
        const [0],
        _t0,
      );
      expect(weather.sources, [metno]);
    });
  });

  group('RouteWeatherSummary', () {
    test('shares the distance out by wind class', () {
      // Out north into a north wind, back south with it behind.
      final samples = [
        _sample(0),
        _sample(2000),
        _sample(4000),
        _sample(6000, bearing: 180),
        _sample(8000, bearing: 180),
      ];
      final summary = RouteWeatherSummary.of(
        _evaluate(samples, hours(_t0, 2, (t, _) => hour(t, windDir: 0))),
      );
      // Weights 1, 2, 2, 2, 1 km of 8.
      expect(summary.headwindShare, closeTo(5 / 8, 1e-9));
      expect(summary.tailwindShare, closeTo(3 / 8, 1e-9));
      expect(summary.crosswindShare, 0);
      expect(summary.calmShare, 0);
    });

    test('finds the temperatures, the gusts, the rain and where it starts', () {
      final samples = [
        _sample(0),
        _sample(2000, offset: const Duration(hours: 1)),
        _sample(4000, offset: const Duration(hours: 2)),
      ];
      final hrs = [
        hour(_t0, temp: 8, precip: 0, gust: 7),
        hour(
          _t0.add(const Duration(hours: 1)),
          temp: 11,
          precip: 0.1,
          precipProb: 60,
          gust: 12,
        ),
        hour(_t0.add(const Duration(hours: 2)), temp: 9, precip: 2),
      ];
      final summary = RouteWeatherSummary.of(_evaluate(samples, hrs));
      expect(summary.minTemp, 8);
      expect(summary.maxTemp, 11);
      expect(summary.maxGustMs, 12);
      // The chance, not the amount, makes the middle sample wet.
      expect(summary.firstRainM, 2000);
      // Half an hour at each end, an hour in the middle.
      expect(summary.totalPrecipMm, closeTo(0.1 * 1 + 2 * 0.5, 1e-9));
      expect(summary.sources, [metno]);
    });

    test('a dry ride has no rain start and no gusts without gust data', () {
      final summary = RouteWeatherSummary.of(
        _evaluate([_sample(0), _sample(2000)], hours(_t0, 2)),
      );
      expect(summary.firstRainM, isNull);
      expect(summary.maxGustMs, isNull);
      expect(summary.totalPrecipMm, 0);
    });

    test('gaps count for no wind class', () {
      final summary = RouteWeatherSummary.of(
        _evaluate([
          _sample(0),
          _sample(2000, offset: const Duration(hours: 5)),
        ], hours(_t0, 2)),
      );
      expect(summary.headwindShare, closeTo(0.5, 1e-9));
    });
  });

  group('bestDeparture', () {
    final samples = [
      _sample(0),
      _sample(5000, offset: const Duration(minutes: 30)),
      _sample(10000, offset: const Duration(hours: 1)),
    ];

    test('waits for the rain to pass', () {
      final forecast = uniformForecast(
        1,
        hours(_t0, 16, (t, i) => hour(t, wind: 1, precip: i < 3 ? 2 : 0)),
      );
      final best = bestDeparture(forecast, samples, const [0, 0, 0], from: _t0);
      // Raining until 10:00, and 10:00 itself still has the 2 mm hour
      // fading in behind it; from 11:00 the ride is dry.
      expect(best, DateTime.utc(2026, 10, 11, 11));
    });

    test('leaves when the headwind has dropped', () {
      final forecast = uniformForecast(
        1,
        hours(_t0, 16, (t, i) => hour(t, wind: i < 4 ? 8 : 2, windDir: 0)),
      );
      final best = bestDeparture(forecast, samples, const [0, 0, 0], from: _t0);
      expect(best, DateTime.utc(2026, 10, 11, 12));
    });

    test('keeps the earliest of equal departures', () {
      final forecast = uniformForecast(1, hours(_t0, 16));
      expect(bestDeparture(forecast, samples, const [0, 0, 0], from: _t0), _t0);
    });

    test('a tailwind earns nothing back', () {
      final tail = _evaluate(
        samples,
        hours(_t0, 3, (t, _) => hour(t, windDir: 180)),
      );
      final calm = _evaluate(
        samples,
        hours(_t0, 3, (t, _) => hour(t, wind: 0)),
      );
      expect(departureScore(tail), 0);
      expect(departureScore(calm), 0);
    });

    test('scores rain and headwind by the documented weights', () {
      final wet = _evaluate(
        samples,
        hours(_t0, 3, (t, _) => hour(t, wind: 0, precip: 1)),
      );
      final windy = _evaluate(
        samples,
        hours(_t0, 3, (t, _) => hour(t, wind: 4, windDir: 0)),
      );
      final likely = _evaluate(
        samples,
        hours(_t0, 3, (t, _) => hour(t, wind: 0, precipProb: 30)),
      );
      expect(departureScore(wet), closeTo(rainWeight * 10, 1e-9));
      expect(departureScore(windy), closeTo(headwindWeight * 4 * 10, 1e-9));
      expect(departureScore(likely), closeTo(rainWeight * 0.3 * 10, 1e-9));
    });

    test('skips departures it may not use', () {
      final forecast = uniformForecast(
        1,
        hours(_t0, 16, (t, i) => hour(t, wind: i < 4 ? 8 : 2, windDir: 0)),
      );
      // The calm from 12:00 is ruled out (night, say): the next best is
      // the first hour still allowed.
      final best = bestDeparture(
        forecast,
        samples,
        const [0, 0, 0],
        from: _t0,
        usable: (d) => d.isBefore(DateTime.utc(2026, 10, 11, 12)),
      );
      expect(best, DateTime.utc(2026, 10, 11, 11, 30));
    });

    test("keeps the rider's departure unless waiting is clearly better", () {
      // 8 m/s against now, 7 m/s from 12:00: an eighth better, not a fifth.
      final small = uniformForecast(
        1,
        hours(_t0, 16, (t, i) => hour(t, wind: i < 4 ? 8 : 7, windDir: 0)),
      );
      expect(
        bestDeparture(small, samples, const [0, 0, 0], from: _t0, current: _t0),
        _t0,
      );
      final large = uniformForecast(
        1,
        hours(_t0, 16, (t, i) => hour(t, wind: i < 4 ? 8 : 2, windDir: 0)),
      );
      expect(
        bestDeparture(large, samples, const [0, 0, 0], from: _t0, current: _t0),
        DateTime.utc(2026, 10, 11, 12),
      );
    });

    test('a ride with next to nothing against it needs no better time', () {
      final forecast = uniformForecast(
        1,
        hours(_t0, 16, (t, i) => hour(t, wind: i < 4 ? 0.04 : 0, windDir: 0)),
      );
      expect(
        bestDeparture(
          forecast,
          samples,
          const [0, 0, 0],
          from: _t0,
          current: _t0,
        ),
        _t0,
      );
    });

    test('is null when no departure has weather for the whole ride', () {
      final forecast = uniformForecast(1, hours(_t0, 1));
      expect(
        bestDeparture(forecast, samples, const [0, 0, 0], from: _t0),
        isNull,
      );
    });
  });
}

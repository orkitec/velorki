import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/units/units.dart' show UnitSystem, formatSpeed;
import 'package:velorki/features/planner/presentation/route_format.dart';
import 'package:velorki/features/weather/domain/route_sampling.dart';
import 'package:velorki/features/weather/domain/route_weather.dart';
import 'package:velorki/features/weather/domain/route_weather_digest.dart';
import 'package:velorki/features/weather/presentation/weather_digest_text.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';

final DateTime _t0 = DateTime.utc(2026, 10, 11, 8);

/// One sample's weather: what is not given is a dry, calm 12 °C.
typedef _W = ({
  WindClass wind,
  double precip,
  double? prob,
  double? temp,
  double? gust,
});

_W _w({
  WindClass wind = WindClass.calm,
  double precip = 0,
  double? prob,
  double? temp = 12,
  double? gust,
}) => (wind: wind, precip: precip, prob: prob, temp: temp, gust: gust);

/// A ride of a sample every 2 km at 20 km/h (6 minutes apart), each with
/// [weather]; `null` for a sample the forecast had nothing for.
RouteWeather _ride(List<_W?> weather) {
  final samples = <RouteWeatherSample>[
    for (var i = 0; i < weather.length; i++)
      RouteWeatherSample(
        distanceM: i * 2000.0,
        position: const LatLng(50, 8),
        bearingDeg: 0,
        offset: Duration(minutes: 6 * i),
      ),
  ];
  return RouteWeather(
    departure: _t0,
    samples: samples,
    weather: <SampleWeather?>[
      for (final (i, w) in weather.indexed)
        w == null
            ? null
            : SampleWeather(
                distanceM: samples[i].distanceM,
                at: _t0.add(samples[i].offset),
                temp: w.temp,
                windMs: w.wind == WindClass.calm ? 1 : 6,
                windFromDeg: 0,
                precipMm: w.precip,
                precipProb: w.prob,
                gust: w.gust,
                headwindMs: 0,
                crosswindMs: 0,
                windClass: w.wind,
              ),
    ],
    sources: const [],
  );
}

RouteWeatherDigest _digest(List<_W?> weather) =>
    RouteWeatherDigest.of(_ride(weather));

/// [n] samples of [w].
List<_W> _times(int n, _W w) => List<_W>.filled(n, w);

void main() {
  group('the wind', () {
    test('a kind on at least half the way is named', () {
      expect(
        _digest([
          ..._times(6, _w(wind: WindClass.tailwind)),
          ..._times(5, _w(wind: WindClass.headwind)),
        ]).wind,
        DigestWind.tailwind,
      );
      expect(
        _digest(_times(4, _w(wind: WindClass.headwind))).wind,
        DigestWind.headwind,
      );
      expect(
        _digest([
          _w(wind: WindClass.crosswind),
          _w(wind: WindClass.crosswind),
          _w(wind: WindClass.crosswind),
          _w(wind: WindClass.tailwind),
        ]).wind,
        DigestWind.crosswind,
      );
    });

    test('none on half the way is mixed wind', () {
      expect(
        _digest([
          ..._times(4, _w(wind: WindClass.headwind)),
          ..._times(4, _w(wind: WindClass.crosswind)),
          ..._times(4, _w(wind: WindClass.tailwind)),
        ]).wind,
        DigestWind.mixed,
      );
    });

    test('calm air on half the way is calm', () {
      expect(
        _digest([
          ..._times(6, _w()),
          ..._times(3, _w(wind: WindClass.headwind)),
          ..._times(2, _w(wind: WindClass.tailwind)),
        ]).wind,
        DigestWind.calm,
      );
    });

    test('shares are by distance: the ends stand for half a stretch', () {
      // Two samples each, but the tailwind's stand for two thirds of the
      // way.
      expect(
        _digest([
          _w(wind: WindClass.headwind),
          _w(wind: WindClass.tailwind),
          _w(wind: WindClass.tailwind),
          _w(wind: WindClass.headwind),
        ]).wind,
        DigestWind.tailwind,
      );
    });

    test('samples without weather count for nothing', () {
      final digest = _digest([
        null,
        null,
        _w(wind: WindClass.tailwind),
        _w(wind: WindClass.tailwind),
      ]);
      expect(digest.wind, DigestWind.tailwind);
      expect(_digest(<_W?>[null, null]).isEmpty, isTrue);
    });
  });

  group('the rain', () {
    test('a dry ride has none', () {
      expect(_digest(_times(5, _w())).rain, isNull);
    });

    test('drizzle under 0.2 mm/h is no rain', () {
      expect(_digest(_times(5, _w(precip: 0.1))).rain, isNull);
      expect(_digest(_times(5, _w(precip: 0.19, prob: 40))).rain, isNull);
    });

    test('the first wet sample says when and where', () {
      final rain = _digest([
        _w(),
        _w(),
        _w(precip: 0.1),
        _w(precip: 2.5),
        _w(precip: 4),
      ]).rain!;
      expect(rain.distanceM, 6000);
      expect(rain.at, _t0.add(const Duration(minutes: 18)));
      expect(rain.light, isFalse);
    });

    test('a likely chance makes it wet; light while under 1 mm/h', () {
      final rain = _digest([_w(), _w(prob: 70), _w(precip: 0.4)]).rain!;
      expect(rain.distanceM, 2000);
      expect(rain.light, isTrue);
    });
  });

  test('the temperature range and a strong gust', () {
    final digest = _digest([
      _w(temp: 11.6, gust: 8),
      _w(temp: 17.2, gust: 12),
      _w(temp: 14),
    ]);
    expect(digest.minTemp, 11.6);
    expect(digest.maxTemp, 17.2);
    expect(digest.gustMs, 12);
    expect(_digest([_w(gust: 9.9)]).gustMs, isNull);
  });

  group('the line', () {
    String clock(DateTime at) =>
        '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';
    String line(List<_W?> weather) => weatherDigestParts(
      l10n,
      UnitSystem.metric,
      _digest(weather),
      clock: clock,
    ).join(' · ');
    final range = l10n.weatherTemperatureRange(
      '12',
      formatTemperature(l10n, UnitSystem.metric, 17),
    );

    test('dry: the wind, dry and the temperatures', () {
      expect(
        line([
          _w(wind: WindClass.tailwind, temp: 12),
          _w(wind: WindClass.tailwind, temp: 17),
        ]),
        [l10n.weatherDry, l10n.weatherMostlyTailwind, range].join(' · '),
      );
    });

    test('rain first, with its time and where', () {
      expect(
        line([
          ..._times(16, _w(wind: WindClass.headwind, temp: 12)),
          _w(wind: WindClass.crosswind, precip: 3, temp: 17),
        ]),
        [
          l10n.weatherRainLikelyFrom(
            '09:36',
            formatDistance(l10n, UnitSystem.metric, 32000),
          ),
          l10n.weatherMostlyHeadwind,
          range,
        ].join(' · '),
      );
    });

    test('light rain from the start; one temperature; a gust', () {
      expect(
        line([_w(precip: 0.5, temp: 12, gust: 14), _w(temp: 12.3)]),
        [
          l10n.weatherLightRainLikelyAtStart,
          l10n.weatherMostlyCalm,
          formatTemperature(l10n, UnitSystem.metric, 12.3),
          l10n.weatherGusts(
            formatMeasure(l10n, formatSpeed(UnitSystem.metric, 14)),
          ),
        ].join(' · '),
      );
    });

    test('mixed wind', () {
      expect(
        line([
          _w(wind: WindClass.headwind),
          _w(wind: WindClass.tailwind),
          _w(wind: WindClass.crosswind),
          _w(wind: WindClass.calm),
        ]),
        contains(l10n.weatherMixedWind),
      );
    });

    test('the free forecast\'s: no gusts, and without its temperature grid '
        'no temperature, the rest as ever', () {
      expect(
        line([
          _w(wind: WindClass.headwind, temp: null),
          _w(wind: WindClass.headwind, temp: null),
        ]),
        [l10n.weatherDry, l10n.weatherMostlyHeadwind].join(' · '),
      );
    });

    test('nothing for a ride the forecast had nothing for', () {
      expect(line(<_W?>[null]), isEmpty);
    });
  });
}

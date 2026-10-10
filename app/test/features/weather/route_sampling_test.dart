import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/weather/domain/route_sampling.dart';
import 'package:velorki_api/velorki_api.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/weather_fixtures.dart';

void main() {
  group('sampleRoute', () {
    test('samples every 2 km, the start and the end included', () {
      final samples = sampleRoute(
        straightRoute(lengthM: 9000),
        typicalSpeedKmh: 18,
      );
      expect(samples.map((s) => s.distanceM.round()), [
        0,
        2000,
        4000,
        6000,
        8000,
        9000,
      ]);
      expect(samples.first.position.lat, closeTo(50, 1e-9));
      expect(samples.last.elevationM, 120);
    });

    test('times the samples at the typical speed without a time model', () {
      final samples = sampleRoute(
        straightRoute(lengthM: 9000),
        typicalSpeedKmh: 18,
      );
      // 18 km/h: 2 km in 400 s.
      expect(samples[1].offset, const Duration(seconds: 400));
      expect(samples.last.offset, const Duration(seconds: 1800));
    });

    test(
      'ignores the route\'s own times, as the planner\'s ride time does',
      () {
        // 500 m per point, 100 s per point: 5 m/s, which the samples do not
        // follow; 18 km/h is 750 m in 150 s, 4 km in 800 s.
        final samples = sampleRoute(
          straightRoute(
            lengthM: 4000,
            times: (n) => [for (var i = 0; i < n; i++) i * 50.0],
          ),
          typicalSpeedKmh: 18,
          spacingM: 750,
        );
        expect(samples[1].distanceM, 750);
        expect(samples[1].offset, const Duration(seconds: 150));
        expect(samples.last.offset, const Duration(seconds: 800));
      },
    );

    test('heads the way the route goes', () {
      for (final bearing in [0.0, 90.0, 180.0, 270.0]) {
        final samples = sampleRoute(
          straightRoute(bearingDeg: bearing),
          typicalSpeedKmh: 18,
        );
        for (final s in samples) {
          final off = ((s.bearingDeg - bearing + 540) % 360) - 180;
          expect(
            off.abs(),
            lessThan(0.5),
            reason: '$bearing at ${s.distanceM}',
          );
        }
      }
    });

    test('a route too long for one request is sampled more sparsely', () {
      final samples = sampleRoute(
        straightRoute(lengthM: 400000, stepM: 5000),
        typicalSpeedKmh: 18,
      );
      expect(samples.length, lessThanOrEqualTo(maxWeatherCells));
      expect(samples.last.distanceM, closeTo(400000, 1));
    });

    test('an empty route has no samples', () {
      expect(
        sampleRoute(straightRoute(lengthM: -1), typicalSpeedKmh: 18),
        isEmpty,
      );
    });
  });

  group('snapCell', () {
    test('snaps to the 0.025° grid with at most three decimals', () {
      final cell = snapCell(const LatLng(52.52437, 13.41053), 37.4);
      expect(cell.lat, 52.525);
      expect(cell.lon, 13.4);
      expect(cell.alt, 50);
      for (var i = 0; i < 2000; i++) {
        final lat = -89.9 + i * 0.0899;
        final lon = -179.9 + i * 0.1799;
        final json = jsonEncode(snapCell(LatLng(lat, lon), null).toJson());
        for (final number in RegExp(r'-?\d+\.(\d+)').allMatches(json)) {
          expect(number.group(1)!.length, lessThanOrEqualTo(3), reason: json);
        }
        final snapped = snapCell(LatLng(lat, lon), null);
        expect(
          (snapped.lat / weatherGridDeg -
                  (snapped.lat / weatherGridDeg).round())
              .abs(),
          lessThan(1e-6),
        );
      }
    });

    test('rounds the altitude to 50 m and leaves an unknown one out', () {
      expect(snapCell(const LatLng(1, 1), 74).alt, 50);
      expect(snapCell(const LatLng(1, 1), 76).alt, 100);
      expect(snapCell(const LatLng(1, 1), -3).alt, 0);
      expect(snapCell(const LatLng(1, 1), null).alt, isNull);
      expect(snapCell(const LatLng(1, 1), null).toJson().keys, ['lat', 'lon']);
    });

    test('never writes a negative zero', () {
      final cell = snapCell(const LatLng(-0.004, -0.004), null);
      expect(jsonEncode(cell.toJson()), '{"lat":0.0,"lon":0.0}');
    });
  });

  group('cellsFor', () {
    test('asks about each cell once and maps every sample to its cell', () {
      final samples = sampleRoute(
        straightRoute(lengthM: 10000),
        typicalSpeedKmh: 18,
      );
      final cells = cellsFor(samples);
      expect(cells.sampleToCell, hasLength(samples.length));
      expect(cells.cells.toSet(), hasLength(cells.cells.length));
      // 10 km north is about 0.09°: four or five 0.025° rows.
      expect(cells.cells.length, inInclusiveRange(4, 5));
      for (final (i, s) in samples.indexed) {
        expect(
          cells.cells[cells.sampleToCell[i]],
          snapCell(s.position, s.elevationM),
        );
      }
      expect(cells.sampleToCell.first, 0);
    });

    test('keeps one request cell for samples in the same cell', () {
      final samples = sampleRoute(
        straightRoute(lengthM: 1000, stepM: 100),
        typicalSpeedKmh: 18,
        spacingM: 200,
      );
      final cells = cellsFor(samples);
      expect(samples.length, 6);
      expect(cells.cells, hasLength(1));
      expect(cells.sampleToCell, everyElement(0));
      expect(
        cells.cells.single,
        const WeatherRequestCell(lat: 50, lon: 8, alt: 100),
      );
    });
  });

  group('requestWindow', () {
    test('starts at the hour and covers the ride and the slider', () {
      final window = requestWindow(
        DateTime.utc(2026, 10, 11, 9),
        const Duration(hours: 2, minutes: 30),
      );
      expect(window.from, DateTime.utc(2026, 10, 11, 9));
      // 2.5 h + 12 h, rounded up, and the hour the ride ends in.
      expect(window.hours, 16);
    });

    test('covers the minutes the departure lies into its hour', () {
      final window = requestWindow(
        DateTime.utc(2026, 10, 11, 10, 45),
        const Duration(hours: 1),
      );
      expect(window.from, DateTime.utc(2026, 10, 11, 10));
      final last = window.from.add(Duration(hours: window.hours - 1));
      expect(
        last.isBefore(
          DateTime.utc(2026, 10, 11, 10, 45).add(const Duration(hours: 13)),
        ),
        isFalse,
      );
    });

    test('floors a local departure to its UTC hour', () {
      final window = requestWindow(
        DateTime.utc(2026, 10, 11, 9, 59).toLocal(),
        Duration.zero,
        sliderSpan: Duration.zero,
      );
      expect(window.from, DateTime.utc(2026, 10, 11, 9));
      expect(window.from.isUtc, isTrue);
      expect(window.hours, 2);
    });

    test('stays within 1 and 72 hours', () {
      expect(
        requestWindow(
          DateTime.utc(2026, 10, 11),
          const Duration(hours: 70),
        ).hours,
        72,
      );
      expect(
        requestWindow(
          DateTime.utc(2026, 10, 11),
          Duration.zero,
          sliderSpan: Duration.zero,
        ).hours,
        1,
      );
    });
  });

  test('defaultDeparture rounds up to the next quarter hour', () {
    expect(
      defaultDeparture(DateTime.utc(2026, 10, 11, 9, 0, 1)),
      DateTime.utc(2026, 10, 11, 9, 15),
    );
    expect(
      defaultDeparture(DateTime.utc(2026, 10, 11, 9, 52)),
      DateTime.utc(2026, 10, 11, 10),
    );
    expect(
      defaultDeparture(DateTime.utc(2026, 10, 11, 9, 30)),
      DateTime.utc(2026, 10, 11, 9, 30),
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/map/domain/stops_along_route.dart';
import 'package:velorki/features/navigation/application/route_geometry.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// Metres per degree of latitude, as near as the tests need it.
const double _mPerLat = 111195;

/// A route due east along 48° N, a point every 500 m, [km] long.
List<LatLng> _eastward(double km) {
  final mPerLon = _mPerLat * 0.66913; // cos 48°
  return <LatLng>[
    for (var m = 0.0; m <= km * 1000 + 1; m += 500)
      LatLng(48, 11 + m / mPerLon),
  ];
}

/// The point [alongKm] along [_eastward] and [offM] north of it.
LatLng _beside(double alongKm, {double offM = 50}) {
  final mPerLon = _mPerLat * 0.66913;
  return LatLng(48 + offM / _mPerLat, 11 + alongKm * 1000 / mPerLon);
}

List<StopAlongRoute<String>> _along(
  List<LatLng> line,
  double alongM,
  Map<String, LatLng> stops,
) => stopsAlongRoute<String>(
  line: line,
  cumulative: cumulativeDistances(line),
  alongM: alongM,
  candidates: stops.keys,
  positionOf: (name) => stops[name]!,
);

void main() {
  group('stopsAlongRoute', () {
    final line = _eastward(80);

    test('a stop beside the stretch already ridden is behind the rider', () {
      final found = _along(line, 10000, {
        'behind': _beside(5),
        'ahead': _beside(15),
      });

      expect(found.map((s) => s.stop), <String>['ahead']);
      expect(found.single.aheadM, closeTo(5000, 60));
      expect(found.single.offM, closeTo(50, 5));
    });

    test('a stop further than 300 m off the route is not on the way', () {
      final found = _along(line, 0, {
        'near': _beside(3, offM: 250),
        'far': _beside(4, offM: 400),
      });

      expect(found.map((s) => s.stop), <String>['near']);
    });

    test('the stops come nearest ahead first', () {
      final found = _along(line, 2000, {
        'c': _beside(30),
        'a': _beside(3),
        'b': _beside(12, offM: -120),
      });

      expect(found.map((s) => s.stop), <String>['a', 'b', 'c']);
      expect(
        found.map((s) => s.aheadM),
        orderedEquals(<double>[...found.map((s) => s.aheadM).toList()..sort()]),
      );
    });

    test('nothing beyond 50 km ahead', () {
      final found = _along(line, 10000, {
        'inside': _beside(58),
        'beyond': _beside(65),
      });

      expect(found.map((s) => s.stop), <String>['inside']);
    });

    test('an out-and-back route places a stop where it is passed next', () {
      // Ten kilometres out and the same ten back.
      final out = _eastward(10);
      final route = <LatLng>[...out, ...out.reversed.skip(1)];
      final stops = {'tap': _beside(2)};

      // On the way out the tap is two kilometres ahead.
      final outbound = _along(route, 1000, stops);
      expect(outbound.single.atM, closeTo(2000, 60));
      expect(outbound.single.aheadM, closeTo(1000, 60));

      // Past it and turned round, it is ahead again, on the way back.
      final inbound = _along(route, 12000, stops);
      expect(inbound.single.atM, closeTo(18000, 60));
      expect(inbound.single.aheadM, closeTo(6000, 60));
    });

    test('a new route (a detour) is searched on its own line', () {
      final stops = {'old': _beside(5), 'new': const LatLng(48.3, 11.06)};
      // The detour heads north, away from the old line.
      final detour = <LatLng>[
        for (var i = 0; i <= 80; i++) LatLng(48 + i * 0.005, 11.06),
      ];

      expect(_along(line, 0, stops).map((s) => s.stop), <String>['old']);
      expect(_along(detour, 0, stops).map((s) => s.stop), <String>['new']);
    });

    test('seen from further on, the distance ahead shrinks', () {
      final found = _along(line, 0, {'tap': _beside(4)});

      expect(found.single.seenFrom(1500).aheadM, closeTo(2500, 60));
    });

    test('a route of fewer than two points has nothing along it', () {
      expect(
        _along(const <LatLng>[LatLng(48, 11)], 0, {'tap': _beside(0)}),
        isEmpty,
      );
    });
  });

  group('routeChunkBoxes', () {
    final line = _eastward(80);
    final cumulative = cumulativeDistances(line);

    test('covers the route from the rider to the far end in 5 km boxes', () {
      final boxes = routeChunkBoxes(line, cumulative, fromM: 10000, toM: 60000);

      expect(boxes, hasLength(inInclusiveRange(9, 11)));
      // The first box starts at the rider, padded; the last reaches 60 km.
      final pad = 300 / _mPerLat;
      expect(boxes.first.south, closeTo(48 - pad, 1e-4));
      expect(boxes.first.contains(_beside(10, offM: 0)), isTrue);
      expect(boxes.first.contains(_beside(9, offM: 0)), isFalse);
      expect(boxes.last.contains(_beside(60, offM: 0)), isTrue);
      expect(boxes.last.contains(_beside(61, offM: 0)), isFalse);
      // Grown by the corridor across the route.
      expect(boxes.first.contains(_beside(12, offM: 290)), isTrue);
    });

    test('nothing to cover past the end of the route', () {
      expect(
        routeChunkBoxes(line, cumulative, fromM: 90000, toM: 140000),
        isEmpty,
      );
    });
  });
}

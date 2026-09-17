import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';
import 'package:velorki_loops/velorki_loops.dart';

const start = LatLng(48.137213, 11.575612);
const lake = LatLng(48.0850, 11.2830); // Starnberger See, ~25 km west-ish

void main() {
  group('RoundtripStrategy', () {
    test('emits one query per direction, 0..315', () async {
      const request = LoopRequest(start: start, targetM: 60000);
      final queries = await const RoundtripStrategy().queries(request).toList();
      expect(queries, hasLength(8));
      expect(queries.map((q) => q.roundTripDirectionDeg).toList(), [
        0.0,
        45.0,
        90.0,
        135.0,
        180.0,
        225.0,
        270.0,
        315.0,
      ]);
    });

    test(
      'every query is a single-point round trip without a way back',
      () async {
        const request = LoopRequest(start: start, targetM: 60000);
        final queries = await const RoundtripStrategy()
            .queries(request)
            .toList();
        for (final q in queries) {
          expect(q.roundTrip, isTrue);
          expect(q.points, [start]);
          expect(q.allowSameWayBack, isFalse);
          expect(q.profile, 'trekking');
        }
      },
    );

    test('no loop query may ride a ferry', () async {
      // The nearest way to a round-trip point invented out at sea is the
      // ferry line, and BRouter will happily ride it out and back.
      const request = LoopRequest(start: start, via: [lake], targetM: 60000);
      final strategies = <CandidateStrategy>[
        const RoundtripStrategy(),
        const ViaOutAndBackStrategy(),
        PerimeterStrategy(),
      ];
      expect(loopProfileParams, <String, String>{'allow_ferries': '0'});
      for (final strategy in strategies) {
        final queries = await strategy.queries(request).toList();
        expect(queries, isNotEmpty, reason: strategy.name);
        for (final q in queries) {
          expect(q.profileParams, loopProfileParams, reason: strategy.name);
        }
      }
    });

    test('the radius inverts BRouter\'s (pi + 2) * radius round trip', () {
      expect(RoundtripStrategy.lengthPerRadius, closeTo(math.pi + 2, 1e-12));
      expect(
        RoundtripStrategy.radiusForTarget(60000),
        closeTo(60000 / (math.pi + 2), 1e-9),
      );
    });

    test('the radius is passed through as roundTripDistanceM', () async {
      const request = LoopRequest(
        start: start,
        targetM: 40000,
        profile: 'gravel',
      );
      final q = await const RoundtripStrategy().queries(request).first;
      expect(
        q.roundTripDistanceM,
        closeTo(RoundtripStrategy.radiusForTarget(40000), 1e-9),
      );
      expect(q.profile, 'gravel');
    });

    test('a configurable number of directions', () async {
      final queries = await const RoundtripStrategy(directions: 4)
          .queries(const LoopRequest(start: start, targetM: 30000))
          .toList();
      expect(queries, hasLength(4));
      expect(queries.map((q) => q.roundTripDirectionDeg), [
        0.0,
        90.0,
        180.0,
        270.0,
      ]);
      expect(
        await const RoundtripStrategy(directions: 0)
            .queries(const LoopRequest(start: start, targetM: 30000))
            .toList(),
        isEmpty,
      );
    });
  });

  group('ViaOutAndBackStrategy', () {
    test('without a via it proposes nothing', () async {
      expect(
        await const ViaOutAndBackStrategy()
            .queries(const LoopRequest(start: start, targetM: 60000))
            .toList(),
        isEmpty,
      );
    });

    test('a generous target gives the plain loop plus four variants', () async {
      const request = LoopRequest(start: start, via: [lake], targetM: 120000);
      final queries = await const ViaOutAndBackStrategy()
          .queries(request)
          .toList();
      expect(queries, hasLength(5));
      for (final q in queries) {
        expect(q.allowSameWayBack, isFalse);
        expect(q.points.first, start);
        expect(q.points.last, start);
        expect(q.points, contains(lake));
      }
    });

    test('the plain variant is start, via, start', () async {
      const request = LoopRequest(start: start, via: [lake], targetM: 120000);
      final first = await const ViaOutAndBackStrategy().queries(request).first;
      expect(first.points, [start, lake, start]);
    });

    test(
      'the variants put the synthetic point out and back, on both sides',
      () async {
        const request = LoopRequest(start: start, via: [lake], targetM: 120000);
        final queries = await const ViaOutAndBackStrategy()
            .queries(request)
            .toList();
        final variants = queries.skip(1).toList();
        expect(variants, hasLength(4));
        // Two have the synthetic point before the via, two after it.
        expect(variants.where((q) => q.points[1] != lake), hasLength(2));
        expect(variants.where((q) => q.points[1] == lake), hasLength(2));
        // The two sides are on opposite sides of the chord.
        final chordBearing = bearingDegrees(start, lake);
        final sides = variants
            .map((q) => q.points.firstWhere((p) => p != start && p != lake))
            .map((p) {
              final delta =
                  (bearingDegrees(start, p) - chordBearing + 360) % 360;
              return delta < 180 ? 1 : -1;
            })
            .toSet();
        expect(sides, {1, -1});
      },
    );

    test('the detour distance follows (target - 2 * chord) / 2', () async {
      const target = 120000.0;
      const request = LoopRequest(start: start, via: [lake], targetM: target);
      final queries = await const ViaOutAndBackStrategy()
          .queries(request)
          .toList();
      final chord = haversineMeters(start, lake);
      final expected = (target - 2 * chord) / 2;
      final mid = destinationPoint(
        start,
        bearingDegrees(start, lake),
        chord / 2,
      );
      final synthetic = queries[1].points.firstWhere(
        (p) => p != start && p != lake,
      );
      expect(
        haversineMeters(mid, synthetic),
        closeTo(expected, expected * 1e-6),
      );
    });

    test('a target already shorter than the out and back gives only the plain '
        'loop', () async {
      final chord = haversineMeters(start, lake);
      final request = LoopRequest(
        start: start,
        via: const [lake],
        targetM: chord * 2,
      );
      final queries = await const ViaOutAndBackStrategy()
          .queries(request)
          .toList();
      expect(queries, hasLength(1));
      expect(queries.single.points, [start, lake, start]);
    });

    test(
      'several vias keep their order and use the last as the turnaround',
      () async {
        const other = LatLng(48.2, 11.4);
        const request = LoopRequest(
          start: start,
          via: [other, lake],
          targetM: 200000,
        );
        final queries = await const ViaOutAndBackStrategy()
            .queries(request)
            .toList();
        expect(queries.first.points, [start, other, lake, start]);
        expect(queries[1].points.sublist(2), [other, lake, start]);
      },
    );
  });

  group('PerimeterStrategy', () {
    test('emits one query per rotation, each a closed ring', () async {
      final queries = await PerimeterStrategy()
          .queries(const LoopRequest(start: start, targetM: 40000))
          .toList();
      expect(queries, hasLength(3));
      for (final q in queries) {
        expect(q.points, hasLength(6)); // start + 4 ring points + start
        expect(q.points.first, start);
        expect(q.points.last, start);
        expect(q.roundTrip, isFalse);
        expect(q.allowSameWayBack, isFalse);
      }
    });

    test('the ring radius makes the circumference the target', () async {
      const target = 40000.0;
      final q = await PerimeterStrategy()
          .queries(const LoopRequest(start: start, targetM: target))
          .first;
      final radius = PerimeterStrategy.radiusForTarget(target);
      expect(radius, closeTo(target / (2 * math.pi), 1e-9));
      for (final p in q.points.sublist(1, 5)) {
        expect(haversineMeters(start, p), closeTo(radius, radius * 1e-6));
      }
    });

    test('the same seed gives the same rotations', () async {
      const request = LoopRequest(start: start, targetM: 40000);
      final a = await PerimeterStrategy(seed: 7).queries(request).toList();
      final b = await PerimeterStrategy(seed: 7).queries(request).toList();
      final c = await PerimeterStrategy(seed: 8).queries(request).toList();
      expect(a.map((q) => q.points).toList(), b.map((q) => q.points).toList());
      expect(a.first.points, isNot(c.first.points));
    });

    test('the rotations differ from each other', () async {
      final queries = await PerimeterStrategy()
          .queries(const LoopRequest(start: start, targetM: 40000))
          .toList();
      expect(queries[0].points[1], isNot(queries[1].points[1]));
      expect(queries[1].points[1], isNot(queries[2].points[1]));
    });

    test('degenerate configurations propose nothing', () async {
      const request = LoopRequest(start: start, targetM: 40000);
      expect(
        await PerimeterStrategy(pointsPerCircle: 2).queries(request).toList(),
        isEmpty,
      );
      expect(
        await PerimeterStrategy(rotations: 0).queries(request).toList(),
        isEmpty,
      );
    });
  });

  test('strategies carry a name for the UI', () {
    expect(const RoundtripStrategy().name, 'roundtrip');
    expect(const ViaOutAndBackStrategy().name, 'viaOutAndBack');
    expect(PerimeterStrategy().name, 'perimeter');
  });

  test('LoopRequest and LoopPrefs are readable values', () {
    const prefs = LoopPrefs(hills: Hills.seek, surface: Surface.gravel);
    expect(prefs, const LoopPrefs(hills: Hills.seek, surface: Surface.gravel));
    expect(
      prefs.hashCode,
      const LoopPrefs(hills: Hills.seek, surface: Surface.gravel).hashCode,
    );
    expect(prefs.avoidTraffic, isTrue);
    expect(prefs.toString(), contains('seek'));
    expect(
      const LoopRequest(start: start, targetM: 60000).toString(),
      contains('60 km'),
    );
    expect(const RouteQuery(points: [start, lake]).profile, 'trekking');
  });
}

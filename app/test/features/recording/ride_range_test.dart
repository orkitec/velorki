import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/geo/climbs.dart';
import 'package:velorki/core/geo/ride_analysis.dart';
import 'package:velorki/features/recording/domain/ride_range.dart';
import 'package:velorki_geo/velorki_geo.dart';

void main() {
  group('RideRange', () {
    test('a split runs from its index times the split length', () {
      const split = Split(
        index: 2,
        distanceM: 1609.344,
        movingTime: Duration(minutes: 5),
        ascentM: 10,
        descentM: 0,
        partial: false,
      );
      final range = RideRange.ofSplit(split, splitLengthM: 1609.344);
      expect(range.startM, closeTo(3218.688, 1e-9));
      expect(range.endM, closeTo(4828.032, 1e-9));
      expect(range.source, RideRangeSource.split);
      expect(range.index, 2);
    });

    test('the partial split at the end is as long as it was', () {
      const split = Split(
        index: 3,
        distanceM: 420,
        movingTime: Duration(minutes: 1),
        ascentM: 0,
        descentM: 0,
        partial: true,
      );
      final range = RideRange.ofSplit(split, splitLengthM: 1000);
      expect(range.startM, 3000);
      expect(range.endM, 3420);
    });

    test('a climb runs from its foot to its top', () {
      const climb = RideClimb(
        startM: 12300,
        lengthM: 2400,
        ascentM: 180,
        maxGradePercent: 11,
        movingTime: Duration(minutes: 12),
      );
      final range = RideRange.ofClimb(climb, index: 1);
      expect(range.startM, 12300);
      expect(range.endM, 14700);
      expect(range.source, RideRangeSource.climb);
      expect(range.index, 1);
      expect(range.selectedIn(RideRangeSource.climb), 1);
      expect(range.selectedIn(RideRangeSource.split), isNull);
    });

    test('equal ranges are equal', () {
      const a = RideRange(
        startM: 0,
        endM: 1000,
        source: RideRangeSource.split,
        index: 0,
      );
      const b = RideRange(
        startM: 0,
        endM: 1000,
        source: RideRangeSource.split,
        index: 0,
      );
      const c = RideRange(
        startM: 0,
        endM: 1000,
        source: RideRangeSource.climb,
        index: 0,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });

  group('trackSlice', () {
    // Five fixes 100 m apart along a meridian.
    final positions = <LatLng>[
      for (var i = 0; i < 5; i++) LatLng(48 + i * 0.001, 11),
    ];
    final distanceAt = <double>[0, 100, 200, 300, 400];

    test('cuts the track between the two distances, ends interpolated', () {
      final slice = trackSlice(positions, distanceAt, startM: 150, endM: 350);
      expect(slice, hasLength(4));
      expect(slice.first.lat, closeTo(48.0015, 1e-9));
      expect(slice[1], positions[2]);
      expect(slice[2], positions[3]);
      expect(slice.last.lat, closeTo(48.0035, 1e-9));
    });

    test('a range on the fixes themselves keeps them', () {
      final slice = trackSlice(positions, distanceAt, startM: 100, endM: 300);
      expect(slice, <LatLng>[positions[1], positions[2], positions[3]]);
    });

    test('the whole track comes back whole', () {
      expect(
        trackSlice(positions, distanceAt, startM: 0, endM: 400),
        positions,
      );
    });

    test('a range past the end is cut to the track', () {
      final slice = trackSlice(positions, distanceAt, startM: 350, endM: 900);
      expect(slice, hasLength(2));
      expect(slice.first.lat, closeTo(48.0035, 1e-9));
      expect(slice.last, positions.last);
    });

    test('a rejected fix standing where the one before it did is skipped '
        'over', () {
      final stuck = <LatLng>[
        const LatLng(48, 11),
        const LatLng(48.001, 11),
        const LatLng(52, 11), // a jump the analysis threw out
        const LatLng(48.002, 11),
      ];
      final slice = trackSlice(
        stuck,
        <double>[0, 100, 100, 200],
        startM: 50,
        endM: 150,
      );
      // The jump is a fix of the track and stays in the line; the ends are
      // lerped on the accepted legs around it.
      expect(slice.first.lat, closeTo(48.0005, 1e-9));
      expect(slice.last.lat, closeTo(50.001, 1e-9));
    });

    test('nothing for a mismatch or an empty range', () {
      expect(
        trackSlice(positions, <double>[0, 100], startM: 0, endM: 100),
        isEmpty,
      );
      expect(
        trackSlice(positions, distanceAt, startM: 200, endM: 200),
        isEmpty,
      );
      expect(
        trackSlice(positions, distanceAt, startM: 500, endM: 600),
        isEmpty,
      );
    });
  });
}

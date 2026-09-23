import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:velorki_fit/velorki_fit.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// The shared format fixtures, see `app/test/fixtures/formats/README.md`.
/// `dart test` runs with the package root as the working directory.
Uint8List fixture(String name) =>
    File('../../test/fixtures/formats/fit/$name').readAsBytesSync();

void main() {
  group('device activities decode into points', () {
    test('a Garmin Edge 820 ride: positions, heart rate and cadence', () {
      final points = FitCodec.decodeActivity(
        fixture('fitparse_garmin_edge820_ride.fit'),
      );
      expect(points, hasLength(15));
      expect(points.first.heartRateBpm, isNotNull);
      expect(points.first.cadenceRpm, isNotNull);
      expect(points.first.time, isNotNull);
      expect(points.first.lat, closeTo(37.4, 0.5));
    });

    test('a Wahoo ELEMNT BOLT file with developer data: power and speed', () {
      final points = FitCodec.decodeActivity(
        fixture('fitparse_wahoo_elemnt_bolt_devdata.fit'),
      );
      // 132 records, one of them without a position.
      expect(points, hasLength(131));
      expect(points.map((p) => p.powerW).nonNulls, isNotEmpty);
      expect(points.map((p) => p.speedMps).nonNulls, isNotEmpty);
    });

    test('a Wahoo ELEMNT ride and a Zwift ride carry power', () {
      for (final name in [
        'msimms_wahoo_elemnt_ride_power.fit',
        'msimms_zwift_ride_power.fit',
      ]) {
        final points = FitCodec.decodeActivity(fixture(name));
        expect(points.length, greaterThan(1000), reason: name);
        expect(
          points.map((p) => p.powerW).nonNulls.length,
          greaterThan(points.length ~/ 2),
          reason: '$name has power on most points',
        );
      }
    });

    test('an indoor trainer file has no positions, so no points come '
        'back from the position decoder', () {
      final points = FitCodec.decodeActivity(
        fixture('fitparse_garmin_indoor_trainer_laps_power.fit'),
      );
      expect(points, isEmpty);
    });

    test('every activity fixture is sniffed as FIT', () {
      for (final name in [
        'fitparse_garmin_edge820_ride.fit',
        'fitparse_wahoo_elemnt_bolt_devdata.fit',
        'fitparse_garmin_edge500_ride_laps.fit',
        'fitparse_garmin_indoor_trainer_laps_power.fit',
        'msimms_wahoo_elemnt_ride_power.fit',
        'msimms_zwift_ride_power.fit',
        'generated_course_with_course_points.fit',
      ]) {
        expect(looksLikeFit(fixture(name)), isTrue, reason: name);
      }
    });
  });

  group('courses (phase 1)', () {
    test('a course file decodes with its name, its track and its course '
        'points, typed and named, with their distance along the course', () {
      final course = FitCodec.decodeCourse(
        fixture('generated_course_with_course_points.fit'),
      );
      expect(course.name, 'Isar bridge loop');
      expect(course.sport, FitSport.cycling);
      expect(course.points, hasLength(6));
      expect(course.points.first.lat, closeTo(48.14, 1e-6));
      expect(course.points.last.ele, closeTo(529, 0.2));
      expect(course.coursePoints, hasLength(5));
      expect(course.coursePoints.map((c) => c.type), [
        FitCoursePointType.generic,
        FitCoursePointType.left,
        FitCoursePointType.water,
        FitCoursePointType.right,
        FitCoursePointType.generic,
      ]);
      expect(course.coursePoints.map((c) => c.name), [
        'Start',
        'Turn left onto Isarweg',
        'Fountain',
        'Turn right',
        'Finish',
      ]);
      expect(course.coursePoints[1].distanceM, closeTo(266, 0.5));
      expect(course.coursePoints[1].pos.lat, closeTo(48.142, 1e-6));
      expect(course.coursePoints[1].time, DateTime.utc(2026, 5, 3, 8, 0, 20));
    });

    test('an activity file is not a course', () {
      expect(
        () =>
            FitCodec.decodeCourse(fixture('fitparse_garmin_edge820_ride.fit')),
        throwsA(isA<FitFormatException>()),
      );
    });

    test('course points written with a course come back the same, in order, '
        'with the distance the track gives them', () {
      final points = [
        for (var i = 0; i < 10; i++)
          TrackPoint(LatLng(48.14 + i * 0.001, 11.58), ele: 500 + i * 1.0),
      ];
      final bytes = FitCodec.encodeCourse(
        points,
        name: 'Cued',
        coursePoints: [
          FitCoursePoint(
            pos: points[3].pos,
            name: 'Turn left',
            type: FitCoursePointType.left,
          ),
          FitCoursePoint(
            pos: points[6].pos,
            name: 'Water',
            type: FitCoursePointType.water,
          ),
        ],
      );
      expect(looksLikeFit(bytes), isTrue);
      final course = FitCodec.decodeCourse(bytes);
      expect(course.coursePoints.map((c) => c.name), ['Turn left', 'Water']);
      expect(course.coursePoints.map((c) => c.type), [
        FitCoursePointType.left,
        FitCoursePointType.water,
      ]);
      // Three points of 111 m each along the way.
      expect(course.coursePoints.first.distanceM, closeTo(333, 5));
      // A long name is cut to what a head unit shows, not refused.
      final long = FitCodec.encodeCourse(
        points,
        name: 'Long',
        coursePoints: [FitCoursePoint(pos: points[1].pos, name: 'x' * 100)],
      );
      expect(
        FitCodec.decodeCourse(long).coursePoints.single.name!.length,
        lessThanOrEqualTo(64),
      );
    });
  });

  group('activity files whole (phase 2)', () {
    test('an Edge 500 ride: four laps and the session totals as the device '
        'wrote them', () {
      final activity = FitCodec.decodeActivityFile(
        fixture('fitparse_garmin_edge500_ride_laps.fit'),
      );
      expect(activity.points, hasLength(greaterThan(3000)));
      expect(activity.laps, hasLength(4));
      expect(activity.laps.first.totalDistanceM, closeTo(9565.43, 0.01));
      expect(activity.laps.first.totalTimerS, closeTo(1232.76, 0.01));
      expect(activity.laps.first.calories, 238);
      expect(activity.laps.first.avgHeartRate, 159);
      final session = activity.session!;
      expect(session.totalDistanceM, closeTo(88797.21, 0.01));
      expect(session.totalTimerS, closeTo(10699.36, 0.01));
      expect(session.totalElapsedS, closeTo(11741.57, 0.01));
      expect(session.calories, 2045);
      expect(session.totalAscentM, 299);
      expect(session.totalDescentM, 287);
      expect(session.avgHeartRate, 166);
      expect(session.numLaps, 4);
      expect(session.sport, FitSport.cycling);
      expect(activity.manufacturer, 'garmin');
    }, skip: 'phase 2');

    test('temperature comes back per point, and averaged on the session', () {
      final wahoo = FitCodec.decodeActivityFile(
        fixture('msimms_wahoo_elemnt_ride_power.fit'),
      );
      expect(wahoo.temperaturesC, hasLength(wahoo.points.length));
      expect(wahoo.temperaturesC.nonNulls, isNotEmpty);
      expect(wahoo.session!.avgTemperatureC, 11);
      expect(wahoo.session!.avgPower, 145);
      expect(wahoo.deviceName, 'ELEMNT');
      expect(wahoo.manufacturer, 'wahoo_fitness');

      final bolt = FitCodec.decodeActivityFile(
        fixture('fitparse_wahoo_elemnt_bolt_devdata.fit'),
      );
      expect(bolt.deviceName, 'ELEMNT BOLT');
      expect(bolt.session!.totalDistanceM, closeTo(963.65, 0.01));
      expect(bolt.laps.single.maxPower, 665);
    }, skip: 'phase 2');

    test('an indoor trainer file keeps its laps and totals although no point '
        'has a position', () {
      final activity = FitCodec.decodeActivityFile(
        fixture('fitparse_garmin_indoor_trainer_laps_power.fit'),
      );
      expect(activity.points, isEmpty);
      expect(activity.laps, hasLength(5));
      expect(activity.laps.first.avgPower, 150);
      expect(activity.session!.calories, 379);
      expect(activity.session!.avgPower, 201);
      expect(activity.session!.totalTimerS, closeTo(2261.85, 0.01));
    }, skip: 'phase 2');

    test('a Zwift ride reports its manufacturer and calories', () {
      final activity = FitCodec.decodeActivityFile(
        fixture('msimms_zwift_ride_power.fit'),
      );
      expect(activity.manufacturer, 'zwift');
      expect(activity.session!.calories, 255);
      expect(activity.session!.totalDistanceM, closeTo(12946.88, 0.01));
      expect(activity.laps.single.avgPower, 192);
    }, skip: 'phase 2');

    test('a file without a session has none, and laps stay empty when there '
        'are none', () {
      final course = FitCodec.decodeActivityFile(
        fixture('generated_course_with_course_points.fit'),
      );
      expect(course.session, isNull);
    }, skip: 'phase 2');
  });
}

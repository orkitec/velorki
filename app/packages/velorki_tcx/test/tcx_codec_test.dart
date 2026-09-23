import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:velorki_geo/velorki_geo.dart';
import 'package:velorki_tcx/velorki_tcx.dart';

/// The shared format fixtures, see `app/test/fixtures/formats/README.md`.
/// `dart test` runs with the package root as the working directory.
String fixture(String name) =>
    File('../../test/fixtures/formats/tcx/$name').readAsStringSync();

Uint8List fixtureBytes(String name) =>
    File('../../test/fixtures/formats/tcx/$name').readAsBytesSync();

/// Everything here is phase 4 of the formats programme; the codec throws
/// until then and these tests say what it will do.
void main() {
  group('activities', () {
    test('a Forerunner run: four laps with calories, heart rate, run cadence '
        'and speed from the TPX extension', () {
      final doc = TcxCodec.decode(
        fixture('activereader_forerunner220_run.tcx'),
      );
      expect(doc.courses, isEmpty);
      final activity = doc.activities.single;
      expect(activity.sport, TcxSport.running);
      expect(activity.creator, 'Garmin Forerunner 220');
      expect(activity.laps, hasLength(4));
      final lap = activity.laps.first;
      expect(lap.startTime, DateTime.utc(2021, 4, 16, 13, 37, 53));
      expect(lap.totalTimeS, closeTo(44.526, 1e-6));
      expect(lap.distanceM, closeTo(52.8, 1e-6));
      expect(lap.calories, 2);
      expect(lap.avgHeartRate, 83);
      expect(lap.maxHeartRate, 92);
      expect(lap.points.first.time, DateTime.utc(2021, 4, 16, 13, 37, 53));
      expect(lap.points.first.heartRateBpm, isNotNull);
      expect(lap.points.first.speedMps, isNotNull);
      expect(activity.points.length, greaterThan(40));
    }, skip: 'phase 4');

    test('a cycling activity: power from ns3:Watts, cadence, and lap watts '
        'from the LX extension', () {
      final doc = TcxCodec.decode(fixture('handwritten_cycling_watts.tcx'));
      final activity = doc.activities.single;
      expect(activity.sport, TcxSport.biking);
      expect(activity.id, DateTime.utc(2026, 5, 3, 8));
      expect(activity.creator, 'Handwritten head unit');
      expect(activity.laps, hasLength(2));
      final first = activity.laps.first;
      expect(first.points.map((p) => p.powerW), [180, 205, 240]);
      expect(first.points.map((p) => p.cadenceRpm), [78, 82, 85]);
      expect(first.points.map((p) => p.heartRateBpm), [112, 118, 124]);
      expect(first.points[1].speedMps, closeTo(13.3, 1e-9));
      expect(first.points[1].ele, 521);
      expect(first.avgWatts, 208);
      expect(first.maxWatts, 240);
      expect(first.avgCadence, 82);
      expect(first.calories, 12);
      final second = activity.laps.last;
      expect(second.points.map((p) => p.powerW), [310, 0, null]);
      expect(second.points.last.cadenceRpm, isNull);
      expect(second.avgWatts, isNull);
      expect(doc.author, 'handwritten for velorki tests');
    }, skip: 'phase 4');

    test('an Edge 705 ride from Garmin Connect: one lap of 500 points with '
        'altitude and distance, no sensors', () {
      final doc = TcxCodec.decode(
        fixture('msimms_garmin_edge705_ride_trimmed.tcx'),
      );
      final activity = doc.activities.single;
      expect(activity.sport, TcxSport.biking);
      expect(activity.laps.single.points, hasLength(500));
      expect(activity.laps.single.points.first.ele, closeTo(0.816, 1e-6));
      expect(activity.laps.single.points.first.heartRateBpm, isNull);
      expect(activity.creator, 'Garmin Communicator Plugin');
    }, skip: 'phase 4');
  });

  group('courses', () {
    test('a course decodes with its name, track and course points, typed and '
        'with their notes', () {
      final doc = TcxCodec.decode(fixture('handwritten_course.tcx'));
      expect(doc.activities, isEmpty);
      final course = doc.courses.single;
      expect(course.name, 'Isar bridge loop');
      expect(course.points, hasLength(6));
      expect(course.distanceM, 670);
      expect(course.coursePoints, hasLength(4));
      expect(course.coursePoints.map((c) => c.type), [
        TcxCoursePointType.generic,
        TcxCoursePointType.left,
        TcxCoursePointType.water,
        TcxCoursePointType.right,
      ]);
      expect(course.coursePoints[1].name, 'Turn left onto Isarweg');
      expect(course.coursePoints[1].time, DateTime.utc(2026, 5, 3, 8, 0, 20));
      expect(course.coursePoints[2].notes, 'Drinking water');
      expect(course.coursePoints[2].pos, const LatLng(48.143, 11.583));
    }, skip: 'phase 4');
  });

  group('export', () {
    final points = [
      for (var i = 0; i < 6; i++)
        TrackPoint(
          LatLng(48.14 + i * 0.001, 11.58 + i * 0.001),
          ele: 520 + i * 2.0,
          time: DateTime.utc(2026, 5, 3, 8, 0, 10 * i),
          heartRateBpm: 110 + i,
          cadenceRpm: 80 + i,
          powerW: 200 + 10 * i,
          speedMps: 13,
        ),
    ];

    test('a ride goes out as one activity of one lap per split and comes back '
        'with its sensors', () {
      final xml = TcxCodec.encodeActivity(
        laps: [
          TcxLap(
            startTime: points.first.time!,
            points: points.sublist(0, 3),
            totalTimeS: 20,
            distanceM: 266,
            calories: 12,
          ),
          TcxLap(
            startTime: points[3].time!,
            points: points.sublist(3),
            totalTimeS: 20,
            distanceM: 270,
            calories: 9,
          ),
        ],
      );
      expect(xml, contains('<TrainingCenterDatabase'));
      expect(xml, contains('Sport="Biking"'));
      expect(xml, contains('<Watts>'));
      final back = TcxCodec.decode(xml).activities.single;
      expect(back.laps, hasLength(2));
      expect(back.laps.first.calories, 12);
      expect(back.points.map((p) => p.powerW), points.map((p) => p.powerW));
      expect(
        back.points.map((p) => p.heartRateBpm),
        points.map((p) => p.heartRateBpm),
      );
      expect(
        back.points.map((p) => p.cadenceRpm),
        points.map((p) => p.cadenceRpm),
      );
      expect(looksLikeTcx(Uint8List.fromList(utf8.encode(xml))), isTrue);
    }, skip: 'phase 4');

    test('a route goes out as a course with its cues as course points', () {
      final xml = TcxCodec.encodeCourse(
        name: 'Cued',
        points: points,
        coursePoints: [
          TcxCoursePoint(
            pos: points[2].pos,
            time: points[2].time!,
            name: 'Turn left',
            type: TcxCoursePointType.left,
          ),
          TcxCoursePoint(
            pos: points[4].pos,
            time: points[4].time!,
            name: 'Fountain',
            type: TcxCoursePointType.water,
            notes: 'Drinking water',
          ),
        ],
      );
      expect(xml, contains('<Courses>'));
      expect(xml, contains('<PointType>Left</PointType>'));
      final back = TcxCodec.decode(xml).courses.single;
      expect(back.name, 'Cued');
      expect(back.points, hasLength(6));
      expect(back.coursePoints.map((c) => c.name), ['Turn left', 'Fountain']);
      expect(back.coursePoints.last.notes, 'Drinking water');
      // A course written without times gets a virtual clock, one point a
      // second, so the course points still find their track point.
      final untimed = TcxCodec.encodeCourse(
        name: 'Untimed',
        points: [for (final p in points) TrackPoint(p.pos, ele: p.ele)],
        coursePoints: [
          TcxCoursePoint(
            pos: points[2].pos,
            time: DateTime.utc(2000),
            name: 'Turn left',
            type: TcxCoursePointType.left,
          ),
        ],
      );
      expect(
        TcxCodec.decode(untimed).courses.single.coursePoints,
        hasLength(1),
      );
    }, skip: 'phase 4');
  });

  group('sniffing and failure', () {
    test('TCX is recognised by its root element, whatever the encoding or the '
        'byte order mark, and other XML is not', () {
      for (final name in [
        'activereader_forerunner220_run.tcx',
        'handwritten_cycling_watts.tcx',
        'handwritten_course.tcx',
        'msimms_garmin_edge705_ride_trimmed.tcx',
      ]) {
        expect(looksLikeTcx(fixtureBytes(name)), isTrue, reason: name);
      }
      final withBom = Uint8List.fromList([
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode(fixture('handwritten_course.tcx')),
      ]);
      expect(looksLikeTcx(withBom), isTrue);
      final gpx = Uint8List.fromList(
        utf8.encode('<?xml version="1.0"?><gpx version="1.1"></gpx>'),
      );
      expect(looksLikeTcx(gpx), isFalse);
      expect(looksLikeTcx(Uint8List(0)), isFalse);
    }, skip: 'phase 4');

    test('a document that is not TCX, or is cut off, is reported as such', () {
      expect(
        () => TcxCodec.decode('<gpx version="1.1"></gpx>'),
        throwsA(isA<TcxFormatException>()),
      );
      expect(
        () => TcxCodec.decode(
          fixture('handwritten_course.tcx').substring(0, 400),
        ),
        throwsA(isA<TcxFormatException>()),
      );
      expect(
        TcxCodec.decode(
          '<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"></TrainingCenterDatabase>',
        ).isEmpty,
        isTrue,
      );
    }, skip: 'phase 4');
  });
}

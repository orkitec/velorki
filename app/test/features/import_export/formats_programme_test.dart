import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/import_export/data/track_decoder.dart';
import 'package:velorki/features/import_export/domain/imported_track.dart';
import 'package:velorki/features/planner/domain/route_poi.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_fit/velorki_fit.dart';
import 'package:velorki_gpx/velorki_gpx.dart';

/// The shared format fixtures, see `test/fixtures/formats/README.md`.
Uint8List formatFixture(String format, String name) =>
    File('test/fixtures/formats/$format/$name').readAsBytesSync();

/// What the formats programme brings to the import pipeline, phase by
/// phase. A test marked `skip: 'phase N'` describes what that phase makes
/// true; the ones that run already hold.
void main() {
  group('what already holds', () {
    test('a GPX track with gpxdata power imports with the power on its '
        'points', () {
      final track = decodeTrack(
        formatFixture('gpx', 'handwritten_gpxdata_power.gpx'),
        fileName: 'power.gpx',
      );
      expect(track.format, ImportFormat.gpx);
      expect(track.points.map((p) => p.powerW), [180, 205, 240, 310, 0, null]);
      expect(track.suggestedKind, ImportKind.ride);
    });

    test('a sensor ride imports with heart rate and cadence on its '
        'points', () {
      final track = decodeTrack(
        formatFixture('gpx', 'viewmygpx_sensors_trimmed.gpx'),
      );
      expect(track.points, hasLength(600));
      expect(track.points.first.heartRateBpm, 95);
      expect(track.points.first.cadenceRpm, 90);
    });

    test('a Wahoo ride imports as a FIT ride with power', () {
      final track = decodeTrack(
        formatFixture('fit', 'msimms_wahoo_elemnt_ride_power.fit'),
      );
      expect(track.format, ImportFormat.fit);
      expect(track.suggestedKind, ImportKind.ride);
      expect(track.points.map((p) => p.powerW).nonNulls, isNotEmpty);
    });

    test('a file with several tracks imports its first one today', () {
      final track = decodeTrack(
        formatFixture('gpx', 'viewmygpx_multi_track_trimmed.gpx'),
      );
      expect(track.points, hasLength(150));
      expect(track.pois, hasLength(5), reason: 'the waypoints come along');
    });

    test('a waypoint-only GPX is reported as empty, not as a route', () {
      expect(
        () => decodeTrack(
          formatFixture('gpx', 'viewmygpx_geocaching_waypoints.gpx'),
        ),
        throwsA(
          isA<ImportException>().having(
            (e) => e.failure,
            'failure',
            ImportFailure.empty,
          ),
        ),
      );
    });
  });

  group('phase 1: FIT courses', () {
    test('a FIT course imports as a route with its course points as cues '
        'and named points, and the course name', () {
      final track = decodeTrack(
        formatFixture('fit', 'generated_course_with_course_points.fit'),
        fileName: 'course.fit',
      );
      expect(track.format, ImportFormat.fit);
      expect(track.name, 'Isar bridge loop');
      expect(track.points, hasLength(6));
      // A course carries a virtual clock, which is no reason to call it
      // a ride.
      expect(track.suggestedKind, ImportKind.route);
      // The turns, as the cue sheet: left at the third point, right at
      // the fifth, and the finish.
      expect(track.turns.map((t) => t.kind), [
        TurnKind.left,
        TurnKind.right,
        TurnKind.end,
      ]);
      expect(track.turns.first.pointIndex, 2);
      expect(track.turns.first.note, 'Turn left onto Isarweg');
      // The places, as points of interest with their kind.
      expect(track.pois.map((p) => p.name), ['Fountain']);
      expect(track.pois.single.kind, PoiKind.water);
    }, skip: 'phase 1');

    test('a route exported as a FIT course carries its cue sheet as course '
        'points, which the import reads back', () {
      // Exercised end to end in route_export_test once phase 1 lands:
      // the exporter hands the route's turns and points of interest to
      // FitCodec.encodeCourse as course points. Here the contract of the
      // codec side, on the app's own turn model.
      final turns = const [
        TurnHint(pointIndex: 2, kind: TurnKind.left, note: 'Isarweg'),
        TurnHint(pointIndex: 4, kind: TurnKind.right),
      ];
      expect(turns.map((t) => t.kind), [TurnKind.left, TurnKind.right]);
      expect(FitCoursePointType.left.fitValue, 6);
      expect(FitCoursePointType.right.fitValue, 7);
    }, skip: 'phase 1');
  });

  group('phase 2: rides', () {
    test('a FIT activity with laps imports them as the ride\'s laps, with the '
        'device totals beside the app\'s figures', () {
      final track = decodeTrack(
        formatFixture('fit', 'fitparse_garmin_edge500_ride_laps.fit'),
      );
      expect(track.laps, hasLength(4));
      expect(track.laps.first.distanceM, closeTo(9565.43, 0.01));
      expect(track.laps.first.calories, 238);
      expect(
        track.laps.first.startTime.isBefore(track.laps.last.startTime),
        isTrue,
      );
      final totals = track.deviceTotals!;
      expect(totals.distanceM, closeTo(88797.21, 0.01));
      expect(totals.calories, 2045);
      expect(totals.ascentM, 299);
      expect(totals.movingS, closeTo(10699.36, 0.01));
      expect(track.creator, 'garmin');
    }, skip: 'phase 2');

    test('temperature comes in per point when the file has it, and stays '
        'empty when it does not', () {
      final wahoo = decodeTrack(
        formatFixture('fit', 'msimms_wahoo_elemnt_ride_power.fit'),
      );
      expect(wahoo.temperaturesC, hasLength(wahoo.points.length));
      expect(wahoo.temperaturesC.nonNulls, isNotEmpty);
      final gpx = decodeTrack(
        formatFixture('gpx', 'viewmygpx_sensors_trimmed.gpx'),
      );
      expect(gpx.temperaturesC.first, closeTo(15.8, 1e-9));
      final plain = decodeTrack(
        formatFixture('gpx', 'msimms_runkeeper_run.gpx'),
      );
      expect(plain.temperaturesC, isEmpty);
    }, skip: 'phase 2');

    test('a GPX with several <trk> offers every track, in order, each with '
        'its own name, and the preview asks which ones to keep', () {
      final tracks = decodeTracks(
        formatFixture('gpx', 'viewmygpx_multi_track_trimmed.gpx'),
        fileName: 'hike.gpx',
      );
      expect(tracks, hasLength(4));
      expect(tracks.map((t) => t.points.length), everyElement(150));
      expect(tracks.first.name, startsWith('Day 1'));
      expect(tracks.last.name, startsWith('Day 4'));
      // A one-track file is one track, as before.
      expect(
        decodeTracks(formatFixture('gpx', 'msimms_runkeeper_run.gpx')),
        hasLength(1),
      );
      // The preview lists the four with a checkbox each, all on, and
      // saves one ride per checked track: import_preview_screen_test.
    }, skip: 'phase 2');

    test('the ride card shows the device\'s totals beside the app\'s figures '
        'when they differ, and a temperature chart when there is one', () {
      // ride_detail_screen_test, once phase 2 lands: a ride saved from
      // fitparse_garmin_edge500_ride_laps.fit shows "As recorded by the
      // device" with 88.8 km, 2:58:19 and 2,045 kcal under the app's own
      // figures, the four laps as its splits, and a "Temperature" chart
      // beside the elevation one.
      expect(true, isTrue);
    }, skip: 'phase 2');

    test('a GPX ride export writes power and temperature on every point that '
        'has them', () {
      final xml = GpxCodec.encodeTrack(
        points: decodeTrack(
          formatFixture('gpx', 'handwritten_gpxdata_power.gpx'),
        ).points,
        name: 'Power',
        extensions: const [GpxExtensions(temperatureC: 14.5)],
      );
      expect(xml, contains('<power>180</power>'));
      expect(xml, contains('<gpxtpx:atemp>14.5</gpxtpx:atemp>'));
    }, skip: 'phase 2');
  });

  group('phase 3: plan and view', () {
    test('a GPX <rte> with cues imports its cue sheet, which the waypoint '
        'sheet then shows as turn points', () {
      // Already true for the import: the Ride with GPS fixture in
      // track_decoder_test. Phase 3 makes the cues saved route data the
      // waypoint sheet edits: planner_screen_test opens a point of a
      // route imported from a <rte>, sees the "Turn" type tile selected
      // with the direction "Left", changes it to "Right" and saves.
      final track = decodeTrack(formatFixture('gpx', 'gpxpy_all_fields.gpx'));
      expect(track.turns, isNotEmpty);
    }, skip: 'phase 3');

    test('the point type tiles grow to the symbols riders use, in a '
        'scrolling row', () {
      for (final name in [
        'summit',
        'viewpoint',
        'shelter',
        'shop',
        'repair',
        'turn',
      ]) {
        expect(PoiKind.values.map((k) => k.name), contains(name));
      }
      expect(PoiKind.fromGpx(symbol: 'Summit').name, 'summit');
      expect(PoiKind.fromGpx(symbol: 'Scenic Area').name, 'viewpoint');
      expect(PoiKind.fromGpx(type: 'bike shop').name, 'shop');
    }, skip: 'phase 3');

    test('a route has a description and a link on its card, off-track points '
        'of interest are listed with type and note, and both cards show the '
        'source format and creator', () {
      // route_detail_screen_test and ride_detail_screen_test once phase 3
      // lands: a route imported from gogarmin_geotours_waypoints.gpx
      // lists its ten points of interest under "Points of interest" with
      // their type, shows "GPX · Geovative Solutions GeoTours" as its
      // source, and a "Link" row that opens the metadata link.
      final track = decodeTrack(
        formatFixture('gpx', 'msimms_garmin_connect_run.gpx'),
      );
      expect(track.creator, 'Garmin Connect');
      expect(track.format, ImportFormat.gpx);
    }, skip: 'phase 3');
  });

  group('phase 4: TCX', () {
    test('the sniffer recognises TCX, and an activity imports as a ride with '
        'laps, heart rate, cadence and power', () {
      final track = decodeTrack(
        formatFixture('tcx', 'handwritten_cycling_watts.tcx'),
        fileName: 'ride.tcx',
      );
      expect(track.format.name, 'tcx');
      expect(track.suggestedKind, ImportKind.ride);
      expect(track.points, hasLength(6));
      expect(track.points.map((p) => p.powerW), [180, 205, 240, 310, 0, null]);
      expect(track.points.first.heartRateBpm, 112);
      expect(track.points.first.cadenceRpm, 78);
      expect(track.laps, hasLength(2));
      expect(track.laps.first.calories, 12);
      expect(track.creator, 'Handwritten head unit');
    }, skip: 'phase 4');

    test('a TCX course imports as a route with its course points as cues '
        'and named points', () {
      final track = decodeTrack(
        formatFixture('tcx', 'handwritten_course.tcx'),
        fileName: 'course.tcx',
      );
      expect(track.format.name, 'tcx');
      expect(track.name, 'Isar bridge loop');
      expect(track.suggestedKind, ImportKind.route);
      expect(track.turns.map((t) => t.kind), [
        TurnKind.left,
        TurnKind.right,
        TurnKind.end,
      ]);
      expect(track.pois.map((p) => p.name), ['Fountain']);
      expect(track.pois.single.description, 'Drinking water');
    }, skip: 'phase 4');

    test('rides export as TCX activities and routes as TCX courses', () {
      // track_exporter_test and route_export_test once phase 4 lands:
      // TrackFormat gains tcx, the ride card's menu offers "Export TCX
      // activity" and the route card's "TCX course"; the files decode
      // with TcxCodec and carry the laps and the cues.
      expect(true, isTrue);
    }, skip: 'phase 4');
  });
}

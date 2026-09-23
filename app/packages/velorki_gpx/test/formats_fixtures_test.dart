import 'dart:io';

import 'package:test/test.dart';
import 'package:velorki_geo/velorki_geo.dart';
import 'package:velorki_gpx/velorki_gpx.dart';

/// The shared format fixtures, see `app/test/fixtures/formats/README.md`.
/// `dart test` runs with the package root as the working directory.
String fixture(String name) =>
    File('../../test/fixtures/formats/gpx/$name').readAsStringSync();

void main() {
  group('Garmin TrackPointExtension sensors', () {
    test('heart rate, cadence and temperature come off every point of a '
        'sensor ride', () {
      final doc = GpxCodec.decode(fixture('viewmygpx_sensors_trimmed.gpx'));
      final track = doc.tracks.single;
      expect(track.pointCount, 600);
      expect(track.type, 'cycling');
      final first = track.extensionsAt(0)!;
      expect(first.heartRate, 95);
      expect(first.cadence, 90);
      expect(first.temperatureC, closeTo(15.8, 1e-9));
      expect(
        track.pointExtensions.every((e) => e?.heartRate != null),
        isTrue,
        reason: 'every point carries the sensors',
      );
      expect(track.points.first.time, DateTime.utc(2025, 4, 12, 9));
    });

    test('a point with hr, cad and atemp beside a gpxx waypoint extension', () {
      final doc = GpxCodec.decode(fixture('gogarmin_hr_cad_atemp.gpx'));
      final ext = doc.tracks.single.extensionsAt(0)!;
      expect(ext.heartRate, 95);
      expect(ext.cadence, 0, reason: 'a cadence of zero is a value');
      expect(ext.temperatureC, 28);
      expect(doc.waypoints.single.pos, const LatLng(1, 2));
    });

    test('a Runkeeper file whose only point is a <wpt> with a heart rate '
        'extension decodes as one waypoint with its time and elevation', () {
      final doc = GpxCodec.decode(fixture('gpxpy_runkeeper_hr.gpx'));
      expect(doc.creator, startsWith('Runkeeper'));
      expect(doc.tracks, isEmpty);
      final waypoint = doc.waypoints.single;
      expect(waypoint.ele, 3.4);
      expect(waypoint.time, DateTime.utc(2016, 6, 17, 23, 41, 3));
      expect(waypoint.pos.lat, closeTo(37.778259, 1e-9));
    });

    test('a Garmin Connect export with the ns3 prefix reads its heart '
        'rate', () {
      final doc = GpxCodec.decode(fixture('msimms_garmin_connect_run.gpx'));
      expect(doc.creator, 'Garmin Connect');
      final track = doc.tracks.single;
      expect(track.pointCount, 560);
      expect(
        track.pointExtensions.where((e) => e?.heartRate != null).length,
        560,
      );
    });
  });

  group('ClueTrust gpxdata extensions', () {
    late GpxDocument doc;
    setUp(
      () => doc = GpxCodec.decode(fixture('handwritten_gpxdata_power.gpx')),
    );

    test('power comes off gpxdata:power, zero included, absent where the '
        'point has none', () {
      final points = doc.tracks.single.points;
      expect(points.map((p) => p.powerW), [180, 205, 240, 310, 0, null]);
    });

    test('heart rate, cadence and temperature come off gpxdata:hr, cadence '
        'and temp, and a point with both schemas reads once', () {
      final track = doc.tracks.single;
      final ext = track.pointExtensions;
      expect(ext.map((e) => e?.heartRate), [112, 118, 124, 131, 135, 133]);
      expect(ext.map((e) => e?.cadence), [78, 82, 85, 88, 90, 0]);
      expect(ext.map((e) => e?.temperatureC), [
        14.5,
        14.5,
        14.6,
        14.6,
        null,
        14.7,
      ]);
    });
  });

  group('several tracks and the rest of GPX 1.1', () {
    test('four <trk> in one file come back as four tracks, in order, with '
        'their names, and the waypoints beside them', () {
      final doc = GpxCodec.decode(fixture('viewmygpx_multi_track_trimmed.gpx'));
      expect(doc.tracks, hasLength(4));
      expect(doc.tracks.map((t) => t.pointCount), everyElement(150));
      expect(doc.tracks.map((t) => t.name).nonNulls, hasLength(4));
      expect(doc.waypoints, hasLength(5));
      expect(doc.waypoints.first.name, 'Milngavie start');
      expect(doc.waypoints.map((w) => w.symbol), [
        'Trailhead',
        'Campground',
        'Campground',
        'Campground',
        'Lodging',
      ]);
      expect(doc.waypoints.first.ele, 35);
    });

    test('the all-fields file: two routes with cues, two tracks, waypoints '
        'with sym, type and link', () {
      final doc = GpxCodec.decode(fixture('gpxpy_all_fields.gpx'));
      expect(doc.name, 'example name');
      expect(doc.tracks, hasLength(2));
      expect(doc.routes, hasLength(2));
      expect(doc.routes.first.name, 'example name');
      expect(doc.routes.first.cues, isNotEmpty);
      expect(doc.routes.first.cues.first.symbol, 'example sym r');
      expect(doc.routes.first.cues.first.type, 'example type r');
      expect(doc.routes.last.name, 'second route');
      expect(doc.waypoints, hasLength(2));
      expect(doc.waypoints.first.symbol, 'example sym');
      expect(doc.waypoints.first.type, 'example type');
    });

    test('a waypoint-only geocaching file has no track and fifteen typed '
        'waypoints', () {
      final doc = GpxCodec.decode(
        fixture('viewmygpx_geocaching_waypoints.gpx'),
      );
      expect(doc.tracks, isEmpty);
      expect(doc.routes, isEmpty);
      expect(doc.waypoints, hasLength(15));
      expect(doc.waypoints.map((w) => w.symbol).toSet(), isNotEmpty);
      expect(doc.isEmpty, isFalse);
    });

    test('a tour file with ten waypoints, each with a symbol and a link', () {
      final doc = GpxCodec.decode(fixture('gogarmin_geotours_waypoints.gpx'));
      expect(doc.name, 'St Louis Zoo sample');
      expect(doc.creator, 'Geovative Solutions GeoTours');
      expect(doc.waypoints, hasLength(10));
      expect(doc.waypoints.every((w) => w.name != null), isTrue);
      expect(doc.waypoints.every((w) => w.symbol != null), isTrue);
    });

    test('a route of 55 named points keeps every name as a cue', () {
      final doc = GpxCodec.decode(fixture('gpxpy_route.gpx'));
      final route = doc.routes.single;
      expect(route.points, hasLength(55));
      expect(route.cues, hasLength(55));
      expect(route.cues.first.name, '#001');
      expect(route.cues.last.pointIndex, 54);
    });

    test('a BRouter export decodes with its track', () {
      final doc = GpxCodec.decode(fixture('gpxpy_brouter.gpx'));
      expect(doc.tracks.single.pointCount, greaterThan(10));
      expect(doc.tracks.single.points.every((p) => p.ele != null), isTrue);
    });

    test('a Runkeeper export without extensions has none', () {
      final doc = GpxCodec.decode(fixture('msimms_runkeeper_run.gpx'));
      expect(doc.tracks.single.pointCount, 626);
      expect(doc.tracks.single.segmentExtensions, isEmpty);
    });
  });

  group('export', () {
    final points = <TrackPoint>[
      TrackPoint(
        const LatLng(48.14, 11.58),
        ele: 520,
        time: DateTime.utc(2026, 5, 3, 8),
        heartRateBpm: 112,
        cadenceRpm: 78,
        powerW: 180,
      ),
      TrackPoint(
        const LatLng(48.141, 11.581),
        ele: 521,
        time: DateTime.utc(2026, 5, 3, 8, 0, 10),
        heartRateBpm: 118,
        cadenceRpm: 82,
        powerW: 205,
      ),
    ];

    test('power goes out with the track and comes back in', () {
      final xml = GpxCodec.encodeTrack(points: points, name: 'Power');
      final back = GpxCodec.decode(xml).tracks.single;
      expect(back.points.map((p) => p.powerW), [180, 205]);
      expect(back.extensionsAt(0)!.heartRate, 112);
      expect(back.extensionsAt(1)!.cadence, 82);
    });

    test('a temperature per point goes out as gpxtpx:atemp and comes back', () {
      final xml = GpxCodec.encodeTrack(
        points: points,
        name: 'Warm',
        extensions: const [
          GpxExtensions(temperatureC: 14.5),
          GpxExtensions(temperatureC: 15),
        ],
      );
      expect(xml, contains('<gpxtpx:atemp>14.5</gpxtpx:atemp>'));
      final back = GpxCodec.decode(xml).tracks.single;
      expect(back.extensionsAt(0)!.temperatureC, 14.5);
      expect(back.extensionsAt(1)!.temperatureC, 15);
      // The point's own sensors are still there beside it.
      expect(back.extensionsAt(0)!.heartRate, 112);
      expect(back.points.map((p) => p.powerW), [180, 205]);
    });

    test('a route goes out as a <rte> with its cues on the points and the '
        'full geometry as a <trk> beside it', () {
      final line = [
        for (var i = 0; i < 20; i++)
          TrackPoint(LatLng(48.14 + i * 0.001, 11.58 + i * 0.001)),
      ];
      final xml = GpxCodec.encodeRoute(
        points: [line[0], line[7], line[19]],
        name: 'Cued',
        cues: const [
          GpxRouteCue(pointIndex: 1, name: 'Turn left', symbol: 'Left'),
          GpxRouteCue(pointIndex: 2, name: 'Finish', symbol: 'Flag'),
        ],
        track: line,
      );
      final doc = GpxCodec.decode(xml);
      expect(doc.routes.single.points, hasLength(3));
      expect(doc.routes.single.cues.map((c) => c.name), [
        'Turn left',
        'Finish',
      ]);
      expect(doc.routes.single.cues.first.symbol, 'Left');
      expect(doc.tracks.single.pointCount, 20);
    });
  });
}

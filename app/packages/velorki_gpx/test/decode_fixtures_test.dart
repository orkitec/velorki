import 'dart:io';

import 'package:test/test.dart';
import 'package:velorki_geo/velorki_geo.dart';
import 'package:velorki_gpx/velorki_gpx.dart';

/// `dart test` runs with the package root as the working directory.
String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  group('mixed.gpx', () {
    late GpxDocument doc;

    setUp(() => doc = GpxCodec.decode(fixture('mixed.gpx')));

    test('reports the metadata and the creator', () {
      expect(doc.creator, 'handwritten');
      expect(doc.name, 'Isar loop');
      expect(doc.description, 'A route, a track and a waypoint in one file.');
      expect(doc.isEmpty, isFalse);
    });

    test('returns the route, the track and the waypoints together', () {
      expect(doc.routes, hasLength(1));
      expect(doc.tracks, hasLength(1));
      expect(doc.waypoints, hasLength(2));
    });

    test('reads the route points', () {
      final route = doc.routes.single;
      expect(route.name, 'Planned way home');
      expect(route.description, 'Two turn points.');
      expect(route.points, hasLength(2));
      expect(route.points.first.pos, const LatLng(48.14, 11.59));
      expect(route.points.first.ele, 520.5);
      expect(route.points.last.ele, isNull);
      expect(route.points.last.time, isNull);
    });

    test('keeps the two track segments apart but flattens on demand', () {
      final track = doc.tracks.single;
      expect(track.name, 'Morning ride');
      expect(track.description, 'Recorded.');
      expect(track.type, 'cycling');
      expect(track.segments, hasLength(2));
      expect(track.segments.first, hasLength(2));
      expect(track.segments.last, hasLength(1));
      expect(track.pointCount, 3);
      expect(track.points, hasLength(3));
      expect(track.points.last.pos, const LatLng(48.14, 11.59));
      expect(track.points.first.time, DateTime.utc(2024, 5, 1, 8, 0, 0));
    });

    test('reads the waypoints with their symbols', () {
      expect(doc.waypoints.first.name, 'Marienplatz');
      expect(doc.waypoints.first.symbol, 'Flag, Blue');
      expect(doc.waypoints.first.type, 'landmark');
      expect(doc.waypoints.first.ele, 519.0);
      expect(doc.waypoints.first.time, DateTime.utc(2024, 5, 1, 7, 55, 0));
      expect(doc.waypoints.last.name, 'Brunnen');
      expect(doc.waypoints.last.symbol, 'Water Source');
      expect(doc.waypoints.last.ele, isNull);
    });

    test('has no extensions, so the parallel list stays empty', () {
      final track = doc.tracks.single;
      expect(track.segmentExtensions, isEmpty);
      expect(track.pointExtensions, isEmpty);
      expect(track.extensionsAt(0), isNull);
      expect(track.extensionsIn(0, 0), isNull);
    });
  });

  group('komoot.gpx', () {
    late GpxDocument doc;

    setUp(() => doc = GpxCodec.decode(fixture('komoot.gpx')));

    test('reports creator and metadata name', () {
      expect(doc.creator, 'komoot.de');
      expect(doc.name, 'Feierabendrunde am Ammersee');
    });

    test('reads the single track with elevations and times', () {
      expect(doc.routes, isEmpty);
      expect(doc.waypoints, isEmpty);

      final track = doc.tracks.single;
      expect(track.name, 'Feierabendrunde am Ammersee');
      expect(track.type, isNull);
      expect(track.pointCount, 3);
      expect(track.points.first.pos.lat, closeTo(48.01429, 1e-9));
      expect(track.points.first.pos.lon, closeTo(11.15016, 1e-9));
      expect(track.points.first.ele, closeTo(533.021973, 1e-6));
      expect(track.points.first.time, DateTime.utc(2024, 6, 12, 16, 4, 41));
      expect(track.segmentExtensions, isEmpty);
    });
  });

  group('ridewithgps.gpx', () {
    late GpxDocument doc;

    setUp(() => doc = GpxCodec.decode(fixture('ridewithgps.gpx')));

    test('reports the creator URL and the metadata name and link', () {
      expect(doc.creator, 'http://ridewithgps.com/');
      expect(doc.name, 'Isar nach Norden');
    });

    test('reads a route export: cue-sheet route points with Garmin '
        'extensions, a water waypoint, no track', () {
      expect(doc.tracks, isEmpty);
      final route = doc.routes.single;
      expect(route.name, 'Isar nach Norden');
      expect(route.points, hasLength(3));
      expect(route.points[1].pos.lat, closeTo(48.13744, 1e-9));
      expect(route.points[1].ele, closeTo(520.1, 1e-6));
      expect(doc.waypoints.single.name, 'Trinkwasser');
      expect(doc.waypoints.single.symbol, 'Water Source');
    });
  });

  group('strava.gpx', () {
    late GpxDocument doc;
    late GpxTrack track;

    setUp(() {
      doc = GpxCodec.decode(fixture('strava.gpx'));
      track = doc.tracks.single;
    });

    test('reports creator, name and the numeric activity type', () {
      expect(doc.creator, 'StravaGPX');
      expect(doc.name, 'Afternoon Ride');
      expect(track.name, 'Afternoon Ride');
      expect(track.type, '1');
      expect(track.pointCount, 5);
    });

    test('parses the gpxtpx prefixed TrackPointExtension', () {
      expect(
        track.extensionsAt(0),
        const GpxExtensions(heartRate: 121, cadence: 78, temperatureC: 18),
      );
    });

    test('parses the ns3 prefixed TrackPointExtension', () {
      // package:gpx's own typed extension only matches `gpxtpx:` and the
      // un-prefixed spelling, so this one is what our local-name walk buys us.
      expect(
        track.extensionsAt(1),
        const GpxExtensions(heartRate: 124, cadence: 80, temperatureC: 18.5),
      );
    });

    test('parses the un-prefixed TrackPointExtension', () {
      expect(track.extensionsAt(2), const GpxExtensions(heartRate: 130));
      expect(track.extensionsAt(2)!.cadence, isNull);
      expect(track.extensionsAt(2)!.temperatureC, isNull);
    });

    test('parses sensor elements written straight into <extensions>', () {
      expect(
        track.extensionsAt(3),
        const GpxExtensions(heartRate: 133, cadence: 82),
      );
    });

    test('leaves points without extensions null', () {
      expect(track.extensionsAt(4), isNull);
      expect(track.extensionsAt(5), isNull);
      expect(track.extensionsAt(-1), isNull);
    });

    test('keeps the extension list parallel to the segments', () {
      expect(track.segmentExtensions, hasLength(track.segments.length));
      expect(
        track.segmentExtensions.first,
        hasLength(track.segments.first.length),
      );
      expect(track.pointExtensions, hasLength(track.pointCount));
      expect(track.extensionsIn(0, 1), track.extensionsAt(1));
      expect(track.extensionsIn(1, 0), isNull);
      expect(track.extensionsIn(0, 99), isNull);
    });

    test('still reads position, elevation and time on extended points', () {
      final point = track.points[1];
      expect(point.pos.lat, closeTo(48.1372, 1e-9));
      expect(point.ele, closeTo(519.8, 1e-9));
      expect(point.time, DateTime.utc(2024, 4, 20, 6, 12, 10));
    });
  });
}

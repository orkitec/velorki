import 'package:test/test.dart';
import 'package:velorki_geo/velorki_geo.dart';
import 'package:velorki_gpx/velorki_gpx.dart';

/// Points used by the round trip tests.
///
/// The timestamps are whole seconds in UTC and the coordinates and elevations
/// are values that Dart's `double.toString()` reproduces exactly (it always
/// emits the shortest string that parses back to the same double). GPX carries
/// both as decimal text, so with these inputs the round trip is lossless and
/// the tests can compare exactly. Sub-second timestamps are *not* lossless —
/// see the dedicated test below.
final _points = <TrackPoint>[
  TrackPoint(
    const LatLng(48.1351, 11.582),
    ele: 519.0,
    time: DateTime.utc(2024, 5, 1, 8, 0, 0),
  ),
  TrackPoint(
    const LatLng(48.1352, 11.5821),
    ele: 519.5,
    time: DateTime.utc(2024, 5, 1, 8, 0, 5),
  ),
  TrackPoint(
    const LatLng(48.14, 11.59),
    ele: 525.25,
    time: DateTime.utc(2024, 5, 1, 8, 10, 0),
  ),
];

final _waypoints = <GpxWaypoint>[
  GpxWaypoint(
    const LatLng(48.1351, 11.582),
    ele: 519.0,
    name: 'Marienplatz',
    description: 'Start of the ride',
    symbol: 'Flag, Blue',
    type: 'landmark',
    time: DateTime.utc(2024, 5, 1, 7, 55, 0),
  ),
  const GpxWaypoint(
    LatLng(48.15, 11.6),
    name: 'Brunnen',
    symbol: 'Water Source',
  ),
];

void expectSamePoints(List<TrackPoint> actual, List<TrackPoint> expected) {
  expect(actual, hasLength(expected.length));
  for (var i = 0; i < expected.length; i++) {
    final a = actual[i];
    final e = expected[i];
    expect(a.lat, closeTo(e.lat, 1e-9), reason: 'lat of point $i');
    expect(a.lon, closeTo(e.lon, 1e-9), reason: 'lon of point $i');
    if (e.ele == null) {
      expect(a.ele, isNull, reason: 'ele of point $i');
    } else {
      expect(a.ele, closeTo(e.ele!, 1e-6), reason: 'ele of point $i');
    }
    expect(a.time, e.time, reason: 'time of point $i');
  }
}

void main() {
  group('track round trip', () {
    test('keeps every point, its elevation and its timestamp', () {
      final xml = GpxCodec.encodeTrack(
        name: 'Morning ride',
        description: 'Along the Isar',
        points: _points,
      );
      final decoded = GpxCodec.decode(xml);

      expect(decoded.creator, 'Velorki');
      expect(decoded.name, 'Morning ride');
      expect(decoded.description, 'Along the Isar');
      expect(decoded.tracks, hasLength(1));

      final track = decoded.tracks.single;
      expect(track.name, 'Morning ride');
      expect(track.description, 'Along the Isar');
      expect(track.segments, hasLength(1));
      expect(track.pointCount, _points.length);
      expectSamePoints(track.points, _points);

      // With whole-second, shortest-representation inputs the round trip is
      // bit-exact, so plain equality holds too.
      expect(track.points, equals(_points));
    });

    test('carries the waypoints alongside the track', () {
      final xml = GpxCodec.encodeTrack(
        name: 'Morning ride',
        points: _points,
        waypoints: _waypoints,
      );
      final decoded = GpxCodec.decode(xml);

      expect(decoded.waypoints, hasLength(2));
      expect(decoded.waypoints.first, _waypoints.first);
      expect(decoded.waypoints.last, _waypoints.last);
      expect(decoded.tracks.single.pointCount, _points.length);
    });

    test('uses the given creator and survives an empty point list', () {
      final xml = GpxCodec.encodeTrack(points: const [], creator: 'Velorki/CI');
      final decoded = GpxCodec.decode(xml);

      expect(decoded.creator, 'Velorki/CI');
      expect(decoded.tracks, hasLength(1));
      expect(decoded.tracks.single.pointCount, 0);
      expect(decoded.tracks.single.extensionsAt(0), isNull);
    });

    test('truncates sub-second timestamps to whole seconds', () {
      // GPX is used at second resolution in practice and the encoder writes
      // `...:SSZ`, so anything below a second is deliberately dropped.
      final xml = GpxCodec.encodeTrack(
        points: [
          TrackPoint(
            const LatLng(48.1, 11.5),
            time: DateTime.utc(2024, 5, 1, 8, 0, 30, 750, 123),
          ),
        ],
      );
      expect(xml, contains('<time>2024-05-01T08:00:30Z</time>'));
      expect(
        GpxCodec.decode(xml).tracks.single.points.single.time,
        DateTime.utc(2024, 5, 1, 8, 0, 30),
      );
    });

    test('converts local timestamps to UTC', () {
      final local = DateTime.utc(2024, 5, 1, 8).toLocal();
      final xml = GpxCodec.encodeTrack(
        points: [TrackPoint(const LatLng(48.1, 11.5), time: local)],
      );
      final time = GpxCodec.decode(xml).tracks.single.points.single.time!;
      expect(time.isUtc, isTrue);
      expect(time, DateTime.utc(2024, 5, 1, 8));
    });
  });

  group('route round trip', () {
    test('keeps every route point', () {
      final xml = GpxCodec.encodeRoute(
        name: 'Planned way home',
        description: 'Two turn points',
        points: _points,
      );
      final decoded = GpxCodec.decode(xml);

      expect(decoded.creator, 'Velorki');
      expect(decoded.tracks, isEmpty);
      expect(decoded.routes, hasLength(1));

      final route = decoded.routes.single;
      expect(route.name, 'Planned way home');
      expect(route.description, 'Two turn points');
      expectSamePoints(route.points, _points);
    });

    test('carries the waypoints alongside the route', () {
      final xml = GpxCodec.encodeRoute(
        name: 'Planned way home',
        points: _points,
        waypoints: _waypoints,
      );
      final decoded = GpxCodec.decode(xml);

      expect(decoded.waypoints, equals(_waypoints));
      expect(decoded.routes.single.points, hasLength(_points.length));
    });
  });

  group('waypoint round trip', () {
    test('keeps name, description, symbol, type, elevation and time', () {
      final xml = GpxCodec.encodeTrack(points: const [], waypoints: _waypoints);
      final decoded = GpxCodec.decode(xml);

      final first = decoded.waypoints.first;
      expect(first.pos, const LatLng(48.1351, 11.582));
      expect(first.ele, 519.0);
      expect(first.name, 'Marienplatz');
      expect(first.description, 'Start of the ride');
      expect(first.symbol, 'Flag, Blue');
      expect(first.type, 'landmark');
      expect(first.time, DateTime.utc(2024, 5, 1, 7, 55, 0));

      final second = decoded.waypoints.last;
      expect(second.name, 'Brunnen');
      expect(second.symbol, 'Water Source');
      expect(second.ele, isNull);
      expect(second.time, isNull);
      expect(second.type, isNull);
    });
  });

  group('sensor round trip', () {
    test('heart rate, cadence and power survive a track', () {
      final points = <TrackPoint>[
        _points.first.copyWith(heartRateBpm: 142, cadenceRpm: 0, powerW: 210),
        _points[1].copyWith(heartRateBpm: 151, cadenceRpm: 88, powerW: 230),
        _points.last,
      ];

      final decoded = GpxCodec.decode(GpxCodec.encodeTrack(points: points))
          .tracks
          .single
          .points;

      expect(decoded, points);
      expect(decoded.first.cadenceRpm, 0, reason: 'a real reading, not absent');
      expect(decoded.last.heartRateBpm, isNull);
      expect(decoded.last.powerW, isNull);
    });

    test('a route keeps them as well', () {
      final points = <TrackPoint>[
        for (final point in _points) point.copyWith(heartRateBpm: 120),
      ];

      final decoded = GpxCodec.decode(GpxCodec.encodeRoute(points: points))
          .routes
          .single
          .points;

      expect(decoded.map((p) => p.heartRateBpm), everyElement(120));
    });

    test('the ns3 spelling other exporters use is read too', () {
      const xml =
          '<?xml version="1.0" encoding="UTF-8"?>'
          '<gpx version="1.1" creator="Garmin Connect" '
          'xmlns="http://www.topografix.com/GPX/1/1" '
          'xmlns:ns3="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">'
          '<trk><trkseg>'
          '<trkpt lat="48.1" lon="11.5"><extensions>'
          '<ns3:TrackPointExtension>'
          '<ns3:hr>147</ns3:hr><ns3:cad>91</ns3:cad>'
          '</ns3:TrackPointExtension>'
          '</extensions></trkpt>'
          '</trkseg></trk></gpx>';

      final point = GpxCodec.decode(xml).tracks.single.points.single;

      expect(point.heartRateBpm, 147);
      expect(point.cadenceRpm, 91);
    });

    test('power is read wherever the writer put it', () {
      String track(String extensions) =>
          '<?xml version="1.0" encoding="UTF-8"?>'
          '<gpx version="1.1" creator="t" '
          'xmlns="http://www.topografix.com/GPX/1/1">'
          '<trk><trkseg><trkpt lat="48.1" lon="11.5">'
          '<extensions>$extensions</extensions>'
          '</trkpt></trkseg></trk></gpx>';

      int? powerOf(String extensions) =>
          GpxCodec.decode(track(extensions)).tracks.single.points.single.powerW;

      expect(powerOf('<power>210</power>'), 210, reason: 'Strava');
      expect(
        powerOf(
          '<TrackPointExtension><PowerInWatts>212</PowerInWatts>'
          '</TrackPointExtension>',
        ),
        212,
      );
      expect(
        powerOf(
          '<TrackPointExtension><Extensions>'
          '<PowerInWatts>214</PowerInWatts>'
          '</Extensions></TrackPointExtension>',
        ),
        214,
        reason: 'Garmin nests it once more',
      );
      expect(powerOf('<atemp>19</atemp>'), isNull);
    });
  });

  group('type', () {
    test('a track keeps its <type> through a round trip', () {
      final decoded = GpxCodec.decode(
        GpxCodec.encodeTrack(points: _points, type: 'mountain_biking'),
      );
      expect(decoded.tracks.single.type, 'mountain_biking');
    });

    test('a route writes its <type> on the route and on the track beside '
        'it, and reads it back from the route', () {
      final xml = GpxCodec.encodeRoute(
        points: _points,
        track: _points,
        type: 'road_biking',
      );
      expect('<type>road_biking</type>'.allMatches(xml), hasLength(2));
      final decoded = GpxCodec.decode(xml);
      expect(decoded.routes.single.type, 'road_biking');
      expect(decoded.tracks.single.type, 'road_biking');
    });

    test('a route without a type reads as none', () {
      final decoded = GpxCodec.decode(GpxCodec.encodeRoute(points: _points));
      expect(decoded.routes.single.type, isNull);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/planner/domain/route_poi.dart';
import 'package:velorki/features/planner/domain/route_waypoints.dart';
import 'package:velorki/features/planner/domain/shape_points.dart';
import 'package:velorki/features/planner/domain/waypoint.dart';
import 'package:velorki_geo/velorki_geo.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

/// A zigzag north of 48°N, about 111 m per step of latitude.
List<LatLng> _track(int n) => <LatLng>[
  for (var i = 0; i < n; i++)
    LatLng(48 + i * 0.001, 11 + (i.isEven ? 0 : 0.002)),
];

List<Waypoint> _ends(List<LatLng> track) => [
  Waypoint(pos: track.first, kind: WaypointKind.start),
  Waypoint(pos: track.last, kind: WaypointKind.end),
];

void main() {
  final track = _track(200);

  test('points of interest on the track become named waypoints in track '
      'order, with kind and note; those off the track do not', () {
    final waypoints = routeWaypoints(
      track: track,
      saved: _ends(track),
      pois: [
        RoutePoi(
          pos: track[150],
          name: 'Bakery',
          kind: PoiKind.food,
          description: 'Croissants',
        ),
        // Ten metres beside the track, still on it.
        RoutePoi(
          pos: LatLng(track[60].lat, track[60].lon + 0.0001),
          name: 'Tap',
          kind: PoiKind.water,
        ),
        // A kilometre away: a place to know about, not to ride to.
        RoutePoi(
          pos: LatLng(track[100].lat, track[100].lon + 0.02),
          name: 'Castle',
        ),
      ],
    );
    final named = waypoints.where((w) => w.hasDetails).toList();
    expect(named.map((w) => w.name), ['Tap', 'Bakery']);
    expect(named.map((w) => w.poiKind), [PoiKind.water, PoiKind.food]);
    expect(named.map((w) => w.note), [null, 'Croissants']);
    expect(named.map((w) => w.kind), everyElement(WaypointKind.via));
    // Snapped onto the track, not left beside it.
    expect(haversineMeters(named.first.pos, track[60]), lessThan(10));
    expect(waypoints.first.kind, WaypointKind.start);
    expect(waypoints.last.kind, WaypointKind.end);
    // Shape points around them keep the course; in order along the track.
    expect(waypoints.length, greaterThan(4));
    expect(waypoints.length, lessThanOrEqualTo(maxShapePoints + 2));
    final along = [for (final w in waypoints) _indexNear(track, w.pos)];
    expect(along, orderedEquals([...along]..sort()));
  });

  test('the cap grows for named points rather than dropping one', () {
    final pois = <RoutePoi>[
      for (var i = 5; i < 200; i += 7) RoutePoi(pos: track[i], name: 'P$i'),
    ];
    expect(pois.length, greaterThan(maxShapePoints));
    final waypoints = routeWaypoints(
      track: track,
      saved: _ends(track),
      pois: pois,
    );
    expect(
      waypoints.where((w) => w.hasDetails).map((w) => w.name),
      pois.map((p) => p.name),
    );
    // Nothing but the named points and the ends: no room for shape points.
    expect(waypoints.length, pois.length + 2);
  });

  test('a point at the start or the end names that end instead of adding '
      'one', () {
    final waypoints = routeWaypoints(
      track: track,
      saved: _ends(track),
      pois: [
        RoutePoi(pos: track.first, name: 'Home', description: 'Leave at 8'),
        RoutePoi(
          pos: LatLng(track.last.lat, track.last.lon + 0.0001),
          name: 'Lake',
          kind: PoiKind.water,
        ),
      ],
    );
    expect(waypoints.first.kind, WaypointKind.start);
    expect(waypoints.first.name, 'Home');
    expect(waypoints.first.note, 'Leave at 8');
    expect(waypoints.last.kind, WaypointKind.end);
    expect(waypoints.last.name, 'Lake');
    expect(waypoints.last.poiKind, PoiKind.water);
    expect(waypoints.where((w) => w.hasDetails).length, 2);
    expect(waypoints.first.pos, track.first);
  });

  test('without points of interest the route gets its shape points, as '
      'before', () {
    final waypoints = routeWaypoints(track: track, saved: _ends(track));
    expect(waypoints.map((w) => w.pos), shapePoints(track).map((p) => p));
    expect(waypoints.any((w) => w.hasDetails), isFalse);
  });

  test('a track of two points comes back as saved', () {
    final short = _track(2);
    final saved = _ends(short);
    expect(
      routeWaypoints(
        track: short,
        saved: saved,
        pois: [RoutePoi(pos: short.first, name: 'Home')],
      ),
      saved,
    );
  });
  test('the cue sheet\'s written turns open as turn points with their '
      'direction; the router\'s unnamed ones do not', () {
    final waypoints = routeWaypoints(
      track: track,
      saved: _ends(track),
      turns: const [
        TurnHint(pointIndex: 40, kind: TurnKind.left, note: 'Onto Isarweg'),
        TurnHint(pointIndex: 90, kind: TurnKind.right),
        TurnHint(pointIndex: 199, kind: TurnKind.end, note: 'Finish'),
      ],
    );
    final turns = waypoints.where((w) => w.poiKind == PoiKind.turn).toList();
    expect(turns, hasLength(1));
    expect(turns.single.name, 'Onto Isarweg');
    expect(turns.single.turn, TurnKind.left);
    expect(turns.single.pos, track[40]);
    expect(waypoints.last.kind, WaypointKind.end);
    expect(waypoints.last.poiKind, PoiKind.generic);
  });

  group('the points beside a route', () {
    test('besideTrackPois keeps what routeWaypoints leaves: together they '
        'are every point, once each', () {
      final onTrack = RoutePoi(pos: track[120], name: 'Tap');
      final offTrack = RoutePoi(
        // Well over a kilometre off the course.
        pos: LatLng(track[120].lat, track[120].lon + 0.05),
        name: 'Castle',
      );
      final pois = [onTrack, offTrack];

      final waypoints = routeWaypoints(
        track: track,
        saved: _ends(track),
        pois: pois,
      );
      expect(waypoints.map((w) => w.name), contains('Tap'));
      expect(waypoints.map((w) => w.name), isNot(contains('Castle')));
      expect(besideTrackPois(track: track, pois: pois), [offTrack]);
    });

    test('a track too short to shape keeps every point beside it, as '
        'routeWaypoints keeps every waypoint', () {
      final short = <LatLng>[track.first, track.last];
      final pois = [RoutePoi(pos: track.first, name: 'Home')];
      expect(besideTrackPois(track: short, pois: pois), pois);
    });

    test('viaIndexAlongTrack puts a point where the route comes past it, '
        'never at an end', () {
      final waypoints = <Waypoint>[
        Waypoint(pos: track.first, kind: WaypointKind.start),
        Waypoint(pos: track[100]),
        Waypoint(pos: track.last, kind: WaypointKind.end),
      ];
      expect(
        viaIndexAlongTrack(track: track, waypoints: waypoints, pos: track[50]),
        1,
      );
      expect(
        viaIndexAlongTrack(track: track, waypoints: waypoints, pos: track[150]),
        2,
      );
      // Beyond the end it is still a via, the last one.
      expect(
        viaIndexAlongTrack(
          track: track,
          waypoints: waypoints,
          pos: LatLng(track.last.lat + 0.01, track.last.lon),
        ),
        2,
      );
      // With nothing to sit between, it simply goes on the end.
      expect(
        viaIndexAlongTrack(
          track: track,
          waypoints: [waypoints.first],
          pos: track[50],
        ),
        1,
      );
    });
  });
}

int _indexNear(List<LatLng> track, LatLng pos) {
  var best = 0;
  var bestD = double.infinity;
  for (var i = 0; i < track.length; i++) {
    final d = haversineMeters(track[i], pos);
    if (d < bestD) {
      bestD = d;
      best = i;
    }
  }
  return best;
}

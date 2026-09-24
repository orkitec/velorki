import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/planner/domain/route_poi.dart';
import 'package:velorki/features/planner/domain/waypoint.dart';
import 'package:velorki_geo/velorki_geo.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

void main() {
  test('a point keeps the word the file called it through the column and '
      'into the points an export writes', () {
    const point = Waypoint(
      pos: LatLng(48, 11),
      name: 'Sprint',
      sourceType: 'sprint',
    );
    final back = Waypoint.fromMap(point.toMap());
    expect(back.sourceType, 'sprint');
    expect(back, point);
    expect(waypointPois(const [point]).single.sourceType, 'sprint');
    expect(
      const Waypoint(pos: LatLng(48, 11)).toMap().containsKey('source'),
      isFalse,
    );
  });

  group('Waypoint', () {
    test('a name, a kind and a note round-trip through the stored map', () {
      const point = Waypoint(
        pos: LatLng(48.1, 11.2),
        kind: WaypointKind.via,
        name: 'Bakery',
        poiKind: PoiKind.food,
        note: 'Croissants before the climb',
      );
      final map = point.toMap();
      expect(map['name'], 'Bakery');
      expect(map['poi'], 'food');
      expect(map['note'], 'Croissants before the climb');
      expect(Waypoint.fromMap(map), point);
    });

    test('a bare point stores nothing but its position and place', () {
      const point = Waypoint(pos: LatLng(48.1, 11.2));
      expect(point.toMap().keys, <String>['lat', 'lon', 'kind']);
      expect(Waypoint.fromMap(point.toMap()), point);
      expect(point.hasDetails, isFalse);
    });

    test('an entry from before the details reads as a generic point', () {
      final point = Waypoint.fromMap(<String, dynamic>{
        'lat': 48.0,
        'lon': 11.0,
        'kind': 'start',
        'name': 'Home',
      });
      expect(point.poiKind, PoiKind.generic);
      expect(point.note, isNull);
      expect(point.hasDetails, isTrue);
    });

    test('waypointPois lists the points with a name or a note', () {
      final pois = waypointPois(const [
        Waypoint(pos: LatLng(48.0, 11.0), kind: WaypointKind.start),
        Waypoint(
          pos: LatLng(48.1, 11.1),
          name: 'Fountain',
          poiKind: PoiKind.water,
        ),
        Waypoint(pos: LatLng(48.2, 11.2), note: 'Steep cobbles'),
        Waypoint(pos: LatLng(48.3, 11.3), kind: WaypointKind.end),
      ]);
      expect(pois, const [
        RoutePoi(
          pos: LatLng(48.1, 11.1),
          name: 'Fountain',
          kind: PoiKind.water,
        ),
        RoutePoi(
          pos: LatLng(48.2, 11.2),
          name: '',
          description: 'Steep cobbles',
        ),
      ]);
    });
  });

  group('turn points', () {
    const line = [
      LatLng(48.0, 11.0),
      LatLng(48.001, 11.0),
      LatLng(48.002, 11.0),
      LatLng(48.003, 11.0),
    ];

    test('a turn point round trips through the column with its direction', () {
      const point = Waypoint(
        pos: LatLng(48.001, 11.0),
        name: 'Onto the bridge',
        poiKind: PoiKind.turn,
        turn: TurnKind.left,
      );
      final back = Waypoint.fromMap(point.toMap());
      expect(back, point);
      expect(point.toMap()['turn'], 'left');
      // A point of another kind writes no direction.
      expect(
        const Waypoint(pos: LatLng(48, 11)).toMap().containsKey('turn'),
        isFalse,
      );
    });

    test('turn points become turns at the nearest point of the line, the '
        'name as the note, and are not points of interest', () {
      const points = [
        Waypoint(pos: LatLng(48.0, 11.0), kind: WaypointKind.start),
        Waypoint(
          pos: LatLng(48.00201, 11.0),
          name: 'Sharp right here',
          poiKind: PoiKind.turn,
          turn: TurnKind.sharpRight,
        ),
        Waypoint(
          pos: LatLng(48.001, 11.0),
          name: 'Tap',
          poiKind: PoiKind.water,
        ),
        Waypoint(pos: LatLng(48.003, 11.0), kind: WaypointKind.end),
      ];
      final turns = waypointTurns(points, line);
      expect(turns, hasLength(1));
      expect(turns.single.pointIndex, 2);
      expect(turns.single.kind, TurnKind.sharpRight);
      expect(turns.single.note, 'Sharp right here');
      expect(waypointPois(points).map((p) => p.name), ['Tap']);
    });

    test('merged into the router\'s turns, a turn point replaces the turn '
        'at its point and the rest stay in order', () {
      const routers = [
        TurnHint(pointIndex: 1, kind: TurnKind.left),
        TurnHint(pointIndex: 2, kind: TurnKind.right),
        TurnHint(pointIndex: 3, kind: TurnKind.end),
      ];
      const points = [
        Waypoint(
          pos: LatLng(48.002, 11.0),
          name: 'Keep right',
          poiKind: PoiKind.turn,
          turn: TurnKind.keepRight,
        ),
      ];
      final merged = mergeWaypointTurns(routers, points, line);
      expect(merged.map((t) => t.pointIndex), [1, 2, 3]);
      expect(merged[1].kind, TurnKind.keepRight);
      expect(merged[1].note, 'Keep right');
      expect(merged[0].kind, TurnKind.left);
      expect(mergeWaypointTurns(routers, const [], line), routers);
    });
  });
}

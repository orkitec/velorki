import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/planner/domain/route_poi.dart';
import 'package:velorki/features/planner/domain/waypoint.dart';
import 'package:velorki_geo/velorki_geo.dart';

void main() {
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
}

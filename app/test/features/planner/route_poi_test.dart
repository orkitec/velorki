import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/planner/domain/route_poi.dart';
import 'package:velorki_geo/velorki_geo.dart';

void main() {
  group('PoiKind.fromGpx', () {
    test('reads Ride with GPS categories from type, sym and cmt', () {
      expect(
        PoiKind.fromGpx(type: 'danger', comment: 'caution'),
        PoiKind.danger,
      );
      expect(PoiKind.fromGpx(type: 'water', symbol: 'Dot'), PoiKind.water);
      expect(PoiKind.fromGpx(symbol: 'Water Source'), PoiKind.water);
      expect(PoiKind.fromGpx(type: 'food'), PoiKind.food);
      expect(PoiKind.fromGpx(comment: 'coffee'), PoiKind.food);
      expect(PoiKind.fromGpx(type: 'generic'), PoiKind.generic);
      expect(PoiKind.fromGpx(), PoiKind.generic);
    });
  });

  test('a point survives the column round trip', () {
    const poi = RoutePoi(
      pos: LatLng(40.7598, -73.8497),
      name: 'START DISMOUNT ZONE',
      description: 'All riders must dismount',
      kind: PoiKind.danger,
    );
    expect(RoutePoi.fromMap(poi.toMap()), poi);
  });

  test('goes out as a GPX waypoint with the category Ride with GPS reads', () {
    final wpt = gpxWaypoints(const <RoutePoi>[
      RoutePoi(pos: LatLng(48, 11), name: 'Tap', kind: PoiKind.water),
    ]).single;
    expect(wpt.name, 'Tap');
    expect(wpt.type, 'water');
    expect(wpt.pos, const LatLng(48, 11));
  });
}

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

  group('the wider kinds', () {
    test('summit, viewpoint, shelter, shop and repair read off the words a '
        'file uses', () {
      expect(PoiKind.fromGpx(symbol: 'Summit'), PoiKind.summit);
      expect(PoiKind.fromGpx(symbol: 'Scenic Area'), PoiKind.viewpoint);
      expect(PoiKind.fromGpx(type: 'viewpoint'), PoiKind.viewpoint);
      expect(PoiKind.fromGpx(symbol: 'Lodge'), PoiKind.shelter);
      expect(PoiKind.fromGpx(comment: 'mountain hut'), PoiKind.shelter);
      expect(PoiKind.fromGpx(type: 'bike shop'), PoiKind.shop);
      expect(PoiKind.fromGpx(symbol: 'Shopping Center'), PoiKind.shop);
      expect(PoiKind.fromGpx(type: 'repair'), PoiKind.repair);
      expect(PoiKind.fromGpx(type: 'bakery'), PoiKind.food);
      expect(PoiKind.fromGpx(type: 'nothing known'), PoiKind.generic);
    });

    test('every kind writes a type and a symbol a file reads back', () {
      for (final kind in PoiKind.values) {
        final out = gpxWaypoints([
          RoutePoi(pos: const LatLng(48, 11), name: 'x', kind: kind),
        ]).single;
        expect(out.type, kind.name, reason: kind.name);
        expect(out.symbol, isNotEmpty, reason: kind.name);
      }
      expect(
        gpxWaypoints([
          const RoutePoi(
            pos: LatLng(48, 11),
            name: 'Top',
            kind: PoiKind.summit,
          ),
        ]).single.symbol,
        'Summit',
      );
    });
  });
}

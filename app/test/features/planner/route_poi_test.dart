import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/planner/domain/route_poi.dart';
import 'package:velorki_geo/velorki_geo.dart';

void main() {
  group('PoiKind.fromGpx', () {
    test('reads the categories other planners write in type, sym and cmt', () {
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

  test('goes out as a GPX waypoint with a category other planners read', () {
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
        expect(out.type, kind.gpxType, reason: kind.name);
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

  group('the places beside a route', () {
    test('first aid, toilet, campsite, parking and transport read off the '
        'words a file uses', () {
      expect(PoiKind.fromGpx(symbol: 'First Aid'), PoiKind.firstAid);
      expect(PoiKind.fromGpx(type: 'first_aid'), PoiKind.firstAid);
      expect(PoiKind.fromGpx(comment: 'pharmacy'), PoiKind.firstAid);
      // An aid station is help, not a platform.
      expect(PoiKind.fromGpx(type: 'aid_station'), PoiKind.firstAid);
      expect(PoiKind.fromGpx(symbol: 'Restroom'), PoiKind.toilet);
      expect(PoiKind.fromGpx(type: 'toilets'), PoiKind.toilet);
      expect(PoiKind.fromGpx(symbol: 'Campground'), PoiKind.campsite);
      expect(PoiKind.fromGpx(type: 'camping'), PoiKind.campsite);
      expect(PoiKind.fromGpx(symbol: 'Parking Area'), PoiKind.parking);
      expect(PoiKind.fromGpx(type: 'transit'), PoiKind.transport);
      expect(PoiKind.fromGpx(symbol: 'Train Station'), PoiKind.transport);
      expect(
        PoiKind.fromGpx(comment: 'ferry to the island'),
        PoiKind.transport,
      );
      // A water station is still water, a food stop still food.
      expect(PoiKind.fromGpx(symbol: 'Water Station'), PoiKind.water);
    });

    test('every kind but the two that stand for nothing in particular comes '
        'back off its own written type', () {
      for (final kind in PoiKind.values) {
        if (kind == PoiKind.generic || kind == PoiKind.turn) continue;
        final out = gpxWaypoints([
          RoutePoi(pos: const LatLng(48, 11), name: 'x', kind: kind),
        ]).single;
        expect(
          PoiKind.fromGpx(type: out.type, symbol: out.symbol),
          kind,
          reason: kind.name,
        );
      }
    });
  });
}

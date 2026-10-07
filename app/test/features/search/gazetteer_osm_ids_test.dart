import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/search/data/gazetteer_store.dart';
import 'package:velorki/features/search/domain/search_result.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/gazetteer_fixture.dart';

void main() {
  late Directory dir;

  setUp(() {
    final root = Directory.systemTemp.createTempSync('velorki-gaz-osm');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    dir = Directory('${root.path}/gazetteer')..createSync(recursive: true);
  });

  Future<GazetteerStore> openStore() async {
    final store = GazetteerStore(dir);
    addTearDown(store.close);
    await store.refresh();
    return store;
  }

  const box = BoundingBox(south: 47.0, west: 9.4, north: 47.2, east: 9.6);

  test('places and POIs carry their OpenStreetMap element', () async {
    buildGazetteer(
      dir,
      'E5_N45',
      places: const <GazPlace>[
        GazPlace(
          1,
          'Vaduz',
          'town',
          47.1410,
          9.5209,
          population: 5450,
          osmType: 'n',
          osmId: 240000001,
        ),
        GazPlace(2, 'Mühleholz', 'village', 47.1465, 9.5150, adminId: 1),
      ],
      streets: fixtureStreets,
      pois: const <GazPoi>[
        GazPoi(
          21,
          'Café Wolf',
          'cafe',
          47.1405,
          9.5220,
          placeId: 1,
          osmType: 'w',
          osmId: 123456,
        ),
      ],
    );
    final store = await openStore();

    final cafe = (await store.search('wolf')).single;
    expect(cafe.osmType, 'way');
    expect(cafe.osmId, 123456);
    expect(cafe.hasOsmElement, isTrue);

    final vaduz = (await store.search('vaduz'))
        .firstWhere((r) => r.kind == SearchKind.place);
    expect((vaduz.osmType, vaduz.osmId), ('node', 240000001));

    // A row without the values has none.
    final village = (await store.search('muhleholz'))
        .firstWhere((r) => r.kind == SearchKind.place);
    expect(village.hasOsmElement, isFalse);

    // Streets never do: they are merged out of many ways.
    for (final street in (await store.search(
      'Städtle',
    )).where((r) => r.kind == SearchKind.street)) {
      expect(street.osmType, isNull);
      expect(street.osmId, isNull);
    }

    final stops = await store.inBox(
      box,
      placeKinds: const ['town'],
      poiKinds: const ['cafe'],
    );
    expect(
      {for (final s in stops) s.name: (s.osmType, s.osmId)},
      <String, (String?, int?)>{
        'Vaduz': ('node', 240000001),
        'Café Wolf': ('way', 123456),
      },
    );

    final settlement = await store.nearestSettlement(
      const LatLng(47.1411, 9.5210),
    );
    expect(settlement?.name, 'Vaduz');
    expect(settlement?.osmId, 240000001);
  });

  test('a file without the columns still answers, without ids', () async {
    buildGazetteer(
      dir,
      'E5_N45',
      places: fixturePlaces,
      streets: fixtureStreets,
      pois: fixturePois,
    );
    final store = await openStore();

    final cafe = (await store.search('wolf')).single;
    expect(cafe.hasOsmElement, isFalse);
    final stops = await store.inBox(box, poiKinds: const ['cafe']);
    expect(stops, isNotEmpty);
    expect(stops.every((s) => !s.hasOsmElement), isTrue);
  });
}

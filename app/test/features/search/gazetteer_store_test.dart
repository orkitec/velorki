import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/search/data/gazetteer_store.dart';
import 'package:velorki/features/search/domain/search_group.dart';
import 'package:velorki/features/search/domain/search_result.dart';
import 'package:velorki/features/search/domain/street_numbers.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/gazetteer_fixture.dart';
import 'support/street_numbers_encoder.dart';

/// The fixture the parallel builder writes; the one test that uses it is
/// skipped while it is not there.
final File realFixture = File('../tools/gazetteer/fixtures/E5_N45.gaz');

void main() {
  late Directory dir;

  setUp(() {
    final root = Directory.systemTemp.createTempSync('velorki-gaz');
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

  Future<GazetteerStore> storeWithFixture() async {
    buildGazetteer(
      dir,
      'E5_N45',
      places: fixturePlaces,
      streets: fixtureStreets,
      pois: fixturePois,
    );
    return openStore();
  }

  test('a gazetteer in the directory makes the store searchable', () async {
    final store = await storeWithFixture();
    expect(store.hasTiles, isTrue);
    expect(store.tiles, <String>['E5_N45']);
  });

  test('covers says which area can be searched on the device', () async {
    final store = await storeWithFixture();

    // Inside E5_N45: everything from its south-west corner up to, but not
    // including, the next tile's.
    expect(store.covers(const LatLng(47.1410, 9.5209)), isTrue);
    expect(store.covers(const LatLng(45.0, 5.0)), isTrue);
    expect(store.covers(const LatLng(49.999, 9.999)), isTrue);
    // The neighbours, and the far side of the planet.
    expect(store.covers(const LatLng(50.0, 9.5)), isFalse);
    expect(store.covers(const LatLng(47.0, 10.0)), isFalse);
    expect(store.covers(const LatLng(48.1374, 11.5755)), isFalse);
    expect(store.covers(const LatLng(32.65, -16.91)), isFalse);
  });

  test('covers is false with no gazetteer at all', () async {
    final store = await openStore();

    expect(store.hasTiles, isFalse);
    expect(store.covers(const LatLng(47.1410, 9.5209)), isFalse);

    final nowhere = GazetteerStore(null);
    addTearDown(nowhere.close);
    await nowhere.refresh();
    expect(nowhere.covers(const LatLng(47.1410, 9.5209)), isFalse);
  });

  test('covers follows the files a rescan finds and a close drops', () async {
    final store = await openStore();
    expect(store.covers(const LatLng(32.65, -16.91)), isFalse);

    buildGazetteer(
      dir,
      'W20_N30',
      places: const <GazPlace>[
        GazPlace(1, 'Funchal', 'city', 32.6500, -16.9100, population: 105000),
      ],
    );
    await store.refresh();
    expect(store.covers(const LatLng(32.65, -16.91)), isTrue);
    expect(store.covers(const LatLng(47.1410, 9.5209)), isFalse);

    store.close();
    expect(store.covers(const LatLng(32.65, -16.91)), isFalse);
  });

  group('nearestSettlement names the ground under a point', () {
    test('the closest of the same standing wins', () async {
      final store = await storeWithFixture();

      // Standing in Mühleholz: the village is 100 m away, Vaduz 700 m, and a
      // village is as good a name for a ride as a town.
      final here = await store.nearestSettlement(const LatLng(47.1466, 9.5151));
      expect(here?.name, 'Mühleholz');
      expect(here?.kind, SearchKind.place);
      expect(here?.detail, 'village');
      expect(here?.city, 'Vaduz', reason: 'the admin area it belongs to');
      expect(here?.distanceMeters, lessThan(200));

      final vaduz = await store.nearestSettlement(
        const LatLng(47.1408, 9.5215),
      );
      expect(vaduz?.name, 'Vaduz');
    });

    test('a suburb does not outrank the town it belongs to', () async {
      buildGazetteer(
        dir,
        'E5_N45',
        places: const <GazPlace>[
          GazPlace(1, 'Vaduz', 'town', 47.1410, 9.5209, population: 5450),
          // A parish a few hundred metres away: where the rider is standing,
          // but not what they call the ride.
          GazPlace(2, 'Ebenholz', 'suburb', 47.1440, 9.5209, adminId: 1),
          GazPlace(3, 'Haberfeld', 'neighbourhood', 47.1442, 9.5209),
          GazPlace(4, 'Vorderer Weiler', 'hamlet', 47.1444, 9.5209),
        ],
      );
      final store = await openStore();

      final named = await store.nearestSettlement(
        const LatLng(47.1442, 9.5209),
      );
      expect(named?.name, 'Vaduz');
      expect(named?.detail, 'town');
    });

    test(
      'the smaller kinds name a ride when nothing larger is in range',
      () async {
        buildGazetteer(
          dir,
          'E5_N45',
          places: const <GazPlace>[
            // Six kilometres off: past the reach of a town, let alone a suburb.
            GazPlace(1, 'Vaduz', 'town', 47.0870, 9.5209, population: 5450),
            GazPlace(2, 'Ebenholz', 'suburb', 47.1440, 9.5209),
          ],
        );
        final store = await openStore();

        final named = await store.nearestSettlement(
          const LatLng(47.1442, 9.5209),
        );
        expect(named?.name, 'Ebenholz');
        expect(named?.detail, 'suburb');
      },
    );

    test('a city reaches further than a village', () async {
      buildGazetteer(
        dir,
        'E5_N45',
        places: const <GazPlace>[
          // Both four kilometres away: inside a city's reach, outside the
          // three kilometres everything smaller gets.
          GazPlace(1, 'Vaduz', 'city', 47.1050, 9.5209, population: 5450),
          GazPlace(2, 'Triesen', 'village', 47.1830, 9.5209),
        ],
      );
      final store = await openStore();

      final named = await store.nearestSettlement(
        const LatLng(47.1440, 9.5209),
      );
      expect(named?.name, 'Vaduz');
      expect(named?.detail, 'city');
    });

    test('nothing within the radius is null', () async {
      final store = await storeWithFixture();

      // Falknis, the peak in the fixture: 3 km of mountain and no village.
      expect(
        await store.nearestSettlement(const LatLng(47.0900, 9.5800)),
        isNull,
      );
      // The same point answers once the radius reaches Triesenberg.
      expect(
        (await store.nearestSettlement(
          const LatLng(47.0900, 9.5800),
          maxKm: 10,
        ))?.name,
        'Triesenberg',
      );
    });

    test('a point no tile covers is null, and so is no tile at all', () async {
      final store = await storeWithFixture();
      expect(
        await store.nearestSettlement(const LatLng(32.6669, -16.9241)),
        isNull,
      );

      final nowhere = GazetteerStore(null);
      addTearDown(nowhere.close);
      await nowhere.refresh();
      expect(
        await nowhere.nearestSettlement(const LatLng(47.1466, 9.5151)),
        isNull,
      );
    });

    test('only settlement kinds answer', () async {
      buildGazetteer(
        dir,
        'E5_N45',
        places: const <GazPlace>[
          GazPlace(1, 'Insel', 'island', 47.1000, 9.5000),
          GazPlace(2, 'Weiler', 'hamlet', 47.1050, 9.5000),
        ],
      );
      final store = await openStore();

      final found = await store.nearestSettlement(const LatLng(47.1001, 9.5));
      expect(
        found?.name,
        'Weiler',
        reason: 'an island is not what a rider calls where they set off from',
      );
    });

    test('a locality is no name for a ride even standing on it', () async {
      buildGazetteer(
        dir,
        'E5_N45',
        places: const <GazPlace>[GazPlace(1, 'Flur', 'locality', 47.1, 9.5)],
      );
      final store = await openStore();

      expect(await store.nearestSettlement(const LatLng(47.1001, 9.5)), isNull);
    });
  });

  test('a prefix of one token finds the place', () async {
    final store = await storeWithFixture();
    final results = await store.search('vad');

    expect(results.map((r) => r.name), contains('Vaduz'));
    final vaduz = results.firstWhere((r) => r.name == 'Vaduz');
    expect(vaduz.source, SearchSource.local);
    expect(vaduz.kind, SearchKind.place);
    expect(vaduz.detail, 'town');
    expect(vaduz.position.lat, closeTo(47.1410, 1e-6));
    expect(vaduz.position.lon, closeTo(9.5209, 1e-6));
  });

  test('diacritics are folded both ways', () async {
    final store = await storeWithFixture();

    for (final typed in <String>['muhleholz', 'Mühleholz', 'MUHLEHOL']) {
      final names = (await store.search(typed)).map((r) => r.name).toList();
      expect(names, contains('Mühleholz'), reason: typed);
    }
  });

  test('a village names the place it belongs to', () async {
    final store = await storeWithFixture();
    final village = (await store.search('muhleholz'))
        .firstWhere((r) => r.kind == SearchKind.place);

    expect(village.city, 'Vaduz');
  });

  test(
    'every token is a prefix, and the name with all of them comes first',
    () async {
      final store = await storeWithFixture();

      final found = await store.search('im muhl');
      final street = found.first;
      expect(street.name, 'Im Mühleholz');
      expect(street.kind, SearchKind.street);
      expect(street.detail, isNull);
      expect(street.city, 'Vaduz');
      expect(street.houseNumber, isNull);
      expect(street.approximate, isFalse);
      expect(
        found.skip(1).map((r) => r.name),
        isNot(contains('Im Mühleholz')),
        reason: 'the rest only holds some of the words',
      );

      expect(
        (await store.search('muhl im')).first.name,
        'Im Mühleholz',
        reason: 'the order of the words is not the rider\'s problem',
      );
      expect(
        (await store.search('sta')).map((r) => r.name),
        contains('Städtle'),
        reason: 'a lone token is a prefix as well',
      );
    },
  );

  test('POIs come back with their kind for the icon', () async {
    final store = await storeWithFixture();

    final tap = (await store.search('brunnen')).single;
    expect(tap.kind, SearchKind.poi);
    expect(tap.detail, 'drinking_water');
    expect(tap.city, 'Mühleholz');

    final peak = (await store.search('falknis')).single;
    expect(peak.detail, 'peak');
    expect(peak.city, isNull, reason: 'the fixture peak has no place');
  });

  test(
    'the nearer namesake wins, and a bigger one only from close by',
    () async {
      buildGazetteer(
        dir,
        'E5_N45',
        places: const <GazPlace>[
          GazPlace(1, 'Testort', 'village', 47.00, 9.00, population: 100),
          GazPlace(2, 'Testort', 'town', 47.50, 9.00, population: 9000),
          GazPlace(3, 'Testort', 'village', 47.10, 9.00, population: 100),
        ],
      );
      final store = await openStore();

      final near = await store.search(
        'testort',
        near: const LatLng(47.05, 9.00),
      );
      expect(near.map((r) => r.position.lat), <double>[
        47.00,
        47.10,
        47.50,
      ], reason: 'the villages 6 km away, not the town 50 km away');

      final far = await store.search(
        'testort',
        near: const LatLng(47.40, 9.00),
      );
      expect(far.map((r) => r.position.lat), <double>[
        47.50,
        47.10,
        47.00,
      ], reason: 'the town 11 km away beats a village 33 km away');

      final unbiased = await store.search('testort');
      expect(unbiased.first.position.lat, 47.50);
    },
  );

  test('a better match outranks a bigger place', () async {
    buildGazetteer(
      dir,
      'E5_N45',
      places: const <GazPlace>[
        // The tighter match is the small one: FTS5 scores the name that is
        // nothing but the query above the one that repeats it.
        GazPlace(1, 'Bergen', 'village', 47.00, 9.00, population: 20),
        GazPlace(2, 'Bergen Bergen', 'city', 60.39, 5.32, population: 280000),
      ],
    );
    final store = await openStore();

    expect(
      (await store.search('bergen')).first.name,
      'Bergen',
      reason: 'bm25 decides before the population does',
    );
  });

  test('the exact name outranks the names that contain it', () async {
    buildGazetteer(
      dir,
      'E5_N45',
      places: const <GazPlace>[GazPlace(1, 'Monte', 'suburb', 32.68, -16.90)],
      pois: const <GazPoi>[
        // Without column sizes bm25 scores these level with the suburb; the
        // shorter name is the closer match.
        GazPoi(2, 'Monte Tea House', 'cafe', 32.68, -16.90),
        GazPoi(3, 'Estação Teleférico do Monte', 'viewpoint', 32.67, -16.90),
      ],
    );
    final store = await openStore();

    final names = (await store.search('monte')).map((r) => r.name).toList();
    expect(names.first, 'Monte');
    expect(names[1], 'Monte Tea House');
  });

  test('the limit is honoured', () async {
    buildGazetteer(
      dir,
      'E5_N45',
      places: <GazPlace>[
        for (var i = 0; i < 20; i++)
          GazPlace(i + 1, 'Musterort $i', 'village', 47 + i / 100, 9.0),
      ],
    );
    final store = await openStore();

    expect(await store.search('musterort'), hasLength(10));
    expect(await store.search('musterort', limit: 3), hasLength(3));
    expect(await store.search('musterort', limit: 0), isEmpty);
  });

  test('below three characters nothing is queried', () async {
    final store = await storeWithFixture();

    expect(await store.search(''), isEmpty);
    expect(await store.search('va'), isEmpty);
    expect(await store.search('  v  '), isEmpty);
    expect(gazetteerMatchExpression('va'), isNull);
  });

  test('odd input never throws', () async {
    final store = await storeWithFixture();

    for (final typed in <String>[
      '"',
      '***',
      'a"b',
      'vaduz"',
      '"vaduz" OR "schaan"',
      'NOT NEAR(',
      '^^^',
      '   ',
      'ü' * 400,
      'vaduz ${'x ' * 40}',
    ]) {
      expect(
        await store.search(typed),
        isA<List<SearchResult>>(),
        reason: typed,
      );
    }

    expect(
      (await store.search('vaduz"')).map((r) => r.name),
      contains('Vaduz'),
      reason: 'a stray quote is text, not syntax',
    );
    expect(
      gazetteerMatchExpression('a"b')!.match,
      '"a"* AND "b"*',
      reason: 'a quote separates words, as it does in the index',
    );
    expect(gazetteerMatchExpression('***'), isNull);
    expect(gazetteerMatchExpression('im muhl')!.match, '"im"* AND "muhl"*');
  });

  test('a file from a newer builder is ignored', () async {
    buildGazetteer(dir, 'E5_N45', schemaVersion: '2', places: fixturePlaces);
    final store = await openStore();

    expect(store.hasTiles, isFalse);
    expect(await store.search('vaduz'), isEmpty);
  });

  test('anything that is not a gazetteer is left alone', () async {
    File('${dir.path}/E5_N45.gaz.part').writeAsStringSync('half a download');
    File('${dir.path}/README').writeAsStringSync('not a database');
    final store = await openStore();

    expect(store.hasTiles, isFalse);
  });

  test('a broken file does not take the good one down', () async {
    buildGazetteer(dir, 'E5_N45', places: fixturePlaces);
    File('${dir.path}/W20_N30.gaz').writeAsStringSync('not sqlite at all');
    final store = await openStore();

    expect(store.tiles, <String>['E5_N45']);
    expect((await store.search('vaduz')).single.name, 'Vaduz');
  });

  test('a rescan picks up a new file and drops a deleted one', () async {
    final store = await openStore();
    expect(store.hasTiles, isFalse);

    final file = buildGazetteer(dir, 'E5_N45', places: fixturePlaces);
    await store.refresh();
    expect(store.tiles, <String>['E5_N45']);
    expect(await store.search('vaduz'), hasLength(1));

    buildGazetteer(
      dir,
      'W20_N30',
      places: const <GazPlace>[
        GazPlace(1, 'Funchal', 'city', 32.6500, -16.9100, population: 105000),
      ],
    );
    await store.refresh();
    expect(store.tiles, <String>['E5_N45', 'W20_N30']);
    expect((await store.search('funch')).single.name, 'Funchal');

    file.deleteSync();
    await store.refresh();
    expect(store.tiles, <String>['W20_N30']);
    expect(await store.search('vaduz'), isEmpty);
  });

  test('a closed store answers nothing and stays closed', () async {
    final store = await storeWithFixture();
    expect(await store.search('vaduz'), hasLength(1));

    store.close();

    expect(store.hasTiles, isFalse);
    expect(await store.search('vaduz'), isEmpty);
    await store.refresh();
    expect(store.hasTiles, isFalse);
  });

  test('a store without a directory is simply empty', () async {
    final store = GazetteerStore(null);
    addTearDown(store.close);
    await store.refresh();

    expect(store.hasTiles, isFalse);
    expect(await store.search('vaduz'), isEmpty);
  });

  group('alternative names', () {
    /// A city that OSM knows under three names, plus one it does not.
    void buildAliases() => buildGazetteer(
      dir,
      'E5_N45',
      places: const <GazPlace>[
        GazPlace(1, 'Brussel', 'city', 50.8500, 4.3500, population: 185000),
        GazPlace(4, 'Brugge', 'city', 51.2090, 3.2247, population: 118000),
      ],
      aliases: const <GazAlias>[
        GazAlias(2, 1, 'Bruxelles'),
        GazAlias(3, 1, 'Brussels'),
      ],
    );

    test('an alias finds the row and shows its primary name', () async {
      buildAliases();
      final store = await openStore();

      final hit = (await store.search('bruxelles')).single;
      expect(hit.name, 'Brussel', reason: 'the primary name is what is shown');
      expect(hit.kind, SearchKind.place);
      expect(hit.detail, 'city');
      expect(hit.position.lat, closeTo(50.85, 1e-6));
    });

    test(
      'a row an alias and its own name both match comes back once',
      () async {
        buildAliases();
        final store = await openStore();

        // "brussel"* matches the primary name and the alias "Brussels".
        final hits = await store.search('brussel');
        expect(hits.map((r) => r.name), <String>['Brussel']);
      },
    );

    test('rows that are not the same row are not deduplicated', () async {
      buildAliases();
      final store = await openStore();

      expect(
        (await store.search('bru')).map((r) => r.name),
        unorderedEquals(<String>['Brussel', 'Brugge']),
      );
    });
  });

  group('house numbers', () {
    /// A street with anchors at 400 and 420, one without any, and a café of
    /// the same name as the first.
    void buildAddresses() => buildGazetteer(
      dir,
      'W20_N30',
      places: const <GazPlace>[
        GazPlace(1, 'Manhattan', 'suburb', 40.7580, -73.9855),
      ],
      streets: const <GazStreet>[
        GazStreet(10, 'West 42nd Street', 40.7570, -73.9900, placeId: 1),
        GazStreet(11, 'East 42nd Street', 40.7510, -73.9750, placeId: 1),
      ],
      pois: const <GazPoi>[
        // A lower id than the street, so a hit list that ignored the number
        // would show the café first.
        GazPoi(5, 'West 42nd Street', 'cafe', 40.7500, -73.9800, placeId: 1),
      ],
      houseNumbers: const <GazHouseNumber>[
        GazHouseNumber(10, 400, 40.7600, -74.0000),
        GazHouseNumber(10, 420, 40.7620, -74.0200),
      ],
    );

    Future<SearchResult> street(GazetteerStore store, String typed) async =>
        (await store.search(typed))
            .firstWhere((r) => r.kind == SearchKind.street);

    test('an exact anchor is the exact position', () async {
      buildAddresses();
      final store = await openStore();

      final hit = await street(store, '400w 42nd');
      expect(hit.name, 'West 42nd Street');
      expect(hit.houseNumber, '400');
      expect(hit.approximate, isFalse);
      expect(hit.position.lat, closeTo(40.7600, 1e-7));
      expect(hit.position.lon, closeTo(-74.0000, 1e-7));
      expect(hit.city, 'Manhattan');
    });

    test('a number between two anchors is interpolated', () async {
      buildAddresses();
      final store = await openStore();

      final hit = await street(store, '410 w 42nd');
      expect(hit.houseNumber, '410');
      expect(hit.approximate, isTrue);
      expect(hit.position.lat, closeTo(40.7610, 1e-7));
      expect(hit.position.lon, closeTo(-74.0100, 1e-7));
    });

    test('a number past the last anchor snaps to it', () async {
      buildAddresses();
      final store = await openStore();

      final high = await street(store, '900 w 42nd');
      expect(high.houseNumber, '900');
      expect(high.approximate, isTrue);
      expect(high.position.lat, closeTo(40.7620, 1e-7));
      expect(high.position.lon, closeTo(-74.0200, 1e-7));

      final low = await street(store, 'w 42nd 2');
      expect(low.approximate, isTrue);
      expect(low.position.lat, closeTo(40.7600, 1e-7));
    });

    test('a street with no anchors answers with the street', () async {
      buildAddresses();
      final store = await openStore();

      final hit = await street(store, '12 east 42nd');
      expect(hit.name, 'East 42nd Street');
      expect(hit.houseNumber, '12');
      expect(hit.approximate, isTrue);
      expect(hit.position.lat, closeTo(40.7510, 1e-7));
    });

    test('a number puts the street above everything else', () async {
      buildAddresses();
      final store = await openStore();

      final numbered = await store.search('400 w 42nd street');
      expect(numbered.first.kind, SearchKind.street);
      expect(numbered.first.houseNumber, '400');
      final cafe = numbered.firstWhere((r) => r.kind == SearchKind.poi);
      expect(cafe.houseNumber, isNull, reason: 'only a street has a number');
      expect(cafe.approximate, isFalse);
      expect(cafe.position.lat, closeTo(40.7500, 1e-7));
    });

    test('an ordinal is a name, not a house number', () async {
      buildAddresses();
      final store = await openStore();

      expect(gazetteerMatchExpression('42nd')!.houseNumber, isNull);
      expect(gazetteerMatchExpression('42nd street')!.houseNumber, isNull);
      final hits = await store.search('42nd');
      expect(hits, isNotEmpty);
      expect(hits.every((r) => r.houseNumber == null), isTrue);
      expect(
        hits.firstWhere((r) => r.kind == SearchKind.street).position.lat,
        closeTo(40.7570, 1e-7),
        reason: 'the street itself, not one of its numbers',
      );
    });

    test('a number alone is still what is searched for', () async {
      buildAddresses();
      final store = await openStore();

      expect(gazetteerMatchExpression('400')!.houseNumber, isNull);
      expect(gazetteerMatchExpression('400')!.match, '"400"*');
      expect(await store.search('400'), isEmpty, reason: 'no name is "400"');
      expect(
        gazetteerMatchExpression('400 w'),
        isNull,
        reason: 'one letter is left to match, which is below the floor',
      );
      expect(await store.search('400 w'), isEmpty);
    });

    test('the query is normalised before it is read', () async {
      final query = gazetteerMatchExpression('400w 42nd')!;
      expect(query.houseNumber, '400');
      expect(query.number, 400);
      expect(query.match, '"w"* AND "42nd"*');

      expect(
        gazetteerMatchExpression('  400   W   42nd  ')!.match,
        '"W"* AND "42nd"*',
      );
      expect(gazetteerMatchExpression('w 42nd 400')!.houseNumber, '400');
      expect(
        gazetteerMatchExpression('400 w 42nd 12')!.houseNumber,
        '400',
        reason: 'the first number wins, the other one is text',
      );
    });

    test('a file with street sides places the number on its side', () async {
      buildGazetteer(
        dir,
        'W20_N30',
        streets: const <GazStreet>[
          GazStreet(10, 'West 42nd Street', 40.7570, -73.9900),
        ],
        // Written by a builder from 2026-10 on: no anchors, the two sides.
        streetNumbers: <int, Uint8List>{
          10: encodeStreetNumbers(
            <(int, double, double)>[
              (401, 40.7601, -74.0001),
              (421, 40.7621, -74.0201),
            ],
            <(int, double, double)>[
              (400, 40.7600, -74.0000),
              (420, 40.7620, -74.0200),
            ],
          ),
        },
      );
      final store = await openStore();

      final hit = (await store.search('410 w 42nd')).single;
      expect(hit.houseNumber, '410');
      expect(hit.approximate, isFalse, reason: 'within 20 m on its own side');
      expect(hit.position.lat, closeTo(40.7610, 1e-7));
      expect(hit.position.lon, closeTo(-74.0100, 1e-7));

      final odd = (await store.search('411 w 42nd')).single;
      expect(odd.position.lat, closeTo(40.7611, 1e-7));

      final past = (await store.search('900 w 42nd')).single;
      expect(past.approximate, isTrue);
      expect(past.position.lat, closeTo(40.7620, 1e-7));
    });

    test('a file from the first builder still answers', () async {
      buildGazetteer(
        dir,
        'W20_N30',
        legacy: true,
        places: const <GazPlace>[
          GazPlace(1, 'Manhattan', 'suburb', 40.7580, -73.9855),
        ],
        streets: const <GazStreet>[
          GazStreet(10, 'West 42nd Street', 40.7570, -73.9900, placeId: 1),
        ],
      );
      final store = await openStore();

      final hit = (await store.search('400 w 42nd')).single;
      expect(hit.name, 'West 42nd Street');
      expect(hit.houseNumber, '400');
      expect(hit.approximate, isTrue, reason: 'no anchors in an old file');
      expect(hit.position.lat, closeTo(40.7570, 1e-7));
      expect((await store.search('manhat')).single.name, 'Manhattan');
    });
  });

  group('the nearest of a kind', () {
    const LatLng centre = LatLng(47.1410, 9.5209);

    /// A latitude [meters] north of [centre].
    double north(double meters) => centre.lat + meters / 111320;

    /// Taps, toilets and racks around the centre, one of each named.
    void buildStops() {
      buildGazetteer(
        dir,
        'E5_N45',
        places: fixturePlaces,
        pois: <GazPoi>[
          GazPoi(
            20,
            'Brunnen Mühleholz',
            'drinking_water',
            north(800),
            centre.lon,
            placeId: 1,
          ),
          GazPoi.unnamed(21, 'drinking_water', north(200), centre.lon),
          GazPoi.unnamed(22, 'toilets', north(100), centre.lon),
          GazPoi.unnamed(23, 'bicycle_parking', north(300), centre.lon),
        ],
      );
    }

    test(
      'an English kind word answers with the nearest of that kind',
      () async {
        buildStops();
        final store = await openStore();

        final found = await store.search('drinking water', near: centre);

        expect(found, hasLength(2));
        expect(found.every((r) => r.detail == 'drinking_water'), isTrue);
        expect(found.first.name, isEmpty, reason: 'the nearest tap is unnamed');
        expect(found.first.distanceMeters, closeTo(200, 5));
        expect(found.last.name, 'Brunnen Mühleholz');
        expect(found.last.distanceMeters, closeTo(800, 5));
      },
    );

    test(
      'a prefix of the word is enough, and so is the localised label',
      () async {
        buildStops();
        final store = await openStore();

        expect(
          (await store.search('toile', near: centre)).single.detail,
          'toilets',
        );
        // What the widget builds from AppLocalizations, in a language that
        // shares no word with the English table.
        final german = await store.search(
          'trink',
          near: centre,
          keywords: const <String, String>{'trinkwasser': 'drinking_water'},
        );
        expect(german, hasLength(2));
        expect(german.first.detail, 'drinking_water');
        expect(
          await store.search('trink', near: centre),
          isEmpty,
          reason: 'without the table the German word names no kind',
        );
      },
    );

    test('at most five rows, nearest first', () async {
      buildGazetteer(
        dir,
        'E5_N45',
        pois: <GazPoi>[
          for (var i = 1; i <= 7; i++)
            GazPoi.unnamed(
              20 + i,
              'bicycle_parking',
              north(i * 100),
              centre.lon,
            ),
        ],
      );
      final store = await openStore();

      final found = await store.search('bike parking', near: centre);

      expect(found, hasLength(kindSearchLimit));
      for (final (index, row) in found.indexed) {
        expect(row.distanceMeters, closeTo((index + 1) * 100, 2));
      }
    });

    test('the box grows to fifty kilometres and stops there', () async {
      buildGazetteer(
        dir,
        'E5_N45',
        pois: <GazPoi>[
          GazPoi.unnamed(21, 'bakery', north(30000), centre.lon),
          GazPoi.unnamed(22, 'bakery', north(60000), centre.lon),
        ],
      );
      final store = await openStore();

      final found = await store.search('bakery', near: centre);

      expect(found, hasLength(1), reason: 'nothing within five kilometres');
      expect(found.single.distanceMeters, closeTo(30000, 50));
    });

    test('without a map centre a kind word is only a name', () async {
      buildStops();
      final store = await openStore();

      expect(await store.search('toilets'), isEmpty);
      expect(
        (await store.search('brunnen')).single.distanceMeters,
        isNull,
        reason: 'a name match is not found by its distance',
      );
    });

    test('kind rows come first and are never listed twice', () async {
      buildStops();
      final store = await openStore();

      final found = await store.search('brunnen', near: centre);
      expect(found.single.name, 'Brunnen Mühleholz');

      // "drinking water" finds the named tap by kind; the name query finds
      // nothing, so it stays one row.
      final byKind = await store.search('drinking water', near: centre);
      expect(byKind.where((r) => r.name == 'Brunnen Mühleholz'), hasLength(1));
    });
  });

  group('search groups', () {
    /// A place and a cafe of the same name: same bm25, same name length, so
    /// only the group order can tell them apart.
    void buildNamesakes() {
      buildGazetteer(
        dir,
        'E5_N45',
        places: const <GazPlace>[
          GazPlace(1, 'Testort', 'village', 47.1400, 9.5200),
        ],
        pois: const <GazPoi>[GazPoi(2, 'Testort', 'cafe', 47.1401, 9.5201)],
      );
    }

    test('a switched-off group is left out of the name matches', () async {
      buildNamesakes();
      final store = await openStore();

      expect((await store.search('testort')), hasLength(2));
      final filtered = await store.search(
        'testort',
        preferences: const SearchPreferences(
          disabled: <SearchGroup>{SearchGroup.cyclingStops},
        ),
      );
      expect(filtered.single.kind, SearchKind.place);
    });

    test('a kind search answers even for a switched-off group', () async {
      buildNamesakes();
      final store = await openStore();

      final found = await store.search(
        'cafe',
        near: const LatLng(47.1400, 9.5200),
        preferences: const SearchPreferences(
          disabled: <SearchGroup>{SearchGroup.cyclingStops},
        ),
      );
      expect(found.single.detail, 'cafe');
    });

    test('the group order breaks a tie before the name length does', () async {
      buildNamesakes();
      final store = await openStore();

      expect((await store.search('testort')).first.kind, SearchKind.place);

      final stopsFirst = SearchPreferences(
        order: <SearchGroup>[
          SearchGroup.cyclingStops,
          for (final group in SearchGroup.values)
            if (group != SearchGroup.cyclingStops) group,
        ],
      );
      expect(
        (await store.search('testort', preferences: stopsFirst)).first.kind,
        SearchKind.poi,
      );
    });

    test('a house number still outranks the group order', () async {
      buildGazetteer(
        dir,
        'E5_N45',
        streets: const <GazStreet>[GazStreet(1, 'Testort', 47.1400, 9.5200)],
        pois: const <GazPoi>[GazPoi(2, 'Testort', 'cafe', 47.1401, 9.5201)],
      );
      final store = await openStore();

      final stopsFirst = SearchPreferences(
        order: <SearchGroup>[
          SearchGroup.cyclingStops,
          for (final group in SearchGroup.values)
            if (group != SearchGroup.cyclingStops) group,
        ],
      );
      final found = await store.search('testort 7', preferences: stopsFirst);
      expect(found.first.kind, SearchKind.street);
      expect(found.first.houseNumber, '7');
    });
  });

  group('typo tolerance', () {
    void buildTypos() {
      buildGazetteer(
        dir,
        'E5_N45',
        places: const <GazPlace>[
          GazPlace(1, 'Funchal', 'town', 32.6500, -16.9100, population: 105000),
          GazPlace(2, 'München', 'city', 48.1370, 11.5750, population: 1500000),
          GazPlace(3, 'Vaduz', 'town', 47.1410, 9.5209, population: 5450),
        ],
      );
    }

    test('a read-only file spells a name back for the rider', () async {
      buildTypos();
      final store = await openStore();

      final found = await store.lookup('Funchall');

      expect(found.correctedQuery, 'funchal');
      expect(found.results.single.name, 'Funchal');
    });

    test('the correction folds diacritics the way the index does', () async {
      buildTypos();
      final store = await openStore();

      final found = await store.lookup('Muinchen');

      expect(found.correctedQuery, 'munchen');
      expect(found.results.single.name, 'München');
    });

    test('a query that finds something is never second-guessed', () async {
      buildTypos();
      final store = await openStore();

      final found = await store.lookup('vaduz');

      expect(found.correctedQuery, isNull);
      expect(found.results.single.name, 'Vaduz');
    });

    test('a short token may be one edit out, a long one two', () async {
      buildTypos();
      final store = await openStore();

      final short = await store.lookup('vzduq');
      expect(short.correctedQuery, isNull, reason: 'two edits, five letters');
      expect(short.results, isEmpty);

      final long = await store.lookup('funhaal');
      expect(
        long.correctedQuery,
        'funchal',
        reason: 'two edits, seven letters',
      );
      expect(long.results.single.name, 'Funchal');
    });

    test('at most five candidates, the commonest word first', () async {
      buildGazetteer(
        dir,
        'E5_N45',
        places: const <GazPlace>[
          GazPlace(1, 'Kahlo', 'village', 47.10, 9.50),
          GazPlace(2, 'Kahlo', 'village', 47.20, 9.60),
          GazPlace(3, 'Kablo', 'village', 47.30, 9.70),
          GazPlace(4, 'Kadlo', 'village', 47.40, 9.80),
          GazPlace(5, 'Kamlo', 'village', 47.50, 9.90),
          GazPlace(6, 'Kaplo', 'village', 47.55, 9.92),
          GazPlace(7, 'Karlo', 'village', 47.60, 9.95),
          GazPlace(8, 'Kaylo', 'village', 47.65, 9.97),
        ],
      );
      final store = await openStore();

      final found = await store.lookup('kaxlo');

      expect(found.correctedQuery, isNotNull);
      expect(found.results.map((r) => r.name).toSet(), <String>{
        'Kahlo',
        'Kablo',
        'Kadlo',
        'Kamlo',
        'Kaplo',
      }, reason: 'the last two never made it into the rewritten query');
    });
  });

  group('reading what the rider meant', () {
    test('"ss" finds "ß" and the other way round', () async {
      buildGazetteer(
        dir,
        'E5_N45',
        streets: const <GazStreet>[
          GazStreet(1, 'Hauptstraße', 47.10, 9.50),
          GazStreet(2, 'Parkstrasse', 47.20, 9.50),
        ],
      );
      final store = await openStore();

      expect((await store.search('hauptstrasse')).first.name, 'Hauptstraße');
      expect((await store.search('parkstraße')).first.name, 'Parkstrasse');
    });

    test('one word typed as two, and two typed as one', () async {
      buildGazetteer(
        dir,
        'E15_N45',
        streets: const <GazStreet>[
          GazStreet(1, 'Mariahilfer Straße', 48.20, 16.35),
          GazStreet(2, 'Hauptstraße', 48.30, 16.40),
        ],
      );
      final store = await openStore();

      expect(
        (await store.search('mariahilferstrasse')).first.name,
        'Mariahilfer Straße',
      );
      expect((await store.search('haupt strasse')).first.name, 'Hauptstraße');
    });

    test('an abbreviation is read from its letters, either way', () async {
      buildGazetteer(
        dir,
        'W5_N50',
        streets: const <GazStreet>[
          GazStreet(1, 'Abbey Road', 51.53, -0.18),
          GazStreet(2, 'Abbey Lane', 51.54, -0.18),
        ],
        pois: const <GazPoi>[
          GazPoi(3, "St Paul's Cathedral", 'place_of_worship', 51.51, -0.10),
          GazPoi(
            4,
            "Saint George's Cathedral",
            'place_of_worship',
            51.50,
            -0.11,
          ),
        ],
      );
      final store = await openStore();

      expect((await store.search('abbey rd')).first.name, 'Abbey Road');
      expect(
        (await store.search('saint pauls cathedral')).first.name,
        "St Paul's Cathedral",
      );
    });

    test('a word the index has never seen does not sink the rest', () async {
      buildGazetteer(
        dir,
        'W5_N50',
        streets: const <GazStreet>[GazStreet(1, 'Abbey Road', 51.53, -0.18)],
      );
      final store = await openStore();

      expect((await store.search('abbey road xyzzy')).first.name, 'Abbey Road');
    });

    test('a town after the street says which street', () async {
      buildGazetteer(
        dir,
        'E10_N50',
        places: const <GazPlace>[
          GazPlace(1, 'Berlin', 'city', 52.52, 13.40, population: 3600000),
          GazPlace(2, 'Kreuzberg', 'suburb', 52.50, 13.40, adminId: 1),
          GazPlace(3, 'München', 'city', 48.14, 11.58, population: 1500000),
          GazPlace(4, 'Schwabing', 'suburb', 48.16, 11.58, adminId: 3),
        ],
        streets: const <GazStreet>[
          GazStreet(10, 'Hauptstraße', 48.16, 11.58, placeId: 4),
          GazStreet(11, 'Hauptstraße', 52.49, 13.35, placeId: 2),
          GazStreet(12, 'Berliner Straße', 48.15, 11.57, placeId: 4),
        ],
      );
      final store = await openStore();
      const munich = LatLng(48.14, 11.58);

      final berlin = await store.search('hauptstrasse 12 berlin', near: munich);
      expect(berlin.first.name, 'Hauptstraße');
      expect(berlin.first.city, 'Kreuzberg');
      expect(berlin.first.houseNumber, '12');

      final here = await store.search('hauptstrasse', near: munich);
      expect(
        here.first.city,
        'Schwabing',
        reason: 'no town named: the near one',
      );
    });

    test('a town before the street says which street too', () async {
      buildGazetteer(
        dir,
        'E15_N45',
        places: const <GazPlace>[
          GazPlace(1, 'Budapest', 'city', 47.50, 19.04, population: 1700000),
          GazPlace(2, 'Győr', 'city', 47.69, 17.63, population: 130000),
        ],
        streets: const <GazStreet>[
          GazStreet(10, 'Fő utca', 47.69, 17.64, placeId: 2),
          GazStreet(11, 'Fő utca', 47.49, 19.05, placeId: 1),
        ],
      );
      final store = await openStore();

      final found = await store.search(
        'Budapest, Fő utca 12',
        near: const LatLng(47.69, 17.63),
      );
      expect(found.first.city, 'Budapest');
      expect(found.first.houseNumber, '12');
    });

    test('a street named after a town stays that street', () async {
      buildGazetteer(
        dir,
        'E0_N45',
        places: const <GazPlace>[
          GazPlace(1, 'Paris', 'city', 48.86, 2.35, population: 2100000),
          GazPlace(2, 'Lyon', 'city', 45.76, 4.84, population: 520000),
        ],
        streets: const <GazStreet>[
          GazStreet(10, 'Rue de Paris', 45.75, 4.85, placeId: 2),
          GazStreet(11, 'Rue de Paris', 48.85, 2.36, placeId: 1),
        ],
      );
      final store = await openStore();

      final found = await store.search(
        'rue de paris',
        near: const LatLng(45.76, 4.84),
      );
      expect(found.first.city, 'Lyon');
    });

    test('the near one of a very common name is found', () async {
      buildGazetteer(
        dir,
        'E10_N50',
        streets: <GazStreet>[
          for (var i = 0; i < 2500; i++)
            GazStreet(i + 1, 'Lindenweg', 50.0 + i * 0.001, 10.0),
          const GazStreet(9000, 'Lindenweg', 54.5, 14.5),
        ],
      );
      final store = await openStore();

      final found = await store.search(
        'lindenweg',
        near: const LatLng(54.5, 14.5),
      );
      expect(found.first.position.lat, closeTo(54.5, 1e-6));
    });

    test(
      'a famous landmark beats namesakes its name only partly fits',
      () async {
        buildGazetteer(
          dir,
          'E0_N45',
          places: const <GazPlace>[
            GazPlace(1, 'Notre-Dame', 'neighbourhood', 48.86, 2.30),
            GazPlace(2, 'Notre-Dame', 'hamlet', 48.70, 2.10),
          ],
          pois: const <GazPoi>[
            GazPoi(
              3,
              'Cathédrale Notre-Dame de Paris',
              'place_of_worship',
              48.853,
              2.3499,
              importance: 85,
            ),
            GazPoi(4, 'Notre-Dame', 'place_of_worship', 48.80, 2.20),
          ],
        );
        final store = await openStore();

        final found = await store.search(
          'notre dame',
          near: const LatLng(48.8566, 2.3522),
        );
        expect(found.first.name, 'Cathédrale Notre-Dame de Paris');
        expect(found.map((r) => r.name), contains('Notre-Dame'));
      },
    );

    test('Cyrillic and Latin find each other in both kinds of file', () async {
      for (final latinIndex in <bool>[false, true]) {
        buildGazetteer(
          dir,
          'E20_N40',
          latinIndex: latinIndex,
          pois: const <GazPoi>[
            GazPoi(
              1,
              'Храм-паметник Св. Александър Невски',
              'place_of_worship',
              42.6958,
              23.3328,
            ),
          ],
          streets: const <GazStreet>[GazStreet(2, 'бул. Витоша', 42.69, 23.32)],
        );
        final store = await openStore();
        final why = latinIndex ? 'indexed in Latin' : 'indexed as written';

        expect(
          (await store.search('александър невски')).first.kind,
          SearchKind.poi,
          reason: why,
        );
        expect(
          (await store.search('витоша 15')).first.houseNumber,
          '15',
          reason: why,
        );
        if (latinIndex) {
          expect(
            (await store.search('aleksandar nevski')).first.name,
            'Храм-паметник Св. Александър Невски',
          );
          expect((await store.search('vitosha')).first.name, 'бул. Витоша');
          expect(
            (await store.search('aleksander nevsky')).first.name,
            'Храм-паметник Св. Александър Невски',
            reason: 'a spelling of its own is a typo away',
          );
        }
        store.close();
      }
    });

    test('the stored vocabulary answers like the computed one', () async {
      for (final vocab in <bool>[false, true]) {
        buildGazetteer(
          dir,
          'E5_N45',
          vocab: vocab,
          places: const <GazPlace>[
            GazPlace(1, 'Funchal', 'town', 32.65, -16.91, population: 105000),
            GazPlace(2, 'München', 'city', 48.137, 11.575),
          ],
        );
        final store = await openStore();

        final found = await store.lookup('Muinchen');
        expect(found.correctedQuery, 'munchen', reason: 'vocab: $vocab');
        expect(found.results.single.name, 'München');
        store.close();
      }
    });
  });

  test(
    'the builder fixture answers the same way',
    () async {
      realFixture.copySync('${dir.path}/E5_N45.gaz');
      final store = await openStore();

      expect(store.hasTiles, isTrue, reason: 'the fixture is schema 1');
      final village = await store.search('muhleholz');
      expect(
        village.map((r) => r.name),
        contains('Mühleholz'),
        reason: 'diacritics are folded in the real file too',
      );
      final street = await store.search('im muhl');
      expect(street.map((r) => r.name), contains('Im Mühleholz'));
      // The Python builder's street_numbers blobs, read by the Dart decoder:
      // street 185 is Landstrasse, its odd side starts at 115.
      final db = sqlite3.open(realFixture.path, mode: OpenMode.readOnly);
      addTearDown(db.close);
      var blobs = 0;
      for (final row in db.select(
        'SELECT street_id, data FROM street_numbers',
      )) {
        final sides = decodeStreetNumbers(row['data'] as Uint8List);
        expect(sides, isNotNull, reason: 'street ${row['street_id']}');
        expect(sides!.odd.every((p) => p.number.isOdd), isTrue);
        expect(sides.even.every((p) => p.number.isEven), isTrue);
        blobs++;
      }
      expect(blobs, greaterThan(900));
      final landstrasse = decodeStreetNumbers(
        db
                .select('SELECT data FROM street_numbers WHERE street_id = 185')
                .single['data']
            as Uint8List,
      )!;
      expect(landstrasse.odd.first.number, 115);
      expect(landstrasse.odd.first.position.lat, closeTo(47.11491, 1e-9));
      expect(landstrasse.odd.first.position.lon, closeTo(9.52398, 1e-9));
      final address = (await store.search('landstrasse 115'))
          .firstWhere((r) => r.kind == SearchKind.street);
      expect(address.houseNumber, '115');

      final vaduz = (await store.search('vaduz'))
          .firstWhere((r) => r.kind == SearchKind.place);
      expect(vaduz.detail, isNotNull);
      expect(vaduz.position.lat, closeTo(47.14, 0.2));
    },
    skip: realFixture.existsSync()
        ? false
        : 'tools/gazetteer/fixtures/E5_N45.gaz is not built yet',
  );
}

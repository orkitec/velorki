import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/search/data/gazetteer_store.dart';
import 'package:velorki/features/search/domain/search_result.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/gazetteer_fixture.dart';

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

  test('every token has to match, and every one is a prefix', () async {
    final store = await storeWithFixture();

    final street = await store.search('im muhl');
    expect(street.map((r) => r.name), <String>['Im Mühleholz']);
    expect(street.single.kind, SearchKind.street);
    expect(street.single.detail, isNull);
    expect(street.single.city, 'Vaduz');
    expect(street.single.houseNumber, isNull);
    expect(street.single.approximate, isFalse);

    expect((await store.search('muhl im')).map((r) => r.name), <String>[
      'Im Mühleholz',
    ], reason: 'the order of the words is not the rider\'s problem');
    expect(
      (await store.search('sta')).map((r) => r.name),
      contains('Städtle'),
      reason: 'a lone token is a prefix as well',
    );
  });

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

  test('ties go to the bigger town, then to the nearer one', () async {
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

    final near = await store.search('testort', near: const LatLng(47.05, 9.00));
    expect(near.map((r) => r.position.lat), <double>[
      47.50,
      47.00,
      47.10,
    ], reason: 'population first, then the shorter way to the map centre');

    final far = await store.search('testort', near: const LatLng(47.40, 9.00));
    expect(far.map((r) => r.position.lat), <double>[47.50, 47.10, 47.00]);

    final unbiased = await store.search('testort');
    expect(unbiased.first.position.lat, 47.50);
  });

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
    expect(gazetteerMatchExpression('a"b')!.match, '"a""b"*');
    expect(gazetteerMatchExpression('***'), isNull);
    expect(gazetteerMatchExpression('im muhl')!.match, '"im"* "muhl"*');
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
      expect(query.match, '"w"* "42nd"*');

      expect(
        gazetteerMatchExpression('  400   W   42nd  ')!.match,
        '"W"* "42nd"*',
      );
      expect(gazetteerMatchExpression('w 42nd 400')!.houseNumber, '400');
      expect(
        gazetteerMatchExpression('400 w 42nd 12')!.houseNumber,
        '400',
        reason: 'the first number wins, the other one is text',
      );
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

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

  test('every token has to match, only the last one is a prefix', () async {
    final store = await storeWithFixture();

    final street = await store.search('im muhl');
    expect(street.map((r) => r.name), <String>['Im Mühleholz']);
    expect(street.single.kind, SearchKind.street);
    expect(street.single.detail, isNull);
    expect(street.single.city, 'Vaduz');

    expect(await store.search('muhl im'), isEmpty, reason: 'im is no prefix');
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
    expect(gazetteerMatchExpression('a"b'), '"a""b"*');
    expect(gazetteerMatchExpression('***'), isNull);
    expect(gazetteerMatchExpression('im muhl'), '"im" "muhl"*');
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

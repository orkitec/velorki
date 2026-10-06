import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/search/data/gazetteer_store.dart';
import 'package:velorki/features/search/domain/search_result.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/gazetteer_fixture.dart';

/// The background store against the one on the calling isolate: the same
/// answers, in any order of questions, across a rescan and a close.
void main() {
  late Directory dir;
  final realFixture = File('../tools/gazetteer/fixtures/E5_N45.gaz');
  const vaduz = LatLng(47.141, 9.521);

  setUp(() {
    final root = Directory.systemTemp.createTempSync('velorki-gaz-worker');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    dir = Directory('${root.path}/gazetteer')..createSync(recursive: true);
  });

  Future<GazetteerStore> open({required bool background}) async {
    final store = GazetteerStore(dir, background: background);
    addTearDown(store.close);
    await store.refresh();
    return store;
  }

  test('the worker answers exactly what the calling isolate would', () async {
    realFixture.copySync('${dir.path}/E5_N45.gaz');
    final here = await open(background: false);
    final there = await open(background: true);

    for (final text in <String>[
      'vaduz',
      'muhleholz',
      'im muhl',
      'landstrasse 115',
      'Vadzu',
      'kathedrale st florin',
      'schloss vaduz triesen',
      'zz',
    ]) {
      final a = await here.lookup(text, near: vaduz);
      final b = await there.lookup(text, near: vaduz);
      expect(b.results, a.results, reason: text);
      expect(b.correctedQuery, a.correctedQuery, reason: text);
    }
    expect(there.workerStarted, isTrue);
    expect(here.workerStarted, isFalse);

    final box = BoundingBox(south: 47.0, west: 9.4, north: 47.3, east: 9.7);
    expect(
      await there.inBox(box, placeKinds: <String>['village', 'town']),
      await here.inBox(box, placeKinds: <String>['village', 'town']),
    );
    expect(
      await there.nearestSettlement(vaduz),
      await here.nearestSettlement(vaduz),
    );
  }, skip: realFixture.existsSync() ? false : 'fixture not built');

  test('typing ahead: every question is answered, stale lookups may be skipped '
      'but never answered with another query', () async {
    realFixture.copySync('${dir.path}/E5_N45.gaz');
    final store = await open(background: true);
    // Warm up so the worker is running before the burst.
    await store.lookup('vaduz');

    const typed = <String>[
      'vad',
      'vadu',
      'vaduz',
      'tries',
      'triesen',
      'schaan',
    ];
    final answers = await Future.wait(<Future<GazetteerSearch>>[
      for (final text in typed) store.lookup(text, near: vaduz),
      // A ride being named in between must not be skipped.
      store
          .nearestSettlement(vaduz)
          .then((place) => GazetteerSearch(results: <SearchResult>[?place])),
    ]);

    for (var i = 0; i < typed.length; i++) {
      final results = answers[i].results;
      if (results.isEmpty) continue; // skipped for a newer lookup
      final prefix = typed[i].substring(0, 3);
      expect(
        results.first.name.toLowerCase(),
        startsWith(prefix),
        reason: '"${typed[i]}" got the answer to another question',
      );
    }
    expect(
      answers[typed.length - 1].results.first.name,
      'Schaan',
      reason: 'the last lookup is always answered',
    );
    expect(answers.last.results.single.name, isNotEmpty);
  }, skip: realFixture.existsSync() ? false : 'fixture not built');

  test('a rescan reaches the worker before the next lookup', () async {
    buildGazetteer(
      dir,
      'E5_N45',
      places: const <GazPlace>[GazPlace(1, 'Vaduz', 'town', 47.14, 9.52)],
    );
    final store = await open(background: true);
    expect((await store.lookup('vaduz')).results.single.name, 'Vaduz');
    expect(await store.lookup('funchal'), isA<GazetteerSearch>());
    expect((await store.lookup('funchal')).results, isEmpty);

    buildGazetteer(
      dir,
      'W20_N30',
      places: const <GazPlace>[GazPlace(1, 'Funchal', 'city', 32.65, -16.91)],
    );
    await store.refresh();
    expect((await store.lookup('funchal')).results.single.name, 'Funchal');

    File('${dir.path}/W20_N30.gaz').deleteSync();
    await store.refresh();
    expect((await store.lookup('funchal')).results, isEmpty);
    expect(store.tiles, <String>['E5_N45']);
  });

  test(
    'closing with questions in flight answers them all, with nothing',
    () async {
      realFixture.copySync('${dir.path}/E5_N45.gaz');
      final store = GazetteerStore(dir, background: true);
      await store.refresh();
      await store.lookup('vaduz');

      final pending = <Future<GazetteerSearch>>[
        for (final text in <String>['triesen', 'schaan', 'balzers', 'vadzu'])
          store.lookup(text),
      ];
      store.close();
      final answers = await Future.wait(pending)
          .timeout(const Duration(seconds: 10));
      expect(answers, hasLength(4), reason: 'no question is left hanging');
      expect((await store.lookup('vaduz')).results, isEmpty);
      expect(await store.nearestSettlement(vaduz), isNull);
      store.close(); // twice is harmless
    },
    skip: realFixture.existsSync() ? false : 'fixture not built',
  );

  test('a burst of lookups, rescans and reverse lookups all settle', () async {
    realFixture.copySync('${dir.path}/E5_N45.gaz');
    final store = GazetteerStore(dir, background: true);
    await store.refresh();

    const words = <String>['vaduz', 'triesen', 'schaan', 'balzers', 'eschen'];
    final all = <Future<Object?>>[];
    for (var i = 0; i < 60; i++) {
      all.add(store.lookup(words[i % words.length], near: vaduz));
      if (i % 7 == 0) all.add(store.refresh());
      if (i % 11 == 0) all.add(store.nearestSettlement(vaduz));
    }
    final last = store.lookup('eschen', near: vaduz);
    await Future.wait(all).timeout(const Duration(seconds: 30));
    expect((await last).results.first.name, 'Eschen');

    store.close();
    expect(await store.lookup('vaduz'), isA<GazetteerSearch>());
  }, skip: realFixture.existsSync() ? false : 'fixture not built');

  test('no worker without files, and none without a directory', () async {
    final empty = await open(background: true);
    expect((await empty.lookup('vaduz')).results, isEmpty);
    expect(empty.workerStarted, isFalse);

    final none = GazetteerStore(null, background: true);
    addTearDown(none.close);
    await none.refresh();
    expect((await none.lookup('vaduz')).results, isEmpty);
    expect(none.workerStarted, isFalse);
  });

  test('a slow search does not hold up the calling isolate', () async {
    buildGazetteer(
      dir,
      'E10_N50',
      streets: <GazStreet>[
        for (var i = 0; i < 5000; i++)
          GazStreet(i + 1, 'Lindenweg ${i % 50}', 50.0 + i * 0.0005, 10.0),
      ],
    );
    final store = await open(background: true);
    await store.lookup('lindenweg');

    // Ticks keep coming while the worker searches: the calling isolate's
    // event loop is free.
    var ticks = 0;
    final timer = Timer.periodic(
      const Duration(milliseconds: 1),
      (_) => ticks++,
    );
    final watch = Stopwatch()..start();
    var searches = 0;
    while (watch.elapsedMilliseconds < 300) {
      await store.lookup('lindenwge 7', near: const LatLng(50.5, 10.0));
      searches++;
    }
    timer.cancel();
    expect(searches, greaterThan(0));
    expect(ticks, greaterThan(100), reason: '$searches searches, $ticks ticks');
  });
}

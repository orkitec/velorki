import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/search/application/place_search_controller.dart';
import 'package:velorki/features/search/data/gazetteer_store.dart';
import 'package:velorki/features/search/data/photon_client.dart';
import 'package:velorki/features/search/domain/search_result.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/fake_http.dart';
import 'support/gazetteer_fixture.dart';

/// A map centre inside `E5_N45`, the tile the fixture gazetteer covers.
const LatLng inTheTile = LatLng(47.1410, 9.5209);

/// A map centre in `E10_N45`, which no gazetteer here covers.
const LatLng outsideTheTile = LatLng(48.1374, 11.5755);

void main() {
  late Directory dir;

  setUp(() {
    final root = Directory.systemTemp.createTempSync('velorki-search');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    dir = Directory('${root.path}/gazetteer')..createSync(recursive: true);
  });

  /// A container whose store holds the fixture when [withGazetteer].
  Future<ProviderContainer> containerFor({
    bool withGazetteer = true,
    bool withGeocoder = true,
    FakeHttpAdapter? adapter,
    Map<String, Object> prefs = const <String, Object>{},
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final preferences = await SharedPreferences.getInstance();
    if (withGazetteer) {
      buildGazetteer(
        dir,
        'E5_N45',
        places: fixturePlaces,
        streets: fixtureStreets,
        pois: fixturePois,
      );
    }
    final store = GazetteerStore(dir);
    addTearDown(store.close);
    await store.refresh();
    final container = ProviderContainer(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(preferences),
        gazetteerStoreProvider.overrideWith((ref) async => store),
        photonClientProvider.overrideWithValue(
          withGeocoder
              ? PhotonClient(
                  'https://photon.test',
                  dio: fakeDio(adapter ?? FakeHttpAdapter(body: photonFixture)),
                )
              : null,
        ),
      ],
    );
    addTearDown(container.dispose);
    // The controller remembers the store as soon as it is open; every search
    // below assumes that has happened, exactly as it has on a running app.
    container.listen(placeSearchProvider, (_, _) {});
    await container.read(gazetteerStoreProvider.future);
    await Future<void>.delayed(Duration.zero);
    return container;
  }

  /// Waits for the debounce and the search behind it.
  // Waits out the debounce and then for the search to finish. A fixed
  // delay races the whole suite's load; polling the state does not.
  Future<void> settle([ProviderContainer? container]) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (container == null) return;
    for (var i = 0; i < 100; i++) {
      final now = container.read(placeSearchProvider);
      if (!now.isLoading && !(now.value?.searching ?? false)) return;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  test('with a gazetteer the search answers from the device', () async {
    final adapter = FakeHttpAdapter(body: photonFixture);
    final container = await containerFor(adapter: adapter);

    container
        .read(placeSearchProvider.notifier)
        .query('vaduz', bias: inTheTile);
    await settle(container);

    final state = container.read(placeSearchProvider).value!;
    expect(state.source, SearchSource.local);
    expect(state.query, 'vaduz');
    expect(state.canSearchOnline, isTrue);
    expect(state.offlineAvailableHere, isTrue);
    expect(state.results.map((r) => r.name), contains('Vaduz'));
    expect(state.results.every((r) => r.source == SearchSource.local), isTrue);
    expect(adapter.requests, isEmpty, reason: 'nothing went to the network');
  });

  test(
    'the next search keeps the last results on screen until it answers',
    () async {
      final container = await containerFor();
      final search = container.read(placeSearchProvider.notifier);

      search.query('vad', bias: inTheTile);
      expect(
        container.read(placeSearchProvider).isLoading,
        isTrue,
        reason: 'nothing to keep yet: the list is only the bar',
      );
      await settle(container);
      final first = container.read(placeSearchProvider).value!;
      expect(first.results, isNotEmpty);
      expect(first.searching, isFalse);

      search.query('vaduz', bias: inTheTile);
      final waiting = container.read(placeSearchProvider);
      expect(waiting.isLoading, isFalse);
      expect(waiting.value!.searching, isTrue);
      expect(waiting.value!.results, first.results);
      expect(waiting.value!.query, 'vad', reason: 'they answer the old text');

      await settle(container);
      final second = container.read(placeSearchProvider).value!;
      expect(second.searching, isFalse);
      expect(second.query, 'vaduz');

      search.query('va', bias: inTheTile);
      expect(
        container.read(placeSearchProvider).value!.results,
        isEmpty,
        reason: 'below three characters the list empties at once',
      );
    },
  );

  test(
    'pasted coordinates are the place, in either map app\'s notation',
    () async {
      final adapter = FakeHttpAdapter(body: photonFixture);
      final container = await containerFor(adapter: adapter);
      final search = container.read(placeSearchProvider.notifier);

      for (final typed in <String>[
        '40.71747105305585 -73.94839976190572',
        '40,71747° N, 73,94840° W',
      ]) {
        search.query(typed, bias: outsideTheTile);
        await settle(container);
        final state = container.read(placeSearchProvider).value!;
        expect(state.results, hasLength(1), reason: typed);
        expect(state.results.single.position.lat, closeTo(40.71747, 1e-4));
        expect(state.results.single.position.lon, closeTo(-73.94840, 1e-4));
        expect(state.results.single.name, '40.71747, -73.94840');
        expect(state.source, SearchSource.local);
      }
      expect(adapter.requests, isEmpty, reason: 'nothing to ask anyone');
    },
  );

  test('a centre outside the downloaded tile asks first and sends nothing, '
      'then searches online, and keeps that until cleared', () async {
    final adapter = FakeHttpAdapter(body: photonFixture);
    final container = await containerFor(adapter: adapter);
    final notifier = container.read(placeSearchProvider.notifier);

    notifier.query('vaduz', lang: 'en', bias: outsideTheTile);
    await settle(container);
    var state = container.read(placeSearchProvider).value!;
    expect(state.choosingSource, isTrue);
    expect(state.results, isEmpty);
    expect(adapter.requests, isEmpty, reason: 'nothing leaves the phone');

    await notifier.searchOnline(lang: 'en', bias: outsideTheTile);
    state = container.read(placeSearchProvider).value!;
    expect(adapter.requests, hasLength(1));
    expect(state.choosingSource, isFalse);
    expect(state.source, SearchSource.online);
    expect(state.results.map((r) => r.name), contains('Munich'));
    expect(
      state.offlineAvailableHere,
      isTrue,
      reason: 'the downloaded areas are one tap away',
    );

    // The pick holds for the next keystrokes.
    notifier.query('vaduz s', lang: 'en', bias: outsideTheTile);
    await settle(container);
    expect(adapter.requests, hasLength(2));

    // Cleared, it asks again.
    notifier
      ..clear()
      ..query('vaduz', lang: 'en', bias: outsideTheTile);
    await settle(container);
    expect(container.read(placeSearchProvider).value!.choosingSource, isTrue);
    expect(adapter.requests, hasLength(2));
  });

  test('outside the tile, the downloaded areas answer when picked', () async {
    final adapter = FakeHttpAdapter(body: photonFixture);
    final container = await containerFor(adapter: adapter);
    final notifier = container.read(placeSearchProvider.notifier);

    notifier.query('vaduz', bias: outsideTheTile);
    await settle(container);
    await notifier.searchOffline(bias: outsideTheTile);

    var state = container.read(placeSearchProvider).value!;
    expect(state.source, SearchSource.local);
    expect(state.results.map((r) => r.name), contains('Vaduz'));
    expect(adapter.requests, isEmpty);

    notifier.query('schaan', bias: outsideTheTile);
    await settle(container);
    state = container.read(placeSearchProvider).value!;
    expect(state.source, SearchSource.local);
    expect(adapter.requests, isEmpty);
  });

  test('with nothing downloaded the search goes online at once', () async {
    final adapter = FakeHttpAdapter(body: photonFixture);
    final container = await containerFor(
      adapter: adapter,
      withGazetteer: false,
    );

    container
        .read(placeSearchProvider.notifier)
        .query('vaduz', lang: 'en', bias: outsideTheTile);
    await settle(container);

    final state = container.read(placeSearchProvider).value!;
    expect(adapter.requests, hasLength(1));
    expect(state.choosingSource, isFalse);
    expect(state.offlineAvailableHere, isFalse);
  });

  test('outside the tile with no online search, the device answers', () async {
    final container = await containerFor(withGeocoder: false);

    container
        .read(placeSearchProvider.notifier)
        .query('vaduz', bias: outsideTheTile);
    await settle(container);

    final state = container.read(placeSearchProvider).value!;
    expect(state.choosingSource, isFalse);
    expect(state.source, SearchSource.local);
    expect(state.results.map((r) => r.name), contains('Vaduz'));
  });

  test('without a map centre there is no area to judge, so online', () async {
    final adapter = FakeHttpAdapter(body: photonFixture);
    final container = await containerFor(adapter: adapter);

    container.read(placeSearchProvider.notifier).query('vaduz', lang: 'en');
    await settle(container);

    final state = container.read(placeSearchProvider).value!;
    expect(adapter.requests, hasLength(1));
    expect(state.source, SearchSource.online);
    expect(
      state.offlineAvailableHere,
      isTrue,
      reason: 'the downloaded areas can still answer, a tap away',
    );
  });

  test('the footer switches the same query both ways', () async {
    final adapter = FakeHttpAdapter(body: photonFixture);
    final container = await containerFor(adapter: adapter);
    final notifier = container.read(placeSearchProvider.notifier);

    notifier.query('vaduz', bias: inTheTile);
    await settle(container);
    expect(
      container.read(placeSearchProvider).value!.source,
      SearchSource.local,
    );

    await notifier.searchOnline(bias: inTheTile);
    var state = container.read(placeSearchProvider).value!;
    expect(state.source, SearchSource.online);
    expect(state.results.map((r) => r.name), contains('Munich'));
    expect(
      state.offlineAvailableHere,
      isTrue,
      reason: 'the way back is offered while the area is downloaded',
    );

    await notifier.searchOffline(bias: inTheTile);
    state = container.read(placeSearchProvider).value!;
    expect(state.source, SearchSource.local);
    expect(state.query, 'vaduz');
    expect(state.results.map((r) => r.name), contains('Vaduz'));
    expect(adapter.requests, hasLength(1), reason: 'nothing else was asked');
  });

  test('the online row runs Photon and replaces the results', () async {
    final adapter = FakeHttpAdapter(body: photonFixture);
    final container = await containerFor(adapter: adapter);
    final notifier = container.read(placeSearchProvider.notifier);

    notifier.query('vaduz', bias: inTheTile);
    await settle(container);
    expect(adapter.requests, isEmpty);

    await notifier.searchOnline(bias: inTheTile);

    final state = container.read(placeSearchProvider).value!;
    expect(adapter.requests, hasLength(1));
    expect(adapter.lastUri.queryParameters['q'], 'vaduz');
    expect(state.source, SearchSource.online);
    expect(state.results.map((r) => r.name), contains('Munich'));
    expect(state.query, 'vaduz');
  });

  test('without a geocoder there is nothing to offer online', () async {
    final container = await containerFor(withGeocoder: false);

    container
        .read(placeSearchProvider.notifier)
        .query('vaduz', bias: inTheTile);
    await settle(container);

    final state = container.read(placeSearchProvider).value!;
    expect(state.source, SearchSource.local);
    expect(state.canSearchOnline, isFalse);
    await container.read(placeSearchProvider.notifier).searchOnline();
    expect(container.read(placeSearchProvider).hasError, isTrue);
  });

  test('without a gazetteer the field behaves as it always did', () async {
    final adapter = FakeHttpAdapter(body: photonFixture);
    final container = await containerFor(
      withGazetteer: false,
      adapter: adapter,
    );

    container.read(placeSearchProvider.notifier).query('munich', lang: 'en');
    await settle(container);

    final state = container.read(placeSearchProvider).value!;
    expect(adapter.requests, hasLength(1));
    expect(adapter.lastUri.queryParameters['lang'], 'en');
    expect(state.source, SearchSource.online);
    expect(state.canSearchOnline, isTrue);
    expect(state.results.map((r) => r.name), contains('Munich'));
  });

  test('below three characters nothing is searched, here or online', () async {
    final adapter = FakeHttpAdapter(body: photonFixture);
    final container = await containerFor(adapter: adapter);

    container.read(placeSearchProvider.notifier).query('va', bias: inTheTile);
    await settle(container);

    expect(container.read(placeSearchProvider).value!.results, isEmpty);
    expect(adapter.requests, isEmpty);
    await container.read(placeSearchProvider.notifier).searchOnline();
    expect(adapter.requests, isEmpty, reason: 'there is no query to send');
  });

  test('a keystroke supersedes the search before it', () async {
    final container = await containerFor();
    final notifier = container.read(placeSearchProvider.notifier)
      ..query('schaan', bias: inTheTile)
      ..query('vaduz', bias: inTheTile);
    await settle(container);

    final state = container.read(placeSearchProvider).value!;
    expect(state.query, 'vaduz');
    expect(state.results.map((r) => r.name), isNot(contains('Schaan')));
    expect(notifier, isNotNull);
  });

  test('a keystroke cancels the request that is in flight', () async {
    final adapter = FakeHttpAdapter(body: photonFixture);
    final container = await containerFor(
      withGazetteer: false,
      adapter: adapter,
    );
    final notifier = container.read(placeSearchProvider.notifier)
      ..query('munich');
    await settle(container);
    expect(adapter.requests, hasLength(1));

    notifier.query('munchen');
    await settle(container);

    expect(adapter.requests, hasLength(2));
    expect(adapter.lastUri.queryParameters['q'], 'munchen');
  });

  test('clear empties the list and forgets the query', () async {
    final container = await containerFor();
    final notifier = container.read(placeSearchProvider.notifier)
      ..query('vaduz', bias: inTheTile);
    await settle(container);
    expect(container.read(placeSearchProvider).value!.results, isNotEmpty);

    notifier.clear();

    final state = container.read(placeSearchProvider).value!;
    expect(state.results, isEmpty);
    expect(state.query, isEmpty);
    await notifier.searchOnline();
    expect(container.read(placeSearchProvider).value!.results, isEmpty);
  });

  test('a geocoder failure is reported as it always was', () async {
    final adapter = FakeHttpAdapter(body: 'not json at all');
    final container = await containerFor(
      withGazetteer: false,
      adapter: adapter,
    );

    container.read(placeSearchProvider.notifier).query('munich');
    await settle(container);

    expect(container.read(placeSearchProvider).hasError, isTrue);
  });
}

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

import 'support/fake_http.dart';
import 'support/gazetteer_fixture.dart';

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
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 300));

  test('with a gazetteer the search answers from the device', () async {
    final adapter = FakeHttpAdapter(body: photonFixture);
    final container = await containerFor(adapter: adapter);

    container.read(placeSearchProvider.notifier).query('vaduz');
    await settle();

    final state = container.read(placeSearchProvider).value!;
    expect(state.source, SearchSource.local);
    expect(state.query, 'vaduz');
    expect(state.canSearchOnline, isTrue);
    expect(state.results.map((r) => r.name), contains('Vaduz'));
    expect(state.results.every((r) => r.source == SearchSource.local), isTrue);
    expect(adapter.requests, isEmpty, reason: 'nothing went to the network');
  });

  test('the online row runs Photon and replaces the results', () async {
    final adapter = FakeHttpAdapter(body: photonFixture);
    final container = await containerFor(adapter: adapter);
    final notifier = container.read(placeSearchProvider.notifier);

    notifier.query('vaduz');
    await settle();
    expect(adapter.requests, isEmpty);

    await notifier.searchOnline();

    final state = container.read(placeSearchProvider).value!;
    expect(adapter.requests, hasLength(1));
    expect(adapter.lastUri.queryParameters['q'], 'vaduz');
    expect(state.source, SearchSource.online);
    expect(state.results.map((r) => r.name), contains('Munich'));
    expect(state.query, 'vaduz');
  });

  test('without a geocoder there is nothing to offer online', () async {
    final container = await containerFor(withGeocoder: false);

    container.read(placeSearchProvider.notifier).query('vaduz');
    await settle();

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
    await settle();

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

    container.read(placeSearchProvider.notifier).query('va');
    await settle();

    expect(container.read(placeSearchProvider).value!.results, isEmpty);
    expect(adapter.requests, isEmpty);
    await container.read(placeSearchProvider.notifier).searchOnline();
    expect(adapter.requests, isEmpty, reason: 'there is no query to send');
  });

  test('a keystroke supersedes the search before it', () async {
    final container = await containerFor();
    final notifier = container.read(placeSearchProvider.notifier)
      ..query('schaan')
      ..query('vaduz');
    await settle();

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
    await settle();
    expect(adapter.requests, hasLength(1));

    notifier.query('munchen');
    await settle();

    expect(adapter.requests, hasLength(2));
    expect(adapter.lastUri.queryParameters['q'], 'munchen');
  });

  test('clear empties the list and forgets the query', () async {
    final container = await containerFor();
    final notifier = container.read(placeSearchProvider.notifier)
      ..query('vaduz');
    await settle();
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
    await settle();

    expect(container.read(placeSearchProvider).hasError, isTrue);
  });
}

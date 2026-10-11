// Offline place search: download the region's tile, then find a place in the
// gazetteer that came with it, with the geocoder wired to a socket that fails
// every request.
//
//   flutter test integration_test/offline_search_test.dart -d emulator-5554 \
//     --dart-define=VELORKI_BROUTER_URL= \
//     --dart-define=VELORKI_SEGMENTS_URL=http://10.0.2.2:8000 \
//     --dart-define=VELORKI_API_URL=
//
// The mirror has to serve `<TILE>.gaz` next to `<TILE>.rd5` and name it in
// `manifest.json`; without that the tile arrives without a search index and
// the test says so rather than quietly passing.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:velorki/core/permissions/location_permission.dart';
import 'package:velorki/features/map/data/map_preferences.dart';
import 'package:velorki/features/map/data/position_provider.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/routing_tiles/data/routing_tiles_repository.dart';
import 'package:velorki/features/search/data/gazetteer_store.dart';
import 'package:velorki/features/search/data/photon_client.dart';
import 'package:velorki/features/search/presentation/search_field.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/fakes.dart';
import 'support/harness.dart';
import 'support/region.dart';
import 'support/tiles.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('finds a place in the downloaded region without a network', (
    tester,
  ) async {
    final photon = FailingHttpAdapter();
    final container = await pumpApp(
      tester,
      overrides: [
        photonClientProvider.overrideWithValue(
          PhotonClient(
            'https://photon.itest',
            dio: Dio()..httpClientAdapter = photon,
          ),
        ),
        locationPermissionGatewayProvider.overrideWithValue(
          const GrantedLocationPermission(),
        ),
        positionSourceProvider.overrideWithValue(
          FixedPositionSource(region.start),
        ),
        // The search answers from the device only for the area under the map
        // centre, so the map opens over the region rather than at the default
        // view of central Europe.
        lastMapCameraProvider.overrideWith(_RegionCamera.new),
      ],
    );
    await ensureRegionTile(tester, container);

    // The gazetteer travels with the tile.
    final tile = TileName.parse(region.tile);
    final repository = await container.read(
      routingTilesRepositoryProvider.future,
    );
    final gazetteer = repository.gazetteerFileFor(tile);
    expect(
      gazetteer.existsSync(),
      isTrue,
      reason:
          'the mirror has to offer ${tile.gazetteerFileName} in its manifest',
    );

    final store = await container.read(gazetteerStoreProvider.future);
    await store.refresh();
    expect(store.hasTiles, isTrue, reason: 'the gazetteer has to be readable');

    // The device's own SQLite runs the second look too: the place with two
    // letters swapped is still found, through the index's vocabulary.
    final name = region.localSearchPlace;
    final swapped =
        '${name.substring(0, 4)}${name[5]}${name[4]}'
        '${name.substring(6)}';
    final mistyped = await store.lookup(swapped, near: region.start);
    expect(
      mistyped.results.map((r) => r.name),
      contains(name),
      reason: '"$swapped" on the device',
    );

    // The app's store searches on a worker isolate: a burst of keystrokes
    // all settle and the last one is answered, a ride is named and a route
    // is matched against places in between, all off the UI isolate.
    expect(store.workerStarted, isTrue, reason: 'the app searches off-thread');
    final typing = <Future<GazetteerSearch>>[
      for (var i = 3; i <= name.length; i++)
        store.lookup(name.substring(0, i), near: region.start),
    ];
    final named = store.nearestSettlement(region.start, maxKm: 20);
    final around = store.inBox(
      BoundingBox(
        south: region.start.lat - 0.1,
        west: region.start.lon - 0.1,
        north: region.start.lat + 0.1,
        east: region.start.lon + 0.1,
      ),
      placeKinds: const <String>['city', 'town', 'village', 'suburb'],
    );
    final typed = await Future.wait(typing);
    expect(typed.last.results.map((r) => r.name), contains(name));
    expect(await named, isNotNull, reason: 'a ride from here gets a name');
    expect(await around, isNotEmpty, reason: 'places around the start');

    // Type into the real field; the debounce and the store do the rest.
    final field = find.descendant(
      of: find.byType(SearchField),
      matching: find.byType(TextField),
    );
    await waitForWidget(tester, field);
    await tester.enterText(field, region.localSearchText);
    await pumpFor(tester, const Duration(milliseconds: 800));

    final row = find.widgetWithText(ListTile, region.localSearchPlace);
    await waitForWidget(tester, row);
    expect(
      photon.requests,
      isEmpty,
      reason: 'the result came off the device, nothing was asked of Photon',
    );
    expect(
      find.descendant(
        of: row,
        matching: find.byIcon(Icons.location_city_outlined),
      ),
      findsOneWidget,
      reason: 'a settlement from the gazetteer',
    );
    // Photon is still one tap away, as the last row.
    expect(find.byIcon(Icons.travel_explore_outlined), findsOneWidget);

    await tapAndPump(tester, row);

    // With an empty plan the place's card makes it the destination of a ride
    // from the rider's position, exactly as the online search test does it.
    await tapAndPump(tester, find.widgetWithText(FilledButton, 'Route here'));

    await waitUntil(
      tester,
      () => container.read(plannerControllerProvider).waypoints.length == 2,
      describe: 'the two waypoints of the offline search',
      onTimeout: () => '${container.read(plannerControllerProvider)}',
    );

    final state = container.read(plannerControllerProvider);
    expect(state.waypoints.first.pos, region.start);
    expect(state.waypoints.last.name, region.localSearchPlace);
    expect(photon.requests, isEmpty);
    debugPrint(
      'VELORKI_OFFLINE_SEARCH ${region.localSearchPlace} at '
      '${state.waypoints.last.pos} from ${gazetteer.path}',
    );
    await screenshot(tester, 'offline-search');

    await unmountApp(tester);
  });
}

/// The camera the app starts at: the region's tile, which is the one whose
/// gazetteer this test downloads.
class _RegionCamera extends LastMapCamera {
  @override
  MapCamera build() => MapCamera(center: region.start, zoom: 12);
}

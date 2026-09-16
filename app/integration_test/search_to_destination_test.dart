// Search for a place, start the ride from the current position, and get a
// routed two-waypoint plan out of the on-device engine.
//
//   flutter test integration_test/search_to_destination_test.dart \
//     -d emulator-5554 --dart-define=VELORKI_BROUTER_URL= \
//     --dart-define=VELORKI_SEGMENTS_URL=http://10.0.2.2:8000 \
//     --dart-define=VELORKI_API_URL=
//
// The geocoder is scripted rather than live. Photon's public instance is a
// third-party service with its own rate limits and outages, and a suite that
// goes red because komoot's server is busy says nothing about Velorki. Only
// the socket is replaced: the real SearchField, the real debounce, the real
// PhotonClient, its URL builder and its GeoJSON parser all run, and the
// result is picked by tapping the row the app drew. Everything downstream —
// the position, the routing, the chip — is the real device.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:velorki/core/permissions/location_permission.dart';
import 'package:velorki/features/map/data/position_provider.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/routing_tiles/presentation/routing_source_chip.dart';
import 'package:velorki/features/search/data/gazetteer_store.dart';
import 'package:velorki/features/search/data/photon_client.dart';
import 'package:velorki/features/search/presentation/search_field.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

import 'support/fakes.dart';
import 'support/harness.dart';
import 'support/region.dart';
import 'support/tiles.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('searches a place and routes to it from the current position', (
    tester,
  ) async {
    final photon = CannedHttpAdapter(
      photonAnswer(
        name: region.searchPlace,
        position: region.searchResult,
        city: region.searchCity,
      ),
    );
    final container = await pumpApp(
      tester,
      overrides: [
        photonClientProvider.overrideWithValue(
          PhotonClient(
            'https://photon.itest',
            dio: Dio()..httpClientAdapter = photon,
          ),
        ),
        // This is the online path. The suite runs its files on one install,
        // so a gazetteer left behind by offline_search_test would answer the
        // search itself and Photon would never be asked.
        gazetteerStoreProvider.overrideWith(
          (ref) async => GazetteerStore(null),
        ),
        locationPermissionGatewayProvider.overrideWithValue(
          const GrantedLocationPermission(),
        ),
        positionSourceProvider.overrideWithValue(
          FixedPositionSource(region.start),
        ),
      ],
    );
    await ensureRegionTile(tester, container);

    // Type into the real field and wait out searchDebounce.
    final field = find.descendant(
      of: find.byType(SearchField),
      matching: find.byType(TextField),
    );
    await waitForWidget(tester, field);
    await tester.enterText(field, region.searchQuery);
    await pumpFor(tester, const Duration(milliseconds: 800));

    final row = find.widgetWithText(ListTile, region.searchPlace);
    await waitForWidget(tester, row);
    expect(
      photon.requests.single.queryParameters['q'],
      region.searchQuery,
      reason: 'the real PhotonClient built the request',
    );
    await tapAndPump(tester, row);

    // With an empty plan the screen offers to start from the rider instead of
    // from the place, which is the two-waypoint case this test is after.
    await tapAndPump(
      tester,
      find.widgetWithText(FilledButton, 'From my position'),
    );

    await waitUntil(
      tester,
      () {
        final state = container.read(plannerControllerProvider);
        if (state.route.hasError) fail('routing failed: ${state.route.error}');
        if (state.error != null) fail('planner error: ${state.error}');
        return state.result != null && !state.isRouting;
      },
      describe: 'the route from the current position to the searched place',
      timeout: const Duration(seconds: 60),
      onTimeout: () => '${container.read(plannerControllerProvider)}',
    );

    final state = container.read(plannerControllerProvider);
    final result = state.result!;
    debugPrint(
      'VELORKI_SEARCH_ROUTE source=${state.routingSource} '
      'length=${result.lengthM.round()}m points=${result.geometry.length}',
    );

    expect(state.waypoints, hasLength(2));
    expect(state.waypoints.first.pos, region.start);
    expect(state.waypoints.last.pos, region.searchResult);
    expect(state.waypoints.last.name, region.searchPlace);
    expect(result.lengthM, greaterThan(0));
    expect(result.geometry, isNotEmpty);
    expect(state.routingSource, RoutingSource.local);

    // The chip that says the route came off the device, in the sheet.
    await dragSheetUp(tester);
    await waitForWidget(tester, find.byType(RoutingSourceChip));
    expect(find.text('ON DEVICE'), findsOneWidget);
    await screenshot(tester, 'search-to-destination');

    await unmountApp(tester);
  });
}

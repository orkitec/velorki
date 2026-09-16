// On-device check for the routing port: download one tile from a segments
// mirror, then plan a route with no routing server configured, so the
// composite backend must route locally.
//
//   python3 -m http.server 8000   # in a dir with W20_N30.rd5 + manifest.json
//   flutter test integration_test/on_device_route_test.dart -d emulator-5554 \
//     --dart-define=VELORKI_SEGMENTS_URL=http://10.0.2.2:8000 \
//     --dart-define=VELORKI_BROUTER_URL= --dart-define=VELORKI_API_URL=
//
// The tile and the two points are Madeira's whatever VELORKI_ITEST_REGION
// says, because this is the port's own check and the numbers it asserts were
// measured on that tile. Everything else in the suite follows the region.
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/routing_tiles/application/tile_download_controller.dart';
import 'package:velorki/features/routing_tiles/data/routing_tiles_repository.dart';
import 'package:velorki/features/routing_tiles/data/segments_manifest_service.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('downloads a tile and routes on the device', (tester) async {
    final container = await pumpApp(tester);

    final tile = TileName.parse('W20_N30');
    final repository = await container.read(
      routingTilesRepositoryProvider.future,
    );
    if (!repository.readyTiles().contains(tile)) {
      final manifest = await container.read(
        segmentsManifestSourceProvider.future,
      );
      final entry = manifest.byTile[tile];
      expect(entry, isNotNull, reason: 'mirror manifest lacks $tile');
      await container.read(tileDownloadQueueProvider.notifier).enqueue([
        entry!,
      ]);
      final downloadClock = Stopwatch()..start();
      await waitUntil(
        tester,
        () => repository.readyTiles().contains(tile),
        describe: 'the $tile tile to download',
        timeout: const Duration(minutes: 3),
      );
      debugPrint(
        'VELORKI_TILE downloaded in ${downloadClock.elapsedMilliseconds}ms',
      );
    }
    // Let the backend provider rebuild with the new tile.
    await pumpFor(tester, const Duration(seconds: 2));

    final planner = container.read(plannerControllerProvider.notifier);
    planner
      ..addWaypoint(const LatLng(32.650, -16.920)) // Funchal
      ..addWaypoint(const LatLng(32.720, -16.770)); // Machico
    final stopwatch = Stopwatch()..start();
    await waitUntil(
      tester,
      () {
        final state = container.read(plannerControllerProvider);
        if (state.route.hasError) fail('routing failed: ${state.route.error}');
        return state.result != null && !state.isRouting;
      },
      describe: 'a route off the on-device engine',
      timeout: const Duration(seconds: 60),
      onTimeout: () => '${container.read(plannerControllerProvider)}',
    );

    final state = container.read(plannerControllerProvider);
    final result = state.result!;
    debugPrint(
      'VELORKI_LOCAL_ROUTE source=${state.routingSource} '
      'length=${result.lengthM.round()}m ascent=${result.ascentM.round()}m '
      'points=${result.geometry.length} elapsed=${stopwatch.elapsedMilliseconds}ms',
    );
    expect(state.routingSource, RoutingSource.local);
    expect(result.lengthM, greaterThan(20000));
    expect(result.lengthM, lessThan(35000));

    await unmountApp(tester);
  });
}

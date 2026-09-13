/// Getting the region's rd5 routing tile onto the device.
///
/// Every planning test routes with no BRouter server configured, so the
/// composite backend has to answer locally, which it can only do once the tile
/// under the coordinates is downloaded. The tile survives between runs, so on
/// a warm emulator this is a no-op; on a cold one (and in CI) it pulls the
/// tile from the mirror at `VELORKI_SEGMENTS_URL`.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/routing_tiles/application/tile_download_controller.dart';
import 'package:velorki/features/routing_tiles/data/routing_tiles_repository.dart';
import 'package:velorki/features/routing_tiles/data/segments_manifest_service.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

import 'harness.dart';
import 'region.dart';

/// Downloads [region]'s tile unless it is already on the device.
Future<void> ensureRegionTile(
  WidgetTester tester,
  ProviderContainer container, {
  Duration timeout = const Duration(minutes: 5),
}) async {
  final tile = TileName.parse(region.tile);
  final repository = await container.read(
    routingTilesRepositoryProvider.future,
  );
  if (!repository.readyTiles().contains(tile)) {
    final manifest = await container.read(
      segmentsManifestSourceProvider.future,
    );
    final entry = manifest.byTile[tile];
    expect(
      entry,
      isNotNull,
      reason: 'the mirror manifest lacks ${region.tile}',
    );
    await container.read(tileDownloadQueueProvider.notifier).enqueue([entry!]);
    final clock = Stopwatch()..start();
    await waitUntil(
      tester,
      () => repository.readyTiles().contains(tile),
      describe: 'the ${region.tile} tile to download',
      timeout: timeout,
    );
    debugPrint('VELORKI_TILE ${region.tile} in ${clock.elapsedMilliseconds}ms');
  }
  // Let the routing backend provider rebuild around the new tile.
  await pumpFor(tester, const Duration(seconds: 2));
}

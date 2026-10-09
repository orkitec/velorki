import 'dart:async';

import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:velorki_cycle_map/velorki_cycle_map.dart';

import '../../routing_tiles/data/on_device_routing.dart';

part 'cycle_map_worker_provider.g.dart';

/// The one cycle map worker of the app, over the routing tiles on the
/// phone. Spawned the first time a map asks for a cycle map, and kept: its
/// caches are what make the second look at an area instant.
///
/// The decoded cells are kept in the cache directory, which the system may
/// empty; they are decoded again then.
@Riverpod(keepAlive: true)
Future<CycleMapWorker> cycleMapWorker(Ref ref) async {
  final (segmentsDir, profilesDir) = await ref.watch(
    onDeviceRoutingProvider.selectAsync(
      (setup) => (setup.segmentsDir, setup.profilesDir),
    ),
  );
  final cache = await getApplicationCacheDirectory();
  final worker = await CycleMapWorker.spawn(
    segmentsDir: segmentsDir,
    lookupsPath: '$profilesDir/lookups.dat',
    cacheDir: '${cache.path}/cycle_map/cells',
    outputDir: '${cache.path}/cycle_map/out',
  );
  ref.onDispose(worker.dispose);
  return worker;
}

/// A [CycleMapRenderer] standing in for the worker until it is spawned,
/// so a map can be bound to the cycle map before anyone asked for one.
class LazyCycleMapRenderer implements CycleMapRenderer {
  /// Hands the requests to the worker [worker] gives.
  LazyCycleMapRenderer(this._worker);

  final Future<CycleMapRenderer> Function() _worker;
  CycleMapRenderer? _ready;

  @override
  Future<CycleMapFile?> render(
    CycleMapRequest request, {
    Object client = 0,
  }) async {
    final worker = _ready ??= await _worker();
    return worker.render(request, client: client);
  }

  @override
  void release(Object client) => _ready?.release(client);

  @override
  void tilesChanged() => _ready?.tilesChanged();
}

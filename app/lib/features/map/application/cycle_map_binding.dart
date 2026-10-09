import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:velorki_brouter/velorki_brouter.dart' show TileName;
import 'package:velorki_geo/velorki_geo.dart';

import '../../routing_tiles/data/on_device_routing.dart';
import '../data/cycle_map_worker_provider.dart';
import '../data/map_preferences.dart';
import '../domain/map_controller.dart';
import 'cycle_map_driver.dart';

part 'cycle_map_binding.g.dart';

/// Whether the shell's map shows the cycle map over an area that is not
/// downloaded: the planner offers the download then.
@Riverpod(keepAlive: true)
class SharedCycleMapNeedsDownload extends _$SharedCycleMapNeedsDownload {
  @override
  bool build() => false;

  /// Sets it; the shell's map host does.
  void set(bool value) => state = value;
}

/// Puts the offline cycle map on a map host's map as the settings say: one
/// [CycleMapDriver] per host, attached to whatever map the host has now,
/// fed the settings and the downloaded tiles.
///
/// A host makes one in `initState`, calls [listen] from `build`, [attach]
/// with each map it is handed and [dispose] when it goes.
class CycleMapBinding {
  /// A binding reading providers through [ref].
  CycleMapBinding(this._ref)
    : driver = CycleMapDriver(
        renderer: LazyCycleMapRenderer(
          () => _ref.read(cycleMapWorkerProvider.future),
        ),
        covers: _coversOf(null),
      ) {
    driver.configure(_ref.read(cycleMapPreferencesProvider));
  }

  final WidgetRef _ref;

  /// The driver, whose `needsDownload` a screen can show.
  final CycleMapDriver driver;

  /// Draws on [map] from now on: a new map, or the same after a style
  /// reload.
  void attach(MapController map) => driver.attach(map);

  /// Follows the settings, and while the cycle map is on the tiles; call
  /// from the host's `build`. The tiles are not asked for before: their
  /// table is read from the database, which a map without a cycle map has
  /// no reason to wait on.
  void listen() {
    _ref.listen(
      cycleMapPreferencesProvider,
      (_, next) => driver.configure(next),
    );
    final shown = _ref.watch(
      cycleMapPreferencesProvider.select((s) => s.shown),
    );
    if (!shown) {
      _tilesSubscription?.close();
      _tilesSubscription = null;
      return;
    }
    // Out of the build: a new answer goes on to the driver, which may
    // write the hint's provider.
    _tilesSubscription ??= _ref.listenManual(
      onDeviceRoutingProvider,
      (_, next) => scheduleMicrotask(() {
        final now = _tilesOf(next);
        if (now == null || setEquals(now, _tiles)) return;
        _tiles = now;
        driver.tilesChanged(_coversOf(now));
      }),
      fireImmediately: true,
    );
  }

  ProviderSubscription<AsyncValue<OnDeviceRouting>>? _tilesSubscription;
  Set<TileName>? _tiles;

  /// Stops for good.
  void dispose() {
    _tilesSubscription?.close();
    driver.dispose();
  }

  static Set<TileName>? _tilesOf(AsyncValue<OnDeviceRouting>? setup) =>
      setup?.value?.readyTiles;

  /// Whether a point lies in one of [tiles]; anywhere while they are not
  /// known yet, so no hint shows before the tile table has been read.
  static bool Function(LatLng point) _coversOf(Set<TileName>? tiles) =>
      tiles == null
      ? (_) => true
      : (point) => tiles.any((tile) => tile.contains(point));
}

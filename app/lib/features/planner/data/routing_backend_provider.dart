import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

import '../../../app/app_config.dart';
import '../../routing_tiles/data/on_device_routing.dart';
import '../../routing_tiles/data/routing_preference_controller.dart';
import '../../routing_tiles/domain/routing_preference.dart';

part 'routing_backend_provider.g.dart';

/// The routing backend the planner, the loop planner and the assistant talk
/// to, or `null` when nothing can route.
///
/// It is a [CompositeRoutingBackend] over up to two backends:
///
/// * [LocalRoutingBackend] over the downloaded rd5 tiles, as soon as the
///   bundled profiles are copied and either a tile is ready, a tile mirror
///   (`VELORKI_SEGMENTS_URL`) is configured, or the rider chose
///   [RoutingPreference.onDeviceOnly] — in the latter two cases even with no
///   tile at all, so a route fails with `missingTiles` and the planner can
///   offer the download instead of claiming there is no routing server;
/// * [BRouterHttpBackend] against `VELORKI_BROUTER_URL`, unless the rider
///   chose [RoutingPreference.onDeviceOnly].
///
/// Which of the two answers a given query is the plan's rule, and lives in
/// `velorki_brouter`: on-device when every tile the route's expanded bounding
/// box touches is downloaded, the server otherwise, never a partial local
/// coverage.
///
/// `null` is a normal state, not an error: a fork can ship without a routing
/// server and without tiles, and the planner then says so. Override this
/// provider in tests with a fake backend.
@Riverpod(keepAlive: true)
RoutingBackend? routingBackend(Ref ref) {
  final config = ref.watch(effectiveConfigProvider);
  final preference = ref.watch(routingPreferenceSettingProvider);

  final onDevice = preference.allowsLocal
      ? ref.watch(onDeviceRoutingProvider).value
      : null;
  // A tile mirror makes the local path worth offering even before the first
  // download: the composite then reports the missing tiles and the planner
  // offers to fetch them, instead of claiming there is no routing server.
  final canDownload = config.segmentsUrl.isNotEmpty;
  LocalRoutingBackend? local;
  if (onDevice != null &&
      (onDevice.hasTiles ||
          canDownload ||
          preference == RoutingPreference.onDeviceOnly)) {
    final backend = LocalRoutingBackend(
      segmentsDir: onDevice.segmentsDir,
      profilesDir: onDevice.profilesDir,
    );
    ref.onDispose(() => unawaited(backend.dispose()));
    local = backend;
  }

  BRouterHttpBackend? remote;
  if (preference.allowsRemote && config.brouterUrl.isNotEmpty) {
    final backend = BRouterHttpBackend(config.brouterUrl);
    ref.onDispose(backend.close);
    remote = backend;
  }

  if (local == null && remote == null) return null;
  return CompositeRoutingBackend(
    local: local,
    remote: remote,
    localTiles: () => onDevice?.readyTiles ?? const <TileName>{},
    localFormatVersions: onDevice?.formatVersions,
    // No format check yet: nothing in the app knows which rd5 version this
    // build of brouter_dart can read, so refusing a tile on a version string
    // would only ever refuse a good one. The version is recorded per tile so
    // the check can be switched on in R5.
  );
}

/// Whether routes may be computed on the device right now.
///
/// The loop sheet says so, because on-device candidates run one after another
/// rather than three at a time.
@Riverpod(keepAlive: true)
bool onDeviceRoutingActive(Ref ref) {
  final backend = ref.watch(routingBackendProvider);
  return backend is CompositeRoutingBackend && backend.local != null;
}

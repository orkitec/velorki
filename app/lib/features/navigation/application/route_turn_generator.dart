import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

import '../../../core/db/database.dart' show RouteSource;
import '../../../core/geo/track_turns.dart';
import '../../planner/data/route_repository.dart';
import '../../planner/data/routing_backend_provider.dart';
import '../../planner/domain/saved_route.dart';

/// The track turn finder over the app's on-device engine, the way
/// `trackSurfaceServiceProvider` is the surface matcher over it: only the
/// on-device half of the composite backend, never the server.
final trackTurnServiceProvider = Provider<TrackTurnService>((ref) {
  final backend = ref.watch(routingBackendProvider);
  final composite = backend is CompositeRoutingBackend ? backend : null;
  return TrackTurnService(
    local: composite?.local,
    decide:
        composite?.decide ??
        (q) => const RoutingDecision(
          source: null,
          requiredTiles: <TileName>[],
          missingTiles: <TileName>[],
        ),
  );
});

/// What came of asking for a route's turns.
enum RouteTurnsOutcome {
  /// The route has turns from the map now.
  created,

  /// There is no on-device routing in this build or setting.
  noRouting,

  /// The tiles for the route's area are not on the phone.
  noTiles,

  /// The router could not follow the route's line.
  unmatched,
}

/// Gives a saved route that has no turn instructions the ones the map has
/// for its line, and remembers that it did (`SavedRoute.turnsGenerated`).
///
/// One job per route at a time: the background job after an import and
/// the rider's "Create" before a ride share it.
class RouteTurnGenerator {
  /// Creates the generator; [service] is read at each job, so a tile
  /// downloaded in the meantime counts.
  RouteTurnGenerator({required this._service, required this._routes});

  final TrackTurnService Function() _service;
  final RouteRepository _routes;
  final Map<
    String,
    ({Future<RouteTurnsOutcome> done, ValueNotifier<double?> progress})
  >
  _jobs = {};

  static final ValueNotifier<double?> _idle = ValueNotifier<double?>(null);

  /// Whether [route] came from a file or a service without turns and was
  /// never given turns from the map: the routes the turns are offered for.
  /// A route planned here had its router's turns already; one without any
  /// has nothing to turn at.
  static bool needsTurns(SavedRoute route) =>
      route.source != RouteSource.planned &&
      route.source != RouteSource.loop &&
      !route.turnsGenerated &&
      lacksTurns(route.turns);

  /// The tiles [route] needs that are not on the phone: empty when all are,
  /// `null` without on-device routing.
  List<TileName>? missingTiles(SavedRoute route) =>
      _service().missingTiles(route.geometry);

  /// How far the job for the route with [id] is, 0 to 1; `null` before the
  /// first chunk is routed or without a job.
  ValueListenable<double?> progressOf(String id) =>
      _jobs[id]?.progress ?? _idle;

  /// Works out the turns of [route] and writes them to it.
  Future<RouteTurnsOutcome> generate(SavedRoute route) {
    final running = _jobs[route.id];
    if (running != null) return running.done;
    final progress = ValueNotifier<double?>(null);
    // The notifier is left to the collector rather than disposed: a dialog
    // may still be listening when the job ends.
    final done = _run(
      route,
      progress,
    ).whenComplete(() => _jobs.remove(route.id));
    _jobs[route.id] = (done: done, progress: progress);
    return done;
  }

  Future<RouteTurnsOutcome> _run(
    SavedRoute route,
    ValueNotifier<double?> progress,
  ) async {
    final result = await _service().generate(
      points: route.geometry,
      onProgress: (done, total) {
        if (total > 0) progress.value = done / total;
      },
    );
    switch (result.state) {
      case TrackTurnsState.noRouting:
        return RouteTurnsOutcome.noRouting;
      case TrackTurnsState.noTiles:
        return RouteTurnsOutcome.noTiles;
      case TrackTurnsState.unmatched:
        return RouteTurnsOutcome.unmatched;
      case TrackTurnsState.generated:
        final written = await _routes.setGeneratedTurns(
          route.id,
          result.turns,
          geometryBlob: route.geometryBlob,
        );
        if (written) return RouteTurnsOutcome.created;
        // The route changed under the job: turns of its own, or another
        // line. Either it has turns now, or these were for another line.
        final now = await _routes.routeById(route.id);
        return now != null && !needsTurns(now)
            ? RouteTurnsOutcome.created
            : RouteTurnsOutcome.unmatched;
    }
  }

  /// After an import, without asking: the turns of [route] when it has
  /// none and every tile its line needs is on the phone. Nothing is said
  /// when it fails; the rider is asked before their ride instead.
  Future<void> fillAfterImport(SavedRoute route) async {
    if (!needsTurns(route)) return;
    try {
      final missing = missingTiles(route);
      if (missing == null || missing.isNotEmpty) return;
      await generate(route);
    } on Object catch (e) {
      debugPrint('velorki: no turns for imported route ${route.id}: $e');
    }
  }
}

/// The app's turn generator.
final routeTurnGeneratorProvider = Provider<RouteTurnGenerator>(
  (ref) => RouteTurnGenerator(
    service: () => ref.read(trackTurnServiceProvider),
    routes: ref.watch(routeRepositoryProvider),
  ),
);

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

import '../../../core/geo/track_surface.dart';
import '../data/routing_backend_provider.dart';

/// The track matcher over the app's routing backend.
///
/// It lives beside the backend rather than in the feature that first needed
/// it: a ride and a route read from a file both ask the same question of the
/// same on-device engine.
///
/// Only the on-device half of the composite backend is handed over; the
/// server, when there is one, is never asked about somebody's track.
final trackSurfaceServiceProvider = Provider<TrackSurfaceService>((ref) {
  final backend = ref.watch(routingBackendProvider);
  final composite = backend is CompositeRoutingBackend ? backend : null;
  return TrackSurfaceService(
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

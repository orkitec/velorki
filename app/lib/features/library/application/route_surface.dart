import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/geo/track_surface.dart';
import '../../planner/application/track_surface_service.dart';
import '../../planner/data/route_repository.dart';

export '../../../core/geo/track_surface.dart'
    show TrackSurface, TrackSurfaceState;

/// The surface breakdown of one saved route: the router's own when the route
/// was planned here, otherwise its track matched against the routing tiles
/// and the answer kept.
///
/// A route read from a file never went through the router, so nothing ever
/// told it what it is paved with. Its track is matched the way a ride's is,
/// by the same service, and written back to the route's own column, so the
/// work happens once per route rather than once per look.
///
/// A route the map could not follow is written back too, as a marker, so it
/// is not routed again on every open; the marker goes when a new tile is
/// downloaded. A route whose area has no tiles is not written at all, so it
/// is matched as soon as they are there. Rebuilds when the tiles change,
/// since the backend does.
final routeSurfaceProvider = FutureProvider.family<TrackSurface, String>((
  ref,
  routeId,
) async {
  final repository = ref.watch(routeRepositoryProvider);
  final service = ref.watch(trackSurfaceServiceProvider);
  // Read once, not watched: this provider writes the answer back to the
  // very row it would be watching, and a watch would set it running
  // again on its own write — and on every unrelated edit to the route.
  final route = await repository.routeById(routeId);
  if (route == null) return TrackSurface.unmatched;

  final stats = route.surfaceStats;
  if (stats != null) return TrackSurface.matched(stats);
  if (route.surfaceUnavailable) return TrackSurface.unmatched;

  final outcome = await service.match(
    points: route.geometry,
    distanceM: route.distanceM,
  );
  switch (outcome.state) {
    case TrackSurfaceState.matched:
      await repository.setSurfaceStats(routeId, outcome.stats);
    case TrackSurfaceState.unmatched:
      await repository.setSurfaceStats(routeId, null);
    case TrackSurfaceState.noRouting:
    case TrackSurfaceState.noTiles:
      break;
  }
  return outcome;
});

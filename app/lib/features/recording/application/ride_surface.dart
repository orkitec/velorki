import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/geo/track_surface.dart';
import '../../planner/application/track_surface_service.dart';
import '../data/ride_repository.dart';
import '../domain/ride.dart';

export '../../../core/geo/track_surface.dart'
    show TrackSurface, TrackSurfaceState;

/// The surface breakdown of a recorded ride.
///
/// The matching itself is not here: a ride and a route read from a file have
/// the same problem and are answered by the same `TrackSurfaceService` under
/// `core/geo`. This is the ride's half — which ride, and where the answer is
/// kept.

/// The surface breakdown of [ride], or `null` when it cannot be had.
extension RideSurfaceMatching on TrackSurfaceService {
  /// Matches [ride] and says what came of it.
  Future<TrackSurface> matchRide(Ride ride) =>
      match(points: ride.points, distanceM: ride.stats.distanceM);
}

/// The surface breakdown of one ride: from the row when it was matched
/// before, otherwise matched now and written back.
///
/// A ride the map could not follow is written back too, as a marker, so it
/// is not routed again on every open; the marker goes when a new tile is
/// downloaded. A ride whose area has no tiles is not written at all, so it is
/// matched as soon as they are there. Rebuilds when the tiles change, since
/// the backend does.
final rideSurfaceProvider = FutureProvider.autoDispose
    .family<TrackSurface, String>((ref, rideId) async {
      final repository = ref.watch(rideRepositoryProvider);
      final service = ref.watch(trackSurfaceServiceProvider);
      final ride = await ref.watch(rideProvider(rideId).future);
      if (ride == null) return TrackSurface.unmatched;

      final cached = ride.surface;
      if (cached != null) {
        final stats = cached.stats;
        if (stats != null) return TrackSurface.matched(stats);
        if (cached.unavailable) return TrackSurface.unmatched;
      }

      final outcome = await service.matchRide(ride);
      switch (outcome.state) {
        case TrackSurfaceState.matched:
          await repository.setSurface(rideId, outcome.stats!);
        case TrackSurfaceState.unmatched:
          await repository.markSurfaceUnavailable(rideId);
        case TrackSurfaceState.noRouting:
        case TrackSurfaceState.noTiles:
          break;
      }
      return outcome;
    });

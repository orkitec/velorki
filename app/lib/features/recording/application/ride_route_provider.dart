import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../planner/data/route_repository.dart';
import '../../planner/domain/saved_route.dart';
import '../data/ride_repository.dart';

/// The route the ride [rideId] followed: `null` for a ride that followed
/// none, and for one whose route has since been deleted.
final rideRouteProvider = FutureProvider.autoDispose
    .family<SavedRoute?, String>((ref, rideId) async {
      final ride = await ref.watch(rideProvider(rideId).future);
      final routeId = ride?.routeId;
      if (routeId == null) return null;
      return ref.watch(savedRouteProvider(routeId).future);
    });

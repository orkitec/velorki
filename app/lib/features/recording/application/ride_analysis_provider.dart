import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/geo/ride_analysis.dart';
import '../../../core/units/units.dart';
import '../data/ride_repository.dart';
import '../domain/ride.dart';

/// What the analysis is asked for: which ride, and how long a split is.
///
/// The split length is part of the key because a rider who switches to miles
/// wants mile splits, and the two sets can sit side by side in the cache.
typedef RideAnalysisRequest = ({String rideId, double splitLengthM});

/// A kilometre or a mile, whichever [system] counts in.
double splitLengthFor(UnitSystem system) =>
    system == UnitSystem.imperial ? metersPerMile : metersPerKilometer;

/// The splits, chart samples and speed bands of one ride.
///
/// Computed once per ride and kept, rather than on every build: a three hour
/// ride is ten thousand fixes, and the ride page rebuilds on every scroll.
final rideAnalysisProvider = FutureProvider.autoDispose
    .family<RideAnalysis, RideAnalysisRequest>((ref, request) async {
      final ride = await ref.watch(rideProvider(request.rideId).future);
      if (ride == null) return RideAnalysis.empty;
      return analyseRide(
        ride.points,
        splitLengthM: request.splitLengthM,
        breaks: statsBreaksOf(ride.pauses),
      );
    });

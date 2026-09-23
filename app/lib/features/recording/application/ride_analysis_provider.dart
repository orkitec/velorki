import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/geo/power_model.dart';
import '../../../core/geo/ride_analysis.dart';
import '../../../core/units/units.dart';
import '../data/ride_repository.dart';
import '../domain/ride.dart';
import '../domain/split_length.dart';

/// What the analysis is asked for: which ride, how long a split is and in
/// which units.
///
/// The choice and the units are part of the key because a rider who switches
/// to miles wants mile splits, and the two sets can sit side by side in the
/// cache. The maximum heart rate cuts the zones; `null` when the rider has
/// not switched them on, so the key does not change with a profile nobody
/// reads. The threshold power cuts the power zones the same way, and the
/// power model, likewise, is `null` unless the power estimate is on and the
/// rider's weight is known.
typedef RideAnalysisRequest = ({
  String rideId,
  SplitLength splitLength,
  UnitSystem system,
  int? maxHeartRateBpm,
  int? thresholdPowerW,
  PowerModel? powerModel,
});

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
        splitLengthM: splitLengthMetres(
          request.splitLength,
          request.system,
          ride.stats.distanceM,
        ),
        breaks: statsBreaksOf(ride.pauses),
        // A ride from a device with laps is cut where the device cut it.
        lapEndsM: lapEndsAlong(ride.points, [
          for (final lap in ride.laps) lap.endedAt,
        ]),
        temperaturesC: ride.temperaturesC,
        maxHeartRateBpm: request.maxHeartRateBpm,
        thresholdPowerW: request.thresholdPowerW,
        powerModel: request.powerModel,
      );
    });

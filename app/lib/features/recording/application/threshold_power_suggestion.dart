import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/geo/ride_analysis.dart';
import '../data/ride_repository.dart';
import '../domain/ride.dart';

/// The share of the best twenty minutes a threshold power is taken as: what
/// the helper under the field tells a rider to do with a 20-minute test.
const double thresholdPowerShare = 0.95;

/// The step the suggestion is rounded to, in watts.
const int thresholdPowerStepW = 5;

/// A threshold power from the best twenty minutes of every ride,
/// [bestTwentyMinutes]: the highest of them times [thresholdPowerShare],
/// rounded to the nearest [thresholdPowerStepW]. `null` when no ride had
/// twenty minutes of power in it.
int? suggestThresholdPower(Iterable<int?> bestTwentyMinutes) {
  int? best;
  for (final watts in bestTwentyMinutes) {
    if (watts != null && (best == null || watts > best)) best = watts;
  }
  if (best == null) return null;
  final scaled = best * thresholdPowerShare;
  return (scaled / thresholdPowerStepW).round() * thresholdPowerStepW;
}

/// The threshold power the rider's own rides suggest, or `null` without a
/// saved ride that carries twenty minutes of a power meter.
///
/// Walks every ride with a meter once, the same analysis the ride page runs,
/// so it is only watched where the figure is offered: the Rider section with
/// the power zones on.
final thresholdPowerSuggestionProvider = FutureProvider.autoDispose<int?>((
  ref,
) async {
  final rides = await ref.watch(ridesProvider.future);
  return suggestThresholdPower(<int?>[
    for (final ride in rides)
      if (ride.stats.avgPowerW != null)
        analyseRide(
          ride.points,
          breaks: statsBreaksOf(ride.pauses),
        ).effort.bestTwentyMinutePowerW,
  ]);
});

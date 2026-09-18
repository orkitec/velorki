import 'package:velorki_geo/velorki_geo.dart';

import '../../../l10n/generated/app_localizations.dart';

/// How close the end of a ride has to be to its start for the ride to be a
/// loop rather than a journey from one place to another.
///
/// A kilometre: far enough that parking the bike a few streets from where it
/// was fetched is still "a loop from Funchal", close enough that the next
/// village over is a destination.
const double rideLoopMeters = 1000;

/// The part of the day a ride is named after, in Strava's buckets.
enum RideTimeOfDay {
  /// 04:00–10:59.
  morning,

  /// 11:00–13:59.
  lunch,

  /// 14:00–16:59.
  afternoon,

  /// 17:00–20:59.
  evening,

  /// 21:00–03:59.
  night;

  /// The word this part of the day is called in the rider's language.
  ///
  /// German glues it onto the rest of the name ("Morgen" + "runde"), so the
  /// word is a separate message from the patterns that use it.
  String label(AppLocalizations l10n) => switch (this) {
    RideTimeOfDay.morning => l10n.rideTimeMorning,
    RideTimeOfDay.lunch => l10n.rideTimeLunch,
    RideTimeOfDay.afternoon => l10n.rideTimeAfternoon,
    RideTimeOfDay.evening => l10n.rideTimeEvening,
    RideTimeOfDay.night => l10n.rideTimeNight,
  };
}

/// Which bucket the local wall-clock time [start] falls into.
RideTimeOfDay rideTimeOfDay(DateTime start) => switch (start.hour) {
  >= 4 && < 11 => RideTimeOfDay.morning,
  >= 11 && < 14 => RideTimeOfDay.lunch,
  >= 14 && < 17 => RideTimeOfDay.afternoon,
  >= 17 && < 21 => RideTimeOfDay.evening,
  _ => RideTimeOfDay.night,
};

/// Whether a ride that ran from [start] to [end] came back to where it began.
///
/// Unknown ends are not loops: a ride nobody could measure is simply a ride.
bool isRideLoop(LatLng? start, LatLng? end) =>
    start != null &&
    end != null &&
    haversineMeters(start, end) <= rideLoopMeters;

/// What a finished ride is called until the rider renames it.
///
/// Following a saved route, the route's own name is the answer — the rider
/// already named this ride when they planned it. Otherwise the name is the
/// part of the day the ride started in plus what is known about where it went:
///
/// * back where it started, near a known place → "Morning loop from Funchal"
/// * between two known places → "Morning ride from Funchal to Monte"
/// * only the start known → "Morning ride from Funchal"
/// * nothing known → "Morning loop" or "Morning ride"
///
/// [startedAt] is the ride's start in the rider's own time zone, not UTC: a
/// ride is named after the clock on the wall the rider set off under.
/// [isLoop] comes from [isRideLoop]; [startPlace] and [endPlace] from the
/// offline gazetteer, and are `null` wherever it has nothing to say.
String defaultRideName(
  AppLocalizations l10n, {
  required DateTime startedAt,
  String? routeName,
  String? startPlace,
  String? endPlace,
  bool isLoop = false,
}) {
  final route = routeName?.trim();
  if (route != null && route.isNotEmpty) return route;

  final time = rideTimeOfDay(startedAt).label(l10n);
  final start = _clean(startPlace);
  final end = _clean(endPlace);
  if (start == null) {
    return isLoop ? l10n.rideNameLoop(time) : l10n.rideNameRide(time);
  }
  if (isLoop) return l10n.rideNameLoopFrom(time, start);
  // Two names for the same place read as a mistake ("from Funchal to
  // Funchal"), so a ride that wandered back into the town it left is named
  // after that town once.
  if (end == null || end == start) return l10n.rideNameFrom(time, start);
  return l10n.rideNameFromTo(time, start, end);
}

String? _clean(String? name) {
  final trimmed = name?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

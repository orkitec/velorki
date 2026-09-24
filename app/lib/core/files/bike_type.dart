/// The bike a file is for, read from what the file calls itself and written
/// back on export.
///
/// GPX has no standard field for it, only a free `<type>` on the track or
/// the route; FIT has the sport and its sub-sport. A file that names no bike
/// the planner has a profile for — `cycling`, a number, nothing — reads as
/// `null`, and the route then opens with whatever the rider rode last.
library;

import 'package:velorki_fit/velorki_fit.dart';

import '../../features/planner/domain/route_profile.dart';

/// The words of a GPX `<type>` for each profile, looked for in this order,
/// so `gravel road` is gravel and `mountain touring` a mountain bike.
const List<(RouteProfile, Set<String>)> _gpxWords = [
  (RouteProfile.mtb, {'mountain', 'mtb', 'enduro', 'downhill'}),
  (RouteProfile.gravel, {'gravel', 'cyclocross'}),
  (RouteProfile.fastbike, {'road', 'roadbike', 'racing', 'rennrad'}),
  (RouteProfile.trekking, {'touring', 'trekking', 'bikepacking'}),
];

/// The profile a GPX `<type>` names, or `null` when it names none.
RouteProfile? profileFromGpxType(String? type) {
  if (type == null) return null;
  final words = type
      .toLowerCase()
      .split(RegExp('[^a-z]+'))
      .where((w) => w.isNotEmpty)
      .toSet();
  for (final (profile, known) in _gpxWords) {
    if (words.any(known.contains)) return profile;
  }
  return null;
}

/// The `<type>` a route of [profile] is exported with.
String gpxTypeOf(RouteProfile profile) => switch (profile) {
  RouteProfile.fastbike => 'road_biking',
  RouteProfile.mtb => 'mountain_biking',
  RouteProfile.gravel => 'gravel_cycling',
  RouteProfile.trekking => 'touring',
  RouteProfile.shortest => 'cycling',
};

/// The profile a FIT file's [sport] and [subSport] name, or `null` when
/// they name none: a generic ride, a commute, an e-bike workout, or not a
/// ride at all.
RouteProfile? profileFromFit(FitSport sport, FitSubSport? subSport) {
  if (sport != FitSport.cycling && sport != FitSport.eBiking) return null;
  return switch (subSport) {
    FitSubSport.road => RouteProfile.fastbike,
    FitSubSport.mountain || FitSubSport.eBikeMountain => RouteProfile.mtb,
    FitSubSport.gravelCycling || FitSubSport.cyclocross => RouteProfile.gravel,
    _ => null,
  };
}

/// The FIT sub-sport a course of [profile] is exported with; its sport is
/// cycling.
FitSubSport fitSubSportOf(RouteProfile profile) => switch (profile) {
  RouteProfile.fastbike => FitSubSport.road,
  RouteProfile.mtb => FitSubSport.mountain,
  RouteProfile.gravel => FitSubSport.gravelCycling,
  RouteProfile.trekking || RouteProfile.shortest => FitSubSport.generic,
};

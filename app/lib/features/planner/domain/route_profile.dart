/// The BRouter profiles the planner offers.
///
/// [brouterName] is the profile file on the routing server (without `.brf`);
/// [typicalSpeedKmh] is the speed the estimated riding time is derived from
/// when the profile itself produced no time model.
enum RouteProfile {
  trekking('trekking', 18),
  fastbike('fastbike', 25),
  gravel('gravel', 16),
  mtb('mtb', 12),
  shortest('shortest', 18);

  const RouteProfile(this.brouterName, this.typicalSpeedKmh);

  /// The profile name BRouter knows, e.g. `trekking`.
  final String brouterName;

  /// Speed a rider of this profile is assumed to keep, in km/h.
  final double typicalSpeedKmh;

  /// The profile with this [brouterName], or [fallback] when none matches.
  static RouteProfile fromName(
    String? name, {
    RouteProfile fallback = RouteProfile.trekking,
  }) {
    for (final p in RouteProfile.values) {
      if (p.brouterName == name) return p;
    }
    return fallback;
  }

  /// Estimated riding time for [distanceM] at [typicalSpeedKmh].
  Duration estimatedTime(double distanceM) {
    if (!(distanceM > 0)) return Duration.zero;
    final hours = distanceM / 1000.0 / typicalSpeedKmh;
    return Duration(seconds: (hours * 3600).round());
  }
}

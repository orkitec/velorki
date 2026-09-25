/// The BRouter profiles the planner offers.
///
/// [brouterName] is the upstream BRouter profile a route is stored and
/// exported under, [engineName] the one the router is asked for;
/// [typicalSpeedKmh] is the speed the estimated riding time is derived from
/// when the profile itself produced no time model.
enum RouteProfile {
  trekking('trekking', 18),
  fastbike('fastbike', 25),
  gravel('gravel', 16),
  mtb('mtb', 12),
  shortest('shortest', 18);

  const RouteProfile(this.brouterName, this.typicalSpeedKmh);

  /// The upstream BRouter profile name, e.g. `trekking`: what a saved route
  /// and its options store, so rows from before Velorki had profiles of its
  /// own still read.
  final String brouterName;

  /// The profile the router is asked for: Velorki's own variant of the
  /// upstream one (`velorki-trekking.brf`, beside the untouched upstream
  /// files), which does not push a bike the wrong way down a one-way street
  /// or along a pavement to save a block. Direct has none: it is the
  /// shortest way, as it always was.
  String get engineName =>
      this == RouteProfile.shortest ? brouterName : 'velorki-$brouterName';

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

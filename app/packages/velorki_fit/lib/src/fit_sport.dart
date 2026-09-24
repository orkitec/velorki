/// The sport recorded in a FIT activity or course file.
///
/// Each value maps to a value of the FIT `sport` enum; [fitValue] is the
/// number that is actually written to the file.
enum FitSport {
  /// FIT `sport.generic` (0) — unspecified activity.
  generic(0),

  /// FIT `sport.running` (1).
  running(1),

  /// FIT `sport.cycling` (2) — the Velorki default.
  cycling(2),

  /// FIT `sport.swimming` (5).
  swimming(5),

  /// FIT `sport.walking` (11).
  walking(11),

  /// FIT `sport.cross_country_skiing` (12).
  crossCountrySkiing(12),

  /// FIT `sport.rowing` (15).
  rowing(15),

  /// FIT `sport.hiking` (17).
  hiking(17),

  /// FIT `sport.e_biking` (21).
  eBiking(21),

  /// FIT `sport.inline_skating` (30).
  inlineSkating(30);

  /// Creates a sport with its FIT enum value.
  const FitSport(this.fitValue);

  /// The numeric value of the FIT `sport` enum for this sport.
  final int fitValue;

  /// The [FitSport] for a raw FIT `sport` enum value, or `null` when the
  /// value is not one this package knows about.
  static FitSport? fromFitValue(int value) {
    for (final sport in FitSport.values) {
      if (sport.fitValue == value) return sport;
    }
    return null;
  }
}

/// The kind of a sport in a FIT file, as far as a bike is concerned.
///
/// Each value maps to a value of the FIT `sub_sport` enum; [fitValue] is the
/// number written to the file. Sub-sports this package has no use for read
/// as `null`.
enum FitSubSport {
  /// FIT `sub_sport.generic` (0).
  generic(0),

  /// FIT `sub_sport.road` (7).
  road(7),

  /// FIT `sub_sport.mountain` (8).
  mountain(8),

  /// FIT `sub_sport.cyclocross` (11).
  cyclocross(11),

  /// FIT `sub_sport.e_bike_fitness` (28).
  eBikeFitness(28),

  /// FIT `sub_sport.gravel_cycling` (46).
  gravelCycling(46),

  /// FIT `sub_sport.e_bike_mountain` (47).
  eBikeMountain(47),

  /// FIT `sub_sport.commuting` (48).
  commuting(48);

  /// Creates a sub-sport with its FIT enum value.
  const FitSubSport(this.fitValue);

  /// The numeric value of the FIT `sub_sport` enum.
  final int fitValue;

  /// The [FitSubSport] for a raw FIT `sub_sport` value, or `null` when the
  /// value is not one this package knows about.
  static FitSubSport? fromFitValue(int value) {
    for (final subSport in FitSubSport.values) {
      if (subSport.fitValue == value) return subSport;
    }
    return null;
  }
}

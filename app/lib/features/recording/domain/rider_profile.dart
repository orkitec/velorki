/// What the rider told us about themselves, for the calorie estimate; nothing
/// else reads it.
enum RiderSex {
  /// Not given, which rules the heart-rate formula out.
  unspecified,

  /// Female.
  female,

  /// Male.
  male;

  /// The value named [name], or [unspecified] when the name is unknown.
  static RiderSex fromName(String? name) => RiderSex.values.firstWhere(
    (sex) => sex.name == name,
    orElse: () => unspecified,
  );
}

/// What the rider sits on, for the power estimate: it decides the drag area
/// and the rolling resistance the model assumes.
enum RiderBike {
  /// A road bike, ridden on the hoods on good tyres.
  road,

  /// A touring or gravel bike: more upright, wider and softer tyres.
  touring,

  /// A mountain bike: upright, knobbly tyres.
  mountain;

  /// The value named [name], or [road] when the name is unknown.
  static RiderBike fromName(String? name) => RiderBike.values.firstWhere(
    (bike) => bike.name == name,
    orElse: () => road,
  );
}

/// The bike weight assumed until the rider enters one: Strava's default for
/// a road bike, in kilograms.
const double defaultBikeWeightKg = 9;

/// What the rider chose under Settings → Rider.
///
/// Every figure here stays on the phone: it is read when a ride page is built
/// and written nowhere else.
class RiderProfile {
  /// Creates the profile. All three estimates are off for a rider who never
  /// opened the section, and nothing about them is known.
  const RiderProfile({
    this.calories = false,
    this.zones = false,
    this.estimatePower = false,
    this.weightKg,
    this.birthYear,
    this.sex = RiderSex.unspecified,
    this.maxHeartRateBpm,
    this.bikeWeightKg = defaultBikeWeightKg,
    this.bike = RiderBike.road,
  });

  /// Whether the ride page shows a calorie estimate.
  final bool calories;

  /// Whether the ride page shows the time in heart-rate zones.
  final bool zones;

  /// Whether a ride without a power meter gets an estimated power.
  final bool estimatePower;

  /// The rider's weight in kilograms, if given.
  final double? weightKg;

  /// The rider's year of birth, if given.
  final int? birthYear;

  /// The rider's sex, for the heart-rate formula.
  final RiderSex sex;

  /// The rider's maximum heart rate in beats per minute, if given; without it
  /// the age estimates one.
  final int? maxHeartRateBpm;

  /// The bike's weight in kilograms, for the power estimate.
  final double bikeWeightKg;

  /// The kind of bike, for the power estimate.
  final RiderBike bike;

  /// How old the rider is in [year], or `null` without a year of birth.
  int? ageIn(int year) => birthYear == null ? null : year - birthYear!;

  /// The maximum heart rate the zones are cut at: the one given, else
  /// 220 minus the age, else nothing.
  int? effectiveMaxHeartRate(int year) {
    if (maxHeartRateBpm != null) return maxHeartRateBpm;
    final age = ageIn(year);
    return age == null ? null : 220 - age;
  }

  /// A copy with the named fields replaced.
  ///
  /// A nullable field is cleared by passing `clearWeight` and friends, since
  /// `null` here means "leave it".
  RiderProfile copyWith({
    bool? calories,
    bool? zones,
    double? weightKg,
    bool clearWeight = false,
    int? birthYear,
    bool clearBirthYear = false,
    RiderSex? sex,
    int? maxHeartRateBpm,
    bool clearMaxHeartRate = false,
    bool? estimatePower,
    double? bikeWeightKg,
    RiderBike? bike,
  }) => RiderProfile(
    calories: calories ?? this.calories,
    zones: zones ?? this.zones,
    estimatePower: estimatePower ?? this.estimatePower,
    weightKg: clearWeight ? null : weightKg ?? this.weightKg,
    birthYear: clearBirthYear ? null : birthYear ?? this.birthYear,
    sex: sex ?? this.sex,
    maxHeartRateBpm: clearMaxHeartRate
        ? null
        : maxHeartRateBpm ?? this.maxHeartRateBpm,
    bikeWeightKg: bikeWeightKg ?? this.bikeWeightKg,
    bike: bike ?? this.bike,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RiderProfile &&
          other.calories == calories &&
          other.zones == zones &&
          other.weightKg == weightKg &&
          other.birthYear == birthYear &&
          other.sex == sex &&
          other.maxHeartRateBpm == maxHeartRateBpm &&
          other.estimatePower == estimatePower &&
          other.bikeWeightKg == bikeWeightKg &&
          other.bike == bike;

  @override
  int get hashCode => Object.hash(
    calories,
    zones,
    weightKg,
    birthYear,
    sex,
    maxHeartRateBpm,
    estimatePower,
    bikeWeightKg,
    bike,
  );

  @override
  String toString() =>
      'RiderProfile(calories: $calories, zones: $zones, '
      'estimatePower: $estimatePower, weightKg: $weightKg, '
      'birthYear: $birthYear, sex: ${sex.name}, '
      'maxHeartRateBpm: $maxHeartRateBpm, bikeWeightKg: $bikeWeightKg, '
      'bike: ${bike.name})';
}

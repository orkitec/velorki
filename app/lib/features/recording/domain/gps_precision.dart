/// How hard the recorder drives the GPS while a ride runs.
///
/// The three profiles are spelled out in `recordingLocationSettings`; what
/// they cost is roughly what they ask of the chip: a fix per second at the
/// best accuracy the phone can manage is the most expensive, ten metres every
/// two seconds the least.
enum GpsPrecision {
  /// Coarser and slower: a fix every ten metres, two seconds apart, which at
  /// 20 km/h is still one every 1.8 s.
  saver,

  /// What a road ride needs: five metres, a second apart.
  normal,

  /// The best fix the phone can give, for trails where the track is the point.
  precise;

  /// The precision named [name], or [normal] when the name is unknown.
  static GpsPrecision fromName(String? name) => GpsPrecision.values.firstWhere(
    (precision) => precision.name == name,
    orElse: () => normal,
  );
}

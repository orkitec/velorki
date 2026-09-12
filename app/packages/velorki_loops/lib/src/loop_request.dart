import 'package:velorki_geo/velorki_geo.dart';

/// How much climbing the rider wants.
enum Hills {
  /// Keep it flat: climbing is penalised above 8 m/km.
  avoid,

  /// No opinion: climbing is penalised only above 15 m/km.
  neutral,

  /// Looking for hills: 10–25 m/km is rewarded.
  seek,
}

/// What the rider wants under the tyres.
enum Surface {
  /// Tarmac only; every unpaved metre is a penalty.
  paved,

  /// A bit of gravel is fine; only a large unpaved share is penalised.
  mixed,

  /// Gravel wanted; an unpaved share is a reward.
  gravel,
}

/// The rider's preferences for a loop.
class LoopPrefs {
  /// Creates loop preferences.
  const LoopPrefs({
    this.hills = Hills.neutral,
    this.surface = Surface.mixed,
    this.avoidTraffic = true,
  });

  /// Climbing preference.
  final Hills hills;

  /// Surface preference.
  final Surface surface;

  /// Whether busy roads should weigh double.
  final bool avoidTraffic;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LoopPrefs &&
          other.hills == hills &&
          other.surface == surface &&
          other.avoidTraffic == avoidTraffic;

  @override
  int get hashCode => Object.hash(hills, surface, avoidTraffic);

  @override
  String toString() =>
      'LoopPrefs(${hills.name}, ${surface.name}, avoidTraffic: $avoidTraffic)';
}

/// "A nice loop of about 60 km from here, past the lake."
class LoopRequest {
  /// Creates a loop request.
  const LoopRequest({
    required this.start,
    required this.targetM,
    this.via = const <LatLng>[],
    this.profile = 'trekking',
    this.prefs = const LoopPrefs(),
  });

  /// Where the ride starts and ends.
  final LatLng start;

  /// Places the loop should pass, in order. May be empty.
  final List<LatLng> via;

  /// Wanted route length in metres.
  final double targetM;

  /// BRouter profile name.
  final String profile;

  /// The rider's preferences.
  final LoopPrefs prefs;

  @override
  String toString() =>
      'LoopRequest($start, ${(targetM / 1000).round()} km, '
      '${via.length} via, $profile, $prefs)';
}

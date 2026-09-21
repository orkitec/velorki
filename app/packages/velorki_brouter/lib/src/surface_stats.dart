import 'segment_message.dart';

/// What the route is made of, as fractions of its total length.
///
/// Computed from BRouter's `messages` table, which carries the OSM way tags
/// per segment. The planner shows these under the elevation profile and
/// `velorki_loops` scores candidates with them.
class SurfaceStats {
  /// Creates surface statistics directly. Prefer [SurfaceStats.fromMessages].
  const SurfaceStats({
    required this.pavedShare,
    required this.unpavedShare,
    required this.unknownShare,
    required this.cyclewayShare,
    required this.busyShare,
    required this.coveredLengthM,
    required this.totalLengthM,
    this.offRoadShare = 0,
  });

  /// All-zero statistics, for a route with no messages or no length.
  static const SurfaceStats empty = SurfaceStats(
    pavedShare: 0,
    unpavedShare: 0,
    unknownShare: 0,
    cyclewayShare: 0,
    busyShare: 0,
    coveredLengthM: 0,
    totalLengthM: 0,
    offRoadShare: 0,
  );

  /// `surface=*` values counted as paved.
  static const Set<String> pavedSurfaces = <String>{
    'asphalt',
    'paved',
    'concrete',
    'concrete:lanes',
    'concrete:plates',
    'paving_stones',
    'paving_stones:lanes',
    'sett',
    'cobblestone',
    'cobblestone:flattened',
    'unhewn_cobblestone',
    'metal',
    'wood',
    'chipseal',
    'bricks',
    'brick',
  };

  /// `surface=*` values counted as unpaved.
  static const Set<String> unpavedSurfaces = <String>{
    'unpaved',
    'compacted',
    'fine_gravel',
    'gravel',
    'shells',
    'rock',
    'pebblestone',
    'ground',
    'dirt',
    'earth',
    'grass',
    'grass_paver',
    'metal_grid',
    'mud',
    'sand',
    'woodchips',
    'snow',
    'ice',
    'salt',
  };

  /// `highway=*` values counted as busy roads.
  static const Set<String> busyHighways = <String>{
    'primary',
    'primary_link',
    'trunk',
    'trunk_link',
  };

  /// `highway=*` values treated as unpaved when no `surface=*` tag is present.
  static const Set<String> unpavedByDefaultHighways = <String>{'track', 'path'};

  /// Share of the route on a paved surface, 0..1.
  final double pavedShare;

  /// Share of the route on an unpaved surface, 0..1.
  final double unpavedShare;

  /// Share of the route whose surface the OSM data does not say, 0..1.
  final double unknownShare;

  /// Share of the route on a cycleway or a way with cycle infrastructure,
  /// 0..1. Overlaps the surface shares on purpose.
  final double cyclewayShare;

  /// Share of the route on a primary or trunk road, 0..1. Overlaps the
  /// surface shares on purpose.
  final double busyShare;

  /// Share of the route that is not on a road at all, 0..1.
  ///
  /// A bike profile only ever routes over a way with a `highway=*` tag, a
  /// ferry (`route=ferry`) or — when the profile sets `add_beeline` — a
  /// beeline drawn straight from a waypoint to the nearest way. So everything
  /// without a `highway` tag is a leg the rider cannot pedal: it is what turns
  /// a "loop" into a line across open water, and `velorki_loops` rejects a
  /// candidate that has any.
  final double offRoadShare;

  /// Length the messages actually accounted for, in metres.
  final double coveredLengthM;

  /// The route length the shares are relative to, in metres.
  final double totalLengthM;

  /// Derives the statistics from a parsed `messages` table.
  ///
  /// [totalLengthM] is the denominator (BRouter's `track-length`), so the
  /// shares stay comparable even when the messages do not cover every metre;
  /// [coveredLengthM] tells you how much they did cover. A non-positive
  /// [totalLengthM] or an empty table yields [empty].
  ///
  /// Classification, in order:
  /// 1. `surface=*` in [pavedSurfaces] or [unpavedSurfaces] decides.
  /// 2. otherwise `highway=track` and `highway=path` count as unpaved
  ///    (the heuristic OSM mappers effectively rely on),
  /// 3. otherwise the segment is unknown.
  ///
  /// Cycleway: `highway=cycleway`, or any `cycleway*` key (`cycleway`,
  /// `cycleway:left`, `cycleway:both`, …) with a value other than `no`.
  /// Busy: `highway` in [busyHighways]. Off-road: no `highway` tag at all,
  /// which is a ferry or a beeline.
  factory SurfaceStats.fromMessages(
    List<SegmentMessage> messages,
    double totalLengthM,
  ) {
    if (messages.isEmpty || !(totalLengthM > 0)) return empty;
    var paved = 0.0;
    var unpaved = 0.0;
    var unknown = 0.0;
    var cycleway = 0.0;
    var busy = 0.0;
    var offRoad = 0.0;
    var covered = 0.0;

    for (final m in messages) {
      final d = m.distanceM;
      if (!(d > 0)) continue;
      covered += d;
      final tags = m.wayTags;
      final surface = tags['surface'];
      final highway = tags['highway'];
      if (surface != null && pavedSurfaces.contains(surface)) {
        paved += d;
      } else if (surface != null && unpavedSurfaces.contains(surface)) {
        unpaved += d;
      } else if (surface == null &&
          highway != null &&
          unpavedByDefaultHighways.contains(highway)) {
        unpaved += d;
      } else {
        // No usable surface tag, or one we do not know: better unknown than a
        // wrong guess.
        unknown += d;
      }

      if (highway == 'cycleway' || _hasCycleInfrastructure(tags)) {
        cycleway += d;
      }
      if (highway != null && busyHighways.contains(highway)) {
        busy += d;
      }
      if (highway == null) {
        offRoad += d;
      }
    }

    return SurfaceStats(
      pavedShare: paved / totalLengthM,
      unpavedShare: unpaved / totalLengthM,
      unknownShare: unknown / totalLengthM,
      cyclewayShare: cycleway / totalLengthM,
      busyShare: busy / totalLengthM,
      coveredLengthM: covered,
      totalLengthM: totalLengthM,
      offRoadShare: offRoad / totalLengthM,
    );
  }

  /// This as JSON, for a database column. [fromJson] reads it back.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'paved': pavedShare,
    'unpaved': unpavedShare,
    'unknown': unknownShare,
    'cycleway': cyclewayShare,
    'busy': busyShare,
    'coveredLengthM': coveredLengthM,
    'totalLengthM': totalLengthM,
    'offRoad': offRoadShare,
  };

  /// Reads [toJson] back. A missing key reads as zero, so a row written
  /// before a share existed still comes back.
  factory SurfaceStats.fromJson(Map<String, dynamic> json) {
    double at(String key) => (json[key] as num? ?? 0).toDouble();
    return SurfaceStats(
      pavedShare: at('paved'),
      unpavedShare: at('unpaved'),
      unknownShare: at('unknown'),
      cyclewayShare: at('cycleway'),
      busyShare: at('busy'),
      coveredLengthM: at('coveredLengthM'),
      totalLengthM: at('totalLengthM'),
      offRoadShare: at('offRoad'),
    );
  }

  static bool _hasCycleInfrastructure(Map<String, String> tags) {
    for (final e in tags.entries) {
      if (e.key == 'cycleway' || e.key.startsWith('cycleway:')) {
        if (e.value.isNotEmpty && e.value != 'no' && e.value != 'separate') {
          return true;
        }
      }
    }
    return false;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SurfaceStats &&
          other.pavedShare == pavedShare &&
          other.unpavedShare == unpavedShare &&
          other.unknownShare == unknownShare &&
          other.cyclewayShare == cyclewayShare &&
          other.busyShare == busyShare &&
          other.coveredLengthM == coveredLengthM &&
          other.totalLengthM == totalLengthM &&
          other.offRoadShare == offRoadShare;

  @override
  int get hashCode => Object.hash(
    pavedShare,
    unpavedShare,
    unknownShare,
    cyclewayShare,
    busyShare,
    coveredLengthM,
    totalLengthM,
    offRoadShare,
  );

  @override
  String toString() =>
      'SurfaceStats(paved: ${_pct(pavedShare)}, '
      'unpaved: ${_pct(unpavedShare)}, unknown: ${_pct(unknownShare)}, '
      'cycleway: ${_pct(cyclewayShare)}, busy: ${_pct(busyShare)}, '
      'offRoad: ${_pct(offRoadShare)})';

  static String _pct(double v) => '${(v * 100).toStringAsFixed(1)}%';
}

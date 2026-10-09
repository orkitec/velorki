/// What a way offers a rider, packed into one int: the kind of way, the
/// infrastructure along each side of a road, the cycle routes on it, and
/// its surface. [classifyWay] makes it from a way's tags.
///
/// The bits are the cache's and the worker's currency; [CycleAttrs] reads
/// them back.
library;

/// The kind of way, for ways a rider uses as a whole.
enum CycleKind {
  /// None of the kinds below: a road, maybe with lanes or tracks beside it.
  none,

  /// A way for bikes: `highway=cycleway`, or a path signed for bikes.
  cycleway,

  /// A path signed for bikes and walkers together, not split between them.
  shared,

  /// A footway or path bikes may use but that is not signed for them.
  allowed,

  /// A street where bikes have priority (`bicycle_road`, `cyclestreet`).
  cyclestreet,
}

/// Sides of a road, as a two-bit mask: left and right of the way's own
/// direction.
abstract final class Side {
  /// Left of the way's direction.
  static const int left = 1;

  /// Right of the way's direction.
  static const int right = 2;

  /// Both sides.
  static const int both = 3;
}

/// The barrier classes a node can have, as drawn.
abstract final class BarrierClass {
  /// Passable on the bike, but narrow: bollards, cycle barriers, blocks.
  static const int narrow = 1;

  /// A gate or a chain that may be closed.
  static const int gate = 2;

  /// The bike has to be carried or pushed: stiles, kissing gates,
  /// turnstiles.
  static const int carry = 3;
}

/// The bit layout of a way's attributes.
abstract final class CycleBits {
  static const int _kindMask = 0x7;
  static const int _trackShift = 3;
  static const int _laneShift = 5;

  /// Bikes may ride against a one-way street.
  static const int contraflow = 1 << 7;

  /// On an international or national cycle route.
  static const int routeNational = 1 << 8;

  /// On a regional cycle route.
  static const int routeRegional = 1 << 9;

  /// On a local cycle route.
  static const int routeLocal = 1 << 10;

  /// Not paved.
  static const int unpaved = 1 << 11;

  /// Bumpy: bad smoothness or cobblestones.
  static const int rough = 1 << 12;
  static const int _mtbShift = 13; // three bits, scale + 1

  /// Any of the cycle routes.
  static const int anyRoute = routeNational | routeRegional | routeLocal;

  /// Packs the parts.
  static int pack({
    CycleKind kind = CycleKind.none,
    int track = 0,
    int lane = 0,
    bool contraflow = false,
    int routes = 0,
    bool unpaved = false,
    bool rough = false,
    int? mtbScale,
  }) =>
      kind.index |
      (track & Side.both) << _trackShift |
      (lane & Side.both) << _laneShift |
      (contraflow ? CycleBits.contraflow : 0) |
      (routes & anyRoute) |
      (unpaved ? CycleBits.unpaved : 0) |
      (rough ? CycleBits.rough : 0) |
      (mtbScale == null ? 0 : (mtbScale.clamp(0, 6) + 1) << _mtbShift);
}

/// Reads the parts of a packed attribute int.
extension type const CycleAttrs(int bits) {
  /// The kind of way.
  CycleKind get kind => CycleKind.values[bits & CycleBits._kindMask];

  /// The sides with a cycle track ([Side] mask).
  int get track => bits >> CycleBits._trackShift & Side.both;

  /// The sides with a cycle lane ([Side] mask).
  int get lane => bits >> CycleBits._laneShift & Side.both;

  /// Bikes may ride against the one-way.
  bool get contraflow => bits & CycleBits.contraflow != 0;

  /// The cycle routes, as [CycleBits.anyRoute] bits.
  int get routes => bits & CycleBits.anyRoute;

  /// Not paved.
  bool get unpaved => bits & CycleBits.unpaved != 0;

  /// Bumpy.
  bool get rough => bits & CycleBits.rough != 0;

  /// The mtb:scale, or null when not tagged.
  int? get mtbScale {
    final v = bits >> CycleBits._mtbShift & 0x7;
    return v == 0 ? null : v - 1;
  }

  /// Whether nothing here is worth drawing.
  bool get isEmpty => bits == 0;
}

const _pathLike = {'path', 'footway', 'pedestrian', 'bridleway'};

/// Roads and tracks a bike may use at all, for the surface and route bits
/// on ways that have no bike kind of their own.
const _rideable = {
  'primary',
  'primary_link',
  'secondary',
  'secondary_link',
  'tertiary',
  'tertiary_link',
  'unclassified',
  'residential',
  'living_street',
  'service',
  'track',
  'road',
  'cycleway',
  ..._pathLike,
};

const _unpavedSurfaces = {
  'unpaved',
  'gravel',
  'ground',
  'dirt',
  'grass',
  'sand',
  'earth',
  'mud',
  'compacted',
  'fine_gravel',
  'pebblestone',
  'clay',
  'rock',
  'stone',
  'woodchips',
};

const _roughSmoothness = {
  'bad',
  'very_bad',
  'horrible',
  'very_horrible',
  'impassable',
  'robust_wheels',
  'high_clearance',
  'off_road_wheels',
  'rough',
  'poor',
};

const _oneway = {'yes', '1', 'true', '-1'};

const _trackValues = {'track', 'opposite_track', 'sidepath', 'path'};
const _laneValues = {'lane', 'opposite_lane', 'share_busway'};

/// The attribute bits of a way with [tags], in the direction the way is
/// stored. Unknown and missing tags count as absent.
int classifyWay(Map<String, String> tags) {
  String t(String key) {
    final v = tags[key];
    return v == null || v == 'unknown' ? '' : v;
  }

  final highway = t('highway');
  if (highway.isEmpty) return 0;
  final bicycle = t('bicycle');
  final noBikes =
      bicycle == 'no' ||
      bicycle == 'dismount' ||
      bicycle == 'private' ||
      bicycle == 'use_sidepath';

  var kind = CycleKind.none;
  final pathLike = _pathLike.contains(highway);
  if (t('bicycle_road') == 'yes' || t('cyclestreet') == 'yes') {
    kind = CycleKind.cyclestreet;
  } else if (!noBikes &&
      (highway == 'cycleway' || pathLike && bicycle == 'designated')) {
    kind = t('foot') == 'designated' && t('segregated') != 'yes'
        ? CycleKind.shared
        : CycleKind.cycleway;
  } else if (pathLike && (bicycle == 'yes' || bicycle == 'permissive')) {
    kind = CycleKind.allowed;
  }

  // Lanes and tracks beside a road, per side. `cycleway=*` without a side
  // is both sides, except the opposite_* values, which describe the one
  // lane against the traffic: on the left of the way's direction where
  // traffic keeps right, which is where most of the map is.
  var track = 0;
  var lane = 0;
  if (kind == CycleKind.none && !pathLike) {
    void side(String value, int sides) {
      if (_trackValues.contains(value)) track |= sides;
      if (_laneValues.contains(value)) lane |= sides;
    }

    final plain = t('cycleway');
    side(plain, plain.startsWith('opposite') ? Side.left : Side.both);
    side(t('cycleway:both'), Side.both);
    side(t('cycleway:left'), Side.left);
    side(t('cycleway:right'), Side.right);
    if (t('sidewalk:bicycle') == 'designated') track |= Side.both;
    if (t('sidewalk:left:bicycle') == 'designated') track |= Side.left;
    if (t('sidewalk:right:bicycle') == 'designated') track |= Side.right;
  }

  final oneway = t('oneway');
  final against = oneway == '-1' ? t('bicycle:forward') : t('bicycle:backward');
  final contraflow =
      _oneway.contains(oneway) &&
      !noBikes &&
      (t('oneway:bicycle') == 'no' ||
          t('cycleway').startsWith('opposite') ||
          t('cycleway:left').startsWith('opposite') ||
          t('cycleway:right').startsWith('opposite') ||
          t('cycleway:left:oneway') == 'no' ||
          t('cycleway:left:oneway') == '-1' ||
          t('cycleway:right:oneway') == 'no' ||
          t('cycleway:right:oneway') == '-1' ||
          against == 'yes' ||
          against == 'designated');

  var routes = 0;
  if (t('route_bicycle_icn') == 'yes' ||
      t('route_bicycle_ncn') == 'yes' ||
      t('ncn') == 'yes') {
    routes |= CycleBits.routeNational;
  }
  if (t('route_bicycle_rcn') == 'yes' || t('rcn') == 'yes') {
    routes |= CycleBits.routeRegional;
  }
  if (t('route_bicycle_lcn') == 'yes' ||
      t('lcn') == 'yes' ||
      t('route_bicycle_') == 'yes' ||
      t('route_bicycle_radweit') == 'yes') {
    routes |= CycleBits.routeLocal;
  }

  final rideable = !noBikes && _rideable.contains(highway);
  var unpaved = false;
  var rough = false;
  if (rideable || kind != CycleKind.none) {
    final surface = t('surface');
    final tracktype = t('tracktype');
    unpaved =
        _unpavedSurfaces.contains(surface) ||
        surface.isEmpty && tracktype.isNotEmpty && tracktype != 'grade1';
    rough =
        _roughSmoothness.contains(t('smoothness')) || surface == 'cobblestone';
  }

  final scale = int.tryParse(t('mtb:scale').replaceAll(RegExp('[^0-9]'), ''));

  return CycleBits.pack(
    kind: kind,
    track: track,
    lane: lane,
    contraflow: contraflow,
    routes: rideable || kind != CycleKind.none ? routes : 0,
    unpaved: unpaved,
    rough: rough,
    mtbScale: rideable ? scale : null,
  );
}

/// The barrier class of a node with [tags], or 0 for none worth drawing.
int classifyNode(Map<String, String> tags) {
  final barrier = tags['barrier'] ?? '';
  final bicycle = tags['bicycle'] ?? '';
  if (bicycle == 'yes' || bicycle == 'designated') {
    // Signed open for bikes: a gate that is a gap, a bollard that is kept
    // wide; still worth a mark when it narrows the way.
    return switch (barrier) {
      'bollard' ||
      'cycle_barrier' ||
      'block' ||
      'chicane' => BarrierClass.narrow,
      _ => 0,
    };
  }
  return switch (barrier) {
    'bollard' ||
    'cycle_barrier' ||
    'block' ||
    'chicane' ||
    'bar' ||
    'motorcycle_barrier' ||
    'bus_trap' => BarrierClass.narrow,
    'gate' ||
    'lift_gate' ||
    'swing_gate' ||
    'chain' ||
    'bump_gate' ||
    'hampshire_gate' ||
    'sliding_gate' ||
    'cattle_grid' => BarrierClass.gate,
    'stile' ||
    'kissing_gate' ||
    'turnstile' ||
    'full-height_turnstile' ||
    'horse_stile' ||
    'sally_port' => BarrierClass.carry,
    _ => bicycle == 'no' || bicycle == 'dismount' ? BarrierClass.carry : 0,
  };
}

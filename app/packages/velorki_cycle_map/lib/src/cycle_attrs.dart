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

  /// Steps: the bike is carried, or pushed up a ramp beside them.
  steps,
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

/// Which way something may be ridden or driven, relative to the way's own
/// direction.
abstract final class Direction {
  /// Not known, or not one-way.
  static const int none = 0;

  /// Only along the way.
  static const int forward = 1;

  /// Only against it.
  static const int backward = 2;

  /// Both ways, said so explicitly.
  static const int both = 3;
}

/// How calm a road is for a bike, or that bikes may not use it.
abstract final class TrafficClass {
  /// Nothing known that sets it apart.
  static const int none = 0;

  /// A speed limit of 30 km/h (or 20 mph) or less.
  static const int limit30 = 1;

  /// 20 km/h or less, or a living street.
  static const int limit20 = 2;

  /// Walking pace.
  static const int walk = 3;

  /// No motor traffic.
  static const int noMotor = 4;

  /// Closed to bikes.
  static const int noBikes = 5;
}

/// How big a road is, for how far beside it its lanes are drawn.
abstract final class RoadClass {
  /// Residential, service, unclassified and the like.
  static const int minor = 0;

  /// Secondary and tertiary.
  static const int middle = 1;

  /// Primary and trunk.
  static const int major = 2;
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

/// The bit layout of a way's attributes; all fit in 32 bits, the highest
/// one included, so a cell keeps them in an `Int32List`.
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

  /// Not paved: gravel or worse.
  static const int unpaved = 1 << 11;

  /// Bumpy: bad smoothness on a paved way, or cobblestones.
  static const int rough = 1 << 12;
  static const int _mtbShift = 13; // three bits, scale + 1
  static const int _onewayShift = 16; // two bits, a [Direction]
  static const int _leftDirShift = 18;
  static const int _rightDirShift = 20;
  static const int _sharedShift = 22; // two bits, a [Side] mask

  /// Steps with a ramp for bikes.
  static const int ramp = 1 << 24;
  static const int _trafficShift = 25; // three bits, a [TrafficClass]
  static const int _roadShift = 28; // two bits, a [RoadClass]

  /// On a mountain-bike route.
  static const int mtbRoute = 1 << 30;

  /// Rugged: only for a mountain bike (ground, mud, very bad smoothness).
  static const int rugged = 1 << 31;

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
    int oneway = Direction.none,
    int leftDirection = Direction.none,
    int rightDirection = Direction.none,
    int sharedLane = 0,
    bool ramp = false,
    int traffic = TrafficClass.none,
    int road = RoadClass.minor,
    bool mtbRoute = false,
    bool rugged = false,
  }) =>
      kind.index |
      (track & Side.both) << _trackShift |
      (lane & Side.both) << _laneShift |
      (contraflow ? CycleBits.contraflow : 0) |
      (routes & anyRoute) |
      (unpaved ? CycleBits.unpaved : 0) |
      (rough ? CycleBits.rough : 0) |
      (mtbScale == null ? 0 : (mtbScale.clamp(0, 6) + 1) << _mtbShift) |
      (oneway & 3) << _onewayShift |
      (leftDirection & 3) << _leftDirShift |
      (rightDirection & 3) << _rightDirShift |
      (sharedLane & Side.both) << _sharedShift |
      (ramp ? CycleBits.ramp : 0) |
      (traffic & 7) << _trafficShift |
      (road & 3) << _roadShift |
      (mtbRoute ? CycleBits.mtbRoute : 0) |
      (rugged ? CycleBits.rugged : 0);
}

/// Reads the parts of a packed attribute int; works on the 32 bits as
/// stored, sign and all.
extension type const CycleAttrs(int bits) {
  /// The kind of way.
  CycleKind get kind => CycleKind.values[bits & CycleBits._kindMask];

  /// The sides with a cycle track ([Side] mask).
  int get track => bits >> CycleBits._trackShift & Side.both;

  /// The sides with a cycle lane ([Side] mask).
  int get lane => bits >> CycleBits._laneShift & Side.both;

  /// The sides with a lane bikes share: a bus lane, a lane marked with
  /// bike symbols only, a shoulder, or a sidewalk bikes may use.
  int get sharedLane => bits >> CycleBits._sharedShift & Side.both;

  /// Bikes may ride against the one-way.
  bool get contraflow => bits & CycleBits.contraflow != 0;

  /// The one-way [Direction]: of bikes on a cycleway or a path, of the
  /// traffic on a road.
  int get oneway => bits >> CycleBits._onewayShift & 3;

  /// The [Direction] of the track or lane on the left.
  int get leftDirection => bits >> CycleBits._leftDirShift & 3;

  /// The [Direction] of the track or lane on the right.
  int get rightDirection => bits >> CycleBits._rightDirShift & 3;

  /// The cycle routes, as [CycleBits.anyRoute] bits.
  int get routes => bits & CycleBits.anyRoute;

  /// On a mountain-bike route.
  bool get mtbRoute => bits & CycleBits.mtbRoute != 0;

  /// Not paved: gravel or worse.
  bool get unpaved => bits & CycleBits.unpaved != 0;

  /// Rugged, for a mountain bike.
  bool get rugged => bits & CycleBits.rugged != 0;

  /// Bumpy.
  bool get rough => bits & CycleBits.rough != 0;

  /// Steps with a ramp for bikes.
  bool get ramp => bits & CycleBits.ramp != 0;

  /// The [TrafficClass].
  int get traffic => bits >> CycleBits._trafficShift & 7;

  /// The [RoadClass].
  int get road => bits >> CycleBits._roadShift & 3;

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

/// Roads with motor traffic, which a speed limit or an access rule can make
/// calm, or close to bikes.
const _roads = {
  'trunk',
  'trunk_link',
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
  'road',
};

const _majorRoads = {'trunk', 'trunk_link', 'primary', 'primary_link'};
const _middleRoads = {
  'secondary',
  'secondary_link',
  'tertiary',
  'tertiary_link',
};

const _gravelSurfaces = {
  'unpaved',
  'gravel',
  'compacted',
  'fine_gravel',
  'pebblestone',
};
const _ruggedSurfaces = {
  'ground',
  'dirt',
  'grass',
  'sand',
  'earth',
  'mud',
  'rock',
  'stone',
  'clay',
  'woodchips',
};
const _pavedSurfaces = {
  'asphalt',
  'paved',
  'concrete',
  'paving_stones',
  'cobblestone',
  'sett',
  'wood',
  'metal',
  'grass_paver',
};
const _smooth = {'excellent', 'good', 'very_good', 'intermediate', 'medium'};
const _ruggedSmoothness = {
  'very_bad',
  'horrible',
  'very_horrible',
  'impassable',
  'robust_wheels',
  'high_clearance',
  'off_road_wheels',
};
const _bumpySmoothness = {'bad', 'rough', 'poor'};

const _oneway = {'yes', '1', 'true', '-1'};
const _noMotor = {'no', 'agricultural'};

const _trackValues = {'track', 'opposite_track', 'sidepath', 'path'};
const _laneValues = {'lane', 'opposite_lane'};
const _sharedValues = {'share_busway', 'shared_lane', 'shoulder'};

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
  final bikesAllowed =
      bicycle == 'yes' || bicycle == 'designated' || bicycle == 'permissive';
  final noBikes =
      bicycle == 'no' ||
      bicycle == 'dismount' ||
      bicycle == 'private' ||
      bicycle == 'use_sidepath';
  final closedToBikes =
      _roads.contains(highway) &&
      (bicycle == 'no' ||
          bicycle == 'private' ||
          bicycle == 'use_sidepath' ||
          !bikesAllowed &&
              (t('motorroad') == 'yes' ||
                  t('vehicle') == 'no' ||
                  t('access') == 'no'));

  var kind = CycleKind.none;
  final pathLike = _pathLike.contains(highway);
  if (highway == 'steps') {
    kind = CycleKind.steps;
  } else if (t('bicycle_road') == 'yes' || t('cyclestreet') == 'yes') {
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
  var shared = 0;
  var leftDirection = Direction.none;
  var rightDirection = Direction.none;
  if (kind == CycleKind.none && !pathLike && !closedToBikes) {
    void side(String value, int sides) {
      if (_trackValues.contains(value)) track |= sides;
      if (_laneValues.contains(value)) lane |= sides;
      if (_sharedValues.contains(value)) shared |= sides;
      if (value.startsWith('opposite')) {
        if (sides & Side.left != 0) leftDirection = Direction.backward;
        if (sides & Side.right != 0) rightDirection = Direction.backward;
      }
    }

    final plain = t('cycleway');
    side(plain, plain.startsWith('opposite') ? Side.left : Side.both);
    side(t('cycleway:both'), Side.both);
    side(t('cycleway:left'), Side.left);
    side(t('cycleway:right'), Side.right);
    if (t('sidewalk:bicycle') == 'designated') track |= Side.both;
    if (t('sidewalk:left:bicycle') == 'designated') track |= Side.left;
    if (t('sidewalk:right:bicycle') == 'designated') track |= Side.right;
    if (t('sidewalk:bicycle') == 'yes') shared |= Side.both;
    if (t('sidewalk:left:bicycle') == 'yes') shared |= Side.left;
    if (t('sidewalk:right:bicycle') == 'yes') shared |= Side.right;
    int sideDirection(String value, int fallback) => switch (value) {
      'yes' => Direction.forward,
      '-1' => Direction.backward,
      'no' => Direction.both,
      _ => fallback,
    };
    leftDirection = sideDirection(t('cycleway:left:oneway'), leftDirection);
    rightDirection = sideDirection(t('cycleway:right:oneway'), rightDirection);
  }
  final sides = track | lane | shared;
  if (sides & Side.left == 0) leftDirection = Direction.none;
  if (sides & Side.right == 0) rightDirection = Direction.none;

  final oneway = t('oneway');
  final roundabout = t('junction') == 'roundabout';
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
  final mtbRoute =
      t('route_mtb_') == 'yes' ||
      t('route_mtb_lcn') == 'yes' ||
      t('route_mtb_rcn') == 'yes' ||
      t('route_mtb_ncn') == 'yes' ||
      t('route_mtb_mtb') == 'yes' ||
      t('route_bicycle_mtb') == 'yes';

  // The surface in three grades, what the smoothness says first, then the
  // track grade, then the surface: a road bike, gravel, a mountain bike.
  final rideable =
      !noBikes && (_rideable.contains(highway) || kind != CycleKind.none);
  var grade = 0;
  var rough = false;
  if (rideable && kind != CycleKind.steps) {
    final surface = t('surface');
    final smoothness = t('smoothness');
    final tracktype = t('tracktype');
    // A road with no surface tagged is paved; a track or a path is not
    // assumed to be.
    final paved =
        _pavedSurfaces.contains(surface) ||
        surface.isEmpty && highway != 'track' && !pathLike;
    if (_ruggedSmoothness.contains(smoothness)) {
      grade = paved && surface.isNotEmpty ? 0 : 2;
    } else if (_bumpySmoothness.contains(smoothness)) {
      grade = paved ? 0 : 1;
    } else if (_smooth.contains(smoothness) ||
        _pavedSurfaces.contains(surface)) {
      grade = 0;
    } else if (tracktype.isNotEmpty) {
      grade = switch (tracktype) {
        'grade1' => 0,
        'grade2' || 'grade3' => 1,
        _ => 2,
      };
    } else if (_gravelSurfaces.contains(surface)) {
      grade = 1;
    } else if (_ruggedSurfaces.contains(surface)) {
      grade = 2;
    }
    rough =
        grade == 0 &&
        (_bumpySmoothness.contains(smoothness) ||
            _ruggedSmoothness.contains(smoothness) ||
            surface == 'cobblestone');
  }

  final scale = int.tryParse(t('mtb:scale').replaceAll(RegExp('[^0-9]'), ''));

  final traffic = closedToBikes
      ? TrafficClass.noBikes
      : !_roads.contains(highway)
      ? TrafficClass.none
      : _noMotor.contains(
          [
            t('motorcar'),
            t('motor_vehicle'),
            t('vehicle'),
            t('access'),
          ].firstWhere((v) => v.isNotEmpty, orElse: () => ''),
        )
      ? TrafficClass.noMotor
      : t('maxspeed') == '10'
      ? TrafficClass.walk
      : t('maxspeed') == '20' ||
            t('zone:maxspeed') == '20' ||
            highway == 'living_street' ||
            t('living_street') == 'yes'
      ? TrafficClass.limit20
      : t('maxspeed') == '30' || t('zone:maxspeed') == '30'
      ? TrafficClass.limit30
      : TrafficClass.none;

  final content = CycleBits.pack(
    kind: kind,
    track: track,
    lane: lane,
    sharedLane: shared,
    leftDirection: leftDirection,
    rightDirection: rightDirection,
    contraflow: contraflow,
    routes: rideable ? routes : 0,
    mtbRoute: rideable && mtbRoute,
    unpaved: grade >= 1,
    rugged: grade == 2,
    rough: rough,
    mtbScale: rideable ? scale : null,
    ramp: kind == CycleKind.steps && t('ramp:bicycle') == 'yes',
    traffic: traffic,
  );
  // A road's one-way: the traffic's direction. On a street bikes may not
  // ride against, it is a line of its own (the one-way streets); with
  // contraflow it says which way the cars go. A roundabout is one-way by
  // nature and not drawn as such.
  final roadOneway = !_roads.contains(highway) || closedToBikes
      ? Direction.none
      : oneway == '-1'
      ? Direction.backward
      : _oneway.contains(oneway)
      ? Direction.forward
      : Direction.none;
  final bikeKind =
      kind == CycleKind.cycleway ||
      kind == CycleKind.shared ||
      kind == CycleKind.allowed;
  if (content == 0 && (bikeKind || roadOneway == Direction.none)) return 0;

  var direction = roadOneway;
  if (bikeKind) {
    final bikeOneway = t('oneway:bicycle');
    direction = bikeOneway == 'no'
        ? Direction.none
        : bikeOneway == 'yes' ||
              oneway == 'yes' ||
              oneway == '1' ||
              oneway == 'true' ||
              roundabout
        ? Direction.forward
        : oneway == '-1'
        ? Direction.backward
        : Direction.none;
  }
  return content |
      CycleBits.pack(
        oneway: direction,
        road: sides == 0
            ? RoadClass.minor
            : _majorRoads.contains(highway)
            ? RoadClass.major
            : _middleRoads.contains(highway)
            ? RoadClass.middle
            : RoadClass.minor,
      );
}

/// Whether a way with [tags] is one whose slope the map shows: a road,
/// track or path a bike may use, neither bridge nor tunnel, whose heights
/// are the terrain's and not its own, outside the densest city cores.
bool isClimbable(Map<String, String> tags) {
  String t(String key) {
    final v = tags[key];
    return v == null || v == 'unknown' ? '' : v;
  }

  final highway = t('highway');
  final bicycle = t('bicycle');
  if (!_rideable.contains(highway)) return false;
  if (bicycle == 'no' || bicycle == 'private' || bicycle == 'use_sidepath') {
    return false;
  }
  // The densest built-up class, the high-rise core of a big city: there
  // the terrain model's heights are the buildings', and its climbs were
  // nearly all false (Midtown Manhattan), while hilly towns and cities keep
  // theirs (tool/climb_eval.dart).
  if (t('estimated_town_class') == '6') return false;
  final tunnel = t('tunnel');
  return (tunnel.isEmpty || tunnel == 'no') && t('bridge').isEmpty;
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

import 'package:flutter/foundation.dart';
import 'package:velorki_geo/velorki_geo.dart';
import 'package:velorki_gpx/velorki_gpx.dart';

/// What a point of interest is about, as far as the map and the voice care.
///
/// Other planners each keep their own long list of categories; these are the
/// ones a rider can tell apart on a handlebar at speed.
enum PoiKind {
  /// Something to watch out for: a dismount zone, a rough patch, traffic.
  danger,

  /// Water: a fountain, a tap, a spring.
  water,

  /// Food: a café, a shop, a bakery.
  food,

  /// Anything else worth a marker.
  generic,

  /// The top of a climb.
  summit,

  /// A view worth stopping for.
  viewpoint,

  /// A roof against the weather: a hut, a bus shelter.
  shelter,

  /// A shop, for whatever runs out.
  shop,

  /// A bike shop or a repair stand.
  repair,

  /// Help: a first-aid post, a pharmacy, a hospital.
  firstAid,

  /// A toilet.
  toilet,

  /// A place to sleep outside: a campsite, a pitch.
  campsite,

  /// A roof and a bed: a hotel, a hostel, a guesthouse. What a rider going
  /// a long way marks, and the one thing a campsite does not cover.
  accommodation,

  /// Somewhere to leave a car or lock a bike.
  parking,

  /// Public transport: a station, a stop, a ferry.
  transport,

  /// A turn of the cue sheet, with its direction on the waypoint.
  turn;

  /// The word an export writes as a waypoint's `type`, and the one the
  /// import reads back: the enum's own name where that is already the word
  /// other planners use, a plainer one where it is not.
  String get gpxType => switch (this) {
    PoiKind.firstAid => 'first_aid',
    PoiKind.toilet => 'restroom',
    PoiKind.campsite => 'campground',
    PoiKind.accommodation => 'lodging',
    PoiKind.parking => 'parking',
    PoiKind.transport => 'transit',
    _ => name,
  };

  /// The kind for the free-form `type`, `sym` and `cmt` strings a GPX
  /// waypoint comes with, in the words the planners and the head units of
  /// the world write them.
  static PoiKind fromGpx({String? type, String? symbol, String? comment}) {
    final words = <String?>[
      type,
      symbol,
      comment,
    ].nonNulls.map((s) => s.toLowerCase()).join(' ');
    if (words.contains('danger') ||
        words.contains('caution') ||
        words.contains('hazard') ||
        words.contains('warning')) {
      return PoiKind.danger;
    }
    // Before anything that looks for a station: an aid station is help, not
    // a platform.
    if (words.contains('first aid') ||
        words.contains('first_aid') ||
        words.contains('firstaid') ||
        words.contains('aid station') ||
        words.contains('aid_station') ||
        words.contains('pharmacy') ||
        words.contains('hospital')) {
      return PoiKind.firstAid;
    }
    if (words.contains('summit') ||
        words.contains('peak') ||
        words.contains('gipfel')) {
      return PoiKind.summit;
    }
    if (words.contains('viewpoint') ||
        words.contains('scenic') ||
        words.contains('view') ||
        words.contains('aussicht')) {
      return PoiKind.viewpoint;
    }
    if (words.contains('shelter') ||
        words.contains('hut') ||
        words.contains('refuge') ||
        words.contains('lodge')) {
      return PoiKind.shelter;
    }
    if (words.contains('camp')) {
      return PoiKind.campsite;
    }
    // A bed rather than a pitch. `lodge` is a shelter and `lodging` a bed,
    // and neither string contains the other, so the two stay apart. `inn`
    // is checked as a word: it sits inside `beginning` and `winning`.
    if (words.contains('lodging') ||
        words.contains('hotel') ||
        words.contains('hostel') ||
        words.contains('guesthouse') ||
        words.contains('guest house') ||
        words.contains('accommodation') ||
        words.contains('herberge') ||
        words.contains('pension') ||
        words.contains('gasthaus') ||
        words.contains('gasthof') ||
        words.contains('unterkunft') ||
        RegExp(r'\binn\b').hasMatch(words)) {
      return PoiKind.accommodation;
    }
    if (words.contains('repair') ||
        words.contains('mechanic') ||
        words.contains('workshop')) {
      return PoiKind.repair;
    }
    if (words.contains('shop') ||
        words.contains('store') ||
        words.contains('supermarket')) {
      return PoiKind.shop;
    }
    if (words.contains('parking') || words.contains('car park')) {
      return PoiKind.parking;
    }
    // Before water: a water closet is the other thing.
    if (words.contains('toilet') ||
        words.contains('restroom') ||
        words.contains('rest room') ||
        words.contains('lavatory')) {
      return PoiKind.toilet;
    }
    if (words.contains('water') ||
        words.contains('drink') ||
        words.contains('fountain')) {
      return PoiKind.water;
    }
    if (words.contains('food') ||
        words.contains('restaurant') ||
        words.contains('cafe') ||
        words.contains('café') ||
        words.contains('bakery') ||
        words.contains('coffee')) {
      return PoiKind.food;
    }
    // Last: a water station is water, a food stop is food.
    if (words.contains('station') ||
        words.contains('ferry') ||
        words.contains('train') ||
        words.contains('bus') ||
        words.contains('tram') ||
        words.contains('metro') ||
        words.contains('transit')) {
      return PoiKind.transport;
    }
    return PoiKind.generic;
  }
}

/// The points as GPX `<wpt>` elements, the kind written back both as a
/// `type` word and as one of the symbol names a head unit knows, so the
/// file round-trips through either.
List<GpxWaypoint> gpxWaypoints(List<RoutePoi> pois) => <GpxWaypoint>[
  for (final poi in pois)
    GpxWaypoint(
      poi.pos,
      name: poi.name,
      description: poi.description,
      type: poi.exportType,
      symbol: switch (poi.kind) {
        PoiKind.danger => 'Danger Area',
        PoiKind.water => 'Drinking Water',
        PoiKind.food => 'Restaurant',
        PoiKind.generic => 'Flag, Blue',
        PoiKind.summit => 'Summit',
        PoiKind.viewpoint => 'Scenic Area',
        PoiKind.shelter => 'Lodge',
        PoiKind.shop => 'Shopping Center',
        PoiKind.repair => 'Bike Trail',
        PoiKind.firstAid => 'First Aid',
        PoiKind.toilet => 'Restroom',
        PoiKind.campsite => 'Campground',
        PoiKind.accommodation => 'Lodging',
        PoiKind.parking => 'Parking Area',
        PoiKind.transport => 'Flag, Blue',
        PoiKind.turn => 'Flag, Blue',
      },
    ),
];

/// A point of interest that came with a route: a named place beside or on
/// the way, with something to say about it.
///
/// Kept with the saved route, drawn on every map that shows the route, said
/// out loud when the rider comes up to it, and written back out with the
/// route as a GPX `<wpt>`.
@immutable
class RoutePoi {
  /// Creates a point.
  const RoutePoi({
    required this.pos,
    required this.name,
    this.description,
    this.kind = PoiKind.generic,
    this.sourceType,
  });

  /// One entry of the `pois_json` column.
  factory RoutePoi.fromMap(Map<String, dynamic> json) => RoutePoi(
    pos: LatLng(
      (json['lat'] as num? ?? 0).toDouble(),
      (json['lon'] as num? ?? 0).toDouble(),
    ),
    name: json['name'] as String? ?? '',
    description: json['description'] as String?,
    kind: PoiKind.values.firstWhere(
      (k) => k.name == json['kind'],
      orElse: () => PoiKind.generic,
    ),
    sourceType: json['source'] as String?,
  );

  /// Where it is.
  final LatLng pos;

  /// What it is called: `START DISMOUNT ZONE`, `Water Fountain`.
  final String name;

  /// A line more about it, if the file had one: `All riders must dismount`.
  final String? description;

  /// What it is about.
  final PoiKind kind;

  /// The word the file this point came from called it: a GPX `type`, a
  /// course point type. `null` for a point a rider made here.
  ///
  /// Kept so an export can write it back, and a category or a marker no
  /// kind of ours stands for survives the round trip.
  final String? sourceType;

  /// The `type` an export writes: the word the file used, while the kind
  /// still agrees with it, and the word for the kind once a rider has
  /// changed it.
  String get exportType {
    final source = sourceType;
    if (source == null || source.isEmpty) return kind.gpxType;
    if (kind == PoiKind.generic) return source;
    return PoiKind.fromGpx(type: source) == kind ? source : kind.gpxType;
  }

  /// One entry of the `pois_json` column.
  Map<String, dynamic> toMap() => <String, dynamic>{
    'lat': pos.lat,
    'lon': pos.lon,
    'name': name,
    if (description != null) 'description': description,
    'kind': kind.name,
    if (sourceType != null) 'source': sourceType,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoutePoi &&
          other.pos == pos &&
          other.name == name &&
          other.description == description &&
          other.kind == kind &&
          other.sourceType == sourceType;

  @override
  int get hashCode => Object.hash(pos, name, description, kind, sourceType);

  @override
  String toString() => 'RoutePoi(${kind.name} "$name" at $pos)';
}

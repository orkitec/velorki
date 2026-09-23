import 'package:flutter/foundation.dart';
import 'package:velorki_geo/velorki_geo.dart';
import 'package:velorki_gpx/velorki_gpx.dart';

/// What a point of interest is about, as far as the map and the voice care.
///
/// Ride with GPS, Komoot and the rest each have their own long list of
/// categories; on a handlebar four are enough to tell a hazard from a tap.
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

  /// A turn of the cue sheet, with its direction on the waypoint.
  turn;

  /// The kind for the free-form `type`, `sym` and `cmt` strings a GPX
  /// waypoint comes with, as Ride with GPS and Garmin write them.
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
    return PoiKind.generic;
  }
}

/// The points as GPX `<wpt>` elements, the kind written back as the `type`
/// Ride with GPS spells and the `sym` Garmin does, so the file round-trips
/// through either.
List<GpxWaypoint> gpxWaypoints(List<RoutePoi> pois) => <GpxWaypoint>[
  for (final poi in pois)
    GpxWaypoint(
      poi.pos,
      name: poi.name,
      description: poi.description,
      type: poi.kind.name,
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
  );

  /// Where it is.
  final LatLng pos;

  /// What it is called: `START DISMOUNT ZONE`, `Water Fountain`.
  final String name;

  /// A line more about it, if the file had one: `All riders must dismount`.
  final String? description;

  /// What it is about.
  final PoiKind kind;

  /// One entry of the `pois_json` column.
  Map<String, dynamic> toMap() => <String, dynamic>{
    'lat': pos.lat,
    'lon': pos.lon,
    'name': name,
    if (description != null) 'description': description,
    'kind': kind.name,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoutePoi &&
          other.pos == pos &&
          other.name == name &&
          other.description == description &&
          other.kind == kind;

  @override
  int get hashCode => Object.hash(pos, name, description, kind);

  @override
  String toString() => 'RoutePoi(${kind.name} "$name" at $pos)';
}

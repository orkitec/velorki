part of 'models.dart';

/// Reads an optional array of objects through [parse], `[]` when absent.
List<T> _objectList<T>(
  Map<String, Object?> json,
  String key,
  T Function(Map<String, Object?> json) parse,
) {
  final value = json[key];
  if (value == null) return List<T>.empty();
  if (value is! List) throw RelayFormatException('$key is not an array');
  return value
      .map((Object? e) {
        if (e is Map<String, Object?>) return parse(e);
        throw RelayFormatException('$key contains a non-object entry');
      })
      .toList(growable: false);
}

/// A point on or beside the route, `{"lat": .., "lon": ..}`.
class DigestPoint {
  /// Creates a point.
  const DigestPoint({required this.lat, required this.lon});

  /// Latitude in degrees.
  final double lat;

  /// Longitude in degrees.
  final double lon;

  /// Parses `{"lat": .., "lon": ..}`.
  factory DigestPoint.fromJson(Map<String, Object?> json) =>
      DigestPoint(lat: _reqDouble(json, 'lat'), lon: _reqDouble(json, 'lon'));

  /// Serialises to `{"lat": .., "lon": ..}`.
  Map<String, Object?> toJson() => <String, Object?>{'lat': lat, 'lon': lon};

  @override
  bool operator ==(Object other) =>
      other is DigestPoint && other.lat == lat && other.lon == lon;

  @override
  int get hashCode => Object.hash(lat, lon);

  @override
  String toString() => 'DigestPoint($lat, $lon)';
}

/// One stretch of the route with the same kind of road, surface and slope.
class DigestStretch {
  /// Creates a stretch.
  const DigestStretch({
    required this.fromKm,
    required this.toKm,
    required this.road,
    required this.surface,
    required this.avgGrade,
    required this.maxGrade,
    required this.start,
    required this.end,
  });

  /// Where it starts, in kilometres from the start of the route.
  final double fromKm;

  /// Where it ends, in kilometres from the start of the route.
  final double toKm;

  /// The road class, OSM's `highway` value (`cycleway`, `track`,
  /// `secondary`, …), `ferry`, or `unknown`.
  final String road;

  /// OSM's `surface` value (`asphalt`, `gravel`, …), or `unknown`.
  final String surface;

  /// Average gradient in percent, negative downhill.
  final double avgGrade;

  /// The steepest gradient over about 100 m in percent, signed.
  final double maxGrade;

  /// Where it starts.
  final DigestPoint start;

  /// Where it ends.
  final DigestPoint end;

  /// Parses one `stretches` entry.
  factory DigestStretch.fromJson(Map<String, Object?> json) => DigestStretch(
    fromKm: _reqDouble(json, 'from_km'),
    toKm: _reqDouble(json, 'to_km'),
    road: _reqString(json, 'road'),
    surface: _reqString(json, 'surface'),
    avgGrade: _reqDouble(json, 'avg_grade'),
    maxGrade: _reqDouble(json, 'max_grade'),
    start: DigestPoint.fromJson(_reqObject(json, 'start')),
    end: DigestPoint.fromJson(_reqObject(json, 'end')),
  );

  /// Serialises to one `stretches` entry.
  Map<String, Object?> toJson() => <String, Object?>{
    'from_km': fromKm,
    'to_km': toKm,
    'road': road,
    'surface': surface,
    'avg_grade': avgGrade,
    'max_grade': maxGrade,
    'start': start.toJson(),
    'end': end.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is DigestStretch &&
      other.fromKm == fromKm &&
      other.toKm == toKm &&
      other.road == road &&
      other.surface == surface &&
      other.avgGrade == avgGrade &&
      other.maxGrade == maxGrade &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode =>
      Object.hash(fromKm, toKm, road, surface, avgGrade, maxGrade, start, end);

  @override
  String toString() =>
      'DigestStretch($fromKm–$toKm km, $road, $surface, '
      '$avgGrade%/$maxGrade%)';
}

/// One climb along the route.
class DigestClimb {
  /// Creates a climb.
  const DigestClimb({
    required this.startKm,
    required this.lengthKm,
    required this.gainM,
    required this.avgGrade,
    required this.maxGrade,
  });

  /// Where it starts, in kilometres from the start of the route.
  final double startKm;

  /// How long it is, in kilometres.
  final double lengthKm;

  /// How much it climbs, in metres.
  final double gainM;

  /// Average gradient in percent.
  final double avgGrade;

  /// The steepest gradient over about 100 m in percent.
  final double maxGrade;

  /// Parses one `climbs` entry.
  factory DigestClimb.fromJson(Map<String, Object?> json) => DigestClimb(
    startKm: _reqDouble(json, 'start_km'),
    lengthKm: _reqDouble(json, 'length_km'),
    gainM: _reqDouble(json, 'gain_m'),
    avgGrade: _reqDouble(json, 'avg_grade'),
    maxGrade: _reqDouble(json, 'max_grade'),
  );

  /// Serialises to one `climbs` entry.
  Map<String, Object?> toJson() => <String, Object?>{
    'start_km': startKm,
    'length_km': lengthKm,
    'gain_m': gainM,
    'avg_grade': avgGrade,
    'max_grade': maxGrade,
  };

  @override
  bool operator ==(Object other) =>
      other is DigestClimb &&
      other.startKm == startKm &&
      other.lengthKm == lengthKm &&
      other.gainM == gainM &&
      other.avgGrade == avgGrade &&
      other.maxGrade == maxGrade;

  @override
  int get hashCode => Object.hash(startKm, lengthKm, gainM, avgGrade, maxGrade);

  @override
  String toString() =>
      'DigestClimb(km $startKm, $lengthKm km, $gainM m, '
      '$avgGrade%/$maxGrade%)';
}

/// A settlement the route passes through.
class DigestTown {
  /// Creates a town.
  const DigestTown({
    required this.name,
    required this.kind,
    required this.km,
    required this.at,
  });

  /// Its name.
  final String name;

  /// `city`, `town` or `village`.
  final String kind;

  /// Where the route comes closest, in kilometres from the start.
  final double km;

  /// Where the settlement is.
  final DigestPoint at;

  /// Parses one `towns` entry.
  factory DigestTown.fromJson(Map<String, Object?> json) => DigestTown(
    name: _reqString(json, 'name'),
    kind: _reqString(json, 'kind'),
    km: _reqDouble(json, 'km'),
    at: DigestPoint(lat: _reqDouble(json, 'lat'), lon: _reqDouble(json, 'lon')),
  );

  /// Serialises to one `towns` entry.
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'kind': kind,
    'km': km,
    'lat': at.lat,
    'lon': at.lon,
  };

  @override
  bool operator ==(Object other) =>
      other is DigestTown &&
      other.name == name &&
      other.kind == kind &&
      other.km == km &&
      other.at == at;

  @override
  int get hashCode => Object.hash(name, kind, km, at);

  @override
  String toString() => 'DigestTown($name, $kind, km $km)';
}

/// A place to stop near the route: a café, water, a viewpoint, …
class DigestPlace {
  /// Creates a place.
  const DigestPlace({
    required this.id,
    required this.kind,
    required this.km,
    required this.offM,
    required this.at,
    this.name,
  });

  /// A short id that is stable within one digest, e.g. `p12`.
  final String id;

  /// The gazetteer's kind: `cafe`, `bakery`, `drinking_water`, `toilets`,
  /// `viewpoint`, `water`, `beach`, `bicycle_shop`,
  /// `bicycle_repair_station` or `station`.
  final String kind;

  /// Its name; `null` for an unnamed one, which a tap often is.
  final String? name;

  /// Where along the route it is, in kilometres from the start.
  final double km;

  /// How far off the route it is, in metres.
  final double offM;

  /// Where it is.
  final DigestPoint at;

  /// Parses one `places` entry.
  factory DigestPlace.fromJson(Map<String, Object?> json) => DigestPlace(
    id: _reqString(json, 'id'),
    kind: _reqString(json, 'kind'),
    name: _optString(json, 'name'),
    km: _reqDouble(json, 'km'),
    offM: _reqDouble(json, 'off_m'),
    at: DigestPoint(lat: _reqDouble(json, 'lat'), lon: _reqDouble(json, 'lon')),
  );

  /// Serialises to one `places` entry.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'kind': kind,
    if (name != null) 'name': name,
    'km': km,
    'off_m': offM,
    'lat': at.lat,
    'lon': at.lon,
  };

  @override
  bool operator ==(Object other) =>
      other is DigestPlace &&
      other.id == id &&
      other.kind == kind &&
      other.name == name &&
      other.km == km &&
      other.offM == offM &&
      other.at == at;

  @override
  int get hashCode => Object.hash(id, kind, name, km, offM, at);

  @override
  String toString() => 'DigestPlace($id, $kind, $name, km $km, $offM m)';
}

/// What a route is made of, for the `describe` step: the stretches it runs
/// over, its climbs, the settlements it passes through and the places to
/// stop beside it.
///
/// Built on the phone from the routing tiles and the offline gazetteer. The
/// relay accepts at most 60 stretches, 20 climbs, 30 towns and 40 places.
class RouteDigest {
  /// Creates a digest.
  const RouteDigest({
    required this.loop,
    this.profile,
    this.stretches = const <DigestStretch>[],
    this.climbs = const <DigestClimb>[],
    this.towns = const <DigestTown>[],
    this.places = const <DigestPlace>[],
  });

  /// The routing profile the route was planned with, e.g. `trekking`.
  final String? profile;

  /// Whether the route ends where it starts.
  final bool loop;

  /// The stretches, in route order, end to end.
  final List<DigestStretch> stretches;

  /// The climbs, in route order.
  final List<DigestClimb> climbs;

  /// The settlements passed through, in route order.
  final List<DigestTown> towns;

  /// The places to stop near the route, in route order.
  final List<DigestPlace> places;

  /// Parses a `digest` object.
  factory RouteDigest.fromJson(Map<String, Object?> json) => RouteDigest(
    profile: _optString(json, 'profile'),
    loop: _reqBool(json, 'loop'),
    stretches: _objectList(json, 'stretches', DigestStretch.fromJson),
    climbs: _objectList(json, 'climbs', DigestClimb.fromJson),
    towns: _objectList(json, 'towns', DigestTown.fromJson),
    places: _objectList(json, 'places', DigestPlace.fromJson),
  );

  /// Serialises to a `digest` object.
  Map<String, Object?> toJson() => <String, Object?>{
    if (profile != null) 'profile': profile,
    'loop': loop,
    'stretches': [for (final s in stretches) s.toJson()],
    'climbs': [for (final c in climbs) c.toJson()],
    'towns': [for (final t in towns) t.toJson()],
    'places': [for (final p in places) p.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is RouteDigest &&
      other.profile == profile &&
      other.loop == loop &&
      _listEquals(other.stretches, stretches) &&
      _listEquals(other.climbs, climbs) &&
      _listEquals(other.towns, towns) &&
      _listEquals(other.places, places);

  @override
  int get hashCode => Object.hash(
    profile,
    loop,
    Object.hashAll(stretches),
    Object.hashAll(climbs),
    Object.hashAll(towns),
    Object.hashAll(places),
  );

  @override
  String toString() =>
      'RouteDigest($profile, loop: $loop, ${stretches.length} stretches, '
      '${climbs.length} climbs, ${towns.length} towns, '
      '${places.length} places)';
}

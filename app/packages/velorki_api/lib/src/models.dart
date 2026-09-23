import 'errors.dart';

/* -------------------------------------------------------------- json help */

/// Reads [key] from [json] as a `String`, or throws [RelayFormatException].
String _reqString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) return value;
  throw RelayFormatException('$key is missing or not a string');
}

/// Reads [key] from [json] as a `double`, or throws [RelayFormatException].
double _reqDouble(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is num) return value.toDouble();
  throw RelayFormatException('$key is missing or not a number');
}

/// Reads [key] from [json] as a `bool`, or throws [RelayFormatException].
bool _reqBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is bool) return value;
  throw RelayFormatException('$key is missing or not a boolean');
}

/// Reads [key] from [json] as a JSON object, or throws [RelayFormatException].
Map<String, Object?> _reqObject(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is Map<String, Object?>) return value;
  throw RelayFormatException('$key is missing or not an object');
}

/// Reads an optional `String`; a present value of the wrong type throws.
String? _optString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is String) return value;
  throw RelayFormatException('$key is not a string');
}

/// Reads an optional `double`; a present value of the wrong type throws.
double? _optDouble(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is num) return value.toDouble();
  throw RelayFormatException('$key is not a number');
}

/// Reads an optional `int`; a present value of the wrong type throws.
int? _optInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is num) return value.toInt();
  throw RelayFormatException('$key is not a number');
}

/// Reads an optional object; a present value of the wrong type throws.
Map<String, Object?>? _optObject(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is Map<String, Object?>) return value;
  throw RelayFormatException('$key is not an object');
}

/// Reads an optional array of strings, defaulting to `null` when absent.
List<String>? _optStringList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! List) throw RelayFormatException('$key is not an array');
  return value
      .map((Object? e) {
        if (e is String) return e;
        throw RelayFormatException('$key contains a non-string entry');
      })
      .toList(growable: false);
}

/// Deep equality for lists, used by the generated-by-hand `==` operators.
bool _listEquals<T>(List<T>? a, List<T>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/* ------------------------------------------------------------------ enums */

/// How much unpaved surface the rider is willing to ride.
///
/// JSON values: `paved`, `mixed`, `gravel`.
enum SurfacePreference {
  /// Sealed roads and cycle paths only.
  paved('paved'),

  /// Mostly sealed, some good gravel is fine.
  mixed('mixed'),

  /// Gravel and forest tracks are wanted.
  gravel('gravel');

  const SurfacePreference(this.json);

  /// The snake_case string used on the wire.
  final String json;

  /// Parses [value], throwing [RelayFormatException] for an unknown string.
  static SurfacePreference fromJson(String value) =>
      _enumFromJson(values, value, 'surface', (e) => e.json);
}

/// The rider's attitude towards climbing.
///
/// JSON values: `avoid`, `neutral`, `seek`.
enum HillPreference {
  /// Keep the route as flat as the terrain allows.
  avoid('avoid'),

  /// No preference either way.
  neutral('neutral'),

  /// Look for climbs.
  seek('seek');

  const HillPreference(this.json);

  /// The snake_case string used on the wire.
  final String json;

  /// Parses [value], throwing [RelayFormatException] for an unknown string.
  static HillPreference fromJson(String value) =>
      _enumFromJson(values, value, 'hills', (e) => e.json);
}

/// How much motor traffic the rider accepts.
///
/// JSON values: `low`, `medium`, `high`.
enum TrafficTolerance {
  /// Quiet lanes only, detours are acceptable.
  low('low'),

  /// Normal secondary roads are fine.
  medium('medium'),

  /// The most direct road will do.
  high('high');

  const TrafficTolerance(this.json);

  /// The snake_case string used on the wire.
  final String json;

  /// Parses [value], throwing [RelayFormatException] for an unknown string.
  static TrafficTolerance fromJson(String value) =>
      _enumFromJson(values, value, 'traffic_tolerance', (e) => e.json);
}

/// A kind of place the rider would like to stop at along the way.
///
/// JSON values: `cafe`, `bakery`, `viewpoint`, `lake`, `water`, `none`.
enum StopKind {
  /// A cafe.
  cafe('cafe'),

  /// A bakery.
  bakery('bakery'),

  /// A viewpoint.
  viewpoint('viewpoint'),

  /// A lake.
  lake('lake'),

  /// Drinking water.
  water('water'),

  /// Explicitly no stops. The relay's default when the model says nothing.
  none('none');

  const StopKind(this.json);

  /// The snake_case string used on the wire.
  final String json;

  /// Parses [value], throwing [RelayFormatException] for an unknown string.
  static StopKind fromJson(String value) =>
      _enumFromJson(values, value, 'stops', (e) => e.json);
}

/// The BRouter profile family that best matches the request.
///
/// JSON values: `trekking`, `fastbike`, `mtb`, `gravel`.
enum ProfileHint {
  /// All-round touring profile.
  trekking('trekking'),

  /// Road bike, prefers speed and sealed surfaces.
  fastbike('fastbike'),

  /// Mountain bike, accepts rough tracks.
  mtb('mtb'),

  /// Gravel bike.
  gravel('gravel');

  const ProfileHint(this.json);

  /// The snake_case string used on the wire.
  final String json;

  /// Parses [value], throwing [RelayFormatException] for an unknown string.
  static ProfileHint fromJson(String value) =>
      _enumFromJson(values, value, 'profile_hint', (e) => e.json);
}

/// Whether a share holds a planned route or a recorded ride.
///
/// JSON values: `route`, `ride`.
enum ShareKind {
  /// A route the rider planned but has not ridden.
  route('route'),

  /// A recorded ride.
  ride('ride');

  const ShareKind(this.json);

  /// The snake_case string used on the wire.
  final String json;

  /// Parses [value], throwing [RelayFormatException] for an unknown string.
  static ShareKind fromJson(String value) =>
      _enumFromJson(values, value, 'kind', (e) => e.json);
}

/// Which unit system the AI answer should use.
///
/// JSON values: `metric`, `imperial`.
enum PlanUnits {
  /// Kilometres and metres.
  metric('metric'),

  /// Miles and feet.
  imperial('imperial');

  const PlanUnits(this.json);

  /// The snake_case string used on the wire.
  final String json;

  /// Parses [value], throwing [RelayFormatException] for an unknown string.
  static PlanUnits fromJson(String value) =>
      _enumFromJson(values, value, 'units', (e) => e.json);
}

/// Shared enum lookup: linear scan over [values], then a typed failure.
///
/// The unknown-value policy of this package is *strict*: an enum string the
/// client does not know throws [RelayFormatException] rather than silently
/// becoming a default. A wrong surface or profile would be turned into a
/// BRouter query and produce a route the rider did not ask for, so failing
/// loudly is the honest choice. Callers that prefer a fallback can catch the
/// exception at the field they care about.
T _enumFromJson<T>(
  List<T> values,
  String value,
  String field,
  String Function(T) key,
) {
  for (final candidate in values) {
    if (key(candidate) == value) return candidate;
  }
  throw RelayFormatException('unknown $field value "$value"');
}

/* ---------------------------------------------------------- route request */

/// Where a proposed ride begins.
///
/// Wire shape: `{"use_current": true, "name": "Freiburg"}`.
class RouteStart {
  /// Creates a start point description.
  const RouteStart({required this.useCurrent, this.name});

  /// True when the ride starts at the rider's current position.
  final bool useCurrent;

  /// Name of the starting place; only meaningful when [useCurrent] is false.
  final String? name;

  /// Parses the `start` object of a `propose_route` call.
  factory RouteStart.fromJson(Map<String, Object?> json) => RouteStart(
    useCurrent: _reqBool(json, 'use_current'),
    name: _optString(json, 'name'),
  );

  /// Serialises to the `start` object; [name] is omitted when null.
  Map<String, Object?> toJson() => <String, Object?>{
    'use_current': useCurrent,
    if (name != null) 'name': name,
  };

  @override
  bool operator ==(Object other) =>
      other is RouteStart &&
      other.useCurrent == useCurrent &&
      other.name == name;

  @override
  int get hashCode => Object.hash(useCurrent, name);

  @override
  String toString() => 'RouteStart(useCurrent: $useCurrent, name: $name)';
}

/// The arguments of the relay's `propose_route` tool call.
///
/// This is what the app turns into a BRouter query. The ranges named in the
/// field docs are the relay's contract and are *not* enforced here: values are
/// carried through exactly as received so a JSON round trip is lossless, and
/// so a relay that widens a limit does not break older clients. Validate at
/// the point of use if it matters.
class RouteRequest {
  /// Creates a route request.
  const RouteRequest({
    required this.distanceKm,
    required this.loop,
    required this.start,
    required this.surface,
    required this.hills,
    required this.trafficTolerance,
    required this.profileHint,
    this.via = const <String>[],
    this.stops = const <StopKind>[StopKind.none],
    this.notes,
    this.confidence = 0.5,
  });

  /// Target ride length in kilometres. The relay's contract is 5 to 300.
  final double distanceKm;

  /// True when the ride should return to its start.
  final bool loop;

  /// Where the ride begins.
  final RouteStart start;

  /// Up to 4 place names the rider explicitly asked to pass through.
  final List<String> via;

  /// Preferred road surface.
  final SurfacePreference surface;

  /// Attitude towards climbing.
  final HillPreference hills;

  /// Tolerance for motor traffic.
  final TrafficTolerance trafficTolerance;

  /// Kinds of stop the rider would like along the way.
  ///
  /// Defaults to `[StopKind.none]`, matching the relay's tool schema.
  final List<StopKind> stops;

  /// Routing profile family that best matches the request.
  final ProfileHint profileHint;

  /// One short sentence for the rider, in the rider's locale. Up to 200
  /// characters by the relay's contract; `null` when the model said nothing.
  final String? notes;

  /// How confident the model is that this matches the request, 0 to 1.
  ///
  /// Defaults to `0.5`, matching the relay's tool schema.
  final double confidence;

  /// Parses a `propose_route` argument object.
  ///
  /// Missing optional fields take the relay's documented defaults. A missing
  /// required field, a field of the wrong JSON type, or an unknown enum string
  /// throws [RelayFormatException].
  factory RouteRequest.fromJson(Map<String, Object?> json) {
    final rawVia = json['via'];
    final rawStops = json['stops'];
    return RouteRequest(
      distanceKm: _reqDouble(json, 'distance_km'),
      loop: _reqBool(json, 'loop'),
      start: RouteStart.fromJson(_reqObject(json, 'start')),
      via: rawVia == null
          ? const <String>[]
          : (_optStringList(json, 'via') ?? const <String>[]),
      surface: SurfacePreference.fromJson(_reqString(json, 'surface')),
      hills: HillPreference.fromJson(_reqString(json, 'hills')),
      trafficTolerance: TrafficTolerance.fromJson(
        _reqString(json, 'traffic_tolerance'),
      ),
      stops: rawStops == null
          ? const <StopKind>[StopKind.none]
          : _parseStops(rawStops),
      profileHint: ProfileHint.fromJson(_reqString(json, 'profile_hint')),
      notes: _optString(json, 'notes'),
      confidence: _optDouble(json, 'confidence') ?? 0.5,
    );
  }

  static List<StopKind> _parseStops(Object? raw) {
    if (raw is! List) throw const RelayFormatException('stops is not an array');
    return raw
        .map((Object? e) {
          if (e is String) return StopKind.fromJson(e);
          throw const RelayFormatException('stops contains a non-string entry');
        })
        .toList(growable: false);
  }

  /// Serialises to the `propose_route` argument object.
  ///
  /// All fields except [notes] are always written, including the ones that
  /// have a default, so the result is a complete tool-call payload.
  Map<String, Object?> toJson() => <String, Object?>{
    'distance_km': distanceKm,
    'loop': loop,
    'start': start.toJson(),
    'via': via,
    'surface': surface.json,
    'hills': hills.json,
    'traffic_tolerance': trafficTolerance.json,
    'stops': stops.map((s) => s.json).toList(growable: false),
    'profile_hint': profileHint.json,
    if (notes != null) 'notes': notes,
    'confidence': confidence,
  };

  /// Returns a copy with the given fields replaced.
  RouteRequest copyWith({
    double? distanceKm,
    bool? loop,
    RouteStart? start,
    List<String>? via,
    SurfacePreference? surface,
    HillPreference? hills,
    TrafficTolerance? trafficTolerance,
    List<StopKind>? stops,
    ProfileHint? profileHint,
    String? notes,
    double? confidence,
  }) => RouteRequest(
    distanceKm: distanceKm ?? this.distanceKm,
    loop: loop ?? this.loop,
    start: start ?? this.start,
    via: via ?? this.via,
    surface: surface ?? this.surface,
    hills: hills ?? this.hills,
    trafficTolerance: trafficTolerance ?? this.trafficTolerance,
    stops: stops ?? this.stops,
    profileHint: profileHint ?? this.profileHint,
    notes: notes ?? this.notes,
    confidence: confidence ?? this.confidence,
  );

  @override
  bool operator ==(Object other) =>
      other is RouteRequest &&
      other.distanceKm == distanceKm &&
      other.loop == loop &&
      other.start == start &&
      _listEquals(other.via, via) &&
      other.surface == surface &&
      other.hills == hills &&
      other.trafficTolerance == trafficTolerance &&
      _listEquals(other.stops, stops) &&
      other.profileHint == profileHint &&
      other.notes == notes &&
      other.confidence == confidence;

  @override
  int get hashCode => Object.hash(
    distanceKm,
    loop,
    start,
    Object.hashAll(via),
    surface,
    hills,
    trafficTolerance,
    Object.hashAll(stops),
    profileHint,
    notes,
    confidence,
  );

  @override
  String toString() =>
      'RouteRequest(distanceKm: $distanceKm, loop: $loop, '
      'start: $start, via: $via, surface: ${surface.json}, '
      'hills: ${hills.json}, trafficTolerance: ${trafficTolerance.json}, '
      'stops: ${stops.map((s) => s.json).toList()}, '
      'profileHint: ${profileHint.json}, notes: $notes, '
      'confidence: $confidence)';
}

/* ------------------------------------------------------------ plan request */

/// A rough starting position for the AI planner.
///
/// The relay rounds latitude and longitude to two decimals (~1.1 km) before
/// they reach the model; the app should round them too rather than rely on it.
class PlanStart {
  /// Creates a start position.
  const PlanStart({required this.lat, required this.lon});

  /// Latitude in degrees, -90 to 90.
  final double lat;

  /// Longitude in degrees, -180 to 180.
  final double lon;

  /// Parses `{"lat": .., "lon": ..}`.
  factory PlanStart.fromJson(Map<String, Object?> json) =>
      PlanStart(lat: _reqDouble(json, 'lat'), lon: _reqDouble(json, 'lon'));

  /// Serialises to `{"lat": .., "lon": ..}`.
  Map<String, Object?> toJson() => <String, Object?>{'lat': lat, 'lon': lon};

  @override
  bool operator ==(Object other) =>
      other is PlanStart && other.lat == lat && other.lon == lon;

  @override
  int get hashCode => Object.hash(lat, lon);

  @override
  String toString() => 'PlanStart($lat, $lon)';
}

/// What the AI planner should know about the rider's situation.
class PlanContext {
  /// Creates a plan context.
  const PlanContext({this.start, this.startLabel, this.today});

  /// The rider's rough position.
  final PlanStart? start;

  /// A human-readable name for [start], e.g. `"Freiburg im Breisgau"`.
  final String? startLabel;

  /// Today's date as the rider sees it, e.g. `"Saturday, 12 September"`.
  final String? today;

  /// Parses a `context` object.
  factory PlanContext.fromJson(Map<String, Object?> json) {
    final start = _optObject(json, 'start');
    return PlanContext(
      start: start == null ? null : PlanStart.fromJson(start),
      startLabel: _optString(json, 'start_label'),
      today: _optString(json, 'today'),
    );
  }

  /// Serialises to a `context` object, omitting absent fields.
  Map<String, Object?> toJson() => <String, Object?>{
    if (start != null) 'start': start!.toJson(),
    if (startLabel != null) 'start_label': startLabel,
    if (today != null) 'today': today,
  };

  @override
  bool operator ==(Object other) =>
      other is PlanContext &&
      other.start == start &&
      other.startLabel == startLabel &&
      other.today == today;

  @override
  int get hashCode => Object.hash(start, startLabel, today);

  @override
  String toString() =>
      'PlanContext(start: $start, startLabel: $startLabel, today: $today)';
}

/// The fraction of a route that falls on each surface class.
///
/// Values are fractions of the total distance, 0 to 1; absent keys mean
/// "unknown", not zero.
class SurfaceMix {
  /// Creates a surface mix.
  const SurfaceMix({this.paved, this.gravel, this.unpaved});

  /// Fraction of the route on sealed surface.
  final double? paved;

  /// Fraction of the route on gravel.
  final double? gravel;

  /// Fraction of the route on other unpaved surface.
  final double? unpaved;

  /// Parses a `surface` object.
  factory SurfaceMix.fromJson(Map<String, Object?> json) => SurfaceMix(
    paved: _optDouble(json, 'paved'),
    gravel: _optDouble(json, 'gravel'),
    unpaved: _optDouble(json, 'unpaved'),
  );

  /// Serialises to a `surface` object, omitting absent fields.
  Map<String, Object?> toJson() => <String, Object?>{
    if (paved != null) 'paved': paved,
    if (gravel != null) 'gravel': gravel,
    if (unpaved != null) 'unpaved': unpaved,
  };

  @override
  bool operator ==(Object other) =>
      other is SurfaceMix &&
      other.paved == paved &&
      other.gravel == gravel &&
      other.unpaved == unpaved;

  @override
  int get hashCode => Object.hash(paved, gravel, unpaved);

  @override
  String toString() =>
      'SurfaceMix(paved: $paved, gravel: $gravel, unpaved: $unpaved)';
}

/// A description of an already computed route, for the `describe` step.
class RouteSummary {
  /// Creates a route summary.
  const RouteSummary({
    required this.distanceKm,
    required this.ascentM,
    this.surface = const SurfaceMix(),
    this.waypoints,
    this.highlights,
  });

  /// Total length in kilometres.
  final double distanceKm;

  /// Total climbing in metres.
  final double ascentM;

  /// How the distance splits across surface classes.
  final SurfaceMix surface;

  /// Up to 50 place names along the route, in order.
  final List<String>? waypoints;

  /// Up to 20 short notes about what makes the route interesting.
  final List<String>? highlights;

  /// Parses a `route_summary` object.
  factory RouteSummary.fromJson(Map<String, Object?> json) {
    final surface = _optObject(json, 'surface');
    return RouteSummary(
      distanceKm: _reqDouble(json, 'distance_km'),
      ascentM: _reqDouble(json, 'ascent_m'),
      surface: surface == null
          ? const SurfaceMix()
          : SurfaceMix.fromJson(surface),
      waypoints: _optStringList(json, 'waypoints'),
      highlights: _optStringList(json, 'highlights'),
    );
  }

  /// Serialises to a `route_summary` object, omitting absent lists.
  Map<String, Object?> toJson() => <String, Object?>{
    'distance_km': distanceKm,
    'ascent_m': ascentM,
    'surface': surface.toJson(),
    if (waypoints != null) 'waypoints': waypoints,
    if (highlights != null) 'highlights': highlights,
  };

  @override
  bool operator ==(Object other) =>
      other is RouteSummary &&
      other.distanceKm == distanceKm &&
      other.ascentM == ascentM &&
      other.surface == surface &&
      _listEquals(other.waypoints, waypoints) &&
      _listEquals(other.highlights, highlights);

  @override
  int get hashCode => Object.hash(
    distanceKm,
    ascentM,
    surface,
    waypoints == null ? null : Object.hashAll(waypoints!),
    highlights == null ? null : Object.hashAll(highlights!),
  );

  @override
  String toString() =>
      'RouteSummary(distanceKm: $distanceKm, '
      'ascentM: $ascentM, surface: $surface, waypoints: $waypoints, '
      'highlights: $highlights)';
}

/// Token usage reported by the relay in the `done` event of `/ai/plan`.
class PlanUsage {
  /// Creates a usage record.
  const PlanUsage({required this.inputTokens, required this.outputTokens});

  /// Prompt tokens billed. Wire key: `in`.
  final int inputTokens;

  /// Completion tokens billed. Wire key: `out`.
  final int outputTokens;

  /// Parses `{"in": .., "out": ..}`; missing counts become 0.
  factory PlanUsage.fromJson(Map<String, Object?> json) => PlanUsage(
    inputTokens: _optInt(json, 'in') ?? 0,
    outputTokens: _optInt(json, 'out') ?? 0,
  );

  /// Serialises to `{"in": .., "out": ..}`.
  Map<String, Object?> toJson() => <String, Object?>{
    'in': inputTokens,
    'out': outputTokens,
  };

  @override
  bool operator ==(Object other) =>
      other is PlanUsage &&
      other.inputTokens == inputTokens &&
      other.outputTokens == outputTokens;

  @override
  int get hashCode => Object.hash(inputTokens, outputTokens);

  @override
  String toString() => 'PlanUsage(in: $inputTokens, out: $outputTokens)';
}

/* ----------------------------------------------------------------- tokens */

/// The OAuth tokens Strava returned, as the relay hands them on.
///
/// [accessToken] and [refreshToken] are wrapped by the relay: opaque strings
/// only the relay can open, which the app stores as they are and sends back
/// in [RelayClient.tokenHeader] and to `/oauth/strava/refresh`. Everything
/// else is Strava's own.
class StravaTokens {
  /// Creates a Strava token set.
  const StravaTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    this.tokenType = 'Bearer',
    this.expiresIn,
    this.athlete,
  });

  /// The bearer token for Strava's API.
  final String accessToken;

  /// The token used to obtain the next access token.
  final String refreshToken;

  /// Absolute expiry as a Unix timestamp in seconds.
  final int expiresAt;

  /// Normally `"Bearer"`.
  final String tokenType;

  /// Seconds until expiry at the time of the response, when Strava sent it.
  final int? expiresIn;

  /// The athlete object Strava attaches to a first token exchange.
  ///
  /// Passed through as raw JSON; this package does not model Strava's athlete.
  final Map<String, Object?>? athlete;

  /// [expiresAt] as a `DateTime` in UTC.
  DateTime get expiresAtUtc =>
      DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000, isUtc: true);

  /// Whether the access token has expired, allowing [leeway] of clock skew.
  bool isExpired({Duration leeway = const Duration(minutes: 5)}) =>
      DateTime.now().toUtc().add(leeway).isAfter(expiresAtUtc);

  /// Parses Strava's token response.
  factory StravaTokens.fromJson(Map<String, Object?> json) => StravaTokens(
    accessToken: _reqString(json, 'access_token'),
    refreshToken: _reqString(json, 'refresh_token'),
    expiresAt:
        _optInt(json, 'expires_at') ??
        (throw const RelayFormatException('expires_at is missing')),
    tokenType: _optString(json, 'token_type') ?? 'Bearer',
    expiresIn: _optInt(json, 'expires_in'),
    athlete: _optObject(json, 'athlete'),
  );

  /// Serialises back to Strava's wire shape.
  Map<String, Object?> toJson() => <String, Object?>{
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'expires_at': expiresAt,
    'token_type': tokenType,
    if (expiresIn != null) 'expires_in': expiresIn,
    if (athlete != null) 'athlete': athlete,
  };

  @override
  bool operator ==(Object other) =>
      other is StravaTokens &&
      other.accessToken == accessToken &&
      other.refreshToken == refreshToken &&
      other.expiresAt == expiresAt &&
      other.tokenType == tokenType &&
      other.expiresIn == expiresIn;

  @override
  int get hashCode =>
      Object.hash(accessToken, refreshToken, expiresAt, tokenType, expiresIn);

  @override
  String toString() =>
      'StravaTokens(expiresAt: $expiresAt, '
      'athlete: ${athlete == null ? 'none' : athlete!['id']})';
}

/// The OAuth tokens Ride with GPS returned, as the relay hands them on.
///
/// [accessToken] is wrapped by the relay, like [StravaTokens.accessToken].
/// Ride with GPS access tokens do not expire, so [refreshToken] and
/// [expiresAt] are usually absent and the relay has no refresh endpoint.
class RwgpsTokens {
  /// Creates a Ride with GPS token set.
  const RwgpsTokens({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
    this.tokenType = 'Bearer',
  });

  /// The bearer token for the Ride with GPS API.
  final String accessToken;

  /// Present only if Ride with GPS ever starts issuing one.
  final String? refreshToken;

  /// Absolute expiry as a Unix timestamp in seconds, when present.
  final int? expiresAt;

  /// Normally `"Bearer"`.
  final String tokenType;

  /// [expiresAt] as a UTC `DateTime`, or `null` when the token never expires.
  DateTime? get expiresAtUtc => expiresAt == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(expiresAt! * 1000, isUtc: true);

  /// Parses the Ride with GPS token response.
  factory RwgpsTokens.fromJson(Map<String, Object?> json) => RwgpsTokens(
    accessToken: _reqString(json, 'access_token'),
    refreshToken: _optString(json, 'refresh_token'),
    expiresAt: _optInt(json, 'expires_at'),
    tokenType: _optString(json, 'token_type') ?? 'Bearer',
  );

  /// Serialises back to the wire shape, omitting absent fields.
  Map<String, Object?> toJson() => <String, Object?>{
    'access_token': accessToken,
    if (refreshToken != null) 'refresh_token': refreshToken,
    if (expiresAt != null) 'expires_at': expiresAt,
    'token_type': tokenType,
  };

  @override
  bool operator ==(Object other) =>
      other is RwgpsTokens &&
      other.accessToken == accessToken &&
      other.refreshToken == refreshToken &&
      other.expiresAt == expiresAt &&
      other.tokenType == tokenType;

  @override
  int get hashCode =>
      Object.hash(accessToken, refreshToken, expiresAt, tokenType);

  @override
  String toString() => 'RwgpsTokens(expiresAt: $expiresAt)';
}

/* ------------------------------------------------------------------ share */

/// The headline numbers stored alongside a shared GPX.
class ShareSummary {
  /// Creates a share summary.
  const ShareSummary({required this.distanceKm, this.ascentM, this.durationS});

  /// Total length in kilometres.
  final double distanceKm;

  /// Total climbing in metres, when known.
  final double? ascentM;

  /// Moving or elapsed time in seconds, when known.
  final int? durationS;

  /// Parses a `summary` object.
  factory ShareSummary.fromJson(Map<String, Object?> json) => ShareSummary(
    distanceKm: _reqDouble(json, 'distance_km'),
    ascentM: _optDouble(json, 'ascent_m'),
    durationS: _optInt(json, 'duration_s'),
  );

  /// Serialises to a `summary` object, omitting absent fields.
  Map<String, Object?> toJson() => <String, Object?>{
    'distance_km': distanceKm,
    if (ascentM != null) 'ascent_m': ascentM,
    if (durationS != null) 'duration_s': durationS,
  };

  @override
  bool operator ==(Object other) =>
      other is ShareSummary &&
      other.distanceKm == distanceKm &&
      other.ascentM == ascentM &&
      other.durationS == durationS;

  @override
  int get hashCode => Object.hash(distanceKm, ascentM, durationS);

  @override
  String toString() =>
      'ShareSummary(distanceKm: $distanceKm, '
      'ascentM: $ascentM, durationS: $durationS)';
}

/// What `POST /share` returns: the public link to a stored GPX.
class ShareLink {
  /// Creates a share link.
  const ShareLink({required this.id, required this.url, this.expiresAt});

  /// The opaque share id; the only capability guarding the stored GPX.
  final String id;

  /// The public page, e.g. `https://relay.velorki.com/s/<id>`.
  final String url;

  /// When the share is deleted, as a Unix timestamp in seconds.
  ///
  /// `null` when the relay did not say — the current relay omits the field and
  /// applies its own retention policy.
  final int? expiresAt;

  /// The GPX download URL, derived from [url].
  String get gpxUrl => '$url.gpx';

  /// [expiresAt] as a UTC `DateTime`, or `null` when unknown.
  DateTime? get expiresAtUtc => expiresAt == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(expiresAt! * 1000, isUtc: true);

  /// Parses the `POST /share` response.
  factory ShareLink.fromJson(Map<String, Object?> json) => ShareLink(
    id: _reqString(json, 'id'),
    url: _reqString(json, 'url'),
    expiresAt: _optInt(json, 'expires_at'),
  );

  /// Serialises back to the wire shape.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'url': url,
    if (expiresAt != null) 'expires_at': expiresAt,
  };

  @override
  bool operator ==(Object other) =>
      other is ShareLink &&
      other.id == id &&
      other.url == url &&
      other.expiresAt == expiresAt;

  @override
  int get hashCode => Object.hash(id, url, expiresAt);

  @override
  String toString() => 'ShareLink($id, $url, expiresAt: $expiresAt)';
}

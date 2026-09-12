import 'package:velorki_geo/velorki_geo.dart';

import 'routing_exception.dart';
import 'segment_message.dart';
import 'surface_stats.dart';

/// A computed route.
class RouteResult {
  /// Creates a route result.
  RouteResult({
    required this.geometry,
    required this.lengthM,
    required this.ascentM,
    required this.descentM,
    required this.messages,
    required this.raw,
    this.plainAscentM = 0,
    this.totalTime,
    this.energyJ,
    this.times = const <double>[],
    this.name,
    this.creator,
  });

  /// The route geometry, with elevation where the routing data had it.
  final List<TrackPoint> geometry;

  /// Route length in metres (BRouter's `track-length`).
  final double lengthM;

  /// Filtered ascent in metres (BRouter's `filtered ascend`), the figure a
  /// cyclist recognises.
  final double ascentM;

  /// Descent in metres.
  ///
  /// BRouter's GeoJSON carries no descent, so this is derived as
  /// `ascent - (lastElevation - firstElevation)` and clamped at zero — the
  /// identity that makes ascent, descent and net gain consistent.
  final double descentM;

  /// Unfiltered ascent in metres (BRouter's `plain-ascend`).
  final double plainAscentM;

  /// The `messages` table, one row per run of equally tagged way.
  final List<SegmentMessage> messages;

  /// The parsed response as it came in, for anything not modelled here.
  final Map<String, dynamic> raw;

  /// Estimated riding time, when the profile produced one.
  final Duration? totalTime;

  /// Estimated energy in joules, when the profile produced one.
  final double? energyJ;

  /// Seconds from the start for each geometry point, when the profile
  /// produced a time model. Same length as [geometry], or empty.
  final List<double> times;

  /// Track name from the response properties.
  final String? name;

  /// `creator` from the response properties, e.g. `BRouter-1.7.8`.
  final String? creator;

  SurfaceStats? _surfaceStats;

  /// Surface, cycleway and busy-road shares, computed on first use.
  SurfaceStats get surfaceStats =>
      _surfaceStats ??= SurfaceStats.fromMessages(messages, lengthM);

  /// The geometry as bare coordinates.
  List<LatLng> get positions =>
      geometry.map((p) => p.pos).toList(growable: false);

  /// The bounding box of the geometry, or `null` for an empty route.
  BoundingBox? get bounds =>
      geometry.isEmpty ? null : BoundingBox.fromPoints(positions);

  /// Parses BRouter's `format=geojson` answer.
  ///
  /// Expects a `FeatureCollection` whose first `LineString` feature is the
  /// track: coordinates are `[lon, lat]` or `[lon, lat, ele]`, properties hold
  /// `track-length`, `filtered ascend`, `plain-ascend`, `total-time`,
  /// `total-energy`, `messages` and `times`. Extra features (BRouter adds
  /// `Point` features when `exportWaypoints=1`) are ignored.
  ///
  /// Throws [RoutingException] with [RoutingErrorKind.invalid] when the
  /// document is not a BRouter GeoJSON track.
  factory RouteResult.fromGeoJson(Map<String, dynamic> json) {
    final features = json['features'];
    if (json['type'] != 'FeatureCollection' || features is! List) {
      throw const RoutingException(
        kind: RoutingErrorKind.invalid,
        message: 'not a GeoJSON FeatureCollection',
      );
    }
    Map<String, dynamic>? track;
    for (final f in features) {
      if (f is Map<String, dynamic> &&
          f['geometry'] is Map &&
          (f['geometry'] as Map)['type'] == 'LineString') {
        track = f;
        break;
      }
    }
    if (track == null) {
      throw const RoutingException(
        kind: RoutingErrorKind.invalid,
        message: 'GeoJSON has no LineString feature',
      );
    }

    final props = (track['properties'] is Map<String, dynamic>)
        ? track['properties'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final coords =
        ((track['geometry'] as Map)['coordinates'] as List?) ??
        const <dynamic>[];

    final geometry = <TrackPoint>[];
    for (final c in coords) {
      if (c is! List || c.length < 2) {
        throw RoutingException(
          kind: RoutingErrorKind.invalid,
          message: 'malformed coordinate $c',
        );
      }
      final lon = _numOrNull(c[0]);
      final lat = _numOrNull(c[1]);
      final ele = c.length > 2 ? _numOrNull(c[2]) : null;
      if (lon == null || lat == null) {
        throw RoutingException(
          kind: RoutingErrorKind.invalid,
          message: 'malformed coordinate $c',
        );
      }
      geometry.add(TrackPoint(LatLng(lat, lon), ele: ele));
    }

    final messages = props['messages'] is List
        ? _parseMessages(props['messages'] as List)
        : const <SegmentMessage>[];

    final ascent = _numOr(props['filtered ascend'], 0);
    final times = props['times'] is List
        ? (props['times'] as List)
              .map((t) => _numOr(t, 0))
              .toList(growable: false)
        : const <double>[];
    final totalSeconds = _numOrNull(props['total-time']);

    return RouteResult(
      geometry: geometry,
      lengthM: _numOr(props['track-length'], 0),
      ascentM: ascent,
      descentM: _descent(geometry, ascent),
      plainAscentM: _numOr(props['plain-ascend'], 0),
      messages: messages,
      raw: json,
      totalTime: totalSeconds == null
          ? null
          : Duration(milliseconds: (totalSeconds * 1000).round()),
      energyJ: _numOrNull(props['total-energy']),
      times: times,
      name: props['name']?.toString(),
      creator: props['creator']?.toString(),
    );
  }

  static List<SegmentMessage> _parseMessages(List<dynamic> rows) {
    try {
      return SegmentMessage.parseTable(rows);
    } on FormatException catch (e) {
      throw RoutingException(
        kind: RoutingErrorKind.invalid,
        message: 'malformed messages table: ${e.message}',
        cause: e,
      );
    }
  }

  static double _descent(List<TrackPoint> geometry, double ascent) {
    double? first;
    double? last;
    for (final p in geometry) {
      if (p.ele == null) continue;
      first ??= p.ele;
      last = p.ele;
    }
    if (first == null || last == null) return 0;
    final descent = ascent - (last - first);
    return descent > 0 ? descent : 0;
  }

  static double? _numOrNull(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().trim());
  }

  static double _numOr(Object? v, double fallback) => _numOrNull(v) ?? fallback;

  @override
  String toString() =>
      'RouteResult(${geometry.length} pts, '
      '${(lengthM / 1000).toStringAsFixed(2)} km, '
      '+${ascentM.round()} m / -${descentM.round()} m)';
}

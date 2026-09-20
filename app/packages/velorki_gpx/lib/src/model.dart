import 'package:velorki_geo/velorki_geo.dart';

/// Per-point sensor values read from a Garmin `TrackPointExtension` block.
///
/// GPX itself has no place for heart rate, cadence or temperature, so every
/// recorder writes them into `<extensions>` using Garmin's
/// `TrackPointExtension` schema. The decoder accepts the `gpxtpx:`, `gpxx:`
/// and `ns3:` prefixes, no prefix at all, and the flattened form where the
/// sensor elements sit directly under `<extensions>`.
class GpxExtensions {
  /// Creates an extension record. All fields are optional; a record where
  /// every field is `null` is considered [isEmpty] and is dropped by the
  /// decoder.
  const GpxExtensions({this.heartRate, this.cadence, this.temperatureC});

  /// Heart rate in beats per minute (`gpxtpx:hr`), if present.
  final int? heartRate;

  /// Cadence in revolutions per minute (`gpxtpx:cad`), if present.
  final int? cadence;

  /// Air temperature in degrees Celsius (`gpxtpx:atemp`), if present.
  final double? temperatureC;

  /// Whether this record carries no value at all.
  bool get isEmpty =>
      heartRate == null && cadence == null && temperatureC == null;

  /// Whether this record carries at least one value.
  bool get isNotEmpty => !isEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GpxExtensions &&
          other.heartRate == heartRate &&
          other.cadence == cadence &&
          other.temperatureC == temperatureC;

  @override
  int get hashCode => Object.hash(heartRate, cadence, temperatureC);

  @override
  String toString() =>
      'GpxExtensions(hr: $heartRate, cad: $cadence, temp: $temperatureC)';
}

/// A `<wpt>`: a named point of interest, not part of a track or route.
class GpxWaypoint {
  /// Creates a waypoint at [pos].
  const GpxWaypoint(
    this.pos, {
    this.ele,
    this.name,
    this.description,
    this.symbol,
    this.type,
    this.time,
    this.comment,
  });

  /// Where the waypoint is.
  final LatLng pos;

  /// Elevation in metres, if the source gave one.
  final double? ele;

  /// `<name>`: the label shown for the waypoint.
  final String? name;

  /// `<desc>`: a longer description.
  final String? description;

  /// `<sym>`: the icon name the source suggests, e.g. `Water Source`.
  final String? symbol;

  /// `<type>`: a free-form classification, e.g. `food`.
  final String? type;

  /// `<time>`: when the waypoint was recorded, in UTC after decoding.
  final DateTime? time;

  /// `<cmt>`: a short comment; Ride with GPS puts its category here
  /// (`caution`, `water`).
  final String? comment;

  /// Latitude shortcut.
  double get lat => pos.lat;

  /// Longitude shortcut.
  double get lon => pos.lon;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GpxWaypoint &&
          other.pos == pos &&
          other.ele == ele &&
          other.name == name &&
          other.description == description &&
          other.symbol == symbol &&
          other.type == type &&
          other.time == time;

  @override
  int get hashCode =>
      Object.hash(pos, ele, name, description, symbol, type, time);

  @override
  String toString() => 'GpxWaypoint($pos, name: $name, sym: $symbol)';
}

/// A `<rte>`: a planned path as an ordered list of turn points.
///
/// Routes have no segments; a route point is just a [TrackPoint] whose
/// [TrackPoint.time] is usually `null`.
class GpxRoute {
  /// Creates a route.
  const GpxRoute({this.name, this.description, this.points = const []});

  /// `<name>` of the route.
  final String? name;

  /// `<desc>` of the route.
  final String? description;

  /// The route points, in order.
  final List<TrackPoint> points;

  @override
  String toString() => 'GpxRoute($name, ${points.length} points)';
}

/// A `<trk>`: a recorded path, split into one or more `<trkseg>`.
///
/// GPX starts a new segment wherever recording was interrupted, so the
/// segments are kept as they were found. Use [points] when the gaps do not
/// matter.
///
/// [TrackPoint] has no room for sensor data, so the Garmin
/// `TrackPointExtension` values live in [segmentExtensions], which mirrors
/// [segments] exactly: `segmentExtensions[s].length == segments[s].length`,
/// and entry `[s][i]` belongs to point `segments[s][i]`. A `null` entry means
/// that point had no extensions. Read them through [extensionsIn] (segment
/// plus index) or [extensionsAt] (index into the flattened [points]) rather
/// than indexing the lists yourself.
class GpxTrack {
  /// Creates a track.
  ///
  /// [segmentExtensions] must either be empty (no sensor data at all) or have
  /// the same shape as [segments]; the decoder always builds it that way.
  const GpxTrack({
    this.name,
    this.description,
    this.type,
    this.segments = const [],
    this.segmentExtensions = const [],
  });

  /// `<name>` of the track.
  final String? name;

  /// `<desc>` of the track.
  final String? description;

  /// `<type>` of the track. Strava writes an activity id here (`1` for a
  /// ride), other tools write words like `cycling`.
  final String? type;

  /// The track segments, in order, each an ordered list of points.
  final List<List<TrackPoint>> segments;

  /// Sensor data parallel to [segments]; see the class documentation.
  final List<List<GpxExtensions?>> segmentExtensions;

  /// All points of all segments, flattened in order.
  ///
  /// Recomputed on every call, so hold on to the result in a loop.
  List<TrackPoint> get points => [for (final s in segments) ...s];

  /// All extension records, flattened in the same order as [points].
  ///
  /// Empty when the track carried no sensor data at all.
  List<GpxExtensions?> get pointExtensions => [
    for (final s in segmentExtensions) ...s,
  ];

  /// The number of points across all segments.
  int get pointCount =>
      segments.fold(0, (sum, segment) => sum + segment.length);

  /// The extensions of point [pointIndex] in segment [segmentIndex], or `null`
  /// when that point has none or the indices are out of range.
  GpxExtensions? extensionsIn(int segmentIndex, int pointIndex) {
    if (segmentIndex < 0 || segmentIndex >= segmentExtensions.length) {
      return null;
    }
    final segment = segmentExtensions[segmentIndex];
    if (pointIndex < 0 || pointIndex >= segment.length) {
      return null;
    }
    return segment[pointIndex];
  }

  /// The extensions of the point at [index] in the flattened [points], or
  /// `null` when that point has none or [index] is out of range.
  GpxExtensions? extensionsAt(int index) {
    if (index < 0) {
      return null;
    }
    var remaining = index;
    for (var s = 0; s < segments.length; s++) {
      final length = segments[s].length;
      if (remaining < length) {
        return extensionsIn(s, remaining);
      }
      remaining -= length;
    }
    return null;
  }

  @override
  String toString() =>
      'GpxTrack($name, ${segments.length} segments, $pointCount points)';
}

/// A decoded GPX file: its metadata plus everything it contained.
class GpxDocument {
  /// Creates a document.
  const GpxDocument({
    this.name,
    this.description,
    this.creator,
    this.tracks = const [],
    this.routes = const [],
    this.waypoints = const [],
  });

  /// `<metadata><name>` of the file, if it had one.
  final String? name;

  /// `<metadata><desc>` of the file, if it had one.
  final String? description;

  /// The `creator` attribute of the root element, e.g. `komoot.de` or
  /// `StravaGPX`. `null` when the file did not set it.
  final String? creator;

  /// The `<trk>` elements, in document order.
  final List<GpxTrack> tracks;

  /// The `<rte>` elements, in document order.
  final List<GpxRoute> routes;

  /// The top level `<wpt>` elements, in document order.
  final List<GpxWaypoint> waypoints;

  /// Whether the file contained no geometry at all.
  bool get isEmpty => tracks.isEmpty && routes.isEmpty && waypoints.isEmpty;

  @override
  String toString() =>
      'GpxDocument($name, creator: $creator, ${tracks.length} tracks, '
      '${routes.length} routes, ${waypoints.length} waypoints)';
}

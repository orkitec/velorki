import 'dart:convert';
import 'dart:typed_data';

import 'package:velorki_brouter/velorki_brouter.dart' show SurfaceStats;
import 'package:velorki_geo/velorki_geo.dart';

import '../../../core/geo/ride_stats.dart';
import 'ride_upload.dart';

/// One interval during which the recording was paused.
class RidePause {
  /// Creates a pause.
  const RidePause({required this.startedAt, this.endedAt, this.seam = false});

  /// Reads a pause back from [toJson].
  factory RidePause.fromJson(Map<String, Object?> json) => RidePause(
    startedAt:
        DateTime.tryParse(json['start'] as String? ?? '')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    endedAt: DateTime.tryParse(json['end'] as String? ?? '')?.toUtc(),
    seam: json['seam'] as bool? ?? false,
  );

  /// When the rider (or auto-pause) stopped the recording.
  final DateTime startedAt;

  /// When it continued; `null` while the pause is still open.
  final DateTime? endedAt;

  /// Whether this pause is the gap a continued ride was picked up across:
  /// from the moment the ride was finished to the moment "Continue this ride"
  /// handed it back to the recorder.
  ///
  /// The flag is kept in the row because the statistics are recomputed from
  /// the whole track every time the ride is saved, and a seam has to stay a
  /// break in them however short it was — see [StatsBreak].
  final bool seam;

  /// How long the pause lasted, zero while it is still open.
  Duration get duration =>
      endedAt == null ? Duration.zero : endedAt!.difference(startedAt);

  /// This pause as a break in the statistics, or `null` while it is open or
  /// when it is an ordinary pause, which the gap between the fixes already
  /// shows.
  StatsBreak? get asStatsBreak => !seam || endedAt == null
      ? null
      : StatsBreak(startedAt: startedAt, endedAt: endedAt!);

  /// A copy that ends at [endedAt].
  RidePause ending(DateTime endedAt) =>
      RidePause(startedAt: startedAt, endedAt: endedAt, seam: seam);

  /// This pause as JSON, for the `pauses_json` column.
  Map<String, Object?> toJson() => <String, Object?>{
    'start': startedAt.toUtc().toIso8601String(),
    if (endedAt != null) 'end': endedAt!.toUtc().toIso8601String(),
    if (seam) 'seam': true,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RidePause &&
          other.startedAt == startedAt &&
          other.endedAt == endedAt &&
          other.seam == seam;

  @override
  int get hashCode => Object.hash(startedAt, endedAt, seam);

  @override
  String toString() =>
      'RidePause($startedAt → $endedAt${seam ? ', seam' : ''})';
}

/// The breaks among [pauses]: every seam a continued ride was picked up
/// across, in the form the statistics take.
List<StatsBreak> statsBreaksOf(List<RidePause> pauses) => <StatsBreak>[
  for (final pause in pauses)
    if (pause.asStatsBreak case final StatsBreak gap) gap,
];

/// The `pauses_json` column.
String encodeRidePauses(List<RidePause> pauses) =>
    jsonEncode(pauses.map((p) => p.toJson()).toList());

/// Parses the `pauses_json` column; anything unreadable yields no pauses
/// rather than an unopenable ride.
List<RidePause> decodeRidePauses(String? json) {
  if (json == null || json.isEmpty) return const <RidePause>[];
  Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException {
    return const <RidePause>[];
  }
  if (decoded is! List) return const <RidePause>[];
  return <RidePause>[
    for (final entry in decoded)
      if (entry is Map<String, Object?>) RidePause.fromJson(entry),
  ];
}

/// What the `surface_stats_json` column of a ride holds.
///
/// Null until the ride was ever matched against the routing tiles; [stats]
/// once it was; [unavailable] once matching failed for a reason a retry
/// would not change, so the page does not route the track again on every
/// open. A ride whose area had no tiles is not recorded at all: it is tried
/// again once they are there.
class RideSurfaceCache {
  /// Creates the cache entry.
  const RideSurfaceCache({this.stats, this.unavailable = false});

  /// The marker for a track the map could not follow.
  static const RideSurfaceCache unmatched = RideSurfaceCache(unavailable: true);

  /// The matched surface breakdown, when there is one.
  final SurfaceStats? stats;

  /// Whether matching failed for good.
  final bool unavailable;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RideSurfaceCache &&
          other.stats == stats &&
          other.unavailable == unavailable;

  @override
  int get hashCode => Object.hash(stats, unavailable);

  @override
  String toString() => unavailable ? 'RideSurfaceCache.unmatched' : '$stats';
}

/// The `surface_stats_json` column: the statistics as `SurfaceStats.toJson`,
/// or `{"unavailable": true}` for a track that could not be matched.
String encodeRideSurface(RideSurfaceCache cache) => jsonEncode(
  cache.unavailable
      ? const <String, Object?>{'unavailable': true}
      : cache.stats?.toJson() ?? const <String, Object?>{},
);

/// Parses the `surface_stats_json` column; null or anything unreadable
/// means "not matched yet", which is safe: the page then matches again.
RideSurfaceCache? decodeRideSurface(String? json) {
  if (json == null || json.isEmpty) return null;
  Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, dynamic>) return null;
  if (decoded['unavailable'] == true) return RideSurfaceCache.unmatched;
  final stats = SurfaceStats.fromJson(decoded);
  return stats.totalLengthM > 0 ? RideSurfaceCache(stats: stats) : null;
}

/// A finished ride, as the app works with it.
///
/// The geometry stays packed until something actually needs the points, which
/// keeps the rides list cheap however long the rides are.
class Ride {
  /// Creates a ride.
  Ride({
    required this.id,
    required this.name,
    required this.startedAt,
    required this.endedAt,
    required this.stats,
    required this.geometry,
    this.routeId,
    this.pauses = const <RidePause>[],
    this.uploads = const <String, RideUpload>{},
    this.notes,
    this.surface,
    this.laps = const <RideLap>[],
    this.deviceTotals,
    this.temperaturesC = const <double?>[],
    this.sourceFormat,
    this.creator,
  });

  /// The format of the file the ride was imported from (`gpx`, `fit`);
  /// `null` for a ride recorded here.
  final String? sourceFormat;

  /// Who wrote that file: its creator, or the device's maker.
  final String? creator;

  /// The laps the recording device cut, for a ride that came from a file
  /// with them; empty for a ride recorded here. They stand in for the
  /// fixed-length splits on the ride's page.
  final List<RideLap> laps;

  /// The totals the recording device wrote, for a ride from a file; shown
  /// beside the app's own figures where the two differ.
  final DeviceTotals? deviceTotals;

  /// The temperature per point, `null` where the point had none; empty for
  /// a ride without a temperature at all.
  final List<double?> temperaturesC;

  /// Row id, a uuid.
  final String id;

  /// The name shown in the library; editable.
  final String name;

  /// When the recording started.
  final DateTime startedAt;

  /// When it was finished.
  final DateTime endedAt;

  /// Distance, times, ascent and speeds.
  final RideStats stats;

  /// The packed track, including timestamps.
  final Uint8List geometry;

  /// The route this ride followed, when it followed one.
  final String? routeId;

  /// Every pause, in order.
  final List<RidePause> pauses;

  /// Where this ride was uploaded to, keyed by [IntegrationService.id].
  final Map<String, RideUpload> uploads;

  /// Free text the rider added.
  final String? notes;

  /// What the routing tiles said about the surface, once the ride was matched
  /// against them; null until then.
  final RideSurfaceCache? surface;

  /// The matched surface breakdown, when there is one.
  SurfaceStats? get surfaceStats => surface?.stats;

  List<TrackPoint>? _points;

  /// The track points, decoded once and kept.
  List<TrackPoint> get points =>
      _points ??= geometry.isEmpty ? const <TrackPoint>[] : _decode();

  /// The positions of [points], for the map.
  List<LatLng> get positions =>
      points.map((p) => p.pos).toList(growable: false);

  /// The extent of the track, or `null` when there is nothing to show.
  BoundingBox? get bounds {
    final track = positions;
    return track.isEmpty ? null : BoundingBox.fromPoints(track);
  }

  /// The upload record for the service [serviceId], when there is one.
  RideUpload? uploadFor(String serviceId) => uploads[serviceId];

  /// A copy with the given fields replaced.
  Ride copyWith({
    String? name,
    String? notes,
    Map<String, RideUpload>? uploads,
    RideSurfaceCache? surface,
  }) => Ride(
    id: id,
    name: name ?? this.name,
    startedAt: startedAt,
    endedAt: endedAt,
    stats: stats,
    geometry: geometry,
    routeId: routeId,
    pauses: pauses,
    uploads: uploads ?? this.uploads,
    notes: notes ?? this.notes,
    surface: surface ?? this.surface,
    laps: laps,
    deviceTotals: deviceTotals,
    temperaturesC: temperaturesC,
    sourceFormat: sourceFormat,
    creator: creator,
  );

  List<TrackPoint> _decode() {
    try {
      return PackedTrack.decode(geometry);
    } on FormatException {
      return const <TrackPoint>[];
    }
  }

  @override
  String toString() => 'Ride($id, $name, $stats)';
}

/// One lap as the recording device cut it.
class RideLap {
  /// Creates a lap.
  const RideLap({
    required this.startedAt,
    required this.endedAt,
    this.distanceM,
    this.movingTime,
    this.calories,
  });

  /// One entry of the `laps_json` column.
  factory RideLap.fromJson(Map<String, Object?> json) => RideLap(
    startedAt:
        DateTime.tryParse(json['start'] as String? ?? '')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    endedAt:
        DateTime.tryParse(json['end'] as String? ?? '')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    distanceM: (json['distance'] as num?)?.toDouble(),
    movingTime: json['moving'] is num
        ? Duration(milliseconds: ((json['moving'] as num) * 1000).round())
        : null,
    calories: (json['calories'] as num?)?.toInt(),
  );

  /// When the lap began.
  final DateTime startedAt;

  /// When it ended.
  final DateTime endedAt;

  /// Its distance in metres, as the device summed it.
  final double? distanceM;

  /// Its moving time, as the device timed it.
  final Duration? movingTime;

  /// Its calories, as the device estimated them.
  final int? calories;

  /// One entry of the `laps_json` column.
  Map<String, Object?> toJson() => <String, Object?>{
    'start': startedAt.toUtc().toIso8601String(),
    'end': endedAt.toUtc().toIso8601String(),
    if (distanceM != null) 'distance': distanceM,
    if (movingTime != null) 'moving': movingTime!.inMilliseconds / 1000,
    if (calories != null) 'calories': calories,
  };
}

/// The totals a recording device wrote for a ride.
class DeviceTotals {
  /// Creates the totals.
  const DeviceTotals({
    this.distanceM,
    this.movingTime,
    this.elapsedTime,
    this.calories,
    this.ascentM,
    this.descentM,
  });

  /// The `device_totals_json` column.
  factory DeviceTotals.fromJson(Map<String, Object?> json) => DeviceTotals(
    distanceM: (json['distance'] as num?)?.toDouble(),
    movingTime: json['moving'] is num
        ? Duration(milliseconds: ((json['moving'] as num) * 1000).round())
        : null,
    elapsedTime: json['elapsed'] is num
        ? Duration(milliseconds: ((json['elapsed'] as num) * 1000).round())
        : null,
    calories: (json['calories'] as num?)?.toInt(),
    ascentM: (json['ascent'] as num?)?.toDouble(),
    descentM: (json['descent'] as num?)?.toDouble(),
  );

  /// Distance in metres.
  final double? distanceM;

  /// Moving time.
  final Duration? movingTime;

  /// Elapsed time.
  final Duration? elapsedTime;

  /// Calories.
  final int? calories;

  /// Ascent in metres.
  final double? ascentM;

  /// Descent in metres.
  final double? descentM;

  /// Whether any total is there at all.
  bool get isEmpty =>
      distanceM == null &&
      movingTime == null &&
      elapsedTime == null &&
      calories == null &&
      ascentM == null &&
      descentM == null;

  /// The `device_totals_json` column.
  Map<String, Object?> toJson() => <String, Object?>{
    if (distanceM != null) 'distance': distanceM,
    if (movingTime != null) 'moving': movingTime!.inMilliseconds / 1000,
    if (elapsedTime != null) 'elapsed': elapsedTime!.inMilliseconds / 1000,
    if (calories != null) 'calories': calories,
    if (ascentM != null) 'ascent': ascentM,
    if (descentM != null) 'descent': descentM,
  };
}

/// The `laps_json` column.
String encodeRideLaps(List<RideLap> laps) =>
    jsonEncode([for (final lap in laps) lap.toJson()]);

/// Parses the `laps_json` column; anything unreadable is no laps.
List<RideLap> decodeRideLaps(String? json) {
  if (json == null || json.isEmpty) return const <RideLap>[];
  try {
    final decoded = jsonDecode(json);
    if (decoded is! List) return const <RideLap>[];
    return [
      for (final entry in decoded)
        if (entry is Map<String, Object?>) RideLap.fromJson(entry),
    ];
  } on FormatException {
    return const <RideLap>[];
  }
}

/// The `device_totals_json` column.
String encodeDeviceTotals(DeviceTotals totals) => jsonEncode(totals.toJson());

/// Parses the `device_totals_json` column; anything unreadable is none.
DeviceTotals? decodeDeviceTotals(String? json) {
  if (json == null || json.isEmpty) return null;
  try {
    final decoded = jsonDecode(json);
    if (decoded is! Map<String, Object?>) return null;
    final totals = DeviceTotals.fromJson(decoded);
    return totals.isEmpty ? null : totals;
  } on FormatException {
    return null;
  }
}

/// The sentinel in the `temperatures` column for a point without one.
const int _noTemperature = -32768;

/// The `temperatures` column: one signed 16-bit tenth of a degree per point.
Uint8List encodeTemperatures(List<double?> temperaturesC) {
  final data = ByteData(temperaturesC.length * 2);
  for (var i = 0; i < temperaturesC.length; i++) {
    final t = temperaturesC[i];
    data.setInt16(
      i * 2,
      t == null || !t.isFinite
          ? _noTemperature
          : (t * 10).round().clamp(-32767, 32767),
      Endian.little,
    );
  }
  return data.buffer.asUint8List();
}

/// Parses the `temperatures` column; empty for none.
List<double?> decodeTemperatures(Uint8List? bytes) {
  if (bytes == null || bytes.length < 2) return const <double?>[];
  final data = ByteData.sublistView(bytes);
  return [
    for (var i = 0; i + 1 < bytes.length; i += 2)
      switch (data.getInt16(i, Endian.little)) {
        _noTemperature => null,
        final tenths => tenths / 10,
      },
  ];
}

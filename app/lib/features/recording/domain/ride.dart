import 'dart:convert';
import 'dart:typed_data';

import 'package:velorki_geo/velorki_geo.dart';

import '../../../core/geo/ride_stats.dart';

/// One interval during which the recording was paused.
class RidePause {
  /// Creates a pause.
  const RidePause({required this.startedAt, this.endedAt});

  /// Reads a pause back from [toJson].
  factory RidePause.fromJson(Map<String, Object?> json) => RidePause(
    startedAt:
        DateTime.tryParse(json['start'] as String? ?? '')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    endedAt: DateTime.tryParse(json['end'] as String? ?? '')?.toUtc(),
  );

  /// When the rider (or auto-pause) stopped the recording.
  final DateTime startedAt;

  /// When it continued; `null` while the pause is still open.
  final DateTime? endedAt;

  /// How long the pause lasted, zero while it is still open.
  Duration get duration =>
      endedAt == null ? Duration.zero : endedAt!.difference(startedAt);

  /// A copy that ends at [endedAt].
  RidePause ending(DateTime endedAt) =>
      RidePause(startedAt: startedAt, endedAt: endedAt);

  /// This pause as JSON, for the `pauses_json` column.
  Map<String, Object?> toJson() => <String, Object?>{
    'start': startedAt.toUtc().toIso8601String(),
    if (endedAt != null) 'end': endedAt!.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RidePause &&
          other.startedAt == startedAt &&
          other.endedAt == endedAt;

  @override
  int get hashCode => Object.hash(startedAt, endedAt);

  @override
  String toString() => 'RidePause($startedAt → $endedAt)';
}

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
    this.notes,
  });

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

  /// Free text the rider added.
  final String? notes;

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

  /// A copy with the given fields replaced.
  Ride copyWith({String? name, String? notes}) => Ride(
    id: id,
    name: name ?? this.name,
    startedAt: startedAt,
    endedAt: endedAt,
    stats: stats,
    geometry: geometry,
    routeId: routeId,
    pauses: pauses,
    notes: notes ?? this.notes,
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

import 'package:flutter/foundation.dart';

import 'recording_snapshot.dart';
import 'ride.dart';

/// What `recording_state.json` says: which ride is being recorded and how.
@immutable
class RecordingState {
  /// Creates a state.
  const RecordingState({
    required this.rideId,
    required this.startedAt,
    required this.status,
    this.routeId,
    this.pauses = const <RidePause>[],
  });

  /// Reads a state back from [toJson]; returns `null` when the map is not one.
  static RecordingState? fromJson(Map<String, Object?> json) {
    final rideId = json['rideId'];
    final startedAt = DateTime.tryParse(json['startedAt'] as String? ?? '');
    if (rideId is! String || rideId.isEmpty || startedAt == null) return null;
    final pauses = json['pauses'];
    return RecordingState(
      rideId: rideId,
      startedAt: startedAt.toUtc(),
      status: RecordingStatus.fromName(json['status'] as String?),
      routeId: json['routeId'] as String?,
      pauses: pauses is List
          ? <RidePause>[
              for (final entry in pauses)
                if (entry is Map<String, Object?>) RidePause.fromJson(entry),
            ]
          : const <RidePause>[],
    );
  }

  /// Id of the ride being recorded; also the journal's file name.
  final String rideId;

  /// When the recording started.
  final DateTime startedAt;

  /// Whether the recorder is active or paused.
  final RecordingStatus status;

  /// The saved route being followed, if any.
  final String? routeId;

  /// Every pause so far, the last one still open while paused.
  final List<RidePause> pauses;

  /// A copy with the given fields replaced.
  RecordingState copyWith({RecordingStatus? status, List<RidePause>? pauses}) =>
      RecordingState(
        rideId: rideId,
        startedAt: startedAt,
        status: status ?? this.status,
        routeId: routeId,
        pauses: pauses ?? this.pauses,
      );

  /// This state as JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'rideId': rideId,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'status': status.name,
    if (routeId != null) 'routeId': routeId,
    'pauses': pauses.map((p) => p.toJson()).toList(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecordingState &&
          other.rideId == rideId &&
          other.startedAt == startedAt &&
          other.status == status &&
          other.routeId == routeId &&
          listEquals(other.pauses, pauses);

  @override
  int get hashCode =>
      Object.hash(rideId, startedAt, status, routeId, Object.hashAll(pauses));

  @override
  String toString() =>
      'RecordingState($rideId, ${status.name}, started $startedAt)';
}

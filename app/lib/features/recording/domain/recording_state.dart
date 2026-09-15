import 'package:flutter/foundation.dart';

import '../../../core/geo/ride_stats.dart';
import 'gps_precision.dart';
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
    this.precision = GpsPrecision.normal,
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
      precision: GpsPrecision.fromName(json['precision'] as String?),
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
  ///
  /// A recording that continues an already saved ride starts with that ride's
  /// pauses plus one [RidePause.seam]: the stretch between the moment the ride
  /// was finished and the moment it was picked up again.
  final List<RidePause> pauses;

  /// Whether this recording continues an already saved ride, which is what a
  /// seam among the [pauses] says.
  bool get isContinuation => pauses.any((pause) => pause.seam);

  /// How hard the GPS is driven for this ride.
  ///
  /// Written down with the rest because the recorder that reads it may be the
  /// foreground service isolate, which has no access to the preferences the
  /// rider set the profile in: the state file is how the choice crosses over.
  final GpsPrecision precision;

  /// The seams, for the statistics: a segment across one counts neither
  /// distance nor moving time.
  List<StatsBreak> get statsBreaks => statsBreaksOf(pauses);

  /// A copy with the given fields replaced.
  RecordingState copyWith({
    RecordingStatus? status,
    List<RidePause>? pauses,
    GpsPrecision? precision,
  }) => RecordingState(
    rideId: rideId,
    startedAt: startedAt,
    status: status ?? this.status,
    routeId: routeId,
    pauses: pauses ?? this.pauses,
    precision: precision ?? this.precision,
  );

  /// This state as JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'rideId': rideId,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'status': status.name,
    if (routeId != null) 'routeId': routeId,
    'pauses': pauses.map((p) => p.toJson()).toList(),
    'precision': precision.name,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecordingState &&
          other.rideId == rideId &&
          other.startedAt == startedAt &&
          other.status == status &&
          other.routeId == routeId &&
          other.precision == precision &&
          listEquals(other.pauses, pauses);

  @override
  int get hashCode => Object.hash(
    rideId,
    startedAt,
    status,
    routeId,
    precision,
    Object.hashAll(pauses),
  );

  @override
  String toString() =>
      'RecordingState($rideId, ${status.name}, started $startedAt)';
}

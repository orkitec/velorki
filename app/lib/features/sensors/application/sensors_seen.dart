import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../recording/application/recording_controller.dart';
import '../../recording/domain/recording_snapshot.dart';

part 'sensors_seen.g.dart';

/// The last reading each kind of sensor gave during one ride.
///
/// A sensor that reported once and fell silent — a watch out of range, a strap
/// that slipped — keeps its tile on the record sheet, dimmed and marked, rather
/// than vanishing as if it had never been there. This is the memory behind
/// that: per ride, so the next ride starts with nothing.
@immutable
class SensorsSeenState {
  /// Creates the memory.
  const SensorsSeenState({
    this.rideId,
    this.heartRateBpm,
    this.cadenceRpm,
    this.powerW,
  });

  /// The ride the values belong to; `null` before any ride.
  final String? rideId;

  /// The last heart rate reported, or `null` while none has been.
  final int? heartRateBpm;

  /// The last cadence reported.
  final int? cadenceRpm;

  /// The last power reported.
  final int? powerW;

  /// Whether any sensor has reported during this ride.
  bool get any => heartRateBpm != null || cadenceRpm != null || powerW != null;

  /// This memory with the readings of [snapshot] folded in.
  SensorsSeenState absorb(RecordingSnapshot snapshot) {
    final same = snapshot.rideId == rideId;
    return SensorsSeenState(
      rideId: snapshot.rideId,
      heartRateBpm: snapshot.heartRateBpm ?? (same ? heartRateBpm : null),
      cadenceRpm: snapshot.cadenceRpm ?? (same ? cadenceRpm : null),
      powerW: snapshot.powerW ?? (same ? powerW : null),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SensorsSeenState &&
          other.rideId == rideId &&
          other.heartRateBpm == heartRateBpm &&
          other.cadenceRpm == cadenceRpm &&
          other.powerW == powerW;

  @override
  int get hashCode => Object.hash(rideId, heartRateBpm, cadenceRpm, powerW);
}

/// Follows the recorder and remembers what the sensors said this ride.
@Riverpod(keepAlive: true)
class SensorsSeen extends _$SensorsSeen {
  @override
  SensorsSeenState build() {
    ref.listen(recordingControllerProvider, (previous, next) {
      final snapshot = next.snapshot;
      if (snapshot == null) return;
      final absorbed = state.absorb(snapshot);
      if (absorbed != state) state = absorbed;
    });
    // Whatever the recorder has said before anybody asked counts too: the
    // sheet reads this provider only once a ride is showing, by which time
    // the first readings have been and gone.
    final current = ref.read(recordingControllerProvider).snapshot;
    return current == null
        ? const SensorsSeenState()
        : const SensorsSeenState().absorb(current);
  }
}

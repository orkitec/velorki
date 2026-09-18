import 'package:flutter/foundation.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../core/geo/ride_stats.dart';

/// What the recorder is doing.
enum RecordingStatus {
  /// Nothing is being recorded.
  idle,

  /// Fixes are being journalled.
  active,

  /// Journalling is suspended, by the user or by auto-pause.
  paused;

  /// Parses the value written to `recording_state.json`; anything unknown is
  /// read as [active] so a corrupt file never loses a ride.
  static RecordingStatus fromName(String? name) => switch (name) {
    'paused' => RecordingStatus.paused,
    'idle' => RecordingStatus.idle,
    _ => RecordingStatus.active,
  };

  /// Whether a recording is under way, paused or not.
  bool get isRecording => this != RecordingStatus.idle;
}

/// Key under which every message between the UI and the recording task carries
/// its kind.
const String recordingMessageKind = 'kind';

/// A [RecordingSnapshot] travelling from the recorder to the UI.
const String recordingSnapshotMessage = 'snapshot';

/// The recorder's acknowledgement that it has stopped and closed the journal.
const String recordingStoppedMessage = 'stopped';

/// A command travelling from the UI to the recorder.
const String recordingCommandMessage = 'command';

/// A `SensorSnapshot` travelling from the UI isolate, which owns the sensor
/// hub, to the recorder, which stamps it onto the fixes.
const String recordingSensorsMessage = 'sensors';

/// Key of the command name inside a [recordingCommandMessage].
const String recordingCommandKey = 'command';

/// Suspend journalling.
const String recordingCommandPause = 'pause';

/// Continue journalling.
const String recordingCommandResume = 'resume';

/// Finish the ride and close the journal.
const String recordingCommandStop = 'stop';

/// Send one snapshot right now, so a reattached UI is not blank for a second.
const String recordingCommandSync = 'sync';

/// One second of a ride, as the recorder sees it.
///
/// This is the only thing that crosses the isolate boundary on Android, so
/// every field survives [toMap]/[fromMap] as a plain JSON value.
@immutable
class RecordingSnapshot {
  /// Creates a snapshot.
  const RecordingSnapshot({
    required this.rideId,
    required this.status,
    required this.startedAt,
    this.autoPaused = false,
    this.distanceM = 0,
    this.elapsed = Duration.zero,
    this.moving = Duration.zero,
    this.speedMps = 0,
    this.avgSpeedMps = 0,
    this.maxSpeedMps = 0,
    this.ascentM = 0,
    this.descentM = 0,
    this.lastPosition,
    this.accuracyM,
    this.headingDeg,
    this.pointCount = 0,
    this.newPoints = const <LatLng>[],
    this.heartRateBpm,
    this.cadenceRpm,
    this.powerW,
    this.avgHeartRateBpm,
    this.maxHeartRateBpm,
    this.avgCadenceRpm,
    this.avgPowerW,
  });

  /// Builds a snapshot from [stats] plus the live state the statistics do not
  /// know about.
  factory RecordingSnapshot.fromStats({
    required String rideId,
    required RecordingStatus status,
    required DateTime startedAt,
    required RideStats stats,
    required Duration elapsed,
    bool autoPaused = false,
    double speedMps = 0,
    TrackPoint? lastPoint,
    List<LatLng> newPoints = const <LatLng>[],
    int? heartRateBpm,
    int? cadenceRpm,
    int? powerW,
  }) => RecordingSnapshot(
    rideId: rideId,
    status: status,
    startedAt: startedAt,
    autoPaused: autoPaused,
    distanceM: stats.distanceM,
    elapsed: elapsed,
    moving: stats.movingTime,
    speedMps: speedMps,
    avgSpeedMps: stats.avgSpeedMps,
    maxSpeedMps: stats.maxSpeedMps,
    ascentM: stats.ascentM,
    descentM: stats.descentM,
    lastPosition: lastPoint?.pos,
    accuracyM: lastPoint?.accuracyM,
    headingDeg: lastPoint?.headingDeg,
    pointCount: stats.pointCount,
    newPoints: newPoints,
    heartRateBpm: heartRateBpm,
    cadenceRpm: cadenceRpm,
    powerW: powerW,
    avgHeartRateBpm: stats.avgHeartRateBpm,
    maxHeartRateBpm: stats.maxHeartRateBpm,
    avgCadenceRpm: stats.avgCadenceRpm,
    avgPowerW: stats.avgPowerW,
  );

  /// Reads a snapshot back from [toMap].
  factory RecordingSnapshot.fromMap(Map<Object?, Object?> map) {
    double number(String key) => (map[key] as num? ?? 0).toDouble();
    final coordinates = (map['newPoints'] as List<Object?>? ?? const [])
        .map((v) => (v as num).toDouble())
        .toList(growable: false);
    final points = <LatLng>[
      for (var i = 0; i + 1 < coordinates.length; i += 2)
        LatLng(coordinates[i], coordinates[i + 1]),
    ];
    final lat = map['lat'] as num?;
    final lon = map['lon'] as num?;
    return RecordingSnapshot(
      rideId: map['rideId'] as String? ?? '',
      status: RecordingStatus.fromName(map['status'] as String?),
      startedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['startedAt'] as num? ?? 0).toInt(),
        isUtc: true,
      ),
      autoPaused: map['autoPaused'] as bool? ?? false,
      distanceM: number('distanceM'),
      elapsed: Duration(milliseconds: (map['elapsedMs'] as num? ?? 0).toInt()),
      moving: Duration(milliseconds: (map['movingMs'] as num? ?? 0).toInt()),
      speedMps: number('speedMps'),
      avgSpeedMps: number('avgSpeedMps'),
      maxSpeedMps: number('maxSpeedMps'),
      ascentM: number('ascentM'),
      descentM: number('descentM'),
      lastPosition: lat == null || lon == null
          ? null
          : LatLng(lat.toDouble(), lon.toDouble()),
      accuracyM: (map['accuracyM'] as num?)?.toDouble(),
      headingDeg: (map['headingDeg'] as num?)?.toDouble(),
      pointCount: (map['pointCount'] as num? ?? 0).toInt(),
      newPoints: points,
      heartRateBpm: (map['heartRateBpm'] as num?)?.toInt(),
      cadenceRpm: (map['cadenceRpm'] as num?)?.toInt(),
      powerW: (map['powerW'] as num?)?.toInt(),
      avgHeartRateBpm: (map['avgHeartRateBpm'] as num?)?.toInt(),
      maxHeartRateBpm: (map['maxHeartRateBpm'] as num?)?.toInt(),
      avgCadenceRpm: (map['avgCadenceRpm'] as num?)?.toInt(),
      avgPowerW: (map['avgPowerW'] as num?)?.toInt(),
    );
  }

  /// Id of the ride being recorded.
  final String rideId;

  /// Whether the recorder is active or paused.
  final RecordingStatus status;

  /// When the recording was started.
  final DateTime startedAt;

  /// Whether [status] is [RecordingStatus.paused] because the rider stopped
  /// moving rather than because they pressed pause.
  final bool autoPaused;

  /// Distance so far, in metres.
  final double distanceM;

  /// Wall-clock time since [startedAt].
  final Duration elapsed;

  /// Time spent above [movingSpeedThresholdMps].
  final Duration moving;

  /// Current speed in metres per second.
  final double speedMps;

  /// Distance over moving time, in metres per second.
  final double avgSpeedMps;

  /// Fastest speed seen, in metres per second.
  final double maxSpeedMps;

  /// Metres climbed.
  final double ascentM;

  /// Metres descended.
  final double descentM;

  /// The last fix, for the map puck.
  final LatLng? lastPosition;

  /// Accuracy of [lastPosition] in metres.
  final double? accuracyM;

  /// Course over ground in degrees, when the fix carried one.
  final double? headingDeg;

  /// How many fixes are in the journal.
  final int pointCount;

  /// The fixes accepted since the previous snapshot, so the UI can extend the
  /// track line without the whole track being sent every second.
  final List<LatLng> newPoints;

  /// Heart rate a sensor is reporting right now, `null` when none is or the
  /// last reading has gone stale.
  final int? heartRateBpm;

  /// Cadence a sensor is reporting right now.
  final int? cadenceRpm;

  /// Power a sensor is reporting right now.
  final int? powerW;

  /// Mean heart rate over the fixes that carried one.
  final int? avgHeartRateBpm;

  /// Highest heart rate seen so far.
  final int? maxHeartRateBpm;

  /// Mean cadence over the fixes that carried one.
  final int? avgCadenceRpm;

  /// Mean power over the fixes that carried one.
  final int? avgPowerW;

  /// Whether a sensor is reporting anything at all right now.
  bool get hasSensors =>
      heartRateBpm != null || cadenceRpm != null || powerW != null;

  /// Whether the user pressed pause, as opposed to auto-pause.
  bool get isManuallyPaused => status == RecordingStatus.paused && !autoPaused;

  /// This snapshot as a plain map, for `FlutterForegroundTask.sendDataToMain`.
  Map<String, Object?> toMap() => <String, Object?>{
    'rideId': rideId,
    'status': status.name,
    'startedAt': startedAt.toUtc().millisecondsSinceEpoch,
    'autoPaused': autoPaused,
    'distanceM': distanceM,
    'elapsedMs': elapsed.inMilliseconds,
    'movingMs': moving.inMilliseconds,
    'speedMps': speedMps,
    'avgSpeedMps': avgSpeedMps,
    'maxSpeedMps': maxSpeedMps,
    'ascentM': ascentM,
    'descentM': descentM,
    if (lastPosition != null) 'lat': lastPosition!.lat,
    if (lastPosition != null) 'lon': lastPosition!.lon,
    if (accuracyM != null) 'accuracyM': accuracyM,
    if (headingDeg != null) 'headingDeg': headingDeg,
    if (heartRateBpm != null) 'heartRateBpm': heartRateBpm,
    if (cadenceRpm != null) 'cadenceRpm': cadenceRpm,
    if (powerW != null) 'powerW': powerW,
    if (avgHeartRateBpm != null) 'avgHeartRateBpm': avgHeartRateBpm,
    if (maxHeartRateBpm != null) 'maxHeartRateBpm': maxHeartRateBpm,
    if (avgCadenceRpm != null) 'avgCadenceRpm': avgCadenceRpm,
    if (avgPowerW != null) 'avgPowerW': avgPowerW,
    'pointCount': pointCount,
    'newPoints': <double>[
      for (final point in newPoints) ...[point.lat, point.lon],
    ],
    recordingMessageKind: recordingSnapshotMessage,
  };

  @override
  String toString() =>
      'RecordingSnapshot($rideId, ${status.name}, '
      '${distanceM.toStringAsFixed(0)} m, $elapsed, $pointCount points)';
}

import 'package:flutter/foundation.dart';

import 'sensor_reading.dart';

/// Heart Rate service.
const String heartRateServiceUuid = '180d';

/// Heart Rate Measurement, the characteristic a strap notifies on.
const String heartRateMeasurementUuid = '2a37';

/// Cycling Speed and Cadence service.
const String cyclingSpeedCadenceServiceUuid = '1816';

/// CSC Measurement, the characteristic a wheel or crank sensor notifies on.
const String cscMeasurementUuid = '2a5b';

/// Cycling Power service.
const String cyclingPowerServiceUuid = '1818';

/// Cycling Power Measurement, the characteristic a power meter notifies on.
const String cyclingPowerMeasurementUuid = '2a63';

/// The three services Velorki scans for and connects to. Everything else a
/// rider owns — lights, radars, trainers — is none of its business.
const Set<String> bleSensorServiceUuids = <String>{
  heartRateServiceUuid,
  cyclingSpeedCadenceServiceUuid,
  cyclingPowerServiceUuid,
};

/// What a device with these services can measure.
///
/// A speed and cadence sensor is listed for both of its kinds even though most
/// are only one of the two: which half a sensor has is not in what it
/// advertises, and a magnet it does not have simply never reports. A power
/// meter counts its crank as well, which is why a rider who has one needs no
/// cadence sensor beside it.
Set<SensorKind> bleKindsForServices(Set<String> serviceUuids) => <SensorKind>{
  if (serviceUuids.contains(heartRateServiceUuid)) SensorKind.heartRate,
  if (serviceUuids.contains(cyclingSpeedCadenceServiceUuid)) ...<SensorKind>[
    SensorKind.speed,
    SensorKind.cadence,
  ],
  if (serviceUuids.contains(cyclingPowerServiceUuid)) ...<SensorKind>[
    SensorKind.power,
    SensorKind.cadence,
  ],
};

/// The wheel a speed sensor is assumed to be on, in millimetres: 700x25c,
/// which is what most road and gravel bikes roll on.
const int defaultWheelCircumferenceMm = 2105;

/// The smallest wheel the setting accepts — a 16" folder with a fat tyre.
const int minWheelCircumferenceMm = 900;

/// The largest — a 29" mountain bike wheel, with room to spare.
const int maxWheelCircumferenceMm = 2500;

/// The setting itself, in millimetres.
const String prefsWheelCircumferenceMm = 'sensors.ble.wheelMm';

/// How long a wheel may report no new revolution before it counts as standing
/// still.
///
/// A CSC sensor keeps notifying once a second with the event time it last saw,
/// so a stopped wheel is silence inside a stream of packets rather than
/// silence on the air. Three seconds is longer than the slowest wheel takes
/// for one turn and short enough that the tile does not hold a speed the rider
/// no longer has.
const Duration wheelStaleAfter = Duration(seconds: 3);

/// One beat count out of a Heart Rate Measurement notification.
///
/// Flags bit 0 chooses the width of the value; the energy expended and the
/// RR intervals that may follow it are not read, and neither are the
/// sensor-contact bits — a strap that says it has lost contact still reports
/// the last beat it saw, and the hub's own staleness is the better judge of
/// whether that is worth showing.
///
/// Returns `null` for a packet too short to hold what its flags promise.
int? parseHeartRateMeasurement(List<int> data) {
  if (data.length < 2) return null;
  final wide = data[0] & 0x01 != 0;
  if (!wide) return data[1] & 0xFF;
  if (data.length < 3) return null;
  return _uint16(data, 1);
}

/// One CSC Measurement notification, as the sensor's own counters.
///
/// Both pairs are cumulative and both event times are in 1/1024 s and wrap:
/// nothing here is a speed or a cadence yet. [CscTracker] turns two of these
/// into one.
@immutable
class CscMeasurement {
  /// Creates a measurement.
  const CscMeasurement({
    this.wheelRevolutions,
    this.wheelEventTime,
    this.crankRevolutions,
    this.crankEventTime,
  });

  /// Cumulative wheel revolutions, `null` when the sensor sent no wheel data.
  final int? wheelRevolutions;

  /// When the last wheel revolution was seen, in 1/1024 s.
  final int? wheelEventTime;

  /// Cumulative crank revolutions, `null` when the sensor sent no crank data.
  final int? crankRevolutions;

  /// When the last crank revolution was seen, in 1/1024 s.
  final int? crankEventTime;

  /// Whether the sensor reported a turning wheel.
  bool get hasWheel => wheelRevolutions != null;

  /// Whether the sensor reported a turning crank.
  bool get hasCrank => crankRevolutions != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CscMeasurement &&
          other.wheelRevolutions == wheelRevolutions &&
          other.wheelEventTime == wheelEventTime &&
          other.crankRevolutions == crankRevolutions &&
          other.crankEventTime == crankEventTime;

  @override
  int get hashCode => Object.hash(
    wheelRevolutions,
    wheelEventTime,
    crankRevolutions,
    crankEventTime,
  );

  @override
  String toString() =>
      'CscMeasurement(wheel: $wheelRevolutions @ $wheelEventTime, '
      'crank: $crankRevolutions @ $crankEventTime)';
}

/// One CSC Measurement notification.
///
/// Flags bit 0 means wheel data — a uint32 of revolutions and a uint16 event
/// time — and bit 1 means crank data, two uint16s, in that order. A sensor
/// sends one, the other or both, which is what tells a wheel magnet from a
/// crank magnet.
///
/// Returns `null` for a packet too short to hold what its flags promise.
CscMeasurement? parseCscMeasurement(List<int> data) {
  if (data.isEmpty) return null;
  final flags = data[0];
  final hasWheel = flags & 0x01 != 0;
  final hasCrank = flags & 0x02 != 0;
  var offset = 1;
  int? wheelRevolutions;
  int? wheelEventTime;
  if (hasWheel) {
    if (data.length < offset + 6) return null;
    wheelRevolutions = _uint32(data, offset);
    wheelEventTime = _uint16(data, offset + 4);
    offset += 6;
  }
  int? crankRevolutions;
  int? crankEventTime;
  if (hasCrank) {
    if (data.length < offset + 4) return null;
    crankRevolutions = _uint16(data, offset);
    crankEventTime = _uint16(data, offset + 2);
  }
  if (!hasWheel && !hasCrank) return null;
  return CscMeasurement(
    wheelRevolutions: wheelRevolutions,
    wheelEventTime: wheelEventTime,
    crankRevolutions: crankRevolutions,
    crankEventTime: crankEventTime,
  );
}

/// One Cycling Power Measurement notification: the watts, and the crank
/// counters when the meter keeps them.
@immutable
class CyclingPowerMeasurement {
  /// Creates a measurement.
  const CyclingPowerMeasurement({
    required this.powerW,
    this.crankRevolutions,
    this.crankEventTime,
  });

  /// Instantaneous power in watts. Signed: a meter that is being back-pedalled
  /// or zeroing itself reports less than nothing.
  final int powerW;

  /// Cumulative crank revolutions, `null` when the meter sent none.
  final int? crankRevolutions;

  /// When the last crank revolution was seen, in 1/1024 s.
  final int? crankEventTime;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CyclingPowerMeasurement &&
          other.powerW == powerW &&
          other.crankRevolutions == crankRevolutions &&
          other.crankEventTime == crankEventTime;

  @override
  int get hashCode => Object.hash(powerW, crankRevolutions, crankEventTime);

  @override
  String toString() =>
      'CyclingPowerMeasurement($powerW W, crank: $crankRevolutions @ '
      '$crankEventTime)';
}

/// One Cycling Power Measurement notification.
///
/// A uint16 of flags and a signed int16 of watts, then the optional fields in
/// the order the specification lists them. Only the crank revolutions are
/// wanted, and they sit behind three fields that may or may not be there, so
/// the offset has to be walked rather than guessed: pedal power balance
/// (bit 0, one byte), accumulated torque (bit 2, two) and wheel revolution
/// data (bit 4, six). Bits 1 and 3 carry no data of their own.
///
/// Returns `null` for a packet too short to hold what its flags promise.
CyclingPowerMeasurement? parseCyclingPowerMeasurement(List<int> data) {
  if (data.length < 4) return null;
  final flags = _uint16(data, 0);
  final powerW = _int16(data, 2);
  if (flags & 0x20 == 0) return CyclingPowerMeasurement(powerW: powerW);

  var offset = 4;
  if (flags & 0x01 != 0) offset += 1;
  if (flags & 0x04 != 0) offset += 2;
  if (flags & 0x10 != 0) offset += 6;
  if (data.length < offset + 4) return null;
  return CyclingPowerMeasurement(
    powerW: powerW,
    crankRevolutions: _uint16(data, offset),
    crankEventTime: _uint16(data, offset + 2),
  );
}

/// What two CSC notifications say once the difference between them is taken.
///
/// Either half may be `null`: a wheel-only sensor never reports a cadence, a
/// crank-only one never a speed, and a counter that has not moved since the
/// last packet reports nothing at all.
@immutable
class CscUpdate {
  /// Creates an update.
  const CscUpdate({this.speedMps, this.cadenceRpm});

  /// Ground speed in metres per second.
  final double? speedMps;

  /// Cadence in revolutions per minute.
  final double? cadenceRpm;

  /// Whether there is anything to report.
  bool get isEmpty => speedMps == null && cadenceRpm == null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CscUpdate &&
          other.speedMps == speedMps &&
          other.cadenceRpm == cadenceRpm;

  @override
  int get hashCode => Object.hash(speedMps, cadenceRpm);

  @override
  String toString() => 'CscUpdate(speed: $speedMps, cadence: $cadenceRpm)';
}

/// Turns a stream of CSC notifications from one sensor into speeds and
/// cadences.
///
/// The sensor counts; the difference between two counts is the measurement, so
/// one of these is kept per device for as long as it is connected. Three
/// things wrap and all three are handled by taking the difference in the
/// counter's own width: the event times are uint16 and go round every 64 s,
/// the wheel revolutions are uint32 and the crank revolutions uint16.
///
/// A packet whose event time has not moved carries no new revolution, so it
/// yields nothing — except for the wheel, which has to be told apart from a
/// wheel that has stopped: after [wheelStaleAfter] without a new event the
/// speed is reported as zero once, and then the sensor is left to fall silent
/// on its own.
class CscTracker {
  int? _wheelRevolutions;
  int? _wheelEventTime;
  int? _crankRevolutions;
  int? _crankEventTime;

  /// When the wheel event time last moved, for [wheelStaleAfter].
  DateTime? _wheelMovedAt;

  /// Whether the zero of a standing wheel has already been reported.
  bool _wheelStopped = false;

  /// Feeds one notification in. [at] is when it arrived, and only the stopped
  /// wheel is judged against it; everything else is derived from the sensor's
  /// own clock.
  ///
  /// Returns `null` when the packet was unreadable or held nothing new.
  CscUpdate? add(
    List<int> data, {
    required DateTime at,
    required double wheelCircumferenceM,
  }) {
    final measurement = parseCscMeasurement(data);
    if (measurement == null) return null;
    final update = CscUpdate(
      speedMps: _speed(
        measurement,
        at: at,
        circumferenceM: wheelCircumferenceM,
      ),
      cadenceRpm: _cadence(measurement),
    );
    return update.isEmpty ? null : update;
  }

  double? _speed(
    CscMeasurement measurement, {
    required DateTime at,
    required double circumferenceM,
  }) {
    final revolutions = measurement.wheelRevolutions;
    final eventTime = measurement.wheelEventTime;
    if (revolutions == null || eventTime == null) return null;
    final previousRevolutions = _wheelRevolutions;
    final previousEventTime = _wheelEventTime;
    _wheelRevolutions = revolutions;
    _wheelEventTime = eventTime;

    if (previousRevolutions == null || previousEventTime == null) {
      _wheelMovedAt = at;
      return null;
    }
    if (eventTime == previousEventTime) {
      final since = _wheelMovedAt;
      if (_wheelStopped || since == null) return null;
      if (at.difference(since) < wheelStaleAfter) return null;
      _wheelStopped = true;
      return 0;
    }
    _wheelMovedAt = at;
    _wheelStopped = false;
    final seconds = _ticks(eventTime, previousEventTime) / 1024;
    if (seconds <= 0) return null;
    final turns = (revolutions - previousRevolutions) & 0xFFFFFFFF;
    return turns * circumferenceM / seconds;
  }

  double? _cadence(CscMeasurement measurement) {
    final revolutions = measurement.crankRevolutions;
    final eventTime = measurement.crankEventTime;
    if (revolutions == null || eventTime == null) return null;
    final previousRevolutions = _crankRevolutions;
    final previousEventTime = _crankEventTime;
    _crankRevolutions = revolutions;
    _crankEventTime = eventTime;
    if (previousRevolutions == null || previousEventTime == null) return null;
    if (eventTime == previousEventTime) return null;
    return _rpm(
      revolutions: revolutions,
      previousRevolutions: previousRevolutions,
      eventTime: eventTime,
      previousEventTime: previousEventTime,
    );
  }
}

/// What a Cycling Power notification says: the watts it carries, and the
/// cadence derived from the crank counters when it has them.
@immutable
class CyclingPowerUpdate {
  /// Creates an update.
  const CyclingPowerUpdate({required this.powerW, this.cadenceRpm});

  /// Instantaneous power in watts.
  final int powerW;

  /// Cadence in revolutions per minute, `null` when the meter keeps no crank
  /// counters or the crank has not turned since the last packet.
  final double? cadenceRpm;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CyclingPowerUpdate &&
          other.powerW == powerW &&
          other.cadenceRpm == cadenceRpm;

  @override
  int get hashCode => Object.hash(powerW, cadenceRpm);

  @override
  String toString() => 'CyclingPowerUpdate($powerW W, cadence: $cadenceRpm)';
}

/// Turns a stream of Cycling Power notifications from one meter into watts and
/// cadences.
///
/// The watts are in every packet; the cadence is the difference between two
/// crank counters, the same arithmetic [CscTracker] does, which is why a power
/// meter that keeps them makes a separate cadence sensor pointless.
class CyclingPowerTracker {
  int? _crankRevolutions;
  int? _crankEventTime;

  /// Feeds one notification in. Returns `null` for an unreadable packet.
  CyclingPowerUpdate? add(List<int> data) {
    final measurement = parseCyclingPowerMeasurement(data);
    if (measurement == null) return null;
    return CyclingPowerUpdate(
      powerW: measurement.powerW,
      cadenceRpm: _cadence(measurement),
    );
  }

  double? _cadence(CyclingPowerMeasurement measurement) {
    final revolutions = measurement.crankRevolutions;
    final eventTime = measurement.crankEventTime;
    if (revolutions == null || eventTime == null) return null;
    final previousRevolutions = _crankRevolutions;
    final previousEventTime = _crankEventTime;
    _crankRevolutions = revolutions;
    _crankEventTime = eventTime;
    if (previousRevolutions == null || previousEventTime == null) return null;
    if (eventTime == previousEventTime) return null;
    return _rpm(
      revolutions: revolutions,
      previousRevolutions: previousRevolutions,
      eventTime: eventTime,
      previousEventTime: previousEventTime,
    );
  }
}

/// Crank revolutions per minute between two uint16 counters, both of which
/// wrap.
double? _rpm({
  required int revolutions,
  required int previousRevolutions,
  required int eventTime,
  required int previousEventTime,
}) {
  final seconds = _ticks(eventTime, previousEventTime) / 1024;
  if (seconds <= 0) return null;
  final turns = (revolutions - previousRevolutions) & 0xFFFF;
  return turns * 60 / seconds;
}

/// The 1/1024 s between two event times, over the wrap at 64 s.
int _ticks(int now, int previous) => (now - previous) & 0xFFFF;

int _uint16(List<int> data, int offset) =>
    (data[offset] & 0xFF) | ((data[offset + 1] & 0xFF) << 8);

int _int16(List<int> data, int offset) => ByteData.sublistView(
  Uint8List.fromList(data),
  offset,
  offset + 2,
).getInt16(0, Endian.little);

int _uint32(List<int> data, int offset) =>
    (data[offset] & 0xFF) |
    ((data[offset + 1] & 0xFF) << 8) |
    ((data[offset + 2] & 0xFF) << 16) |
    ((data[offset + 3] & 0xFF) << 24);

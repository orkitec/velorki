import 'dart:async';

import 'package:logging/logging.dart';

import '../domain/ble_profiles.dart';
import '../domain/sensor_reading.dart';
import '../domain/sensor_source.dart';
import 'ble_gateway.dart';
import 'paired_sensors.dart';

final Logger _log = Logger('velorki.sensors.ble');

/// What every Bluetooth source's [SensorSource.id] begins with, so the hub's
/// live source ids can be read back as device ids.
const String bleSensorSourceIdPrefix = 'ble:';

/// How long to wait before each attempt at getting a dropped device back.
///
/// A strap that slipped is back in a second; one that went out of range
/// behind a rider's back should not be retried at that rate for the rest of
/// the ride, so the wait grows and then settles at the last step, which is
/// what the connection goes on being retried at for as long as the device is
/// meant to be connected.
const List<Duration> bleReconnectBackoff = <Duration>[
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 5),
  Duration(seconds: 10),
];

/// The id a source for [deviceId] registers itself with.
String bleSensorSourceId(String deviceId) =>
    '$bleSensorSourceIdPrefix$deviceId';

/// One paired Bluetooth device, as a source.
///
/// It connects, discovers what the device actually has, subscribes to the
/// measurement characteristics that match the kinds it was paired for, and
/// turns every notification into readings through the parsers in
/// `ble_profiles.dart` — no plugin type gets this far. A device that drops is
/// reconnected to on [bleReconnectBackoff] for as long as the source is meant
/// to be connected, because a strap losing contact for a corner is the normal
/// case rather than the end of it.
class BleSensorSource implements SensorSource {
  /// Creates the source. Nothing is connected until [start].
  ///
  /// [wheelCircumferenceM] is asked again for every packet rather than fixed,
  /// so a rider who corrects the setting mid-ride is believed at once.
  BleSensorSource({
    required this.gateway,
    required this.device,
    required this.wheelCircumferenceM,
    this.onLinkChanged,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// The radio the device is reached over.
  final BleGateway gateway;

  /// What was paired: the id to connect to, and what it measures.
  final PairedSensor device;

  /// How far the bike rolls in one wheel turn, in metres.
  final double Function() wheelCircumferenceM;

  /// Called whenever [isConnected] may have changed, so a screen showing the
  /// link can follow it without polling.
  final void Function()? onLinkChanged;

  final DateTime Function() _clock;

  final StreamController<SensorReading> _readings =
      StreamController<SensorReading>.broadcast();

  /// The counters the last connection left behind. Replaced on every drop:
  /// the sensor's own counters are cumulative and its event times wrap every
  /// 64 s, so the difference across a gap in the link is not a measurement of
  /// anything.
  CscTracker _csc = CscTracker();
  CyclingPowerTracker _power = CyclingPowerTracker();

  final List<StreamSubscription<List<int>>> _notifications =
      <StreamSubscription<List<int>>>[];

  BleConnection? _connection;
  StreamSubscription<BleConnectionState>? _state;
  Timer? _retry;
  int _attempt = 0;

  /// Whether the source is meant to be connected right now.
  bool _wanted = false;

  /// Whether it is connected right now.
  bool _connected = false;

  @override
  String get id => bleSensorSourceId(device.id);

  @override
  String get name => device.name.isEmpty ? device.id : device.name;

  @override
  Set<SensorKind> get kinds => device.kinds;

  @override
  int get priority => bluetoothSensorPriority;

  @override
  Stream<SensorReading> get readings => _readings.stream;

  /// Whether the device is connected and reporting.
  bool get isConnected => _connected;

  /// Whether the source is trying to be connected, whether it is or not.
  bool get isStarted => _wanted;

  /// Connects and subscribes. Returns once the first attempt is over, whether
  /// it worked or not: a device that is not there is retried in the
  /// background rather than kept anyone waiting for.
  Future<void> start() async {
    if (_wanted) return;
    _wanted = true;
    _attempt = 0;
    await _connect();
  }

  /// Disconnects and closes the stream; the source cannot be started again.
  Future<void> dispose() async {
    _wanted = false;
    _retry?.cancel();
    _retry = null;
    await _drop();
    await _readings.close();
  }

  Future<void> _connect() async {
    if (!_wanted || _connection != null) return;
    try {
      final connection = await gateway.connect(device.id);
      if (!_wanted) {
        await connection.disconnect();
        return;
      }
      _connection = connection;
      _state = connection.connectionState.listen(
        (state) {
          if (state == BleConnectionState.disconnected) _onDropped();
        },
        onError: (Object error, StackTrace stackTrace) {
          _log.warning('ble ${device.id} state failed', error, stackTrace);
          _onDropped();
        },
      );
      final services = await connection.discoverServices();
      if (!_wanted) return;
      _connected = true;
      _attempt = 0;
      _subscribe(connection, services);
      onLinkChanged?.call();
    } on Object catch (error, stackTrace) {
      _log.info('ble ${device.id} could not connect', error, stackTrace);
      await _drop();
      _scheduleRetry();
    }
  }

  /// Subscribes to every measurement the device has and was paired for.
  void _subscribe(BleConnection connection, Set<String> services) {
    void listen(
      String serviceUuid,
      String characteristicUuid,
      void Function(List<int> data) onData,
    ) {
      if (!services.contains(serviceUuid)) return;
      _notifications.add(
        connection
            .notifications(serviceUuid, characteristicUuid)
            .listen(
              onData,
              onError: (Object error, StackTrace stackTrace) => _log.warning(
                'ble ${device.id} $characteristicUuid failed',
                error,
                stackTrace,
              ),
            ),
      );
    }

    if (kinds.contains(SensorKind.heartRate)) {
      listen(heartRateServiceUuid, heartRateMeasurementUuid, _onHeartRate);
    }
    if (kinds.contains(SensorKind.speed) ||
        kinds.contains(SensorKind.cadence)) {
      listen(cyclingSpeedCadenceServiceUuid, cscMeasurementUuid, _onCsc);
    }
    if (kinds.contains(SensorKind.power)) {
      listen(cyclingPowerServiceUuid, cyclingPowerMeasurementUuid, _onPower);
    }
  }

  void _onHeartRate(List<int> data) {
    final bpm = parseHeartRateMeasurement(data);
    // A strap that has lost the rider's chest reports zero rather than
    // nothing; that is no heart rate.
    if (bpm == null || bpm <= 0) return;
    _emit(SensorKind.heartRate, bpm.toDouble());
  }

  void _onCsc(List<int> data) {
    final update = _csc.add(
      data,
      at: _clock(),
      wheelCircumferenceM: wheelCircumferenceM(),
    );
    if (update == null) return;
    if (update.speedMps case final speed?) _emit(SensorKind.speed, speed);
    if (update.cadenceRpm case final cadence?) {
      _emit(SensorKind.cadence, cadence);
    }
  }

  void _onPower(List<int> data) {
    final update = _power.add(data);
    if (update == null) return;
    // Zero watts is a true reading — the rider is coasting — but the signed
    // field also goes negative while a meter zeroes itself or is turned
    // backwards, and that is not an effort.
    _emit(SensorKind.power, update.powerW < 0 ? 0 : update.powerW.toDouble());
    if (update.cadenceRpm case final cadence?) {
      _emit(SensorKind.cadence, cadence);
    }
  }

  void _emit(SensorKind kind, double value) {
    if (_readings.isClosed) return;
    _readings.add(
      SensorReading(
        kind: kind,
        value: value,
        at: _clock().toUtc(),
        sourceId: id,
      ),
    );
  }

  void _onDropped() {
    if (!_wanted || _connection == null) return;
    _log.info('ble ${device.id} dropped');
    unawaited(_drop().then((_) => _scheduleRetry()));
  }

  /// Lets go of the connection and everything hanging off it.
  Future<void> _drop() async {
    final was = _connected;
    _connected = false;
    _csc = CscTracker();
    _power = CyclingPowerTracker();
    final connection = _connection;
    _connection = null;
    // Cancelled rather than awaited: a drop is noticed from inside the state
    // stream's own callback, and waiting there for that subscription to
    // finish cancelling would be waiting for the event being handled to
    // finish being handled, which is this.
    unawaited(_state?.cancel());
    _state = null;
    for (final subscription in _notifications) {
      unawaited(subscription.cancel());
    }
    _notifications.clear();
    if (connection != null) await connection.disconnect();
    if (was) onLinkChanged?.call();
  }

  void _scheduleRetry() {
    if (!_wanted || _retry != null) return;
    final wait =
        bleReconnectBackoff[_attempt.clamp(0, bleReconnectBackoff.length - 1)];
    _attempt++;
    _retry = Timer(wait, () {
      _retry = null;
      unawaited(_connect());
    });
  }
}

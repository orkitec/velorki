import 'dart:async';

import '../domain/sensor_reading.dart';
import '../domain/sensor_source.dart';
import 'watch_gateway.dart';
import 'watch_protocol.dart';

/// The id [WatchSensorSource] registers itself with.
const String watchSensorSourceId = 'watch';

/// Heart rate off the rider's wrist.
///
/// A push rather than a poll: the watch app runs a workout session and sends
/// what its own sensor measures, about once a second, so this is the liveliest
/// source there is — which is what [watchSensorPriority] says. It takes over
/// from the health store the moment the watch app reports, and hands back to
/// it when the rider stops the workout or takes the watch off.
///
/// The reading keeps the watch's own timestamp rather than the moment the
/// message arrived: a message that waited for the phone's radio is still a
/// measurement of when it was taken.
class WatchSensorSource implements SensorSource {
  /// Creates the source over [gateway]. Nothing is read until [start].
  WatchSensorSource({required this.gateway});

  /// The link to the watch app.
  final WatchGateway gateway;

  final StreamController<SensorReading> _readings =
      StreamController<SensorReading>.broadcast();

  StreamSubscription<Map<String, Object?>>? _subscription;

  @override
  String get id => watchSensorSourceId;

  @override
  String get name => watchName;

  @override
  Set<SensorKind> get kinds => const <SensorKind>{SensorKind.heartRate};

  @override
  int get priority => watchSensorPriority;

  @override
  Stream<SensorReading> get readings => _readings.stream;

  /// Whether the source is listening to the watch.
  bool get isListening => _subscription != null;

  /// Starts listening to the watch's messages.
  void start() {
    if (_subscription != null) return;
    _subscription = gateway.messages.listen(handle);
  }

  /// Stops listening and closes the stream; the source cannot be started
  /// again.
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    await _readings.close();
  }

  /// Turns one message from the watch into a reading, if it is one.
  ///
  /// Public so a test can hand a message over without a gateway; the app only
  /// ever gets here through [start]. Everything else the watch sends — the
  /// buttons, the end of its workout — belongs to the bridge, and is ignored
  /// here.
  void handle(Map<String, Object?> message) {
    if (message[watchTypeKey] != watchHeartRateType) return;
    if (_readings.isClosed) return;
    final bpm = message[watchBpmKey];
    final at = message[watchAtKey];
    if (bpm is! num || at is! num) return;
    // A watch that reports nothing reports zero; that is no heart rate.
    if (bpm <= 0) return;
    _readings.add(
      SensorReading(
        kind: SensorKind.heartRate,
        value: bpm.toDouble(),
        at: DateTime.fromMillisecondsSinceEpoch(at.toInt(), isUtc: true),
        sourceId: id,
      ),
    );
  }
}

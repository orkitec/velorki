import 'sensor_reading.dart';

/// Priority of a paired watch: the closest thing to a chest strap most riders
/// own, and the only source that keeps measuring with the phone in a pocket.
const int watchSensorPriority = 3;

/// Priority of a Bluetooth sensor: a real strap or a crank, but one that drops
/// out whenever the rider leaves it behind.
const int bluetoothSensorPriority = 2;

/// Priority of a health store: yesterday's samples written by something else,
/// good enough only when nothing live is reporting.
const int healthSensorPriority = 1;

/// Anything that reports sensor readings.
///
/// One source per device or service, whatever the transport. The hub takes the
/// reading of the highest-[priority] source that is still reporting, so the
/// ranking is fixed here rather than at every call site: a watch (
/// [watchSensorPriority]) beats a Bluetooth sensor
/// ([bluetoothSensorPriority]), which beats a health store
/// ([healthSensorPriority]).
abstract interface class SensorSource {
  /// Stable identity of this source, unique among the registered ones.
  String get id;

  /// What to call it in the interface.
  String get name;

  /// What it can measure. A source may report fewer kinds than it claims —
  /// a combined strap whose cadence pod is missing, say.
  Set<SensorKind> get kinds;

  /// Everything it measures, as it measures it.
  Stream<SensorReading> get readings;

  /// How much this source is trusted over another reporting the same kind.
  int get priority;
}

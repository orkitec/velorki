import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../app/app_config.dart';
import '../domain/sensor_reading.dart';

final Logger _log = Logger('velorki.sensors.ble');

/// The devices the rider has paired, as a JSON list.
const String prefsPairedSensors = 'sensors.ble.devices';

/// One Bluetooth device the rider has paired with Velorki.
///
/// Pairing here is Velorki's own list, not the phone's: a strap is bonded to
/// nothing, and forgetting it removes a line from the preferences rather than
/// touching the operating system.
@immutable
class PairedSensor {
  /// Creates a paired device.
  const PairedSensor({
    required this.id,
    required this.name,
    required this.kinds,
  });

  /// Reads one back from [toJson]. Returns `null` for a row that no longer
  /// makes sense, which is how a preferences file from an older version is
  /// survived.
  static PairedSensor? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    return PairedSensor(
      id: id,
      name: json['name'] is String ? json['name'] as String : '',
      kinds: <SensorKind>{
        for (final kind in json['kinds'] as List<Object?>? ?? const [])
          for (final known in SensorKind.values)
            if (known.name == kind) known,
      },
    );
  }

  /// What the platform calls the device; what a connection is made to.
  final String id;

  /// What it calls itself, or what the rider renamed it to.
  final String name;

  /// What it was found to measure when it was paired.
  final Set<SensorKind> kinds;

  /// A copy with the named fields replaced.
  PairedSensor copyWith({String? name, Set<SensorKind>? kinds}) =>
      PairedSensor(id: id, name: name ?? this.name, kinds: kinds ?? this.kinds);

  /// This device as a plain map, for the preferences.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'kinds': <String>[for (final kind in kinds) kind.name],
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PairedSensor &&
          other.id == id &&
          other.name == name &&
          setEquals(other.kinds, kinds);

  @override
  int get hashCode => Object.hash(id, name, Object.hashAllUnordered(kinds));

  @override
  String toString() =>
      'PairedSensor($id "$name", ${<String>[for (final k in kinds) k.name]})';
}

/// The paired Bluetooth devices, kept in shared_preferences.
///
/// The key is removed rather than written empty once the last device is
/// forgotten, so an app that has never been to the Bluetooth screen holds
/// nothing at all — which is what makes the whole feature optional. Nothing
/// scans or connects while this list is empty.
class PairedSensorsController extends Notifier<List<PairedSensor>> {
  @override
  List<PairedSensor> build() {
    final stored = ref
        .watch(sharedPreferencesProvider)
        .getString(prefsPairedSensors);
    if (stored == null || stored.isEmpty) return const <PairedSensor>[];
    try {
      final decoded = jsonDecode(stored);
      if (decoded is! List) return const <PairedSensor>[];
      return List<PairedSensor>.unmodifiable(<PairedSensor>[
        for (final row in decoded) ?PairedSensor.fromJson(row),
      ]);
    } on FormatException catch (error, stackTrace) {
      _log.warning('paired sensors unreadable', error, stackTrace);
      return const <PairedSensor>[];
    }
  }

  /// Adds [sensor], replacing whatever was stored under the same id — which is
  /// what pairing the same device twice means.
  Future<void> pair(PairedSensor sensor) => _write(<PairedSensor>[
    for (final paired in state)
      if (paired.id != sensor.id) paired,
    sensor,
  ]);

  /// Removes the device with [id]. It stops being connected to on the next
  /// pass of the sources controller.
  Future<void> forget(String id) => _write(<PairedSensor>[
    for (final paired in state)
      if (paired.id != id) paired,
  ]);

  /// Gives the device with [id] a name of the rider's choosing.
  Future<void> rename(String id, String name) => _write(<PairedSensor>[
    for (final paired in state)
      if (paired.id == id) paired.copyWith(name: name) else paired,
  ]);

  Future<void> _write(List<PairedSensor> sensors) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (sensors.isEmpty) {
      await prefs.remove(prefsPairedSensors);
    } else {
      await prefs.setString(
        prefsPairedSensors,
        jsonEncode(<Map<String, Object?>>[
          for (final sensor in sensors) sensor.toJson(),
        ]),
      );
    }
    state = List<PairedSensor>.unmodifiable(sensors);
  }
}

/// The devices the rider has paired.
final pairedSensorsProvider =
    NotifierProvider<PairedSensorsController, List<PairedSensor>>(
      PairedSensorsController.new,
    );

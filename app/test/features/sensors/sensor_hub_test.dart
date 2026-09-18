import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/sensors/application/sensor_hub.dart';
import 'package:velorki/features/sensors/domain/sensor_reading.dart';
import 'package:velorki/features/sensors/domain/sensor_snapshot.dart';
import 'package:velorki/features/sensors/domain/sensor_source.dart';

final DateTime _start = DateTime.utc(2026, 9, 12, 10);

DateTime _at(int seconds) => _start.add(Duration(seconds: seconds));

/// A source the test pushes readings into by hand.
class FakeSensorSource implements SensorSource {
  FakeSensorSource({
    required this.id,
    required this.priority,
    this.kinds = const <SensorKind>{SensorKind.heartRate},
    this.name = 'Fake',
  });

  @override
  final String id;

  @override
  final String name;

  @override
  final Set<SensorKind> kinds;

  @override
  final int priority;

  final StreamController<SensorReading> _controller =
      StreamController<SensorReading>.broadcast();

  @override
  Stream<SensorReading> get readings => _controller.stream;

  /// Pushes one reading and lets the hub process it.
  Future<void> report(SensorKind kind, double value, DateTime at) async {
    _controller.add(
      SensorReading(kind: kind, value: value, at: at, sourceId: id),
    );
    await pumpEventQueue();
  }

  /// Makes the stream fail once, as a dropping connection does.
  Future<void> fail() async {
    _controller.addError(StateError('the strap went away'));
    await pumpEventQueue();
  }

  Future<void> close() => _controller.close();
}

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  SensorHub hub() => container.read(sensorHubProvider.notifier);

  SensorSnapshot snapshot() => container.read(sensorHubProvider);

  test('starts with nothing', () {
    expect(snapshot(), SensorSnapshot.empty);
    expect(snapshot().isEmpty, isTrue);
    expect(hub().sources, isEmpty);
  });

  test('a registered source reaches the snapshot', () async {
    final strap = FakeSensorSource(
      id: 'strap',
      priority: bluetoothSensorPriority,
    );
    addTearDown(strap.close);
    hub().register(strap);

    await strap.report(SensorKind.heartRate, 142.4, _at(0));

    expect(snapshot().heartRateBpm, 142);
    expect(snapshot().heartRateAt, _at(0));
    expect(snapshot().liveSourceIds, {'strap'});
    expect(hub().sources, hasLength(1));
  });

  test('every kind is carried on its own', () async {
    final meter = FakeSensorSource(
      id: 'meter',
      priority: bluetoothSensorPriority,
      kinds: SensorKind.values.toSet(),
    );
    addTearDown(meter.close);
    hub().register(meter);

    await meter.report(SensorKind.heartRate, 130, _at(0));
    await meter.report(SensorKind.cadence, 88, _at(0));
    await meter.report(SensorKind.speed, 7.5, _at(0));
    await meter.report(SensorKind.power, 210, _at(0));

    final now = snapshot();
    expect(now.heartRateBpm, 130);
    expect(now.cadenceRpm, 88);
    expect(now.speedMps, 7.5);
    expect(now.powerW, 210);
    expect(now.isNotEmpty, isTrue);
  });

  test('the higher priority source wins while it is reporting', () async {
    final watch = FakeSensorSource(id: 'watch', priority: watchSensorPriority);
    final health = FakeSensorSource(
      id: 'health',
      priority: healthSensorPriority,
    );
    addTearDown(watch.close);
    addTearDown(health.close);
    hub()
      ..register(health)
      ..register(watch);

    await health.report(SensorKind.heartRate, 100, _at(0));
    expect(snapshot().heartRateBpm, 100);

    await watch.report(SensorKind.heartRate, 150, _at(1));
    expect(snapshot().heartRateBpm, 150);

    // The health store keeps reporting; the watch still wins.
    await health.report(SensorKind.heartRate, 101, _at(2));
    expect(snapshot().heartRateBpm, 150);
    expect(snapshot().liveSourceIds, {'watch', 'health'});
  });

  test(
    'a lower priority source takes over when the higher goes stale',
    () async {
      final watch = FakeSensorSource(
        id: 'watch',
        priority: watchSensorPriority,
      );
      final health = FakeSensorSource(
        id: 'health',
        priority: healthSensorPriority,
      );
      addTearDown(watch.close);
      addTearDown(health.close);
      hub()
        ..register(watch)
        ..register(health);

      await watch.report(SensorKind.heartRate, 150, _at(0));
      await health.report(SensorKind.heartRate, 100, _at(5));
      expect(snapshot().heartRateBpm, 150, reason: 'the watch is still fresh');

      // Eleven seconds after the watch last spoke: past the ten second window.
      await health.report(SensorKind.heartRate, 102, _at(11));

      expect(snapshot().heartRateBpm, 102);
      expect(snapshot().liveSourceIds, {'health'});
    },
  );

  test('unregistering forgets what the source reported', () async {
    final watch = FakeSensorSource(id: 'watch', priority: watchSensorPriority);
    final health = FakeSensorSource(
      id: 'health',
      priority: healthSensorPriority,
    );
    addTearDown(watch.close);
    addTearDown(health.close);
    hub()
      ..register(watch)
      ..register(health);

    await watch.report(SensorKind.heartRate, 150, _at(0));
    await health.report(SensorKind.heartRate, 100, _at(0));
    expect(snapshot().heartRateBpm, 150);

    hub().unregister('watch');

    expect(snapshot().heartRateBpm, 100);
    expect(hub().sources, hasLength(1));

    hub().unregister('health');
    expect(snapshot(), SensorSnapshot.empty);
  });

  test('a reading from an unregistered source is ignored', () async {
    final strap = FakeSensorSource(
      id: 'strap',
      priority: bluetoothSensorPriority,
    );
    addTearDown(strap.close);
    hub()
      ..register(strap)
      ..unregister('strap');

    await strap.report(SensorKind.heartRate, 142, _at(0));

    expect(snapshot(), SensorSnapshot.empty);
  });

  test('registering the same id twice replaces the source', () async {
    final first = FakeSensorSource(
      id: 'strap',
      priority: bluetoothSensorPriority,
    );
    final second = FakeSensorSource(
      id: 'strap',
      priority: bluetoothSensorPriority,
    );
    addTearDown(first.close);
    addTearDown(second.close);
    hub()
      ..register(first)
      ..register(second);

    await first.report(SensorKind.heartRate, 100, _at(0));
    expect(snapshot().heartRateBpm, isNull, reason: 'the old stream is gone');

    await second.report(SensorKind.heartRate, 155, _at(0));
    expect(snapshot().heartRateBpm, 155);
    expect(hub().sources, hasLength(1));
  });

  test('a failing source does not disturb the others', () async {
    final broken = FakeSensorSource(
      id: 'broken',
      priority: watchSensorPriority,
    );
    final strap = FakeSensorSource(
      id: 'strap',
      priority: bluetoothSensorPriority,
    );
    addTearDown(broken.close);
    addTearDown(strap.close);
    hub()
      ..register(broken)
      ..register(strap);

    await broken.fail();
    await strap.report(SensorKind.heartRate, 140, _at(0));

    expect(snapshot().heartRateBpm, 140);
  });

  test('refresh drops what has gone stale', () async {
    final strap = FakeSensorSource(
      id: 'strap',
      priority: bluetoothSensorPriority,
    );
    addTearDown(strap.close);
    hub().register(strap);

    await strap.report(SensorKind.heartRate, 142, _at(0));
    hub().refresh(_at(30));

    expect(snapshot().heartRateBpm, isNull);
    expect(snapshot().liveSourceIds, isEmpty);
  });

  group('SensorSnapshot', () {
    test('readingsAt keeps the fresh values and drops the rest', () {
      final snapshot = SensorSnapshot(
        heartRateBpm: 140,
        cadenceRpm: 85,
        heartRateAt: _at(0),
        cadenceAt: _at(20),
        liveSourceIds: const {'strap'},
      );

      final fresh = snapshot.readingsAt(_at(25));

      expect(fresh.heartRateBpm, isNull);
      expect(fresh.heartRateAt, isNull);
      expect(fresh.cadenceRpm, 85);
      expect(fresh.liveSourceIds, {'strap'});
    });

    test('readingsAt returns the same object when everything is fresh', () {
      final snapshot = SensorSnapshot(
        heartRateBpm: 140,
        cadenceRpm: 85,
        speedMps: 7,
        powerW: 200,
        heartRateAt: _at(0),
        cadenceAt: _at(0),
        speedAt: _at(0),
        powerAt: _at(0),
      );
      expect(identical(snapshot.readingsAt(_at(1)), snapshot), isTrue);
    });

    test('timestampOf names the right field', () {
      final snapshot = SensorSnapshot(powerAt: _at(3));
      expect(snapshot.timestampOf(SensorKind.power), _at(3));
      expect(snapshot.timestampOf(SensorKind.speed), isNull);
    });

    test('survives the map round trip to the service isolate', () {
      final snapshot = SensorSnapshot(
        heartRateBpm: 140,
        cadenceRpm: 0,
        speedMps: 7.5,
        powerW: 210,
        heartRateAt: _at(1),
        cadenceAt: _at(2),
        speedAt: _at(3),
        powerAt: _at(4),
        liveSourceIds: const {'strap', 'watch'},
      );

      expect(SensorSnapshot.fromMap(snapshot.toMap()), snapshot);
      expect(
        SensorSnapshot.fromMap(SensorSnapshot.empty.toMap()),
        SensorSnapshot.empty,
      );
    });

    test('equality and hashCode', () {
      final one = SensorSnapshot(heartRateBpm: 140, heartRateAt: _at(0));
      final same = SensorSnapshot(heartRateBpm: 140, heartRateAt: _at(0));
      expect(one, same);
      expect(one.hashCode, same.hashCode);
      expect(
        one,
        isNot(SensorSnapshot(heartRateBpm: 141, heartRateAt: _at(0))),
      );
      expect(one.toString(), contains('SensorSnapshot'));
    });
  });

  group('SensorReading', () {
    test('rounds to the integer a track point stores', () {
      final reading = SensorReading(
        kind: SensorKind.power,
        value: 210.6,
        at: _at(0),
        sourceId: 'meter',
      );
      expect(reading.rounded, 211);
      expect(reading.toString(), contains('power'));
    });

    test('equality and hashCode', () {
      final one = SensorReading(
        kind: SensorKind.heartRate,
        value: 140,
        at: _at(0),
        sourceId: 'strap',
      );
      final same = SensorReading(
        kind: SensorKind.heartRate,
        value: 140,
        at: _at(0),
        sourceId: 'strap',
      );
      expect(one, same);
      expect(one.hashCode, same.hashCode);
      expect(
        one,
        isNot(
          SensorReading(
            kind: SensorKind.cadence,
            value: 140,
            at: _at(0),
            sourceId: 'strap',
          ),
        ),
      );
    });
  });

  test('the priorities rank watch over bluetooth over health', () {
    expect(watchSensorPriority, greaterThan(bluetoothSensorPriority));
    expect(bluetoothSensorPriority, greaterThan(healthSensorPriority));
  });
}

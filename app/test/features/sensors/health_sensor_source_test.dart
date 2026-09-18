import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/sensors/data/health_gateway.dart';
import 'package:velorki/features/sensors/data/health_sensor_source.dart';
import 'package:velorki/features/sensors/domain/sensor_reading.dart';
import 'package:velorki/features/sensors/domain/sensor_source.dart';
import 'package:velorki/features/sensors/testing/fake_health_gateway.dart';

final DateTime _start = DateTime.utc(2026, 9, 18, 9);

HeartRateSample _sample(int bpm, int second) => HeartRateSample(
  bpm: bpm,
  at: _start.add(Duration(seconds: second)),
  sourceName: 'Watch',
);

void main() {
  group('HealthSensorSource', () {
    late FakeHealthGateway gateway;
    late DateTime now;
    late Duration interval;

    HealthSensorSource source() => HealthSensorSource(
      gateway: gateway,
      interval: () => interval,
      clock: () => now,
      platform: TargetPlatform.android,
    );

    setUp(() {
      gateway = FakeHealthGateway();
      now = _start;
      interval = healthPollInterval;
    });

    test('announces itself as the health store', () {
      final health = source();
      addTearDown(health.dispose);

      expect(health.id, 'health');
      expect(health.name, 'Health Connect');
      expect(health.priority, healthSensorPriority);
      expect(health.kinds, <SensorKind>{SensorKind.heartRate});
    });

    test(
      'the first poll looks a minute back and emits what it finds',
      () async {
        gateway.samples.addAll([_sample(138, -30), _sample(141, -5)]);
        final health = source();
        addTearDown(health.dispose);
        final seen = <SensorReading>[];
        health.readings.listen(seen.add);

        await health.start();
        await health.stop();
        await Future<void>.delayed(Duration.zero);

        expect(
          gateway.queries.single.from,
          _start.subtract(healthFirstPollWindow),
        );
        expect(gateway.queries.single.to, _start);
        expect(seen.map((r) => r.value), <double>[138, 141]);
        expect(seen.map((r) => r.kind), everyElement(SensorKind.heartRate));
        expect(seen.map((r) => r.sourceId), everyElement('health'));
        expect(seen.map((r) => r.at), <DateTime>[
          _start.subtract(const Duration(seconds: 30)),
          _start.subtract(const Duration(seconds: 5)),
        ]);
      },
    );

    test('a sample already seen is not emitted twice', () async {
      gateway.samples.add(_sample(140, -1));
      final health = source();
      addTearDown(health.dispose);
      final seen = <SensorReading>[];
      health.readings.listen(seen.add);

      await health.start();
      await health.stop();
      now = _start.add(const Duration(seconds: 5));
      await health.poll();
      await Future<void>.delayed(Duration.zero);

      expect(seen, hasLength(1));
      expect(gateway.queries.last.from, _sample(140, -1).at);
    });

    test('later samples are emitted in time order', () async {
      gateway.samples.add(_sample(140, -1));
      final health = source();
      addTearDown(health.dispose);
      final seen = <SensorReading>[];
      health.readings.listen(seen.add);

      await health.start();
      await health.stop();
      gateway.samples.addAll([_sample(150, 3), _sample(145, 1)]);
      now = _start.add(const Duration(seconds: 5));
      await health.poll();
      await Future<void>.delayed(Duration.zero);

      expect(seen.map((r) => r.value), <double>[140, 145, 150]);
    });

    test('polls every five seconds, and every thirty in battery saver', () {
      fakeAsync((async) {
        final health = source();
        unawaited(health.start());
        async.flushMicrotasks();
        expect(gateway.queries, hasLength(1), reason: 'the first poll');

        for (var i = 0; i < 3; i++) {
          now = now.add(healthPollInterval);
          async.elapse(healthPollInterval);
        }
        expect(gateway.queries, hasLength(4));

        interval = healthPollSaverInterval;
        now = now.add(healthPollInterval);
        async.elapse(healthPollInterval);
        expect(
          gateway.queries,
          hasLength(5),
          reason: 'the wait already running keeps its old length',
        );

        now = now.add(healthPollInterval);
        async.elapse(healthPollInterval);
        expect(gateway.queries, hasLength(5), reason: 'the saver stretched it');

        now = now.add(healthPollSaverInterval);
        async.elapse(healthPollSaverInterval);
        expect(gateway.queries, hasLength(6));

        unawaited(health.dispose());
        async.flushTimers();
      });
    });

    test('stopping ends the polling', () {
      fakeAsync((async) {
        final health = source();
        unawaited(health.start());
        async.flushMicrotasks();
        unawaited(health.stop());
        async.flushMicrotasks();

        now = now.add(const Duration(minutes: 5));
        async.elapse(const Duration(minutes: 5));

        expect(gateway.queries, hasLength(1));
        expect(health.isPolling, isFalse);
        unawaited(health.dispose());
        async.flushTimers();
      });
    });
  });
}

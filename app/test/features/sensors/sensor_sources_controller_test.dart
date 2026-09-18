import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/recording/data/recording_service.dart';
import 'package:velorki/features/recording/domain/recording_snapshot.dart';
import 'package:velorki/features/sensors/application/sensor_hub.dart';
import 'package:velorki/features/sensors/application/sensor_sources_controller.dart';
import 'package:velorki/features/sensors/data/health_gateway.dart';
import 'package:velorki/features/sensors/data/sensor_settings.dart';
import 'package:velorki/features/sensors/testing/fake_health_gateway.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../recording/support/fakes.dart';

RecordingSnapshot _snapshot({required RecordingStatus status}) =>
    RecordingSnapshot(
      rideId: 'ride-1',
      status: status,
      startedAt: DateTime.utc(2026, 9, 18, 9),
      distanceM: 1200,
      elapsed: const Duration(minutes: 5),
      moving: const Duration(minutes: 5),
      speedMps: 6,
      avgSpeedMps: 5,
      lastPosition: const LatLng(48.1, 11.2),
      pointCount: 30,
    );

RecordingSnapshot _riding() => _snapshot(status: RecordingStatus.active);

RecordingSnapshot _stopped() => _snapshot(status: RecordingStatus.idle);

void main() {
  late FakeRecordingService service;
  late FakeHealthGateway gateway;

  Future<ProviderContainer> containerWith({
    required bool health,
    bool hasStore = true,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      if (health) 'sensors.health': true,
    });
    final prefs = await SharedPreferences.getInstance();
    service = FakeRecordingService();
    addTearDown(service.dispose);
    gateway = FakeHealthGateway();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        recordingServiceProvider.overrideWithValue(service),
        healthGatewayProvider.overrideWithValue(hasStore ? gateway : null),
      ],
    );
    addTearDown(container.dispose);
    container.read(sensorSourcesProvider);
    await container.read(sensorSourcesProvider.notifier).settled;
    return container;
  }

  Future<void> settle(ProviderContainer container) async {
    await pumpEventQueue();
    await container.read(sensorSourcesProvider.notifier).settled;
  }

  Iterable<String> registered(ProviderContainer container) =>
      container.read(sensorHubProvider.notifier).sources.map((s) => s.id);

  test('with Health off a ride registers nothing', () async {
    final container = await containerWith(health: false);

    service.emit(_riding());
    await settle(container);

    expect(registered(container), isEmpty);
    expect(gateway.queries, isEmpty, reason: 'the store was never touched');
  });

  test('with Health on and no ride nothing is registered', () async {
    final container = await containerWith(health: true);

    expect(registered(container), isEmpty);
    expect(gateway.queries, isEmpty);
  });

  test('Health on plus a ride registers the source and polls', () async {
    final container = await containerWith(health: true);

    service.emit(_riding());
    await settle(container);

    expect(registered(container), <String>['health']);
    expect(gateway.queries, hasLength(1), reason: 'the first poll ran');
  });

  test('ending the ride unregisters it again', () async {
    final container = await containerWith(health: true);
    service.emit(_riding());
    await settle(container);

    service.emit(_stopped());
    await settle(container);

    expect(registered(container), isEmpty);
  });

  test('switching Health off mid-ride unregisters it', () async {
    final container = await containerWith(health: true);
    service.emit(_riding());
    await settle(container);

    await container.read(sensorSettingsProvider.notifier).setHealth(false);
    await settle(container);

    expect(registered(container), isEmpty);
  });

  test('switching Health on mid-ride registers it', () async {
    final container = await containerWith(health: false);
    service.emit(_riding());
    await settle(container);

    await container.read(sensorSettingsProvider.notifier).setHealth(true);
    await settle(container);

    expect(registered(container), <String>['health']);
  });

  test('a platform without a health store registers nothing', () async {
    final container = await containerWith(health: true, hasStore: false);

    service.emit(_riding());
    await settle(container);

    expect(registered(container), isEmpty);
  });
}

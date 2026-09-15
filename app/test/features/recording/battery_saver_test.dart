import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/recording/data/battery_saver.dart';
import 'package:velorki/features/recording/data/recording_service.dart';
import 'package:velorki/features/recording/data/recording_settings.dart';
import 'package:velorki/features/recording/domain/recording_snapshot.dart';
import 'package:velorki/features/settings/data/appearance_controller.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/fakes.dart';

RecordingSnapshot _snapshot({
  RecordingStatus status = RecordingStatus.active,
}) => RecordingSnapshot(
  rideId: 'ride-1',
  status: status,
  startedAt: DateTime.utc(2026, 9, 12, 10),
  distanceM: 1200,
  elapsed: const Duration(minutes: 5),
  moving: const Duration(minutes: 5),
  speedMps: 6,
  avgSpeedMps: 5,
  ascentM: 10,
  descentM: 5,
  lastPosition: const LatLng(48.1, 11.2),
  accuracyM: 4,
  pointCount: 30,
);

void main() {
  late FakeRecordingService service;

  Future<ProviderContainer> containerWith({required bool saver}) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      if (saver) 'recording.saver': true,
    });
    final prefs = await SharedPreferences.getInstance();
    service = FakeRecordingService();
    addTearDown(service.dispose);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        recordingServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);
    // Something has to be listening for the snapshots to reach the state.
    container.listen(appearanceOverrideProvider, (_, _) {});
    return container;
  }

  test('nothing is overridden while no ride is being recorded', () async {
    final container = await containerWith(saver: true);

    expect(container.read(batterySaverActiveProvider), isFalse);
    expect(container.read(appearanceOverrideProvider), isNull);
  });

  test('a saver ride runs the app dark and the map black', () async {
    final container = await containerWith(saver: true);

    service.emit(_snapshot());
    await pumpEventQueue();

    expect(container.read(batterySaverActiveProvider), isTrue);
    final override = container.read(appearanceOverrideProvider);
    expect(override?.mode, ThemeMode.dark);
    expect(override?.mapLook, MapLook.black);
  });

  test('the rider gets their own look back when the ride ends', () async {
    final container = await containerWith(saver: true);
    service.emit(_snapshot());
    await pumpEventQueue();
    expect(container.read(appearanceOverrideProvider), isNotNull);

    service.emit(_snapshot(status: RecordingStatus.idle));
    await pumpEventQueue();

    expect(container.read(batterySaverActiveProvider), isFalse);
    expect(container.read(appearanceOverrideProvider), isNull);
    // The stored choice was never touched in the first place.
    expect(container.read(appearanceSettingProvider).mapLook, MapLook.auto);
  });

  test('switching the saver off mid-ride hands the look back too', () async {
    final container = await containerWith(saver: true);
    service.emit(_snapshot());
    await pumpEventQueue();
    expect(container.read(appearanceOverrideProvider), isNotNull);

    await container.read(recordingSettingsProvider.notifier).setSaver(false);

    expect(container.read(appearanceOverrideProvider), isNull);
  });

  test('a ride without the saver changes nothing', () async {
    final container = await containerWith(saver: false);

    service.emit(_snapshot());
    await pumpEventQueue();

    expect(container.read(batterySaverActiveProvider), isFalse);
    expect(container.read(appearanceOverrideProvider), isNull);
  });
}

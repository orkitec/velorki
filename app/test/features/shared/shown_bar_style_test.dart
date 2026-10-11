import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/core/power/system_power_save.dart';
import 'package:velorki/features/recording/data/recording_service.dart';
import 'package:velorki/features/recording/domain/recording_snapshot.dart';
import 'package:velorki/features/shared/application/shown_bar_style.dart';
import 'package:velorki/features/shared/presentation/floating_bar.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../recording/support/fakes.dart';

RecordingSnapshot _snapshot({
  RecordingStatus status = RecordingStatus.active,
}) => RecordingSnapshot(
  rideId: 'ride-1',
  status: status,
  startedAt: DateTime.utc(2026, 10, 8, 10),
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
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(PowerSaveChannel.channelName);

  /// What the fake platform answers `isOn` with.
  var systemOn = false;
  setUp(() {
    systemOn = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      return call.method == 'isOn' ? systemOn : null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  /// The platform reporting that its power-saving mode was switched.
  Future<void> switchSystem({required bool on}) async {
    systemOn = on;
    await messenger.handlePlatformMessage(
      PowerSaveChannel.channelName,
      const StandardMethodCodec().encodeMethodCall(MethodCall('changed', on)),
      (_) {},
    );
    await pumpEventQueue();
  }

  late FakeRecordingService service;

  Future<ProviderContainer> containerWith({
    bool appSaver = false,
    BarStyle chosen = BarStyle.clear,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      if (appSaver) 'recording.saver': true,
      'appearance.bar': chosen.name,
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
    container.listen(shownBarStyleProvider, (_, _) {});
    await pumpEventQueue();
    return container;
  }

  group('systemPowerSaveProvider', () {
    test('reads the mode, then follows every switch', () async {
      systemOn = true;
      final container = await containerWith();
      expect(container.read(systemPowerSaveProvider).value, isTrue);

      await switchSystem(on: false);
      expect(container.read(systemPowerSaveProvider).value, isFalse);

      await switchSystem(on: true);
      expect(container.read(systemPowerSaveProvider).value, isTrue);
    });

    test('is false where the platform has no answer', () async {
      messenger.setMockMethodCallHandler(channel, null);
      final container = await containerWith();
      // No handler: the question fails on the platform side, later.
      expect(await container.read(systemPowerSaveProvider.future), isFalse);
    });
  });

  group('shownBarStyleProvider', () {
    test('the chosen glass stands with nothing saving power', () async {
      final container = await containerWith(chosen: BarStyle.subtle);
      expect(container.read(shownBarStyleProvider), BarStyle.subtle);
    });

    test('the phone saving power turns it solid, live', () async {
      final container = await containerWith();
      expect(container.read(shownBarStyleProvider), BarStyle.clear);

      await switchSystem(on: true);
      expect(container.read(shownBarStyleProvider), BarStyle.solid);

      await switchSystem(on: false);
      expect(container.read(shownBarStyleProvider), BarStyle.clear);
    });

    test('a ride recorded in battery saver turns it solid', () async {
      final container = await containerWith(appSaver: true);
      expect(
        container.read(shownBarStyleProvider),
        BarStyle.clear,
        reason: 'the saver alone, without a ride, keeps the glass',
      );

      service.emit(_snapshot());
      await pumpEventQueue();
      expect(container.read(shownBarStyleProvider), BarStyle.solid);

      service.emit(_snapshot(status: RecordingStatus.idle));
      await pumpEventQueue();
      expect(container.read(shownBarStyleProvider), BarStyle.clear);
    });

    test('a ride without the saver keeps the glass', () async {
      final container = await containerWith();
      service.emit(_snapshot());
      await pumpEventQueue();
      expect(container.read(shownBarStyleProvider), BarStyle.clear);
    });
  });

  group('FloatingBarStyle.of', () {
    Future<BarStyle> resolved(
      WidgetTester tester,
      ProviderContainer container, {
      bool highContrast = false,
    }) async {
      late BarStyle style;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MediaQuery(
            data: MediaQueryData(highContrast: highContrast),
            child: Consumer(
              builder: (context, ref, _) => FloatingBarStyle(
                style: ref.watch(shownBarStyleProvider),
                child: Builder(
                  builder: (context) {
                    style = FloatingBarStyle.of(context);
                    return const SizedBox();
                  },
                ),
              ),
            ),
          ),
        ),
      );
      return style;
    }

    testWidgets('is solid while the phone saves power', (tester) async {
      systemOn = true;
      final container = await tester.runAsync(containerWith);
      expect(await resolved(tester, container!), BarStyle.solid);
    });

    testWidgets('is solid on a battery-saver ride', (tester) async {
      final container = await tester.runAsync(
        () => containerWith(appSaver: true),
      );
      expect(await resolved(tester, container!), BarStyle.clear);
      await tester.runAsync(() async {
        service.emit(_snapshot());
        await pumpEventQueue();
      });
      await tester.pump();
      expect(await resolved(tester, container), BarStyle.solid);
    });

    testWidgets('is solid in high contrast, whatever else', (tester) async {
      final container = await tester.runAsync(containerWith);
      expect(
        await resolved(tester, container!, highContrast: true),
        BarStyle.solid,
      );
    });
  });
}

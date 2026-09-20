import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/navigation/application/navigation_controller.dart';
import 'package:velorki/features/navigation/domain/navigation_progress.dart';
import 'package:velorki/features/recording/application/ride_finish_request.dart';
import 'package:velorki/features/recording/data/recording_service.dart';
import 'package:velorki/features/recording/domain/recording_snapshot.dart';
import 'package:velorki/features/sensors/application/sensor_hub.dart';
import 'package:velorki/features/sensors/application/watch_ride_bridge.dart';
import 'package:velorki/features/sensors/data/sensor_settings.dart';
import 'package:velorki/features/sensors/data/watch_gateway.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/features/sensors/data/watch_protocol.dart';
import 'package:velorki/features/settings/data/appearance_controller.dart';
import 'package:velorki/features/sensors/data/watch_sensor_source.dart';
import 'package:velorki/features/sensors/testing/fake_watch_gateway.dart';
import 'package:velorki/features/settings/data/units.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../recording/support/fakes.dart';

/// When the ride under test started.
final DateTime _start = DateTime.utc(2026, 9, 18, 10);

/// A turn to the left, somewhere along the route.
const TurnHint _left = TurnHint(
  pointIndex: 10,
  kind: TurnKind.left,
  distanceToNextM: 500,
);

RecordingSnapshot _snapshot({
  double distanceM = 3200,
  Duration elapsed = const Duration(seconds: 42),
  double speedMps = 5,
  RecordingStatus status = RecordingStatus.active,
}) => RecordingSnapshot(
  rideId: 'ride-1',
  status: status,
  startedAt: _start,
  distanceM: distanceM,
  elapsed: elapsed,
  speedMps: speedMps,
  lastPosition: const LatLng(48, 11),
);

/// A navigator that reports whatever the test puts in it; the real one needs a
/// route and a stream of fixes to say anything.
class _StubNavigation extends NavigationController {
  _StubNavigation(this._progress);

  NavigationProgress? _progress;

  @override
  NavigationProgress? build() => _progress;

  /// Reports [progress] from now on.
  void emit(NavigationProgress? progress) {
    _progress = progress;
    state = progress;
  }
}

/// A clock the test winds forward by hand.
class _Clock {
  DateTime now = _start;

  void advance(Duration by) => now = now.add(by);
}

/// The bridge with a fake watch on one side and a fake recorder on the other.
class _Harness {
  _Harness._(
    this.container,
    this.service,
    this.navigation,
    this.watch,
    this.clock,
  );

  static Future<_Harness> create({
    bool enabled = true,
    bool reachable = true,
    NavigationProgress? progress,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      if (enabled) 'sensors.watch': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final service = FakeRecordingService();
    final navigation = _StubNavigation(progress);
    final watch = FakeWatchGateway(reachable: reachable);
    final clock = _Clock();
    final container = ProviderContainer(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        // The figures go to the watch already formatted, so the test has to
        // pin the units and the language the same way the app does.
        localeCountryProvider.overrideWithValue(null),
        recordingServiceProvider.overrideWithValue(service),
        navigationControllerProvider.overrideWith(() => navigation),
        navigationLocalizationsProvider.overrideWithValue(
          lookupAppLocalizations(const Locale('en')),
        ),
        watchGatewayProvider.overrideWithValue(watch),
        watchClockProvider.overrideWithValue(() => clock.now),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(service.dispose);
    addTearDown(watch.dispose);
    // `bootstrap()` does exactly this: a provider nobody reads is one that
    // never exists, and then it observes nothing.
    container.read(watchRideBridgeProvider);
    final harness = _Harness._(container, service, navigation, watch, clock);
    await harness.settle();
    return harness;
  }

  final ProviderContainer container;
  final FakeRecordingService service;
  final _StubNavigation navigation;
  final FakeWatchGateway watch;
  final _Clock clock;

  /// Pushes one snapshot through the recorder and lets the bridge react.
  Future<void> record(RecordingSnapshot snapshot) async {
    service.emit(snapshot);
    await settle();
  }

  /// Ends the ride, as the record screen does when the rider saves.
  Future<void> finish() => record(
    RecordingSnapshot(
      rideId: 'ride-1',
      status: RecordingStatus.idle,
      startedAt: _start,
    ),
  );

  /// Plays the watch: sends [message] as if it had come off the wrist.
  Future<void> fromWatch(Map<String, Object?> message) async {
    watch.receive(message);
    await settle();
  }

  /// Taps a button on the wrist.
  Future<void> tap(String command) => fromWatch(<String, Object?>{
    watchTypeKey: watchCommandType,
    watchCommandKey: command,
  });

  /// The last context the watch was given, or `null` when it was given none.
  Map<String, Object?>? get lastContext =>
      watch.contexts.isEmpty ? null : watch.contexts.last;

  /// Everything the phone asked the watch to do with its workout, in order.
  List<Object?> get workouts => <Object?>[
    for (final message in watch.sent)
      if (message[watchTypeKey] == watchWorkoutType)
        message[watchWorkoutActionKey],
  ];

  /// Lets the streams deliver and the bridge's queue drain.
  Future<void> settle() async {
    for (var i = 0; i < 3; i++) {
      await Future<void>.delayed(Duration.zero);
      await container.read(watchRideBridgeProvider.notifier).settled;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the watch as a sensor', () {
    test('turns what the wrist measures into a reading in the hub', () async {
      final harness = await _Harness.create();
      final at = _start.add(const Duration(minutes: 1));

      await harness.fromWatch(<String, Object?>{
        watchTypeKey: watchHeartRateType,
        watchBpmKey: 150,
        watchAtKey: at.millisecondsSinceEpoch,
      });

      final snapshot = harness.container.read(sensorHubProvider);
      expect(snapshot.heartRateBpm, 150);
      expect(snapshot.heartRateAt, at);
      expect(snapshot.liveSourceIds, contains(watchSensorSourceId));
    });

    test('registers nothing at all while the switch is off', () async {
      final harness = await _Harness.create(enabled: false);

      await harness.record(_snapshot());
      await harness.fromWatch(<String, Object?>{
        watchTypeKey: watchHeartRateType,
        watchBpmKey: 150,
        watchAtKey: _start.millisecondsSinceEpoch,
      });

      expect(harness.container.read(sensorHubProvider).heartRateBpm, isNull);
      expect(harness.watch.contexts, isEmpty);
      expect(harness.watch.sent, isEmpty);
    });

    test('is given up when the switch goes off mid-ride', () async {
      final harness = await _Harness.create();
      await harness.record(_snapshot());

      await harness.container
          .read(sensorSettingsProvider.notifier)
          .setWatch(false);
      await harness.settle();

      // The watch is told to stop measuring, and its readings no longer
      // reach the hub.
      expect(harness.workouts, <Object?>[watchWorkoutStart, watchWorkoutStop]);
      await harness.fromWatch(<String, Object?>{
        watchTypeKey: watchHeartRateType,
        watchBpmKey: 150,
        watchAtKey: _start.millisecondsSinceEpoch,
      });
      expect(harness.container.read(sensorHubProvider).heartRateBpm, isNull);
    });
  });

  group('the buttons on the wrist', () {
    test('start a ride with the notification the record screen uses', () async {
      final harness = await _Harness.create();

      await harness.tap(watchCommandStart);

      expect(harness.service.calls, <String>['start(null)']);
    });

    test('a start from the wrist is announced on the phone, so a tap brings '
        'the app up', () async {
      final harness = await _Harness.create();

      await harness.tap(watchCommandStart);

      expect(harness.watch.notifications, <(String, String)>[
        (
          'Ride started from your watch',
          'Open Velorki once so the phone records your track.',
        ),
      ]);
    });

    test('a start from the wrist is counted, so the app can show the ride, '
        'and a repeat of it is not', () async {
      final harness = await _Harness.create();
      expect(harness.container.read(watchRideStartsProvider), 0);

      await harness.tap(watchCommandStart);
      expect(harness.container.read(watchRideStartsProvider), 1);

      // The watch resends until the phone confirms; the recorder is already
      // running, so nothing happens twice.
      await harness.record(_snapshot());
      await harness.tap(watchCommandStart);
      expect(harness.service.calls, <String>['start(null)']);
      expect(harness.container.read(watchRideStartsProvider), 1);
    });

    test('pause and resume the recorder', () async {
      final harness = await _Harness.create();
      await harness.record(_snapshot());

      await harness.tap(watchCommandPause);
      await harness.record(_snapshot(status: RecordingStatus.paused));
      await harness.tap(watchCommandResume);

      expect(harness.service.calls, <String>['pause', 'resume']);
    });

    test('stop the recording and leave the ride for the save sheet', () async {
      final harness = await _Harness.create();
      await harness.record(_snapshot());

      await harness.tap(watchCommandStop);

      // Nothing is saved from the wrist: the ride is named on a sheet, so the
      // recorder is put down and the screen is asked to finish it.
      expect(harness.service.calls, <String>['pause']);
      expect(harness.service.savedNames, isEmpty);
      expect(harness.container.read(rideFinishRequestProvider), isTrue);
    });

    test('are ignored when they make no sense', () async {
      final harness = await _Harness.create();

      // Nothing is being recorded, so there is nothing to pause or stop.
      await harness.tap(watchCommandPause);
      await harness.tap(watchCommandResume);
      await harness.tap(watchCommandStop);

      expect(harness.service.calls, isEmpty);
      expect(harness.container.read(rideFinishRequestProvider), isFalse);
    });
  });

  group('the workout on the watch', () {
    test('is started with the ride and ended with it', () async {
      final harness = await _Harness.create();

      await harness.record(_snapshot());
      expect(harness.workouts, <Object?>[watchWorkoutStart]);

      await harness.finish();
      expect(harness.workouts, <Object?>[watchWorkoutStart, watchWorkoutStop]);
    });

    test('is launched through HealthKit while the watch app is not running, '
        'and still ended with the ride', () async {
      final harness = await _Harness.create(reachable: false);

      await harness.record(_snapshot());

      expect(harness.workouts, isEmpty, reason: 'no message to a closed app');
      expect(harness.watch.launches, 1);

      await harness.finish();
      expect(harness.workouts, <Object?>[watchWorkoutStop]);
    });

    test(
      'is launched again when the watch falls silent mid-ride, not '
      'while the ride is paused, and not more than every two minutes',
      () async {
        final harness = await _Harness.create(reachable: false);
        await harness.record(_snapshot());
        expect(harness.watch.launches, 1);

        // Readings arrive; the clock moves; nothing to do.
        harness.clock.advance(const Duration(seconds: 30));
        await harness.fromWatch(<String, Object?>{
          watchTypeKey: watchHeartRateType,
          watchBpmKey: 140,
          watchAtKey: harness.clock.now.millisecondsSinceEpoch,
        });
        await harness.record(_snapshot());
        expect(harness.watch.launches, 1);

        // Fifty seconds without a reading, but the ride's own launch was
        // less than two minutes ago: not yet.
        harness.clock.advance(const Duration(seconds: 50));
        await harness.record(_snapshot());
        expect(harness.watch.launches, 1);

        // Two minutes and more since the launch, still silent: again.
        harness.clock.advance(const Duration(seconds: 60));
        await harness.record(_snapshot());
        expect(harness.watch.launches, 2);

        // A minute later, still silent: the last launch was too recent.
        harness.clock.advance(const Duration(seconds: 60));
        await harness.record(_snapshot());
        expect(harness.watch.launches, 2);

        // Paused, the silence is expected, however long.
        harness.clock.advance(const Duration(minutes: 3));
        await harness.record(_snapshot(status: RecordingStatus.paused));
        expect(harness.watch.launches, 2);

        // Riding again, still nothing from the wrist: once more.
        await harness.record(_snapshot());
        expect(harness.watch.launches, 3);
      },
    );

    test('is launched once for one ride', () async {
      final harness = await _Harness.create(reachable: false);

      await harness.record(_snapshot());
      await harness.record(_snapshot());

      expect(harness.watch.launches, 1);
    });

    test('a launch watchOS refuses leaves nothing owed at the end', () async {
      final harness = await _Harness.create(reachable: false);
      harness.watch.launchSucceeds = false;

      await harness.record(_snapshot());
      await harness.finish();

      expect(harness.workouts, isEmpty);
    });

    test('is not stopped twice when the rider stopped it first', () async {
      final harness = await _Harness.create();
      await harness.record(_snapshot());

      await harness.fromWatch(<String, Object?>{
        watchTypeKey: watchHeartRateStoppedType,
      });
      await harness.finish();

      expect(harness.workouts, <Object?>[watchWorkoutStart]);
    });
  });

  group('what the watch shows', () {
    test('is the ride, formatted as the lock screen has it', () async {
      final harness = await _Harness.create(
        progress: const NavigationProgress(next: _left, distanceToNextM: 150),
      );

      await harness.record(_snapshot());

      expect(harness.lastContext, <String, Object?>{
        watchStatusKey: watchStatusActive,
        watchDistanceKey: '3.2 km',
        watchElapsedKey: '00:42',
        watchSpeedKey: '18.0 km/h',
        watchTurnIconKey: 'arrow.turn.up.left',
        watchTurnLabelKey: 'Turn left',
        watchTurnDistanceKey: '150 m',
        watchOffRouteKey: false,
        watchCueKey: 0,
        watchAccentKey: '#C8F542',
      });
    });

    test('carries the accent the rider picked, so the wrist matches', () async {
      final harness = await _Harness.create();
      await harness.record(_snapshot());
      await harness.container
          .read(appearanceSettingProvider.notifier)
          .setAccent(AccentPreset.ember);
      await harness.settle();
      expect(harness.lastContext?[watchAccentKey], '#FF7A45');
    });

    test('goes out the moment the ride is paused', () async {
      final harness = await _Harness.create();
      await harness.record(_snapshot());
      final before = harness.watch.contexts.length;

      // No second has passed, but the status is what the rider is looking at.
      await harness.record(_snapshot(status: RecordingStatus.paused));

      expect(harness.watch.contexts, hasLength(before + 1));
      expect(harness.lastContext?[watchStatusKey], watchStatusPaused);
    });

    test('waits out the throttle for the figures', () async {
      final harness = await _Harness.create();
      await harness.record(_snapshot());
      final before = harness.watch.contexts.length;

      harness.clock.advance(const Duration(seconds: 1));
      await harness.record(_snapshot(distanceM: 3300));
      expect(harness.watch.contexts, hasLength(before));

      harness.clock.advance(watchContextThrottle);
      await harness.record(_snapshot(distanceM: 3400));
      expect(harness.watch.contexts, hasLength(before + 1));
      expect(harness.lastContext?[watchDistanceKey], '3.4 km');
    });

    test('carries a cue straight to the wrist', () async {
      final harness = await _Harness.create(
        progress: const NavigationProgress(
          next: _left,
          distanceToNextM: 150,
          offRoute: true,
        ),
      );
      await harness.record(_snapshot());
      final before = harness.watch.contexts.length;

      final cue = _start.add(const Duration(minutes: 2));
      harness.container.read(navigationCueProvider.notifier).fire(cue);
      await harness.settle();

      expect(harness.watch.contexts, hasLength(before + 1));
      expect(harness.lastContext?[watchCueKey], cue.millisecondsSinceEpoch);
      // Which haptic it is worth is the watch's decision, from this.
      expect(harness.lastContext?[watchOffRouteKey], isTrue);
    });

    test('says a ride is over once it is', () async {
      final harness = await _Harness.create();
      await harness.record(_snapshot());

      await harness.finish();

      expect(harness.lastContext?[watchStatusKey], watchStatusIdle);
      expect(harness.lastContext?[watchDistanceKey], '');
    });
  });
}

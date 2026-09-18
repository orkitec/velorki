import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/navigation/application/navigation_controller.dart';
import 'package:velorki/features/navigation/domain/navigation_progress.dart';
import 'package:velorki/features/recording/application/ride_notification_updater.dart';
import 'package:velorki/features/recording/data/live_activity.dart';
import 'package:velorki/features/recording/data/notification_updater.dart';
import 'package:velorki/features/recording/data/recording_service.dart';
import 'package:velorki/features/recording/domain/recording_snapshot.dart';
import 'package:velorki/features/recording/testing/fake_live_activity.dart';
import 'package:velorki/features/recording/testing/fake_notification_updater.dart';
import 'package:velorki/features/settings/data/units.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/fakes.dart';

/// When the ride under test started.
final DateTime _start = DateTime.utc(2026, 9, 12, 10);

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
  int? heartRateBpm,
}) => RecordingSnapshot(
  rideId: 'ride-1',
  status: status,
  startedAt: _start,
  distanceM: distanceM,
  elapsed: elapsed,
  speedMps: speedMps,
  lastPosition: const LatLng(48, 11),
  heartRateBpm: heartRateBpm,
);

/// A navigator that reports whatever the test puts in it.
///
/// The real controller needs a route, a plan and a stream of fixes to say
/// anything; what is under test here is what is done with its answer.
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

/// A container with the recorder, the navigator, the notification and the
/// lock-screen card all faked out.
class _Harness {
  _Harness._(
    this.container,
    this.service,
    this.navigation,
    this.notifications,
    this.activity,
    this.clock,
  );

  static Future<_Harness> create({NavigationProgress? progress}) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final service = FakeRecordingService();
    final navigation = _StubNavigation(progress);
    final notifications = FakeNotificationUpdater();
    final activity = FakeRideLiveActivity();
    final clock = _Clock();
    final container = ProviderContainer(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        localeCountryProvider.overrideWithValue(null),
        recordingServiceProvider.overrideWithValue(service),
        navigationControllerProvider.overrideWith(() => navigation),
        navigationLocalizationsProvider.overrideWithValue(
          lookupAppLocalizations(const Locale('en')),
        ),
        notificationUpdaterProvider.overrideWithValue(notifications),
        rideLiveActivityProvider.overrideWithValue(activity),
        rideNotificationClockProvider.overrideWithValue(() => clock.now),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(service.dispose);
    // Listening is what creates the updater and keeps its own listeners
    // awake; `HomeShell` does exactly this for the running app.
    container.listen(rideNotificationUpdaterProvider, (previous, next) {});
    return _Harness._(
      container,
      service,
      navigation,
      notifications,
      activity,
      clock,
    );
  }

  final ProviderContainer container;
  final FakeRecordingService service;
  final _StubNavigation navigation;
  final FakeNotificationUpdater notifications;
  final FakeRideLiveActivity activity;
  final _Clock clock;

  /// Pushes one snapshot through the recorder and lets the listeners run.
  Future<void> record(RecordingSnapshot snapshot) async {
    service.emit(snapshot);
    await _settle();
  }

  /// Ends the ride, as the record screen does when the rider stops.
  Future<void> finish() async {
    service.emit(
      RecordingSnapshot(
        rideId: 'ride-1',
        status: RecordingStatus.idle,
        startedAt: _start,
      ),
    );
    await _settle();
  }

  /// Puts [progress] in the navigator's mouth and lets the listeners run.
  Future<void> navigate(NavigationProgress? progress) async {
    navigation.emit(progress);
    await _settle();
  }

  Future<void> _settle() => Future<void>.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the notification text', () {
    test('is distance and time while nothing is being navigated', () async {
      final harness = await _Harness.create();

      await harness.record(_snapshot());

      expect(harness.notifications.lastText, '3.2 km · 00:42');
    });

    test('leads with the next turn and how far it is', () async {
      final harness = await _Harness.create(
        progress: const NavigationProgress(next: _left, distanceToNextM: 150),
      );

      await harness.record(_snapshot());

      expect(
        harness.notifications.lastText,
        'Turn left in 150 m · 3.2 km · 00:42',
      );
    });

    test('says so while the rider is off route', () async {
      final harness = await _Harness.create(
        progress: const NavigationProgress(
          next: _left,
          distanceToNextM: 150,
          offRoute: true,
        ),
      );

      await harness.record(_snapshot());

      expect(harness.notifications.lastText, 'Off route · 3.2 km · 00:42');
    });

    test('marks a paused ride', () async {
      final harness = await _Harness.create();

      await harness.record(_snapshot(status: RecordingStatus.paused));

      expect(harness.notifications.lastText, '3.2 km · 00:42 · ⏸');
    });
  });

  group('the updater', () {
    test('writes nothing when the text has not changed', () async {
      final harness = await _Harness.create();

      await harness.record(_snapshot());
      harness.clock.advance(const Duration(seconds: 10));
      await harness.record(_snapshot());

      expect(harness.notifications.texts, <String>['3.2 km · 00:42']);
    });

    test('writes at most once every two seconds', () async {
      final harness = await _Harness.create();

      await harness.record(_snapshot());
      // One second on, a longer ride: the text changed, but the throttle has
      // not run out yet.
      harness.clock.advance(const Duration(seconds: 1));
      await harness.record(
        _snapshot(distanceM: 3300, elapsed: const Duration(seconds: 43)),
      );
      expect(harness.notifications.texts, <String>['3.2 km · 00:42']);

      harness.clock.advance(const Duration(seconds: 1));
      await harness.record(
        _snapshot(distanceM: 3400, elapsed: const Duration(seconds: 44)),
      );
      expect(harness.notifications.texts, <String>[
        '3.2 km · 00:42',
        '3.4 km · 00:44',
      ]);
    });

    test('follows the navigator as well as the recorder', () async {
      final harness = await _Harness.create();

      await harness.record(_snapshot());
      harness.clock.advance(const Duration(seconds: 3));
      await harness.navigate(
        const NavigationProgress(next: _left, distanceToNextM: 80),
      );

      expect(
        harness.notifications.lastText,
        'Turn left in 80 m · 3.2 km · 00:42',
      );
    });

    test(
      'leases the text from the service isolate and gives it back',
      () async {
        final harness = await _Harness.create();

        await harness.record(_snapshot());
        expect(harness.notifications.leases, <Duration>[notificationLease]);

        await harness.finish();
        expect(harness.notifications.leases.last, Duration.zero);
      },
    );
  });

  group('the live activity', () {
    test('starts with the ride and ends with it', () async {
      final harness = await _Harness.create(
        progress: const NavigationProgress(next: _left, distanceToNextM: 150),
      );

      await harness.record(_snapshot());
      expect(harness.activity.calls, <String>['start']);
      expect(harness.activity.last, <String, Object?>{
        'distance': '3.2 km',
        'elapsed': '00:42',
        'speed': '18.0 km/h',
        'heartRate': '',
        'turnIcon': 'arrow.turn.up.left',
        'turnLabel': 'Turn left',
        'turnDistance': '150 m',
        'paused': 0,
      });

      await harness.finish();
      expect(harness.activity.calls, <String>['start', 'end']);
    });

    test('the heart rate reaches the card when a sensor reports one', () async {
      final harness = await _Harness.create();

      await harness.record(_snapshot(heartRateBpm: 142));

      expect(harness.activity.last!['heartRate'], '142');
    });

    test('is redrawn at most once every five seconds', () async {
      final harness = await _Harness.create();

      await harness.record(_snapshot());
      harness.clock.advance(const Duration(seconds: 3));
      await harness.record(
        _snapshot(distanceM: 3300, elapsed: const Duration(seconds: 45)),
      );
      expect(harness.activity.calls, <String>['start']);

      harness.clock.advance(const Duration(seconds: 3));
      await harness.record(
        _snapshot(distanceM: 3400, elapsed: const Duration(seconds: 48)),
      );
      expect(harness.activity.calls, <String>['start', 'update']);
    });
  });
}

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/platform_features.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/features/recording/data/recording_service.dart';
import 'package:velorki/features/recording/domain/recording_snapshot.dart';
import 'package:velorki/features/settings/data/package_info_provider.dart';
import 'package:velorki/features/shared/application/active_tab.dart';
import 'package:velorki/features/store_prompts/application/calm_moment.dart';
import 'package:velorki/features/store_prompts/application/review_prompts.dart';
import 'package:velorki/features/store_prompts/data/store_services.dart';

import '../recording/support/fakes.dart';

final DateTime _launch = DateTime.utc(2026, 10, 20, 9);

PackageInfo _package(String version) => PackageInfo(
  appName: 'Velorki',
  packageName: 'com.orkitec.velorki',
  version: version,
  buildNumber: '1',
);

/// The prompts over fake counts, a fake recorder and a counting request.
class _Harness {
  _Harness(
    this.container,
    this.service,
    this.rides,
    this.routes,
    this.prefs,
    this.clock,
  );

  final ProviderContainer container;
  final FakeRecordingService service;
  final StreamController<int> rides;
  final StreamController<int> routes;
  final SharedPreferences prefs;
  final List<DateTime> clock;
  int requests = 0;

  static Future<_Harness> create({
    String version = '1.1.0',
    PlatformFeatures features = PlatformFeatures.device,
    Map<String, Object> stored = const <String, Object>{},
  }) async {
    SharedPreferences.setMockInitialValues(stored);
    final prefs = await SharedPreferences.getInstance();
    final service = FakeRecordingService();
    final rides = StreamController<int>.broadcast();
    final routes = StreamController<int>.broadcast();
    final clock = <DateTime>[_launch];
    late final _Harness harness;
    final container = ProviderContainer(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        platformFeaturesProvider.overrideWithValue(features),
        recordingServiceProvider.overrideWithValue(service),
        packageInfoProvider.overrideWith((ref) async => _package(version)),
        recordedRideCountProvider.overrideWith((ref) => rides.stream),
        keptRouteCountProvider.overrideWith((ref) => routes.stream),
        storePromptClockProvider.overrideWithValue(() => clock.last),
        reviewRequestProvider.overrideWithValue(() async {
          harness.requests++;
        }),
      ],
    );
    harness = _Harness(container, service, rides, routes, prefs, clock);
    return harness;
  }

  /// Starts the prompts with the counts the database already holds.
  void start(FakeAsync async, {int rides = 0, int routes = 0}) {
    startReviewPrompts(container);
    async.flushMicrotasks();
    this.rides.add(rides);
    this.routes.add(routes);
    async.flushMicrotasks();
  }

  /// A save: the database's count goes up, and the moment settles.
  void save(FakeAsync async, {int? rides, int? routes}) {
    if (rides != null) this.rides.add(rides);
    if (routes != null) this.routes.add(routes);
    async.flushMicrotasks();
    async.elapse(calmSettle * 2);
  }

  void dispose() {
    container.dispose();
    unawaited(rides.close());
    unawaited(routes.close());
  }
}

RecordingSnapshot _riding() => RecordingSnapshot(
  rideId: 'ride-1',
  status: RecordingStatus.active,
  startedAt: _launch,
  distanceM: 1200,
  elapsed: const Duration(minutes: 5),
);

void main() {
  test('the third recorded ride asks, once the moment is calm', () async {
    final h = await _Harness.create();
    fakeAsync((async) {
      h.start(async, rides: 1);
      h.save(async, rides: 2);
      expect(h.requests, 0);
      h.rides.add(3);
      async.flushMicrotasks();
      // Not at once: the save's snackbar and screen settle first.
      expect(h.requests, 0);
      async.elapse(calmSettle * 2);
      expect(h.requests, 1);
    });
    h.dispose();
  });

  test('the fifth kept route asks too', () async {
    final h = await _Harness.create();
    fakeAsync((async) {
      h.start(async, routes: 3);
      h.save(async, routes: 4);
      expect(h.requests, 0);
      h.save(async, routes: 5);
      expect(h.requests, 1);
    });
    h.dispose();
  });

  test('a rider who already had the rides is asked on the next save, '
      'not at launch', () async {
    final h = await _Harness.create();
    fakeAsync((async) {
      h.start(async, rides: 12, routes: 30);
      async.elapse(const Duration(minutes: 1));
      expect(h.requests, 0);
      h.save(async, routes: 31);
      expect(h.requests, 1);
    });
    h.dispose();
  });

  test('a deletion is not a save', () async {
    final h = await _Harness.create();
    fakeAsync((async) {
      h.start(async, routes: 6);
      h.save(async, routes: 5);
      expect(h.requests, 0);
    });
    h.dispose();
  });

  test('at most once per app version', () async {
    final h = await _Harness.create();
    fakeAsync((async) {
      h.start(async, rides: 3);
      h.save(async, rides: 4);
      h.save(async, rides: 5);
      h.save(async, routes: 9);
      expect(h.requests, 1);
    });
    h.dispose();
  });

  test('a new version asks again, but not within 90 days', () async {
    final asked = _launch.subtract(const Duration(days: 30));
    final stored = <String, Object>{
      'store_prompts.review_version': '1.0.0',
      'store_prompts.review_at': asked.millisecondsSinceEpoch,
    };
    final h = await _Harness.create(stored: stored);
    fakeAsync((async) {
      h.start(async, rides: 3);
      h.save(async, rides: 4);
      expect(h.requests, 0);
      h.clock.add(asked.add(reviewInterval));
      h.save(async, rides: 5);
      expect(h.requests, 1);
    });
    expect(h.prefs.getString('store_prompts.review_version'), '1.1.0');
    h.dispose();
  });

  test('never while a ride records: it waits for the ride to end', () async {
    final h = await _Harness.create();
    fakeAsync((async) {
      h.start(async, routes: 4);
      h.container.read(rideCalmProvider);
      h.service.emit(_riding());
      async.flushMicrotasks();
      expect(h.container.read(rideCalmProvider), isFalse);
      h.save(async, routes: 5);
      async.elapse(const Duration(minutes: 30));
      expect(h.requests, 0);
      h.service.emit(
        RecordingSnapshot(
          rideId: 'ride-1',
          status: RecordingStatus.idle,
          startedAt: _launch,
        ),
      );
      async.flushMicrotasks();
      async.elapse(calmSettle * 2);
      expect(h.requests, 1);
    });
    h.dispose();
  });

  test('on the Record tab it waits for the Library or the Plan', () async {
    final h = await _Harness.create();
    fakeAsync((async) {
      h.container.read(activeTabProvider.notifier).show(recordingRoute);
      h.start(async, rides: 2);
      h.save(async, rides: 3);
      async.elapse(const Duration(minutes: 5));
      expect(h.requests, 0);
      h.container.read(activeTabProvider.notifier).show(libraryRoute);
      async.flushMicrotasks();
      async.elapse(calmSettle * 2);
      expect(h.requests, 1);
    });
    h.dispose();
  });

  test('nothing in a browser', () async {
    final h = await _Harness.create(features: PlatformFeatures.browser);
    fakeAsync((async) {
      h.start(async, rides: 2);
      h.save(async, rides: 3);
      h.save(async, routes: 5);
      expect(h.requests, 0);
    });
    h.dispose();
  });

  test('reviewDue counts either threshold and the interval', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    bool due({int rides = 0, int routes = 0}) => reviewDue(
      prefs,
      rides: rides,
      routes: routes,
      version: '1.1.0',
      now: _launch,
    );
    expect(due(rides: 2, routes: 4), isFalse);
    expect(due(rides: 3), isTrue);
    expect(due(routes: 5), isTrue);
  });
}

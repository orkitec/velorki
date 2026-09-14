import 'dart:math' as math;
import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/core/db/database.dart' show RouteSource;
import 'package:velorki/features/navigation/application/navigation_controller.dart';
import 'package:velorki/features/navigation/data/turn_speaker.dart';
import 'package:velorki/features/navigation/domain/navigation_progress.dart';
import 'package:velorki/features/navigation/testing/fake_turn_speaker.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/planner/data/routing_backend_provider.dart';
import 'package:velorki/features/planner/domain/planner_state.dart';
import 'package:velorki/features/planner/domain/route_profile.dart';
import 'package:velorki/features/planner/domain/routing_options.dart';
import 'package:velorki/features/planner/domain/saved_route.dart';
import 'package:velorki/features/planner/domain/waypoint.dart';
import 'package:velorki/features/recording/application/recording_controller.dart';
import 'package:velorki/features/recording/data/recording_service.dart';
import 'package:velorki/features/recording/domain/recording_snapshot.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../planner/support/fakes.dart' show FakeRoutingBackend;
import '../recording/support/fakes.dart';

/// One degree of latitude, the same figure the recording fakes use.
const double _metresPerDegree = 111194.9266;

/// One degree of longitude at 48°.
final double _metresPerDegreeEast =
    _metresPerDegree * math.cos(48 * math.pi / 180);

/// A point [alongM] north of 48°/11°, [asideM] metres east of the route.
LatLng _at(double alongM, {double asideM = 0}) =>
    LatLng(48 + alongM / _metresPerDegree, 11 + asideM / _metresPerDegreeEast);

/// A straight kilometre north, a point every 50 m.
List<TrackPoint> _geometry() => <TrackPoint>[
  for (var i = 0; i <= 20; i++) TrackPoint(_at(i * 50.0)),
];

/// Turn left at 500 m, arrive at 1000 m.
const List<TurnHint> _turns = <TurnHint>[
  TurnHint(pointIndex: 10, kind: TurnKind.left, distanceToNextM: 500),
  TurnHint(pointIndex: 20, kind: TurnKind.end),
];

/// The points the plan was drawn through: start, two stops, finish.
const List<double> _waypointsAlongM = <double>[0, 500, 800, 1000];

SavedRoute _savedRoute({
  List<TurnHint> turns = _turns,
  List<double> waypointsAlongM = _waypointsAlongM,
}) => SavedRoute(
  id: 'route-1',
  name: 'Along the river',
  source: RouteSource.planned,
  profile: RouteProfile.trekking,
  createdAt: DateTime.utc(2026, 9, 12),
  updatedAt: DateTime.utc(2026, 9, 12),
  distanceM: 1000,
  ascentM: 0,
  descentM: 0,
  bounds: BoundingBox.fromPoints(<LatLng>[_at(0), _at(1000)]),
  geometryBlob: PackedTrack.encode(_geometry()),
  waypoints: <Waypoint>[
    for (final alongM in waypointsAlongM) Waypoint(pos: _at(alongM)),
  ],
  options: const RoutingOptions(),
  turns: turns,
);

RouteResult _plannedRoute() => RouteResult(
  geometry: _geometry(),
  lengthM: 1000,
  ascentM: 0,
  descentM: 0,
  messages: const <SegmentMessage>[],
  raw: const <String, dynamic>{},
  turns: _turns,
);

/// The way back the fake router hands out: the same kilometre north, but a
/// kilometre to the east, so a rider on the original line is nowhere near it.
RouteResult _detourRoute({double asideM = 1000, double fromM = 400}) =>
    RouteResult(
      geometry: <TrackPoint>[
        for (var alongM = fromM; alongM <= 1000; alongM += 100)
          TrackPoint(_at(alongM, asideM: asideM)),
      ],
      lengthM: 1000 - fromM,
      ascentM: 0,
      descentM: 0,
      messages: const <SegmentMessage>[],
      raw: const <String, dynamic>{},
      turns: const <TurnHint>[],
    );

/// A clock the tests wind forward by hand.
class _Clock {
  DateTime now = DateTime.utc(2026, 9, 12, 10);

  void advance(Duration by) => now = now.add(by);
}

RecordingSnapshot _snapshot({
  required double alongM,
  double asideM = 0,
  RecordingStatus status = RecordingStatus.active,
  double speedMps = 6,
}) => RecordingSnapshot(
  rideId: 'ride-1',
  status: status,
  startedAt: DateTime.utc(2026, 9, 12, 10),
  autoPaused: false,
  distanceM: alongM,
  elapsed: const Duration(minutes: 3),
  moving: const Duration(minutes: 3),
  speedMps: speedMps,
  avgSpeedMps: speedMps,
  ascentM: 0,
  descentM: 0,
  lastPosition: _at(alongM, asideM: asideM),
  accuracyM: 4,
  pointCount: 10,
  newPoints: const <LatLng>[],
);

/// A planner that hands out one canned result instead of routing.
class _StubPlanner extends PlannerController {
  _StubPlanner(this.result);

  /// The route the Plan tab is showing.
  final RouteResult? result;

  @override
  PlannerState build() => PlannerState(route: AsyncData<RouteResult?>(result));
}

/// A container with the recorder, the speaker and the routes faked out.
class _NavHarness {
  _NavHarness._(
    this.container,
    this.service,
    this.speaker,
    this.backend,
    this.clock,
  );

  static Future<_NavHarness> create({
    SavedRoute? saved,
    RouteResult? planned,
    Map<String, Object> preferences = const <String, Object>{},
    FakeRoutingBackend? backend,
  }) async {
    SharedPreferences.setMockInitialValues(preferences);
    final prefs = await SharedPreferences.getInstance();
    final service = FakeRecordingService();
    final speaker = FakeTurnSpeaker();
    final router = backend ?? FakeRoutingBackend(result: _detourRoute());
    final clock = _Clock();
    final container = ProviderContainer(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        recordingServiceProvider.overrideWithValue(service),
        turnSpeakerProvider.overrideWithValue(speaker),
        navigationLocalizationsProvider.overrideWithValue(
          lookupAppLocalizations(const Locale('en')),
        ),
        routingBackendProvider.overrideWithValue(router),
        navigationClockProvider.overrideWithValue(() => clock.now),
        plannerControllerProvider.overrideWith(() => _StubPlanner(planned)),
        if (saved != null)
          savedRouteProvider(saved.id)
              .overrideWith((ref) => Stream<SavedRoute?>.value(saved)),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(service.dispose);
    // Listening is what starts the controller and keeps its own listeners
    // awake; `HomeShell` does exactly this for the running app.
    container.listen(navigationControllerProvider, (previous, next) {});
    return _NavHarness._(container, service, speaker, router, clock);
  }

  final ProviderContainer container;
  final FakeRecordingService service;
  final FakeTurnSpeaker speaker;
  final FakeRoutingBackend backend;
  final _Clock clock;

  /// What the controller currently says.
  NavigationProgress? get progress =>
      container.read(navigationControllerProvider);

  /// The detour being followed, if there is one.
  GuidedRoute? get detour => container.read(detourRouteProvider);

  /// The route navigation is running on right now.
  GuidedRoute? get active => container.read(activeGuidedRouteProvider);

  /// Chooses the saved route to follow and lets the database answer.
  Future<void> follow(String? routeId) async {
    container.read(recordingControllerProvider.notifier).selectRoute(routeId);
    await _settle();
  }

  /// Pushes one fix through the recorder.
  Future<void> ride(
    double alongM, {
    double asideM = 0,
    double speedMps = 6,
  }) async {
    service.emit(_snapshot(alongM: alongM, asideM: asideM, speedMps: speedMps));
    await _settle();
  }

  /// Pushes one fix 200 m to the side of the route through the recorder.
  Future<void> stray(double alongM, {double speedMps = 6}) =>
      ride(alongM, asideM: 200, speedMps: speedMps);

  /// Three stray fixes in a row, which is what it takes to be off route.
  Future<void> strayOff({double from = 300}) async {
    for (var i = 0; i < 3; i++) {
      await stray(from + i * 50);
    }
  }

  /// Ends the ride.
  Future<void> stopRiding() async {
    service.emit(_snapshot(alongM: 1000, status: RecordingStatus.idle));
    await _settle();
  }

  static Future<void> _settle() =>
      Future<void>.delayed(const Duration(milliseconds: 1));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a ride along a saved route closes in on the next turn', () async {
    final h = await _NavHarness.create(saved: _savedRoute());
    await h.follow('route-1');

    await h.ride(0);
    final first = h.progress;
    expect(first, isNotNull);
    expect(first!.next?.kind, TurnKind.left);
    expect(first.distanceToNextM, closeTo(500, 2));

    await h.ride(250);
    expect(h.progress!.distanceToNextM, closeTo(250, 2));

    await h.ride(480);
    expect(h.progress!.distanceToNextM, closeTo(20, 2));
    expect(h.progress!.offRoute, isFalse);
  });

  test('every cue is spoken once, in English', () async {
    final h = await _NavHarness.create(saved: _savedRoute());
    await h.follow('route-1');

    for (final alongM in <double>[0, 250, 260, 480, 490, 600, 800, 810, 990]) {
      await h.ride(alongM);
    }

    expect(h.speaker.spoken, <String>[
      'In 250 metres, turn left',
      'Now turn left',
      'In 200 metres, arrive',
      'Now arrive',
      'You have arrived',
    ]);
    expect(
      h.speaker.spoken.toSet(),
      hasLength(h.speaker.spoken.length),
      reason: 'a cue is given once, not once per fix',
    );
  });

  test('a silent ride still shows the turns', () async {
    final h = await _NavHarness.create(
      saved: _savedRoute(),
      preferences: <String, Object>{'navigation.voice': false},
    );
    await h.follow('route-1');

    await h.ride(250);
    await h.ride(480);

    expect(h.progress!.next?.kind, TurnKind.left);
    expect(h.speaker.spoken, isEmpty);
  });

  test('turn directions switched off leave the controller silent', () async {
    final h = await _NavHarness.create(
      saved: _savedRoute(),
      preferences: <String, Object>{'navigation.turns': false},
    );
    await h.follow('route-1');

    await h.ride(250);
    await h.ride(480);

    expect(h.progress, isNull);
    expect(h.speaker.spoken, isEmpty);
  });

  test('the end of the ride clears the banner and the voice', () async {
    final h = await _NavHarness.create(saved: _savedRoute());
    await h.follow('route-1');
    await h.ride(250);
    expect(h.progress, isNotNull);

    await h.stopRiding();

    expect(h.progress, isNull);
    expect(h.speaker.stops, 1);
  });

  test('without a followed route the plan is the guided route', () async {
    final h = await _NavHarness.create(planned: _plannedRoute());

    await h.ride(0);
    await h.ride(250);

    expect(h.progress, isNotNull);
    expect(h.progress!.next?.kind, TurnKind.left);
    expect(h.progress!.distanceToNextM, closeTo(250, 2));
    expect(h.speaker.spoken, contains('In 250 metres, turn left'));
  });

  group('re-routing', () {
    test('three stray fixes while moving ask for a way back', () async {
      final h = await _NavHarness.create(saved: _savedRoute());
      await h.follow('route-1');
      await h.ride(0);
      await h.ride(250);

      await h.strayOff();

      expect(h.backend.callCount, 1);
      expect(h.backend.queries.single.points, <LatLng>[
        _at(400, asideM: 200),
        _at(500),
        _at(800),
        _at(1000),
      ]);
      expect(h.backend.queries.single.profile, 'trekking');
      expect(h.backend.queries.single.alternativeIdx, 0);
    });

    test('a rider who has stopped is left alone', () async {
      final h = await _NavHarness.create(saved: _savedRoute());
      await h.follow('route-1');
      await h.ride(0);

      for (var i = 0; i < 3; i++) {
        await h.stray(300 + i * 50, speedMps: 0.4);
      }

      expect(h.progress!.offRoute, isTrue);
      expect(h.backend.callCount, 0);
    });

    test('the way back becomes the route, and is announced once', () async {
      final h = await _NavHarness.create(saved: _savedRoute());
      await h.follow('route-1');
      await h.ride(0);
      await h.ride(250);

      await h.strayOff();

      expect(h.detour, isNotNull);
      expect(h.active!.line, _detourRoute().positions);
      expect(h.progress!.rerouting, isFalse);
      expect(
        h.speaker.spoken.where((s) => s == 'Route recalculated'),
        hasLength(1),
      );
      expect(h.speaker.spoken, contains('Off route'));
    });

    test('a second way back is not asked for within twenty seconds', () async {
      final h = await _NavHarness.create(saved: _savedRoute());
      await h.follow('route-1');
      await h.ride(0);
      await h.strayOff();
      expect(h.backend.callCount, 1);

      // Off the detour as well, but too soon after the first attempt.
      await h.strayOff(from: 450);

      expect(h.progress!.offRoute, isTrue);
      expect(h.backend.callCount, 1);

      h.clock.advance(const Duration(seconds: 21));
      await h.stray(600);

      expect(h.backend.callCount, 2);
    });

    test('re-routing switched off asks for nothing', () async {
      final h = await _NavHarness.create(
        saved: _savedRoute(),
        preferences: const <String, Object>{'navigation.reroute': false},
      );
      await h.follow('route-1');
      await h.ride(0);

      await h.strayOff();

      expect(h.progress!.offRoute, isTrue);
      expect(h.backend.callCount, 0);
      expect(h.detour, isNull);
    });

    test('a router that fails leaves the rider off route, and is asked '
        'again after thirty seconds', () async {
      final h = await _NavHarness.create(
        saved: _savedRoute(),
        backend: FakeRoutingBackend(
          error: const RoutingException(
            kind: RoutingErrorKind.noRoute,
            message: 'nothing here',
          ),
        ),
      );
      await h.follow('route-1');
      await h.ride(0);

      await h.strayOff();

      expect(h.backend.callCount, 1);
      expect(h.detour, isNull);
      expect(h.progress!.offRoute, isTrue);
      expect(h.progress!.rerouting, isFalse);

      h.clock.advance(const Duration(seconds: 21));
      await h.stray(500);
      expect(h.backend.callCount, 1, reason: 'a failure waits longer');

      h.clock.advance(const Duration(seconds: 10));
      await h.stray(550);
      expect(h.backend.callCount, 2);
    });

    test('the banner is told while the request is out', () async {
      final h = await _NavHarness.create(
        saved: _savedRoute(),
        backend: FakeRoutingBackend(
          result: _detourRoute(),
          delay: const Duration(milliseconds: 50),
        ),
      );
      await h.follow('route-1');
      await h.ride(0);

      await h.strayOff();

      expect(h.progress!.rerouting, isTrue);
      expect(h.detour, isNull);

      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(h.progress!.rerouting, isFalse);
      expect(h.detour, isNotNull);
    });

    test('riding back onto the plan drops the detour', () async {
      final h = await _NavHarness.create(saved: _savedRoute());
      await h.follow('route-1');
      await h.ride(0);
      await h.strayOff();
      expect(h.detour, isNotNull);

      await h.ride(700);

      expect(h.detour, isNull);
      expect(h.active!.key, 'saved:route-1');
      expect(h.progress!.offRoute, isFalse);
    });

    test('the end of the ride drops the detour', () async {
      final h = await _NavHarness.create(saved: _savedRoute());
      await h.follow('route-1');
      await h.ride(0);
      await h.strayOff();
      expect(h.detour, isNotNull);

      await h.stopRiding();

      expect(h.detour, isNull);
      expect(h.progress, isNull);
    });

    test('a plan with no waypoints is re-routed to its end', () async {
      final h = await _NavHarness.create(
        saved: _savedRoute(waypointsAlongM: const <double>[]),
      );
      await h.follow('route-1');
      await h.ride(0);

      await h.strayOff();

      expect(h.backend.queries.single.points, hasLength(2));
      expect(h.backend.queries.single.points.first, _at(400, asideM: 200));
    });
  });
}

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
import 'package:velorki/features/navigation/application/off_route_machine.dart';
import 'package:velorki/features/navigation/domain/navigation_progress.dart';
import 'package:velorki/features/navigation/domain/off_route_guidance.dart';
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
import '../../support/units.dart';

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

/// Five kilometres north, a point every 50 m: far enough that the end of the
/// ride is nowhere near the two-kilometre rejoin window.
List<TrackPoint> _longGeometry() => <TrackPoint>[
  for (var i = 0; i <= 100; i++) TrackPoint(_at(i * 50.0)),
];

SavedRoute _longRoute() => SavedRoute(
  id: 'route-2',
  name: 'The long way round',
  source: RouteSource.planned,
  profile: RouteProfile.trekking,
  createdAt: DateTime.utc(2026, 9, 12),
  updatedAt: DateTime.utc(2026, 9, 12),
  distanceM: 5000,
  ascentM: 0,
  descentM: 0,
  bounds: BoundingBox.fromPoints(<LatLng>[_at(0), _at(5000)]),
  geometryBlob: PackedTrack.encode(_longGeometry()),
  waypoints: <Waypoint>[
    Waypoint(pos: _at(0)),
    Waypoint(pos: _at(5000)),
  ],
  options: const RoutingOptions(),
  turns: const <TurnHint>[TurnHint(pointIndex: 100, kind: TurnKind.end)],
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
  double? headingDeg = 0,
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
  headingDeg: headingDeg,
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
    this.router,
    this.clock,
  );

  static Future<_NavHarness> create({
    SavedRoute? saved,
    RouteResult? planned,
    Map<String, Object> preferences = const <String, Object>{},
    RoutingBackend? backend,
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
        // The host locale must not decide what the cues say.
        metricUnits,
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
  final RoutingBackend router;
  final _Clock clock;

  /// The plain fake, for the tests that gave no backend of their own.
  FakeRoutingBackend get backend => router as FakeRoutingBackend;

  /// The scripted one, for the tests that did.
  _ScriptedBackend get scripted => router as _ScriptedBackend;

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
    double? headingDeg = 0,
  }) async {
    service.emit(
      _snapshot(
        alongM: alongM,
        asideM: asideM,
        speedMps: speedMps,
        headingDeg: headingDeg,
      ),
    );
    await _settle();
  }

  /// Pushes one fix [asideM] metres to the side of the route.
  Future<void> stray(
    double alongM, {
    double asideM = 200,
    double speedMps = 6,
    double? headingDeg = 0,
  }) =>
      ride(alongM, asideM: asideM, speedMps: speedMps, headingDeg: headingDeg);

  /// Two stray fixes in a row, which is what it takes to be off route.
  Future<void> strayOff({double from = 300, double asideM = 200}) async {
    for (var i = 0; i < 2; i++) {
      await stray(from + i * 20, asideM: asideM);
    }
  }

  /// Rides away from the route, far enough that the travel since leaving it
  /// asks for a way back.
  Future<void> driftAway({double from = 300}) async {
    await strayOff(from: from);
    for (var i = 1; i <= 5; i++) {
      await stray(from + 20, asideM: 200 + i * 50);
    }
  }

  /// Where the ride stands in relation to the plan.
  OffRouteState get offRouteState =>
      progress?.offRouteState ?? OffRouteState.onRoute;

  /// The way back the banner would show.
  OffRouteGuidance? get guidance => progress?.guidance;

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

    // At 6 m/s the warning comes 60 m out and the now cue 30 m out.
    for (final alongM in <double>[0, 250, 450, 460, 480, 600, 950, 990]) {
      await h.ride(alongM);
    }

    expect(h.speaker.spoken, <String>[
      'In 50 metres, turn left',
      'Now turn left',
      'In 50 metres, arrive',
      'Now arrive',
      'You have arrived',
    ]);
    expect(
      h.speaker.spoken.toSet(),
      hasLength(h.speaker.spoken.length),
      reason: 'a cue is given once, not once per fix',
    );
  });

  test(
    'the voice is left to the speaker to resolve unless one was chosen',
    () async {
      final h = await _NavHarness.create(saved: _savedRoute());
      await h.follow('route-1');

      await h.ride(450);

      // `null` is what makes the speaker rank the installed voices; the ride
      // never names one itself.
      expect(h.speaker.selections, <String?>[null]);
    },
  );

  test('a chosen voice is the one the ride is spoken in', () async {
    final h = await _NavHarness.create(
      saved: _savedRoute(),
      preferences: <String, Object>{
        'navigation.voiceId': 'com.apple.voice.compact.en-US.Samantha',
      },
    );
    await h.follow('route-1');

    await h.ride(450);

    expect(h.speaker.selections, <String?>[
      'com.apple.voice.compact.en-US.Samantha',
    ]);
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

  test(
    'a ride muted from the banner keeps its turns but says nothing',
    () async {
      final h = await _NavHarness.create(saved: _savedRoute());
      await h.follow('route-1');
      await h.ride(0);

      h.container.read(voiceMutedForRideProvider.notifier).toggle();
      // At 6 m/s this is where the warning cue would have gone out.
      await h.ride(250);
      await h.ride(450);
      await h.ride(460);

      expect(h.progress!.next?.kind, TurnKind.left);
      expect(h.progress!.distanceToNextM, closeTo(40, 2));
      expect(h.speaker.spoken, isEmpty);

      // The cue was still worked out while the rider had it muted, so the
      // voice picks up at the next one rather than repeating itself.
      h.container.read(voiceMutedForRideProvider.notifier).toggle();
      await h.ride(480);

      expect(h.speaker.spoken, <String>['Now turn left']);
    },
  );

  test('the mute lasts one ride only', () async {
    final h = await _NavHarness.create(saved: _savedRoute());
    await h.follow('route-1');
    await h.ride(250);

    h.container.read(voiceMutedForRideProvider.notifier).toggle();
    expect(h.container.read(voiceMutedForRideProvider), isTrue);

    await h.stopRiding();

    expect(h.container.read(voiceMutedForRideProvider), isFalse);
  });

  test('a new ride starts with the voice back on', () async {
    final h = await _NavHarness.create(saved: _savedRoute());
    await h.follow('route-1');
    h.container.read(voiceMutedForRideProvider.notifier).toggle();

    await h.ride(0);

    expect(h.container.read(voiceMutedForRideProvider), isFalse);
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
    await h.ride(450);

    expect(h.progress, isNotNull);
    expect(h.progress!.next?.kind, TurnKind.left);
    expect(h.progress!.distanceToNextM, closeTo(50, 2));
    expect(h.speaker.spoken, contains('In 50 metres, turn left'));
  });

  group('leaving the route', () {
    test('one stray fix changes nothing', () async {
      final h = await _NavHarness.create(saved: _savedRoute());
      await h.follow('route-1');
      await h.ride(250);

      await h.stray(300);

      expect(h.offRouteState, OffRouteState.onRoute);
      expect(h.guidance, isNull);
      expect(h.backend.callCount, 0);
    });

    test(
      'two in a row guide the rider back, without asking the router',
      () async {
        final h = await _NavHarness.create(saved: _savedRoute());
        await h.follow('route-1');
        await h.ride(250);

        await h.strayOff();

        expect(h.offRouteState, OffRouteState.guiding);
        expect(h.backend.callCount, 0, reason: 'guidance costs no routing');
        expect(h.detour, isNull);
        expect(h.active!.key, 'saved:route-1');
      },
    );

    test(
      'the way back names the nearest point ahead and the way to turn',
      () async {
        final h = await _NavHarness.create(saved: _savedRoute());
        await h.follow('route-1');
        await h.ride(250);

        // Riding north 200 m east of the route: the way back is to the left.
        await h.strayOff(from: 300);

        final guidance = h.guidance!;
        expect(guidance.alongM, greaterThanOrEqualTo(300));
        expect(guidance.distanceM, closeTo(200, 20));
        expect(guidance.direction, RelativeDirection.left);
        expect(
          h.speaker.spoken.last,
          'Off route. In 200 metres, back to the route, on your left',
        );
      },
    );

    test('it is said once, and again only when the gap grows', () async {
      final h = await _NavHarness.create(saved: _savedRoute());
      await h.follow('route-1');
      await h.strayOff();
      expect(h.speaker.spoken.where(_isWayBack), hasLength(1));

      // Time alone never repeats it: fixes at the same distance stay quiet
      // (short steps, so the rejoin trigger does not fire first).
      h.clock.advance(const Duration(seconds: 8));
      await h.stray(340);
      h.clock.advance(const Duration(seconds: 8));
      await h.stray(360);
      expect(h.speaker.spoken.where(_isWayBack), hasLength(1));

      // Another 300 m further from the plan, and it is said once more.
      h.clock.advance(const Duration(seconds: 8));
      await h.stray(380, asideM: 520);
      expect(h.speaker.spoken.where(_isWayBack), hasLength(2));
    });

    test('the now cue may cut a cue off; the way back may not', () async {
      final h = await _NavHarness.create(saved: _savedRoute());
      await h.follow('route-1');
      await h.ride(0);
      await h.ride(480);
      expect(h.speaker.urgent, <String>['Now turn left']);

      await h.strayOff(from: 600);

      expect(h.speaker.spoken.where(_isWayBack), hasLength(1));
      expect(h.speaker.urgent, <String>['Now turn left']);
    });

    test('riding back onto the route ends the guidance quietly', () async {
      final h = await _NavHarness.create(saved: _savedRoute());
      await h.follow('route-1');
      await h.strayOff();
      expect(h.offRouteState, OffRouteState.guiding);
      final saidSoFar = h.speaker.spoken.length;

      await h.ride(400);

      expect(h.offRouteState, OffRouteState.onRoute);
      expect(h.guidance, isNull);
      expect(
        h.speaker.spoken.length,
        saidSoFar,
        reason: 'finding the route again is not worth saying',
      );
    });
  });

  group('the rejoin', () {
    test('half a minute off the route asks for one', () async {
      final h = await _NavHarness.create(
        saved: _savedRoute(),
        backend: _rejoinBackend(),
      );
      await h.follow('route-1');
      await h.ride(250);
      await h.strayOff();
      expect(h.scripted.callCount, 0);

      h.clock.advance(const Duration(seconds: 31));
      await h.stray(340);

      expect(h.scripted.callCount, greaterThan(0));
      expect(h.detour, isNotNull);
      expect(h.offRouteState, OffRouteState.detour);
    });

    test('a hundred and fifty metres of travel asks sooner', () async {
      final h = await _NavHarness.create(
        saved: _savedRoute(),
        backend: _rejoinBackend(),
      );
      await h.follow('route-1');
      await h.ride(250);

      await h.driftAway();

      expect(h.detour, isNotNull);
      expect(h.offRouteState, OffRouteState.detour);
    });

    test(
      'the nearest way back that is a road, and no further asking',
      () async {
        final h = await _NavHarness.create(
          saved: _savedRoute(),
          backend: _rejoinBackend(),
        );
        await h.follow('route-1');
        await h.ride(300);

        await h.driftAway(from: 320);

        expect(h.detour!.rejoinAlongM, closeTo(600, 2));
        expect(
          h.scripted.queries,
          hasLength(1),
          reason:
              'the first candidate answered, so the others were never asked',
        );
        expect(h.scripted.queries.single.points.last, _at(600));
        expect(h.scripted.queries.single.profile, 'trekking');
      },
    );

    test('a candidate needing four times its beeline is skipped', () async {
      final h = await _NavHarness.create(
        saved: _savedRoute(),
        // A river between the rider and the point three hundred metres on.
        backend: _rejoinBackend(factors: <double, double>{600: 4}),
      );
      await h.follow('route-1');
      await h.ride(300);

      await h.driftAway(from: 320);

      expect(h.detour!.rejoinAlongM, closeTo(1000, 2));
      expect(h.scripted.queries.map((q) => q.points.last), <LatLng>[
        _at(600),
        _at(1000),
      ], reason: 'the candidates are asked in order, nearest first');
    });

    test('when every candidate loops, the shortest way back wins', () async {
      final h = await _NavHarness.create(
        saved: _savedRoute(),
        backend: _rejoinBackend(factors: <double, double>{600: 8, 1000: 3.5}),
      );
      await h.follow('route-1');
      await h.ride(300);

      await h.driftAway(from: 320);

      // Eight times a 440 m beeline is longer than three and a half times a
      // 750 m one, so the far rejoin is the shorter ride of the two.
      expect(h.detour!.rejoinAlongM, closeTo(1000, 2));
      expect(h.scripted.queries, hasLength(2));
    });

    test('the finish of a long plan is never a candidate', () async {
      final h = await _NavHarness.create(
        saved: _longRoute(),
        // Everything loops, so all three candidates are really asked for.
        backend: _rejoinBackend(factor: 10),
      );
      await h.follow('route-2');
      await h.ride(300);

      await h.driftAway(from: 320);

      final asked = h.scripted.queries
          .map((q) => (q.points.last.lat - 48) * _metresPerDegree)
          .toList(growable: false);
      expect(asked, hasLength(3));
      expect(asked[0], closeTo(600, 60));
      expect(asked[1], closeTo(1100, 60));
      expect(asked[2], closeTo(2300, 60));
      expect(
        h.scripted.queries.map((q) => q.points.last),
        isNot(contains(_at(5000))),
        reason:
            'the end of the ride is three kilometres past the last '
            'candidate, and heading for it is not a way back onto the plan',
      );
    });

    test('a moving rider is routed through a point ahead of them', () async {
      final h = await _NavHarness.create(
        saved: _savedRoute(),
        backend: _rejoinBackend(),
      );
      await h.follow('route-1');
      await h.ride(300);

      await h.driftAway(from: 320);

      final points = h.scripted.queries.first.points;
      expect(points, hasLength(3), reason: 'start, heading via, target');
      expect(
        haversineMeters(points[0], points[1]),
        closeTo(headingViaMeters, 1),
      );
      // Due north, the way the rider was going.
      expect(points[1].lat, greaterThan(points[0].lat));
      expect(points[1].lon, closeTo(points[0].lon, 1e-9));
    });

    test('a rider barely moving is routed straight there', () async {
      final h = await _NavHarness.create(
        saved: _savedRoute(),
        backend: _rejoinBackend(),
      );
      await h.follow('route-1');
      await h.ride(300);
      await h.strayOff(from: 320);

      h.clock.advance(const Duration(seconds: 31));
      await h.stray(340, speedMps: 0.4);

      expect(h.scripted.queries.first.points, hasLength(2));
    });

    test(
      'the branch is drawn beside the plan, and navigated into it',
      () async {
        final h = await _NavHarness.create(
          saved: _savedRoute(),
          backend: _rejoinBackend(),
        );
        await h.follow('route-1');
        await h.ride(300);

        await h.driftAway(from: 320);

        final detour = h.detour!;
        expect(
          detour.branch,
          isNotEmpty,
          reason: 'the map draws this on its own',
        );
        expect(detour.line.length, greaterThan(detour.branch.length));
        expect(detour.line.first, detour.branch.first);
        expect(
          detour.line.last,
          _at(1000),
          reason: 'it runs to the end of the ride',
        );
        // The plan's own "arrive" comes after the rejoin, re-indexed onto the
        // stitched line; the way back's own end hint is dropped.
        expect(detour.turns.last.kind, TurnKind.end);
        expect(detour.turns.last.pointIndex, detour.line.length - 1);
      },
    );

    test('drifting off the branch asks for another, at most every twenty '
        'seconds', () async {
      final h = await _NavHarness.create(
        saved: _savedRoute(),
        backend: _rejoinBackend(),
      );
      await h.follow('route-1');
      await h.ride(300);
      await h.driftAway(from: 320);
      final asked = h.scripted.callCount;

      // Well away from the branch, which runs 500 m east.
      await h.stray(360, asideM: 1500);
      expect(h.scripted.callCount, asked, reason: 'too soon');

      h.clock.advance(const Duration(seconds: 21));
      await h.stray(380, asideM: 1500);
      expect(h.scripted.callCount, greaterThan(asked));
    });

    test('reaching the plan again drops the branch and carries on', () async {
      final h = await _NavHarness.create(
        saved: _savedRoute(),
        backend: _rejoinBackend(),
      );
      await h.follow('route-1');
      await h.ride(300);
      await h.driftAway(from: 320);
      expect(h.detour, isNotNull);
      final saidSoFar = h.speaker.spoken.length;

      await h.ride(700);

      expect(h.detour, isNull);
      expect(h.active!.key, 'saved:route-1');
      expect(h.offRouteState, OffRouteState.onRoute);
      expect(h.progress!.offRoute, isFalse);
      expect(h.progress!.alongM, closeTo(700, 5));
      expect(h.speaker.spoken.length, saidSoFar);
    });

    test(
      'a router that answers nothing leaves the rider being guided',
      () async {
        final h = await _NavHarness.create(
          saved: _savedRoute(),
          backend: _ScriptedBackend((_) => null),
        );
        await h.follow('route-1');
        await h.ride(300);

        await h.driftAway(from: 320);

        expect(h.detour, isNull);
        expect(h.offRouteState, OffRouteState.guiding);
        expect(h.progress!.rerouting, isFalse);
      },
    );

    test('the end of the ride drops the branch', () async {
      final h = await _NavHarness.create(
        saved: _savedRoute(),
        backend: _rejoinBackend(),
      );
      await h.follow('route-1');
      await h.ride(300);
      await h.driftAway(from: 320);
      expect(h.detour, isNotNull);

      await h.stopRiding();

      expect(h.detour, isNull);
      expect(h.progress, isNull);
    });

    test('a tap on the banner asks for one now', () async {
      final h = await _NavHarness.create(
        saved: _savedRoute(),
        backend: _rejoinBackend(),
      );
      await h.follow('route-1');
      await h.ride(300);
      await h.strayOff(from: 320);
      expect(h.scripted.callCount, 0);

      h.container.read(navigationControllerProvider.notifier).requestRejoin();
      await _NavHarness._settle();

      expect(h.detour, isNotNull);
    });
  });

  group('re-routing switched off', () {
    test('the rider is guided back and nothing else happens', () async {
      final h = await _NavHarness.create(
        saved: _savedRoute(),
        backend: _rejoinBackend(),
        preferences: const <String, Object>{'navigation.reroute': false},
      );
      await h.follow('route-1');
      await h.ride(300);

      await h.driftAway(from: 320);
      h.clock.advance(const Duration(minutes: 10));
      await h.stray(400, asideM: 5000);

      expect(h.scripted.callCount, 0);
      expect(h.detour, isNull);
      expect(h.offRouteState, OffRouteState.guiding);
      expect(h.guidance, isNotNull);
    });

    test('a tap on the banner does not go behind the rider\'s back', () async {
      final h = await _NavHarness.create(
        saved: _savedRoute(),
        backend: _rejoinBackend(),
        preferences: const <String, Object>{'navigation.reroute': false},
      );
      await h.follow('route-1');
      await h.ride(300);
      await h.strayOff(from: 320);

      h.container.read(navigationControllerProvider.notifier).requestRejoin();
      await _NavHarness._settle();

      expect(h.scripted.callCount, 0);
      expect(h.detour, isNull);
    });

    test('but the rider may still ask for a new route outright', () async {
      final h = await _NavHarness.create(
        saved: _savedRoute(),
        backend: _rejoinBackend(),
        preferences: const <String, Object>{'navigation.reroute': false},
      );
      await h.follow('route-1');
      await h.ride(300);
      await h.strayOff(from: 320);

      h.container
          .read(navigationControllerProvider.notifier)
          .requestFullReroute();
      await _NavHarness._settle();

      expect(h.detour, isNotNull);
      expect(h.detour!.replacesPlan, isTrue);
    });
  });

  group('the whole ride re-planned', () {
    test('three kilometres out for five minutes', () async {
      final h = await _NavHarness.create(
        saved: _savedRoute(),
        backend: _rejoinBackend(),
      );
      await h.follow('route-1');
      await h.ride(300);
      await h.strayOff(from: 320, asideM: 4000);
      expect(h.scripted.callCount, 0);

      h.clock.advance(const Duration(minutes: 6));
      await h.stray(340, asideM: 4000);

      final detour = h.detour!;
      expect(detour.replacesPlan, isTrue);
      expect(
        detour.branch,
        isEmpty,
        reason: 'it is the plan now, not a branch',
      );
      expect(h.active!.key, detour.key);
      expect(h.speaker.spoken, contains('Route recalculated'));
      // The new route runs from where the rider stands to the rest of the
      // plan's waypoints, exactly as a re-route always did.
      expect(h.scripted.queries.last.points.first, _at(340, asideM: 4000));
      expect(h.scripted.queries.last.points.last, _at(1000));
    });

    test('a long way out but not for long is still only a rejoin', () async {
      final h = await _NavHarness.create(
        saved: _savedRoute(),
        backend: _rejoinBackend(),
      );
      await h.follow('route-1');
      await h.ride(300);
      await h.strayOff(from: 320, asideM: 4000);

      h.clock.advance(const Duration(seconds: 31));
      await h.stray(340, asideM: 4000);

      expect(h.detour!.replacesPlan, isFalse);
      expect(h.detour!.branch, isNotEmpty);
    });

    test('the new route is the one the rider is then held to', () async {
      final h = await _NavHarness.create(
        saved: _savedRoute(),
        backend: _rejoinBackend(),
      );
      await h.follow('route-1');
      await h.ride(300);
      await h.strayOff(from: 320, asideM: 4000);

      h.container
          .read(navigationControllerProvider.notifier)
          .requestFullReroute();
      await _NavHarness._settle();
      expect(h.detour!.replacesPlan, isTrue);

      // Back on the plan's own line, which the new route no longer is: that
      // is now off route, not a restore.
      await h.ride(400);
      await h.ride(420);

      expect(h.detour!.replacesPlan, isTrue, reason: 'the new route stands');
    });
  });
}

/// Whether [phrase] is the spoken way back onto the route.
bool _isWayBack(String phrase) => phrase.startsWith('Off route.');

/// A route from [from] to [to] in 100 m steps, [lengthM] long as far as the
/// cost comparison is concerned.
RouteResult _wayBack(LatLng from, LatLng to, double lengthM) => RouteResult(
  geometry: <TrackPoint>[
    TrackPoint(from),
    TrackPoint(LatLng((from.lat + to.lat) / 2, from.lon)),
    TrackPoint(LatLng((from.lat + to.lat) / 2, to.lon)),
    TrackPoint(to),
  ],
  lengthM: lengthM,
  ascentM: 0,
  descentM: 0,
  messages: const <SegmentMessage>[],
  raw: const <String, dynamic>{},
  turns: const <TurnHint>[
    TurnHint(pointIndex: 1, kind: TurnKind.right),
    TurnHint(pointIndex: 3, kind: TurnKind.end),
  ],
);

/// A backend that answers every rejoin with a way back [factor] times the
/// straight line to the target it was asked for.
///
/// Under three that is a road that bends; over three it is a loop round a
/// river, and the candidate is skipped. [factors] overrides the multiple for
/// the candidate at that many metres along the plan.
_ScriptedBackend _rejoinBackend({
  double factor = 1.2,
  Map<double, double> factors = const <double, double>{},
}) => _ScriptedBackend((q) {
  final target = q.points.last;
  final alongM = (target.lat - 48) * _metresPerDegree;
  var multiple = factor;
  for (final entry in factors.entries) {
    if ((entry.key - alongM).abs() < 20) multiple = entry.value;
  }
  return _wayBack(
    q.points.first,
    target,
    haversineMeters(q.points.first, target) * multiple,
  );
});

/// A router that answers from a script and remembers what it was asked.
class _ScriptedBackend implements RoutingBackend {
  _ScriptedBackend(this.answer);

  /// The answer for one query, or `null` for "no route between those".
  final RouteResult? Function(RouteQuery query) answer;

  /// Every query that arrived, in order.
  final List<RouteQuery> queries = <RouteQuery>[];

  /// How often [route] was called.
  int get callCount => queries.length;

  @override
  Future<RouteResult> route(RouteQuery q, {CancelToken? cancel}) async {
    queries.add(q);
    if (cancel != null && cancel.isCancelled) throw cancel.toException();
    final result = answer(q);
    if (result == null) {
      throw const RoutingException(
        kind: RoutingErrorKind.noRoute,
        message: 'nothing here',
      );
    }
    return result;
  }
}

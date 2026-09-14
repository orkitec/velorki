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
import 'package:velorki/features/planner/domain/planner_state.dart';
import 'package:velorki/features/planner/domain/route_profile.dart';
import 'package:velorki/features/planner/domain/routing_options.dart';
import 'package:velorki/features/planner/domain/saved_route.dart';
import 'package:velorki/features/recording/application/recording_controller.dart';
import 'package:velorki/features/recording/data/recording_service.dart';
import 'package:velorki/features/recording/domain/recording_snapshot.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../recording/support/fakes.dart';

/// One degree of latitude, the same figure the recording fakes use.
const double _metresPerDegree = 111194.9266;

/// A point [alongM] north of 48°/11°.
LatLng _at(double alongM) => LatLng(48 + alongM / _metresPerDegree, 11);

/// A straight kilometre north, a point every 50 m.
List<TrackPoint> _geometry() => <TrackPoint>[
  for (var i = 0; i <= 20; i++) TrackPoint(_at(i * 50.0)),
];

/// Turn left at 500 m, arrive at 1000 m.
const List<TurnHint> _turns = <TurnHint>[
  TurnHint(pointIndex: 10, kind: TurnKind.left, distanceToNextM: 500),
  TurnHint(pointIndex: 20, kind: TurnKind.end),
];

SavedRoute _savedRoute({List<TurnHint> turns = _turns}) => SavedRoute(
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
  waypoints: const [],
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

RecordingSnapshot _snapshot({
  required double alongM,
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
  lastPosition: _at(alongM),
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
  _NavHarness._(this.container, this.service, this.speaker);

  static Future<_NavHarness> create({
    SavedRoute? saved,
    RouteResult? planned,
    Map<String, Object> preferences = const <String, Object>{},
  }) async {
    SharedPreferences.setMockInitialValues(preferences);
    final prefs = await SharedPreferences.getInstance();
    final service = FakeRecordingService();
    final speaker = FakeTurnSpeaker();
    final container = ProviderContainer(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        recordingServiceProvider.overrideWithValue(service),
        turnSpeakerProvider.overrideWithValue(speaker),
        navigationLocalizationsProvider.overrideWithValue(
          lookupAppLocalizations(const Locale('en')),
        ),
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
    return _NavHarness._(container, service, speaker);
  }

  final ProviderContainer container;
  final FakeRecordingService service;
  final FakeTurnSpeaker speaker;

  /// What the controller currently says.
  NavigationProgress? get progress =>
      container.read(navigationControllerProvider);

  /// Chooses the saved route to follow and lets the database answer.
  Future<void> follow(String? routeId) async {
    container.read(recordingControllerProvider.notifier).selectRoute(routeId);
    await _settle();
  }

  /// Pushes one fix through the recorder.
  Future<void> ride(double alongM, {double speedMps = 6}) async {
    service.emit(_snapshot(alongM: alongM, speedMps: speedMps));
    await _settle();
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
}

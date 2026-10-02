import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/settings/data/units.dart';
import 'package:velorki/core/db/tables/routes.dart' show RouteSource;
import 'package:velorki/core/plus/plus_gate.dart';
import 'package:velorki/features/assistant/application/ai_request_settings.dart';
import 'package:velorki/features/assistant/application/assistant_controller.dart';
import 'package:velorki/features/assistant/application/route_advice_controller.dart';
import 'package:velorki/features/assistant/application/route_digest_service.dart';
import 'package:velorki/features/assistant/domain/ai_consent.dart';
import 'package:velorki/features/assistant/domain/assistant_state.dart';
import 'package:velorki/features/integrations/common/data/relay_client_provider.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/data/routing_backend_provider.dart';
import 'package:velorki/features/planner/domain/avoid_area.dart';
import 'package:velorki/features/planner/domain/planner_state.dart';
import 'package:velorki/features/planner/domain/route_poi.dart';
import 'package:velorki/features/planner/domain/route_profile.dart';
import 'package:velorki_api/velorki_api.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../integrations/support/fakes.dart';
import 'support/fakes.dart';

/// Three points along one parallel, about 7.45 km apart.
const LatLng _a = LatLng(48.0, 11.0);
const LatLng _b = LatLng(48.0, 11.1);
const LatLng _c = LatLng(48.0, 11.2);

/// A router that rides straight from one point of a query to the next, so
/// a test knows how far along the route anything is; on a gravel bike it
/// bends each leg a kilometre north in its middle, so the same kilometres
/// name other places.
class _LineBackend implements RoutingBackend {
  final List<RouteQuery> queries = <RouteQuery>[];

  @override
  Future<RouteResult> route(RouteQuery q, {CancelToken? cancel}) async {
    queries.add(q);
    final from = q.points.first;
    final to = q.points.last;
    final bend = q.profile == RouteProfile.gravel.engineName ? 0.009 : 0.0;
    final geometry = <TrackPoint>[
      for (var i = 0; i <= 10; i++)
        TrackPoint(
          LatLng(
            from.lat +
                (to.lat - from.lat) * i / 10 +
                bend * (5 - (i - 5).abs()) / 5,
            from.lon + (to.lon - from.lon) * i / 10,
          ),
          ele: 500,
        ),
    ];
    final length = cumulativeDistancesMeters([for (final p in geometry) p.pos])
        .last;
    return RouteResult(
      geometry: geometry,
      lengthM: length,
      ascentM: 0,
      descentM: 0,
      messages: <SegmentMessage>[
        SegmentMessage(
          position: to,
          elevationM: 500,
          distanceM: length,
          costPerKm: 1000,
          elevCost: 0,
          turnCost: 0,
          nodeCost: 0,
          initialCost: 0,
          wayTags: SegmentMessage.parseTags('highway=primary surface=asphalt'),
          nodeTags: const <String, String>{},
          timeS: length / 5,
          energyJ: 0,
        ),
      ],
      raw: const <String, dynamic>{},
    );
  }
}

/// The digest the fake service answers with: a café on the second leg and
/// water on the first, both a little off the line.
const RouteDigest _digest = RouteDigest(
  loop: false,
  profile: 'trekking',
  places: <DigestPlace>[
    DigestPlace(
      id: 'p1',
      kind: 'drinking_water',
      km: 3,
      offM: 40,
      at: DigestPoint(lat: 48.0003, lon: 11.0403),
    ),
    DigestPlace(
      id: 'p2',
      kind: 'cafe',
      name: 'Café am Weg',
      km: 10,
      offM: 30,
      at: DigestPoint(lat: 48.0002, lon: 11.1343),
    ),
  ],
);

RouteAdvice _advice(List<RouteFinding> findings) =>
    RouteAdvice(answer: 'There is a café at 10 km.', findings: findings);

const RouteFinding _coffee = RouteFinding(
  kind: FindingKind.food,
  text: 'Café am Weg, 30 m off the route.',
  placeId: 'p2',
  fix: AddStopFix('p2'),
);

const RouteFinding _water = RouteFinding(
  kind: FindingKind.water,
  text: 'A tap at 3 km.',
  placeId: 'p1',
  fix: AddStopFix('p1'),
);

const RouteFinding _mainRoad = RouteFinding(
  kind: FindingKind.traffic,
  text: 'A main road from 2 to 4 km.',
  fromKm: 2,
  toKm: 4,
  fix: AvoidFix(fromKm: 2, toKm: 4),
);

const RouteFinding _gravel = RouteFinding(
  kind: FindingKind.profile,
  text: 'A gravel bike suits it.',
  fix: ProfileFix(ProfileHint.gravel),
);

class _Setup {
  _Setup(this.container, this.relay, this.backend, this.digests);

  final ProviderContainer container;
  final FakeRelayClient relay;
  final _LineBackend backend;
  final FakeRouteDigestService digests;

  PlannerController get planner =>
      container.read(plannerControllerProvider.notifier);
  PlannerState get plan => container.read(plannerControllerProvider);
  RouteAdviceController get advice =>
      container.read(routeAdviceControllerProvider.notifier);
  RouteAdviceState get state => container.read(routeAdviceControllerProvider);
}

/// A planner with A-B-C routed and a relay answering with [findings].
Future<_Setup> _setup(
  WidgetTester tester, {
  List<RouteFinding> findings = const <RouteFinding>[_coffee],
  bool entitled = true,
  AiConsent? consent = AiConsent.textOnly,
  Map<String, Object> prefs = const <String, Object>{},
  Object? digestError,
  RouteDigest digest = _digest,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    if (consent != null) aiConsentPrefsKey: consent.name,
    ...prefs,
  });
  final preferences = await SharedPreferences.getInstance();
  final relay = FakeRelayClient(
    planEvents: <PlanEvent>[
      RouteAdviceEvent(_advice(findings)),
      const DoneEvent(),
    ],
  );
  final backend = _LineBackend();
  final digests = FakeRouteDigestService(
    digest: digestError == null ? digest : null,
    error: digestError,
  );
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      relayClientProvider.overrideWithValue(relay),
      routingBackendProvider.overrideWithValue(backend),
      routeDigestServiceProvider.overrideWithValue(digests),
      systemLocalesProvider.overrideWithValue(const [Locale('de', 'DE')]),
      localeCountryProvider.overrideWithValue(null),
    ],
  );
  addTearDown(container.dispose);
  container.read(plusEntitledProvider.notifier).value = entitled;
  // Kept alive for the test, as the sheet does by watching it.
  container.listen(routeAdviceControllerProvider, (_, _) {});
  container.read(plannerControllerProvider.notifier)
    ..addWaypoint(_a)
    ..addWaypoint(_b)
    ..addWaypoint(_c);
  await tester.pump(plannerDebounce);
  await tester.pump();
  expect(container.read(plannerControllerProvider).result, isNotNull);
  return _Setup(container, relay, backend, digests);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(plannerDebounce);
  await tester.pump();
}

void main() {
  group('asking about the route on the map', () {
    testWidgets('sends the question with the digest of the planned route, '
        'in the app language and units, without a position', (tester) async {
      final s = await _setup(tester, prefs: {'units.system': 'imperial'});

      await s.advice.ask('  Where can I get coffee?  ');

      final call = s.relay.planCalls.single;
      expect(call.step, routeStep);
      expect(call.prompt, 'Where can I get coffee?');
      expect(call.locale, 'de-DE');
      expect(call.units, PlanUnits.imperial);
      expect(call.context, isNull);
      expect(call.routeSummary!.digest, _digest);
      expect(call.routeSummary!.distanceKm, closeTo(14.9, 0.1));
      // The planner's route came from the router, so its own messages are
      // the digest's ways: nothing is matched again.
      final (line, messages) = s.digests.tracks.single;
      expect(line, same(s.plan.result!.geometry));
      expect(messages, isNotEmpty);

      expect(s.state.phase, RouteAdvicePhase.answered);
      expect(s.state.advice!.answer, 'There is a café at 10 km.');
      expect(s.state.advice!.findings.single.fix, const AddStopFix('p2'));
    });

    testWidgets('a digest the phone cannot build still lets the question go, '
        'on the figures', (tester) async {
      final s = await _setup(tester, digestError: StateError('no tiles'));
      await s.advice.ask('Check this route');
      final digest = s.relay.planCalls.single.routeSummary!.digest!;
      expect(digest.places, isEmpty);
      expect(digest.profile, 'trekking');
      expect(digest.loop, isFalse);
    });

    testWidgets('an error event is the problem shown', (tester) async {
      final s = await _setup(tester);
      s.relay.planEvents = const <PlanEvent>[
        ErrorEvent(
          RelayError(code: RelayErrorCode.invalidRequest, message: 'nope'),
        ),
      ];
      await s.advice.ask('Check this route');
      expect(s.state.phase, RouteAdvicePhase.failed);
      expect(s.state.problem!.failure, AssistantFailure.relay);
      expect(s.state.problem!.message, 'nope');

      s.advice.clearProblem();
      expect(s.state.problem, isNull);
      expect(s.state.question, 'Check this route');
    });

    testWidgets('without Velorki Plus nothing is sent', (tester) async {
      final s = await _setup(tester, entitled: false);
      await s.advice.ask('Check this route');
      expect(s.relay.planCalls, isEmpty);
      expect(s.state.problem!.failure, AssistantFailure.notEntitled);
    });

    testWidgets('a "part of Plus" error goes once Plus is active, and the '
        'question stays', (tester) async {
      final s = await _setup(tester, entitled: false);
      await s.advice.ask('Check this route');
      expect(s.state.problem!.failure, AssistantFailure.notEntitled);

      s.container.read(plusEntitledProvider.notifier).value = true;
      await tester.pump(const Duration(milliseconds: 1));
      expect(s.state.problem, isNull);
      expect(s.state.question, 'Check this route');
    });

    testWidgets('without consent nothing is sent', (tester) async {
      final s = await _setup(tester, consent: AiConsent.denied);
      await s.advice.ask('Check this route');
      expect(s.relay.planCalls, isEmpty);
      expect(s.state.problem!.failure, AssistantFailure.consentRequired);
    });

    testWidgets('a stop the digest does not have loses its fix', (
      tester,
    ) async {
      final s = await _setup(
        tester,
        findings: const [
          RouteFinding(
            kind: FindingKind.food,
            text: 'A café.',
            fix: AddStopFix('p9'),
          ),
        ],
      );
      await s.advice.ask('Coffee?');
      expect(s.state.advice!.findings.single.fix, isNull);
      expect(s.state.advice!.findings.single.text, 'A café.');
    });
  });

  group('a route from Strava', () {
    test('is never offered to the assistant', () {
      final route = AsyncData<RouteResult?>(
        RouteResult(
          geometry: const [TrackPoint(_a), TrackPoint(_b)],
          lengthM: 7450,
          ascentM: 0,
          descentM: 0,
          messages: const <SegmentMessage>[],
          raw: const <String, dynamic>{},
        ),
      );
      expect(canAskAboutRoute(PlannerState(route: route)), isTrue);
      expect(
        canAskAboutRoute(
          PlannerState(route: route, savedRouteSource: RouteSource.strava),
        ),
        isFalse,
      );
      expect(
        canAskAboutRoute(
          PlannerState(route: route, savedRouteSource: RouteSource.rwgps),
        ),
        isTrue,
      );
      expect(canAskAboutRoute(const PlannerState()), isFalse);
    });
  });

  group('applying a fix', () {
    testWidgets('a stop goes into the leg the route passes it on, with its '
        'name and kind, and Undo takes it out', (tester) async {
      final s = await _setup(tester, findings: const [_water, _coffee]);
      await s.advice.ask('Coffee and water?');

      s.advice.apply(1);
      expect(s.plan.waypoints.map((w) => w.pos), <LatLng>[
        _a,
        _b,
        const LatLng(48.0002, 11.1343),
        _c,
      ]);
      final stop = s.plan.waypoints[2];
      expect(stop.name, 'Café am Weg');
      expect(stop.poiKind, PoiKind.food);
      expect(s.state.applied, {1});
      await _settle(tester);

      // The route changed, so the next stop goes where the new route
      // passes it.
      s.advice.apply(0);
      expect(s.plan.waypoints[1].pos, const LatLng(48.0003, 11.0403));
      expect(s.plan.waypoints[1].poiKind, PoiKind.water);
      expect(s.plan.waypoints[1].name, isNull);
      expect(s.state.applied, {0, 1});

      s.planner.undo();
      s.planner.undo();
      expect(s.plan.positions, <LatLng>[_a, _b, _c]);
    });

    testWidgets('a finding that names a place but came without a fix still '
        'offers the stop there', (tester) async {
      final s = await _setup(
        tester,
        findings: const [
          RouteFinding(
            kind: FindingKind.food,
            text: 'Café am Weg, 30 m off the route.',
            placeId: 'p2',
          ),
        ],
      );
      await s.advice.ask('Coffee?');
      expect(s.state.advice!.findings.single.fix, const AddStopFix('p2'));
      expect(s.advice.apply(0), isTrue);
      expect(s.plan.waypoints[2].name, 'Café am Weg');
      await _settle(tester);
    });

    testWidgets('the same course handed out as a new result still puts a '
        'stop at its distance along the route asked about', (tester) async {
      // Where the route passes it, 10 km in, is not where it lies nearest
      // the line, by the tap at 3 km.
      const digest = RouteDigest(
        loop: false,
        places: [
          DigestPlace(
            id: 'p1',
            kind: 'cafe',
            name: 'Kiosk',
            km: 10,
            offM: 30,
            at: DigestPoint(lat: 48.0003, lon: 11.0403),
          ),
        ],
      );
      final s = await _setup(
        tester,
        digest: digest,
        findings: const [
          RouteFinding(
            kind: FindingKind.food,
            text: 'A kiosk.',
            placeId: 'p1',
            fix: AddStopFix('p1'),
          ),
        ],
      );
      await s.advice.ask('Coffee?');
      final asked = s.plan.result!;
      s.planner.loadComputedRoute(
        result: RouteResult(
          geometry: [...asked.geometry],
          lengthM: asked.lengthM,
          ascentM: asked.ascentM,
          descentM: asked.descentM,
          messages: const [],
          raw: const <String, dynamic>{},
        ),
        waypoints: s.plan.waypoints,
        options: s.plan.options,
      );
      expect(s.state.advice, isNotNull, reason: 'the same plan');
      expect(s.advice.apply(0), isTrue);
      expect(s.plan.waypoints[2].name, 'Kiosk');
      await _settle(tester);
    });

    test('the same course is the same line, whatever object', () {
      RouteResult line(List<LatLng> points) => RouteResult(
        geometry: [for (final p in points) TrackPoint(p)],
        lengthM: cumulativeDistancesMeters(points).last,
        ascentM: 0,
        descentM: 0,
        messages: const [],
        raw: const <String, dynamic>{},
      );
      final ab = line(const [_a, _b]);
      expect(sameCourse(ab, line(const [_a, _b])), isTrue);
      expect(sameCourse(ab, line(const [_a, LatLng(48, 11.05), _b])), isTrue);
      expect(
        sameCourse(ab, line(const [_a, LatLng(48.01, 11.05), _b])),
        isFalse,
      );
      expect(sameCourse(ab, line(const [_a, _c])), isFalse);
    });

    testWidgets('a fix is applied once', (tester) async {
      final s = await _setup(tester);
      await s.advice.ask('Coffee?');
      s.advice
        ..apply(0)
        ..apply(0);
      expect(s.plan.waypoints, hasLength(4));
      expect(s.plan.undoStack, hasLength(4));
      await _settle(tester);
    });

    testWidgets('a profile fix switches the bike, undoably', (tester) async {
      final s = await _setup(tester, findings: const [_gravel]);
      await s.advice.ask('Is this ok for gravel?');

      s.advice.apply(0);
      expect(s.plan.options.profile, RouteProfile.gravel);
      await _settle(tester);
      expect(s.backend.queries.last.profile, RouteProfile.gravel.engineName);

      s.planner.undo();
      expect(s.plan.options.profile, RouteProfile.trekking);
    });

    testWidgets('a fix taken back with Undo is offered again, and only that '
        'one', (tester) async {
      final s = await _setup(tester, findings: const [_water, _coffee]);
      await s.advice.ask('Coffee and water?');
      s.advice.apply(1);
      await _settle(tester);
      s.advice.apply(0);
      await _settle(tester);
      expect(s.state.applied, {0, 1});

      s.planner.undo();
      expect(s.state.applied, {1});
      s.planner.undo();
      expect(s.state.applied, isEmpty);

      expect(s.advice.apply(1), isTrue);
      expect(s.state.applied, {1});
      await _settle(tester);
    });

    testWidgets('an avoid fix keeps every leg off the stretch, draws it, and '
        'Undo lets the router back on', (tester) async {
      final s = await _setup(tester, findings: const [_mainRoad]);
      await s.advice.ask('Avoid the main road');
      final before = s.backend.queries.length;

      s.advice.apply(0);
      expect(s.plan.avoid, hasLength(1));
      final area = s.plan.avoid.single;
      expect(area.fromKm, 2);
      expect(area.toKm, 4);
      expect(
        haversineMeters(area.line.first, area.line.last),
        closeTo(2000, 30),
      );
      expect(area.nogos, isNotEmpty);
      expect(area.nogos.every((n) => n.weight != null), isTrue);
      await _settle(tester);

      // Only the first leg runs over the stretch, so only it is routed
      // again, around it.
      final rerouted = s.backend.queries.sublist(before);
      expect(rerouted, hasLength(1));
      expect(rerouted.single.points, <LatLng>[_a, _b]);
      expect(rerouted.single.nogos, area.nogos);

      // Every leg routed from now on keeps off it too.
      s.planner.moveWaypoint(2, const LatLng(48.0, 11.25));
      await _settle(tester);
      expect(s.backend.queries.last.nogos, area.nogos);

      s.planner
        ..undo()
        ..undo();
      expect(s.plan.avoid, isEmpty);
    });

    testWidgets('clearing the avoided stretches routes every leg again', (
      tester,
    ) async {
      final s = await _setup(tester, findings: const [_mainRoad]);
      await s.advice.ask('Avoid the main road');
      s.advice.apply(0);
      await _settle(tester);
      final before = s.backend.queries.length;

      s.planner.clearAvoided();
      expect(s.plan.avoid, isEmpty);
      await _settle(tester);
      final again = s.backend.queries.sublist(before);
      expect(again, hasLength(2));
      expect(again.every((q) => q.nogos.isEmpty), isTrue);

      s.planner.undo();
      expect(s.plan.avoid, hasLength(1));
    });

    testWidgets('a stretch the route does not have is not offered to be '
        'avoided', (tester) async {
      final s = await _setup(
        tester,
        findings: const [
          RouteFinding(
            kind: FindingKind.traffic,
            text: 'Past the end.',
            fix: AvoidFix(fromKm: 40, toKm: 45),
          ),
        ],
      );
      await s.advice.ask('Avoid the main road');
      expect(s.state.advice!.findings.single.fix, isNull);
      expect(s.state.advice!.findings.single.text, 'Past the end.');
      expect(s.advice.apply(0), isFalse);
      expect(s.state.failures, isEmpty);
      expect(s.plan.avoid, isEmpty);
      expect(s.plan.undoStack, hasLength(3));
    });

    /// Asks about [fix] and applies it; the area it put on the plan.
    Future<AvoidArea> avoid(WidgetTester tester, AvoidFix fix) async {
      final s = await _setup(
        tester,
        findings: [
          RouteFinding(kind: FindingKind.traffic, text: 'A road.', fix: fix),
        ],
      );
      await s.advice.ask('Avoid the main road');
      expect(s.advice.apply(0), isTrue);
      expect(s.state.failures, isEmpty);
      expect(s.state.applied, {0});
      await _settle(tester);
      return s.plan.avoid.single;
    }

    double lengthOf(AvoidArea area) =>
        cumulativeDistancesMeters(area.line).last;

    testWidgets('a point to avoid is widened to a stretch around it', (
      tester,
    ) async {
      final area = await avoid(tester, const AvoidFix(fromKm: 5, toKm: 5));
      expect(lengthOf(area), closeTo(avoidMinStretchM, 1));
      expect(area.fromKm, closeTo(4.85, 0.001));
      expect(area.toKm, closeTo(5.15, 0.001));
    });

    testWidgets('a stretch running past the end stops at the end', (
      tester,
    ) async {
      final area = await avoid(tester, const AvoidFix(fromKm: 14, toKm: 20));
      expect(area.fromKm, 14);
      expect(area.line.last, _c);
    });

    testWidgets('a stretch starting where the route ends is its last metres', (
      tester,
    ) async {
      final area = await avoid(
        tester,
        const AvoidFix(fromKm: 15.0, toKm: 15.5),
      );
      expect(area.line.last, _c);
      expect(lengthOf(area), closeTo(avoidMinStretchM, 1));
    });

    testWidgets('an avoid applied after a stop changed the route keeps off '
        'the stretch the answer was about', (tester) async {
      final s = await _setup(tester, findings: const [_water, _mainRoad]);
      await s.advice.ask('Water, and the main road?');
      final asked = s.plan.result!.positions;

      // The stop at 3 km lies inside the stretch and bends the route.
      expect(s.advice.apply(0), isTrue);
      await _settle(tester);
      expect(s.plan.result!.positions, isNot(asked));

      expect(s.advice.apply(1), isTrue);
      expect(s.state.failures, isEmpty);
      expect(s.plan.avoid.single.line, AvoidArea.cut(asked, 2000, 4000));
      await _settle(tester);
      // The leg the stretch lies on, now split by the stop, is routed
      // around it; the last leg is not.
      expect(s.backend.queries.last.nogos, s.plan.avoid.single.nogos);
    });

    testWidgets('an avoid applied after the bike changed keeps off the '
        'stretch the answer was about', (tester) async {
      final s = await _setup(tester, findings: const [_gravel, _mainRoad]);
      await s.advice.ask('Gravel, and the main road?');
      final asked = s.plan.result!.positions;

      expect(s.advice.apply(0), isTrue);
      await _settle(tester);
      // On the gravel bike the same kilometres are somewhere else.
      final now = s.plan.result!.positions;
      expect(
        AvoidArea.cut(now, 2000, 4000),
        isNot(AvoidArea.cut(asked, 2000, 4000)),
      );

      expect(s.advice.apply(1), isTrue);
      expect(s.state.failures, isEmpty);
      expect(s.plan.avoid.single.line, AvoidArea.cut(asked, 2000, 4000));
    });
  });

  group('the conversation', () {
    testWidgets('lasts while the plan has the same ends, fixes and all', (
      tester,
    ) async {
      final s = await _setup(tester);
      await s.advice.ask('Coffee?');
      s.advice.apply(0);
      await _settle(tester);
      expect(s.state.applied, {0});
      expect(s.state.advice, isNotNull);

      s.planner.setProfile(RouteProfile.fastbike);
      await _settle(tester);
      expect(s.state.advice, isNotNull);
      expect(s.state.question, 'Coffee?');
    });

    testWidgets('starts afresh when the plan is cleared or has other ends', (
      tester,
    ) async {
      final s = await _setup(tester);
      await s.advice.ask('Coffee?');
      s.planner.moveWaypoint(0, const LatLng(48.01, 11.0));
      expect(s.state.isEmpty, isTrue);

      await _settle(tester);
      await s.advice.ask('Coffee?');
      expect(s.state.advice, isNotNull);
      s.planner.clear();
      expect(s.state.isEmpty, isTrue);
    });

    testWidgets('Start over forgets the question and the answer', (
      tester,
    ) async {
      final s = await _setup(tester);
      await s.advice.ask('Coffee?');
      s.advice.reset();
      expect(s.state.isEmpty, isTrue);
      expect(s.state.applied, isEmpty);
    });
  });
}

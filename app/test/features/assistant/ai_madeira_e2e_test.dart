// "This route" and "Describe this route" end to end, on a real route: planned
// on the oracle's Madeira tile, its digest built on the phone from the tile
// and the committed gazetteer, sent through the app's RelayClient to the relay
// mocked at the HTTP layer, whose answers name places of the digest the app
// actually sent. The fixes go through the real planner and router.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/core/db/tables/routes.dart' show RouteSource;
import 'package:velorki/core/permissions/location_permission.dart';
import 'package:velorki/core/plus/plus_gate.dart';
import 'package:velorki/features/assistant/application/route_advice_controller.dart';
import 'package:velorki/features/assistant/application/route_description_controller.dart';
import 'package:velorki/features/assistant/data/ai_consent_controller.dart';
import 'package:velorki/features/assistant/domain/ai_consent.dart';
import 'package:velorki/features/assistant/presentation/assistant_sheet.dart';
import 'package:velorki/features/assistant/presentation/describe_route_sheet.dart';
import 'package:velorki/features/library/presentation/route_detail_screen.dart';
import 'package:velorki/features/map/data/position_provider.dart';
import 'package:velorki/features/navigation/presentation/turn_phrases.dart';
import 'package:velorki/features/planner/domain/route_poi.dart';
import 'package:velorki/features/map/domain/map_controller.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/planner/domain/route_profile.dart';
import 'package:velorki/features/planner/domain/routing_options.dart';
import 'package:velorki/features/planner/domain/waypoint.dart';
import 'package:velorki/features/planner/presentation/planner_screen.dart';
import 'package:velorki/features/planner/presentation/route_format.dart';
import 'package:velorki/features/shared/presentation/stat_tile.dart';
import 'package:velorki/features/smart_loop/application/smart_loop_controller.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';
import '../planner/support/pump.dart';
import 'support/ai_e2e.dart';
import 'support/fakes.dart';

const String _question = 'Where can I get a coffee, and is there traffic?';

/// The stretch a model would call busy: the first on a main road, away from
/// both ends; else the middle of the route.
(double, double) _busyStretch(RecordedPlanRequest request) {
  final length = request.routeSummary!['distance_km']! as num;
  final stretches = (request.digest!['stretches'] as List<Object?>? ?? [])
      .cast<Map<String, Object?>>();
  for (final s in stretches) {
    final from = s['from_km']! as num;
    final to = s['to_km']! as num;
    if (const {'primary', 'secondary', 'trunk'}.contains(s['road']) &&
        from > 1 &&
        to < length - 1 &&
        to - from > 0.3) {
      return (from.toDouble(), to.toDouble());
    }
  }
  return (length * 0.45, length * 0.55);
}

/// The first café of the digest [request] carries.
Map<String, Object?> _cafe(RecordedPlanRequest request) =>
    (request.digest!['places']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .firstWhere((p) => p['kind'] == 'cafe');

/// What the model answers about the route it was sent: a café of its digest
/// to stop at, a busy stretch to keep off and a faster bike.
RelayReply _advice({bool stopOnly = false}) => RelayReply.answering((request) {
  final cafe = _cafe(request);
  final (from, to) = _busyStretch(request);
  return RelayReply.stream([
    SseFrame.routeAdvice({
      'answer': '${cafe['name']} is right by the road at ${cafe['km']} km.',
      'findings': [
        {
          'kind': 'food',
          'place_id': cafe['id'],
          'text': '${cafe['name']}, ${cafe['off_m']} m off the route.',
          'fix': {'type': 'add_stop', 'place_id': cafe['id']},
        },
        if (!stopOnly) ...[
          {
            'kind': 'traffic',
            'from_km': from,
            'to_km': to,
            'text': 'A busy main road.',
            'fix': {'type': 'avoid', 'from_km': from, 'to_km': to},
          },
          {
            'kind': 'profile',
            'text': 'Mostly asphalt: the road bike suits it.',
            'fix': {'type': 'profile', 'profile': 'fastbike'},
          },
        ],
      ],
    }),
    SseFrame.done(),
  ], gap: const Duration(milliseconds: 300));
});

/// The Plan tab with a route from Funchal to Machico on the map, Plus and
/// consent in place; or, with [load], whatever it puts on the planner.
Future<(PlannerHarness, ProviderContainer)> _plannedRoute(
  WidgetTester tester,
  Madeira madeira,
  MockRelay relay, {
  Future<void> Function(PlannerHarness h, ProviderContainer c)? load,
}) async {
  final harness = await pumpScreen(
    tester,
    const PlannerScreen(),
    harness: PlannerHarness(backend: RealRouting(madeira.composite)),
    extraOverrides: [
      ...mockRelayOverrides(relay),
      ...madeira.overrides,
      locationPermissionGatewayProvider.overrideWithValue(
        const GrantedLocationPermission(),
      ),
      positionSourceProvider.overrideWithValue(
        const FixedPositionSource(Madeira.funchal),
      ),
    ],
  );
  final c = ProviderScope.containerOf(
    tester.element(find.byType(PlannerScreen)),
  );
  c.read(plusEntitledProvider.notifier).value = true;
  await c.read(aiConsentControllerProvider.notifier).set(AiConsent.textOnly);
  if (load != null) {
    await load(harness, c);
    await tester.pumpAndSettle();
    if (c.read(plannerControllerProvider).hasPoints) {
      await settle(tester, () => _routed(c), what: 'the route loaded');
    }
    return (harness, c);
  }
  c.read(plannerControllerProvider.notifier)
    ..addWaypoint(Madeira.funchal)
    ..addWaypoint(Madeira.machico);
  await settle(tester, () => _routed(c), what: 'the route to Machico');
  return (harness, c);
}

/// A round trip from Funchal as the smart loop's round-trip search draws
/// it: one query point, the start.
Future<RouteResult> _roundTrip(WidgetTester tester, Madeira madeira) async =>
    (await tester.runAsync(
      () => madeira.local.route(
        const RouteQuery(
          points: [Madeira.funchal],
          profile: 'velorki-trekking',
          roundTrip: true,
          roundTripDistanceM: 6000,
          roundTripDirectionDeg: 60,
        ),
      ),
    ))!;

/// The route from Funchal to Machico as the router draws it.
Future<RouteResult> _toMachico(WidgetTester tester, Madeira madeira) async =>
    (await tester.runAsync(
      () => madeira.local.route(
        const RouteQuery(
          points: [Madeira.funchal, Madeira.machico],
          profile: 'velorki-trekking',
        ),
      ),
    ))!;

/// The share of [before]'s points that are still points of [after].
double _kept(RouteResult before, RouteResult after) {
  final now = {for (final p in after.positions) p};
  return before.positions.where(now.contains).length / before.positions.length;
}

/// Asks [_advice] about whatever is on the map, then applies Add as stop
/// and Avoid, each of which must go through and leave a route.
Future<void> _stopAndAvoid(
  WidgetTester tester,
  ProviderContainer c,
  MockRelay relay,
) async {
  await _openAssistant(tester);
  await _ask(tester, c);
  final cafe = _cafe(relay.last);
  for (final label in [l10n.assistantFixAddStop, l10n.assistantFixAvoid]) {
    await _applyFix(tester, c, label);
    final plan = c.read(plannerControllerProvider);
    expect(
      c.read(routeAdviceControllerProvider).failures,
      isEmpty,
      reason: label,
    );
    expect(inSheet(find.text(l10n.assistantFixNotApplicable)), findsNothing);
    expect(plan.error, isNull, reason: label);
    expect(plan.result, isNotNull, reason: label);
  }
  final plan = c.read(plannerControllerProvider);
  expect(plan.waypoints.map((w) => w.name), contains(cafe['name']));
  expect(plan.avoid, hasLength(1));
  expect(inSheet(find.text(l10n.assistantFixApplied)), findsNWidgets(2));
}

bool _routed(ProviderContainer c) {
  final plan = c.read(plannerControllerProvider);
  return plan.result != null && !plan.isRouting;
}

Future<void> _openAssistant(WidgetTester tester) async {
  await tester.tap(
    find.widgetWithText(LabeledIconButton, l10n.assistantAction),
  );
  await tester.pumpAndSettle();
}

Future<void> _ask(WidgetTester tester, ProviderContainer c) async {
  await tester.enterText(inSheet(find.byType(TextField)), _question);
  await tester.tap(
    inSheet(find.widgetWithText(FilledButton, l10n.assistantSend)),
  );
  await settle(
    tester,
    () => !c.read(routeAdviceControllerProvider).busy,
    what: 'the answer',
  );
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

/// Taps the fix button [label] and waits for the planner to route with it.
Future<void> _applyFix(
  WidgetTester tester,
  ProviderContainer c,
  String label,
) async {
  final button = inSheet(find.widgetWithText(FilledButton, label));
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pump();
  await settle(tester, () => _routed(c), what: 'the route with "$label"');
  await tester.pumpAndSettle();
}

void main() {
  final spec = OpenApi.load();
  late Madeira madeira;

  Future<void> openMadeira(WidgetTester tester) async {
    await tester.runAsync(() async => madeira = await Madeira.open());
    addTearDown(() => tester.runAsync(madeira.close));
  }

  testWidgets('2 · a question about a planned route goes with its digest; '
      'Add as stop, Avoid and the bike each change the route, and Undo '
      'takes each back', (tester) async {
    await openMadeira(tester);
    final relay = MockRelay(schemas: spec.check)..reply(_advice());
    final (harness, c) = await _plannedRoute(tester, madeira, relay);
    final asked = c.read(plannerControllerProvider).result!;

    await _openAssistant(tester);
    expect(inSheet(find.text(l10n.assistantRouteTitle)), findsOneWidget);
    await _ask(tester, c);

    // What went out: the route, read on the phone, and nothing of the rider.
    final sent = relay.requests.single;
    expect(sent.step, 'route');
    expect(sent.prompt, _question);
    expect(sent.locale, appLanguageTag);
    expect(sent.units, 'metric');
    expect(sent.consented, isTrue);
    expect(sent.body.containsKey('context'), isFalse);
    expect(
      sent.routeSummary!['distance_km']! as num,
      closeTo(asked.lengthM / 1000, 0.5),
    );
    expect(sent.digest!['profile'], 'trekking');
    expect(sent.digest!['stretches'], isNotEmpty);
    final towns = [
      for (final t in sent.digest!['towns']! as List<Object?>)
        (t! as Map<String, Object?>)['name'],
    ];
    expect(towns, containsAll(<String>['Funchal', 'Machico']));
    final cafe = _cafe(sent);

    // The answer and its three findings, each with its fix.
    expect(inSheet(find.textContaining('${cafe['name']} is right')), findsOne);
    final fastbike = l10n.assistantFixProfile(
      profileLabel(l10n, RouteProfile.fastbike),
    );
    for (final label in [
      l10n.assistantFixAddStop,
      l10n.assistantFixAvoid,
      fastbike,
    ]) {
      expect(inSheet(find.widgetWithText(FilledButton, label)), findsOne);
    }

    // Add as stop: the café goes in between, and the map goes to it.
    harness.map.movedTo = null;
    await _applyFix(tester, c, l10n.assistantFixAddStop);
    var plan = c.read(plannerControllerProvider);
    final at = LatLng(
      (cafe['lat']! as num).toDouble(),
      (cafe['lon']! as num).toDouble(),
    );
    expect(plan.waypoints.map((w) => w.name), [null, cafe['name'], null]);
    expect(plan.waypoints[1].pos, at);
    expect(plan.error, isNull);
    expect(harness.map.movedTo, at);
    final withStop = plan.result!;

    // Avoid: the stretch is kept off, the route goes another way, and the
    // map shows the stretch.
    harness.map.fittedBounds = null;
    await _applyFix(tester, c, l10n.assistantFixAvoid);
    plan = c.read(plannerControllerProvider);
    expect(c.read(routeAdviceControllerProvider).failures, isEmpty);
    expect(plan.avoid, hasLength(1));
    expect(plan.error, isNull);
    expect(plan.result!.geometry, isNot(withStop.geometry));
    expect(harness.map.fittedBounds, isNotNull);

    // The bike.
    await _applyFix(tester, c, fastbike);
    plan = c.read(plannerControllerProvider);
    expect(plan.options.profile, RouteProfile.fastbike);
    expect(plan.error, isNull);
    expect(inSheet(find.text(l10n.assistantFixApplied)), findsNWidgets(3));

    // Undo, on the planner, takes the three back one by one.
    await tester.tapAt(const Offset(500, 40));
    await tester.pumpAndSettle();
    expect(find.byType(AssistantSheet), findsNothing);
    final undo = find.widgetWithText(LabeledIconButton, l10n.plannerUndo);
    for (var i = 0; i < 3; i++) {
      await tester.ensureVisible(undo);
      await tester.tap(undo);
      await settle(tester, () => _routed(c), what: 'undo ${i + 1}');
    }
    plan = c.read(plannerControllerProvider);
    expect(plan.waypoints.map((w) => w.pos), [
      Madeira.funchal,
      Madeira.machico,
    ]);
    expect(plan.avoid, isEmpty);
    expect(plan.options.profile, RouteProfile.trekking);
    expect(plan.result!.lengthM, closeTo(asked.lengthM, 1));

    // The answer is still there, and the fixes taken back are offered again.
    await _openAssistant(tester);
    expect(inSheet(find.textContaining('${cafe['name']} is right')), findsOne);
    expect(inSheet(find.text(l10n.assistantFixApplied)), findsNothing);
    expect(
      inSheet(find.widgetWithText(FilledButton, l10n.assistantFixAddStop)),
      findsOne,
    );
  });

  testWidgets('9 · Show marks the place on the map with its name and icon, '
      'without touching the plan; Add as stop puts the waypoint in its place, '
      'and Start over takes a mark away', (tester) async {
    await openMadeira(tester);
    final relay = MockRelay(schemas: spec.check)..reply(_advice());
    final (harness, c) = await _plannedRoute(tester, madeira, relay);
    final before = c.read(plannerControllerProvider);
    await _openAssistant(tester);
    await _ask(tester, c);
    final cafe = _cafe(relay.last);
    final at = LatLng(
      (cafe['lat']! as num).toDouble(),
      (cafe['lon']! as num).toDouble(),
    );
    final marker = MapPoi(
      position: at,
      name: cafe['name']! as String,
      kind: MapPoiKind.food,
      icon: poiIcon(PoiKind.food),
      selected: true,
    );
    // tapInSheet looks inside the sheet itself.
    Finder show() => find.widgetWithText(TextButton, l10n.assistantFindingShow);

    expect(harness.map.pois, isNot(contains(marker)));
    await tapInSheet(tester, show().first);
    expect(harness.map.movedTo, at);
    expect(harness.map.pois, contains(marker));
    final plan = c.read(plannerControllerProvider);
    expect(plan.waypoints, before.waypoints);
    expect(plan.pois, isEmpty);
    expect(plan.undoStack, hasLength(before.undoStack.length));
    expect(plan.isRouting, isFalse);

    // The stretch: fitted, the mark stays.
    harness.map.fittedBounds = null;
    await tapInSheet(tester, show().at(1));
    expect(harness.map.fittedBounds, isNotNull);
    expect(harness.map.pois, contains(marker));

    await _applyFix(tester, c, l10n.assistantFixAddStop);
    expect(harness.map.pois, isNot(contains(marker)));
    expect(harness.map.waypoints.map((w) => w.position), contains(at));

    // Shown again after Undo, then cleared by Start over.
    c.read(plannerControllerProvider.notifier).undo();
    await settle(tester, () => _routed(c), what: 'undo');
    await tapInSheet(tester, show().first);
    expect(harness.map.pois, contains(marker));
    await tapInSheet(tester, find.text(l10n.assistantStartOver));
    expect(harness.map.pois, isNot(contains(marker)));
  });

  testWidgets('7 · closed and opened again the sheet keeps the question and '
      'the answer about the route; Start over clears both', (tester) async {
    await openMadeira(tester);
    final relay = MockRelay(schemas: spec.check)
      ..reply(_advice(stopOnly: true));
    final (_, c) = await _plannedRoute(tester, madeira, relay);
    await _openAssistant(tester);
    await _ask(tester, c);
    final answer = c.read(routeAdviceControllerProvider).advice!.answer;
    expect(inSheet(find.text(answer)), findsOne);

    await tester.tapAt(const Offset(500, 40));
    await tester.pumpAndSettle();
    await _openAssistant(tester);
    expect(inSheet(find.text(answer)), findsOne);
    expect(sheetField(tester).controller!.text, _question);
    expect(relay.requests, hasLength(1), reason: 'nothing asked again');

    await tapInSheet(tester, find.text(l10n.assistantStartOver));
    expect(inSheet(find.text(answer)), findsNothing);
    expect(sheetField(tester).controller!.text, isEmpty);
    expect(c.read(routeAdviceControllerProvider).isEmpty, isTrue);
    expect(inSheet(find.text(l10n.assistantExamples.toUpperCase())), findsOne);
  });

  testWidgets('6 · asked about the route, a relay that goes silent is given '
      'up after the idle timeout, and Try again asks again', (tester) async {
    await openMadeira(tester);
    final relay = MockRelay(schemas: spec.check)
      ..reply(RelayReply.stall())
      ..reply(_advice(stopOnly: true));
    final (_, c) = await _plannedRoute(tester, madeira, relay);
    await _openAssistant(tester);
    await tester.enterText(inSheet(find.byType(TextField)), _question);
    await tester.tap(
      inSheet(find.widgetWithText(FilledButton, l10n.assistantSend)),
    );
    await settle(tester, () => relay.requests.isNotEmpty, what: 'the request');
    expect(sheetUnlocked(tester), isFalse);

    await tester.pump(const Duration(seconds: 46));
    await tester.pumpAndSettle();
    expect(
      inSheet(
        find.text(l10n.assistantFailed('The Velorki relay stopped answering.')),
      ),
      findsOne,
    );
    expect(sheetUnlocked(tester), isTrue);
    expect(relay.cancelledStreams, 1);

    await tapInSheet(tester, find.text(l10n.assistantRetry));
    expect(sheetField(tester).controller!.text, _question);
    await tester.tap(
      inSheet(find.widgetWithText(FilledButton, l10n.assistantSend)),
    );
    await settle(
      tester,
      () =>
          c.read(routeAdviceControllerProvider).phase ==
          RouteAdvicePhase.answered,
      what: 'the second answer',
    );
    expect(relay.requests, hasLength(2));
    expect(relay.requests.last.placeIds, relay.requests.first.placeIds);
  });

  group('8 · Add as stop and Avoid work on every kind of route on the map', () {
    testWidgets('a round trip from Make a loop, which has only its start', (
      tester,
    ) async {
      await openMadeira(tester);
      final relay = MockRelay(schemas: spec.check)..reply(_advice());
      final loop = await _roundTrip(tester, madeira);
      final (_, c) = await _plannedRoute(
        tester,
        madeira,
        relay,
        load: (_, c) async => c
            .read(plannerControllerProvider.notifier)
            .loadComputedRoute(
              result: loop,
              waypoints: const [Waypoint(pos: Madeira.funchal)],
              options: const RoutingOptions(),
            ),
      );
      expect(c.read(plannerControllerProvider).waypoints, hasLength(1));
      await _stopAndAvoid(tester, c, relay);

      // Still the loop, back where it started: only the stretches around
      // the stop and the avoided road were routed again.
      final after = c.read(plannerControllerProvider).result!;
      expect(
        haversineMeters(after.positions.first, after.positions.last),
        lessThan(300),
      );
      expect(after.lengthM, greaterThan(loop.lengthM * 0.6));
      expect(_kept(loop, after), greaterThan(0.4));

      // One Undo each, back to the round trip as it came.
      for (var i = 0; i < 2; i++) {
        c.read(plannerControllerProvider.notifier).undo();
        await settle(tester, () => _routed(c), what: 'undo ${i + 1}');
      }
      expect(c.read(plannerControllerProvider).waypoints, hasLength(1));
      expect(
        c.read(plannerControllerProvider).result!.lengthM,
        closeTo(loop.lengthM, 1),
      );
    });

    testWidgets('a loop the assistant made: New route asks for a loop, the '
        'loop search puts it on the map, This route asks about it, and Add '
        'as stop, Avoid and Undo all work on it', (tester) async {
      await openMadeira(tester);
      final relay = MockRelay(schemas: spec.check)
        ..reply(
          RelayReply.stream([
            SseFrame.routeRequest({
              'distance_km': 12,
              'loop': true,
              'via': <String>[],
              'stops': <String>[],
              'notes': 'A loop from here.',
            }),
            SseFrame.done(),
          ]),
        )
        ..reply(_advice());
      final (_, c) = await _plannedRoute(
        tester,
        madeira,
        relay,
        load: (_, c) async {},
      );
      await _openAssistant(tester);
      expect(inSheet(find.text(l10n.assistantTitle)), findsOne);
      await tester.enterText(
        inSheet(find.byType(TextField)),
        'A 12 km loop from here',
      );
      await tester.tap(
        inSheet(find.widgetWithText(FilledButton, l10n.assistantSend)),
      );
      await settle(
        tester,
        () =>
            find.byType(AssistantSheet).evaluate().isEmpty &&
            _routed(c) &&
            !c.read(smartLoopControllerProvider).running,
        what: 'the loop on the map',
      );
      // The loop sheet over the planner goes, the loop stays.
      await tester.tapAt(const Offset(500, 40));
      await tester.pumpAndSettle();
      final loop = c.read(plannerControllerProvider).result!;
      expect(
        c.read(plannerControllerProvider).isRoutable,
        isFalse,
        reason: 'a round trip comes with its start alone',
      );

      await _stopAndAvoid(tester, c, relay);
      expect(relay.requests.last.step, 'route');
      final after = c.read(plannerControllerProvider).result!;
      expect(
        haversineMeters(after.positions.first, after.positions.last),
        lessThan(300),
      );
      expect(_kept(loop, after), greaterThan(0.4));

      await tester.tapAt(const Offset(500, 40));
      await tester.pumpAndSettle();
      final undo = find.widgetWithText(LabeledIconButton, l10n.plannerUndo);
      for (var i = 0; i < 2; i++) {
        await tester.ensureVisible(undo);
        await tester.tap(undo);
        await settle(tester, () => _routed(c), what: 'undo ${i + 1}');
      }
      final plan = c.read(plannerControllerProvider);
      expect(plan.avoid, isEmpty);
      expect(plan.result!.lengthM, closeTo(loop.lengthM, 1));
      expect(plan.result!.positions, loop.positions);
    });

    testWidgets('a round trip saved to the Library and opened again', (
      tester,
    ) async {
      await openMadeira(tester);
      final relay = MockRelay(schemas: spec.check)..reply(_advice());
      final loop = await _roundTrip(tester, madeira);
      final (_, c) = await _plannedRoute(
        tester,
        madeira,
        relay,
        load: (h, c) async {
          final repo = RouteRepository(h.db.routesDao);
          final saved = await repo.savePlannedRoute(
            name: 'Round Funchal',
            route: loop,
            waypoints: const [Waypoint(pos: Madeira.funchal)],
            options: const RoutingOptions(),
            source: RouteSource.loop,
          );
          c
              .read(plannerControllerProvider.notifier)
              .loadSavedRoute((await repo.routeById(saved.id))!);
        },
      );
      expect(c.read(plannerControllerProvider).isRoutable, isFalse);
      await _stopAndAvoid(tester, c, relay);
      final after = c.read(plannerControllerProvider).result!;
      expect(_kept(loop, after), greaterThan(0.4));
    });

    testWidgets('a planned route saved to the Library and opened again', (
      tester,
    ) async {
      await openMadeira(tester);
      final relay = MockRelay(schemas: spec.check)..reply(_advice());
      final route = await _toMachico(tester, madeira);
      final (_, c) = await _plannedRoute(
        tester,
        madeira,
        relay,
        load: (h, c) async {
          final repo = RouteRepository(h.db.routesDao);
          final saved = await repo.savePlannedRoute(
            name: 'Funchal to Machico',
            route: route,
            waypoints: const [
              Waypoint(pos: Madeira.funchal),
              Waypoint(pos: Madeira.machico),
            ],
            options: const RoutingOptions(),
          );
          c
              .read(plannerControllerProvider.notifier)
              .loadSavedRoute((await repo.routeById(saved.id))!);
        },
      );
      await _stopAndAvoid(tester, c, relay);
    });

    testWidgets('a GPX track imported to the Library keeps its course but '
        'around the stop and the avoided road', (tester) async {
      await openMadeira(tester);
      final relay = MockRelay(schemas: spec.check)..reply(_advice());
      final track = await _toMachico(tester, madeira);
      final (_, c) = await _plannedRoute(
        tester,
        madeira,
        relay,
        load: (h, c) async {
          final repo = RouteRepository(h.db.routesDao);
          final saved = await repo.saveImportedRoute(
            name: 'Coast ride',
            points: track.geometry,
            source: RouteSource.importedGpx,
          );
          c
              .read(plannerControllerProvider.notifier)
              .loadSavedRoute((await repo.routeById(saved.id))!);
        },
      );
      expect(
        c.read(plannerControllerProvider).planLegs.every((l) => l!.kept),
        isTrue,
      );
      await _stopAndAvoid(tester, c, relay);
      expect(
        _kept(track, c.read(plannerControllerProvider).result!),
        greaterThan(0.4),
      );
    });
  });

  group('3 · Describe this route', () {
    /// The route detail of a route planned from Funchal to Machico.
    Future<(PlannerHarness, ProviderContainer, String)> openDetail(
      WidgetTester tester,
      MockRelay relay,
    ) async {
      await openMadeira(tester);
      final h = PlannerHarness(backend: RealRouting(madeira.composite));
      final result = (await tester.runAsync(
        () => madeira.local.route(
          const RouteQuery(
            points: [Madeira.funchal, Madeira.machico],
            profile: 'velorki-trekking',
          ),
        ),
      ))!;
      final saved = await RouteRepository(h.db.routesDao).savePlannedRoute(
        name: 'Funchal to Machico',
        route: result,
        waypoints: const [
          Waypoint(pos: Madeira.funchal, name: 'Funchal'),
          Waypoint(pos: Madeira.machico, name: 'Machico'),
        ],
        options: const RoutingOptions(),
      );
      await pumpApp(
        tester,
        initialLocation: routeDetailLocation(saved.id),
        harness: h,
        extraOverrides: [...mockRelayOverrides(relay), ...madeira.overrides],
      );
      await tester.pumpAndSettle();
      final c = ProviderScope.containerOf(
        tester.element(find.byType(RouteDetailScreen)),
      );
      c.read(plusEntitledProvider.notifier).value = true;
      await c
          .read(aiConsentControllerProvider.notifier)
          .set(AiConsent.textOnly);
      final describe = find.text(l10n.describeAction);
      await tester.ensureVisible(describe);
      await tester.pumpAndSettle();
      await tester.tap(describe);
      await tester.pump();
      await settle(tester, () => relay.requests.isNotEmpty, what: 'request');
      return (h, c, saved.id);
    }

    const parts = [
      'From Funchal the road climbs ',
      'along the coast past Caniço ',
      'and drops into Machico.',
    ];

    testWidgets('the text arrives a delta at a time while the sheet says it '
        'is writing; Save keeps it on the route', (tester) async {
      final relay = MockRelay(schemas: spec.check)
        ..reply(
          RelayReply.stream([
            for (final p in parts) SseFrame.text(p),
            SseFrame.done(),
          ], gap: const Duration(seconds: 1)),
        );
      final (_, c, id) = await openDetail(tester, relay);

      final sent = relay.requests.single;
      expect(sent.step, 'describe');
      expect(sent.prompt, 'Funchal to Machico');
      expect(sent.locale, appLanguageTag);
      expect(sent.units, 'metric');
      expect(sent.body.containsKey('context'), isFalse);
      expect(sent.routeSummary!['waypoints'], ['Funchal', 'Machico']);
      expect(sent.digest!['stretches'], isNotEmpty);
      expect(sent.placeIds, isNotEmpty);

      Finder busy() => find.widgetWithText(FilledButton, l10n.describeRunning);
      for (var i = 0; i < parts.length; i++) {
        await tester.pump(const Duration(seconds: 1));
        expect(
          find.text(parts.take(i + 1).join()),
          findsOne,
          reason: 'after ${i + 1} deltas',
        );
        expect(busy(), findsOne);
        expect(tester.widget<FilledButton>(busy()).onPressed, isNull);
      }
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(busy(), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, l10n.describeSave));
      await tester.pumpAndSettle();
      expect(find.byType(DescribeRouteSheet), findsNothing);
      expect(find.text(l10n.describeSaved), findsOne);
      final stored = await c.read(routeRepositoryProvider).routeById(id);
      expect(stored!.description, parts.join().trim());
      expect(stored.aiDescriptionGenerated, isTrue);
      await unmountApp(tester);
    });

    testWidgets('an upstream_error event mid-stream keeps what arrived, says '
        'what went wrong and offers to write again', (tester) async {
      final relay = MockRelay(schemas: spec.check)
        ..reply(
          RelayReply.stream([
            SseFrame.text(parts[0]),
            SseFrame.ping,
            SseFrame.error('upstream_error', 'The model provider failed.'),
          ], gap: const Duration(milliseconds: 500)),
        );
      final (_, c, _) = await openDetail(tester, relay);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(find.text(parts[0]), findsOne);
      expect(
        find.text(
          l10n.describeFailed(
            l10n.assistantFailed('The model provider failed.'),
          ),
        ),
        findsOne,
      );
      expect(c.read(routeDescriptionControllerProvider).running, isFalse);
      final again = find.widgetWithText(TextButton, l10n.describeAgain);
      expect(tester.widget<TextButton>(again).onPressed, isNotNull);

      // Written again, from the documented example this time.
      await tester.tap(again);
      await tester.pump();
      await settle(
        tester,
        () => relay.requests.length == 2,
        what: 'the second request',
      );
      await tester.pumpAndSettle();
      expect(find.text('Diese Runde führt '), findsOne);
      expect(find.text(parts[0]), findsNothing);
      await unmountApp(tester);
    });
  });
}

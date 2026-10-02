import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/db/tables/routes.dart' show RouteSource;
import 'package:velorki/core/permissions/location_permission.dart';
import 'package:velorki/core/plus/plus_gate.dart';
import 'package:velorki/features/assistant/application/route_digest_service.dart';
import 'package:velorki/features/assistant/data/ai_consent_controller.dart';
import 'package:velorki/features/assistant/domain/ai_consent.dart';
import 'package:velorki/features/assistant/presentation/assistant_sheet.dart';
import 'package:velorki/features/integrations/common/data/relay_client_provider.dart';
import 'package:velorki/features/map/data/position_provider.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/domain/route_profile.dart';
import 'package:velorki/features/planner/domain/routing_options.dart';
import 'package:velorki/features/planner/domain/saved_route.dart';
import 'package:velorki/features/planner/domain/waypoint.dart';
import 'package:velorki/features/planner/presentation/planner_screen.dart';
import 'package:velorki/features/planner/presentation/route_format.dart';
import 'package:velorki/features/settings/data/units.dart';
import 'package:velorki/features/shared/presentation/stat_tile.dart';
import 'package:velorki_api/velorki_api.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';
import '../integrations/support/fakes.dart';
import '../planner/support/pump.dart';
import 'support/fakes.dart';

const LatLng _start = LatLng(48, 11);
const LatLng _end = LatLng(48.1, 11.1);

/// A route in the library, as the planner opens it.
SavedRoute _route({RouteSource source = RouteSource.planned}) => SavedRoute(
  id: 'r1',
  name: 'Isar loop',
  source: source,
  profile: RouteProfile.trekking,
  createdAt: DateTime(2026, 9, 1),
  updatedAt: DateTime(2026, 9, 1),
  distanceM: 13400,
  ascentM: 80,
  descentM: 80,
  bounds: const BoundingBox(south: 48, west: 11, north: 48.1, east: 11.1),
  geometryBlob: PackedTrack.encode(const [
    TrackPoint(_start),
    TrackPoint(LatLng(48.05, 11.05)),
    TrackPoint(_end),
  ]),
  waypoints: const [
    Waypoint(pos: _start, name: 'Munich'),
    Waypoint(pos: _end, name: 'Grünwald'),
  ],
  options: const RoutingOptions(),
);

const RouteDigest _digest = RouteDigest(
  loop: false,
  places: <DigestPlace>[
    DigestPlace(
      id: 'p1',
      kind: 'cafe',
      name: 'Kiosk',
      km: 6.7,
      offM: 20,
      at: DigestPoint(lat: 48.0502, lon: 11.0501),
    ),
  ],
);

const RouteAdvice _advice = RouteAdvice(
  answer: 'The Kiosk at 6.7 km is about halfway.',
  findings: <RouteFinding>[
    RouteFinding(
      kind: FindingKind.food,
      text: 'Kiosk, a café 20 m off the route.',
      placeId: 'p1',
      fix: AddStopFix('p1'),
    ),
    RouteFinding(
      kind: FindingKind.profile,
      text: 'Mostly gravel tracks.',
      fix: ProfileFix(ProfileHint.gravel),
    ),
    RouteFinding(
      kind: FindingKind.steep,
      text: 'A steep ramp.',
      fromKm: 2,
      toKm: 3,
    ),
  ],
);

Finder _inSheet(Finder finder) =>
    find.descendant(of: find.byType(AssistantSheet), matching: finder);

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(PlannerScreen)));

/// The planner with [route] on its map, if any, and the assistant open.
Future<PlannerHarness> _openSheet(
  WidgetTester tester, {
  required FakeRelayClient relay,
  SavedRoute? route,
  Size surfaceSize = const Size(1000, 2000),
}) async {
  // The screen the sheet measures itself against, at one pixel a point.
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = surfaceSize;
  addTearDown(tester.view.reset);
  final harness = await pumpScreen(
    tester,
    const PlannerScreen(),
    surfaceSize: surfaceSize,
    extraOverrides: [
      relayClientProvider.overrideWithValue(relay),
      routeDigestServiceProvider.overrideWithValue(
        FakeRouteDigestService(digest: _digest),
      ),
      locationPermissionGatewayProvider.overrideWithValue(
        const GrantedLocationPermission(),
      ),
      positionSourceProvider.overrideWithValue(
        const FixedPositionSource(_start),
      ),
    ],
  );
  final container = _container(tester);
  container.read(plusEntitledProvider.notifier).value = true;
  await container
      .read(aiConsentControllerProvider.notifier)
      .set(AiConsent.textOnly);
  if (route != null) {
    container.read(plannerControllerProvider.notifier).loadSavedRoute(route);
  }
  await tester.pumpAndSettle();
  await tester.tap(
    find.widgetWithText(LabeledIconButton, l10n.assistantAction),
  );
  await tester.pumpAndSettle();
  return harness;
}

/// Asks [question] and lets the answer arrive.
Future<void> _ask(WidgetTester tester, String question) async {
  await tester.enterText(_inSheet(find.byType(TextField)), question);
  await tester.tap(
    _inSheet(find.widgetWithText(FilledButton, l10n.assistantSend)),
  );
  await tester.pumpAndSettle();
}

FakeRelayClient _answering() => FakeRelayClient(
  planEvents: const <PlanEvent>[RouteAdviceEvent(_advice), DoneEvent()],
);

void main() {
  testWidgets('without a route there is only the new route to ask for', (
    tester,
  ) async {
    await _openSheet(tester, relay: FakeRelayClient());

    expect(find.byType(SegmentedButton<AssistantMode>), findsNothing);
    expect(_inSheet(find.text(l10n.assistantTitle)), findsOneWidget);
    expect(_inSheet(find.text(l10n.assistantExampleFlatLoop)), findsOneWidget);
  });

  testWidgets('with a route the sheet asks about it first, with its own '
      'examples, and switches to a new route', (tester) async {
    await _openSheet(tester, relay: FakeRelayClient(), route: _route());

    expect(find.byType(SegmentedButton<AssistantMode>), findsOneWidget);
    expect(_inSheet(find.text(l10n.assistantRouteTitle)), findsOneWidget);
    expect(_inSheet(find.text(l10n.assistantRouteIntro)), findsOneWidget);
    for (final example in [
      l10n.assistantRouteExampleCheck,
      l10n.assistantRouteExampleCoffee,
      l10n.assistantRouteExampleWater,
      l10n.assistantRouteExampleAvoid,
      l10n.assistantRouteExampleRoadBike,
    ]) {
      expect(_inSheet(find.text(example)), findsOneWidget);
    }

    await tester.tap(_inSheet(find.text(l10n.assistantRouteExampleCoffee)));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(_inSheet(find.byType(TextField)))
          .controller!
          .text,
      l10n.assistantRouteExampleCoffee,
    );

    await tester.tap(find.text(l10n.assistantModeNew));
    await tester.pumpAndSettle();
    expect(_inSheet(find.text(l10n.assistantTitle)), findsOneWidget);
    expect(_inSheet(find.text(l10n.assistantExampleFlatLoop)), findsOneWidget);
    // Each mode keeps its own text.
    expect(
      tester
          .widget<TextField>(_inSheet(find.byType(TextField)))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('a route from Strava is not offered', (tester) async {
    await _openSheet(
      tester,
      relay: FakeRelayClient(),
      route: _route(source: RouteSource.strava),
    );

    expect(find.byType(SegmentedButton<AssistantMode>), findsNothing);
    expect(_inSheet(find.text(l10n.assistantTitle)), findsOneWidget);
  });

  testWidgets('while the model thinks, the locked button says so', (
    tester,
  ) async {
    final relay = ManualRelayClient();
    await _openSheet(tester, relay: relay, route: _route());

    await tester.enterText(_inSheet(find.byType(TextField)), 'Coffee?');
    await tester.tap(
      _inSheet(find.widgetWithText(FilledButton, l10n.assistantSend)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final busy = _inSheet(
      find.widgetWithText(FilledButton, l10n.assistantThinking),
    );
    expect(busy, findsOneWidget);
    expect(tester.widget<FilledButton>(busy).onPressed, isNull);
    expect(
      find.descendant(
        of: busy,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(relay.planCalls.single.step, 'route');
    expect(relay.planCalls.single.context, isNull);

    relay.emit(const RouteAdviceEvent(_advice));
    await relay.finish();
    await tester.pumpAndSettle();
    expect(_inSheet(find.text(l10n.assistantSend)), findsOneWidget);
  });

  testWidgets('the answer lists its findings, with Show and Apply, and the '
      'questions to ask next', (tester) async {
    final harness = await _openSheet(
      tester,
      relay: _answering(),
      route: _route(),
    );
    await _ask(tester, l10n.assistantRouteExampleCoffee);

    expect(_inSheet(find.text(_advice.answer)), findsOneWidget);
    expect(
      _inSheet(find.text(l10n.assistantRouteFindings.toUpperCase())),
      findsOneWidget,
    );
    for (final finding in _advice.findings) {
      expect(_inSheet(find.text(finding.text)), findsOneWidget);
    }
    String km(double km) => formatDistance(l10n, UnitSystem.metric, km * 1000);
    expect(_inSheet(find.text(l10n.assistantFindingAt(km(6.7)))), findsOne);
    expect(
      _inSheet(find.text(l10n.assistantFindingBetween(km(2), km(3)))),
      findsOne,
    );
    expect(_inSheet(find.text(l10n.assistantFixAddStop)), findsOneWidget);
    expect(
      _inSheet(
        find.text(
          l10n.assistantFixProfile(profileLabel(l10n, RouteProfile.gravel)),
        ),
      ),
      findsOneWidget,
    );
    // Something located can be shown; a finding without a fix has no Apply.
    expect(_inSheet(find.text(l10n.assistantFindingShow)), findsNWidgets(2));

    // The question asked is not offered again.
    expect(
      _inSheet(find.text(l10n.assistantRouteFollowUps.toUpperCase())),
      findsOneWidget,
    );
    expect(
      _inSheet(
        find.widgetWithText(ActionChip, l10n.assistantRouteExampleCheck),
      ),
      findsOneWidget,
    );
    expect(
      _inSheet(
        find.widgetWithText(ActionChip, l10n.assistantRouteExampleCoffee),
      ),
      findsNothing,
    );

    await tester.ensureVisible(
      _inSheet(find.text(l10n.assistantFindingShow)).first,
    );
    await tester.tap(_inSheet(find.text(l10n.assistantFindingShow)).first);
    await tester.pump();
    expect(harness.map.movedTo, const LatLng(48.0502, 11.0501));
  });

  testWidgets('Apply puts the stop on the route, the sheet stays open and '
      'says it was applied', (tester) async {
    await _openSheet(tester, relay: _answering(), route: _route());
    await _ask(tester, l10n.assistantRouteExampleCoffee);

    await tester.ensureVisible(_inSheet(find.text(l10n.assistantFixAddStop)));
    await tester.tap(_inSheet(find.text(l10n.assistantFixAddStop)));
    await tester.pumpAndSettle();

    final plan = _container(tester).read(plannerControllerProvider);
    expect(plan.waypoints.map((w) => w.pos), <LatLng>[
      _start,
      const LatLng(48.0502, 11.0501),
      _end,
    ]);
    expect(plan.waypoints[1].name, 'Kiosk');
    expect(find.byType(AssistantSheet), findsOneWidget);
    expect(_inSheet(find.text(l10n.assistantFixApplied)), findsOneWidget);
    expect(_inSheet(find.text(l10n.assistantFixAddStop)), findsNothing);

    await tester.ensureVisible(
      _inSheet(
        find.text(
          l10n.assistantFixProfile(profileLabel(l10n, RouteProfile.gravel)),
        ),
      ),
    );
    await tester.tap(
      _inSheet(
        find.text(
          l10n.assistantFixProfile(profileLabel(l10n, RouteProfile.gravel)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      _container(tester).read(plannerControllerProvider).options.profile,
      RouteProfile.gravel,
    );
    expect(_inSheet(find.text(l10n.assistantFixApplied)), findsNWidgets(2));
  });

  testWidgets('Add as stop shows the new stop on the map above the sheet, '
      'which is where the rider looks for it', (tester) async {
    final harness = await _openSheet(
      tester,
      relay: _answering(),
      route: _route(),
    );
    await _ask(tester, l10n.assistantRouteExampleCoffee);
    harness.map.movedTo = null;

    await tester.ensureVisible(_inSheet(find.text(l10n.assistantFixAddStop)));
    await tester.tap(_inSheet(find.text(l10n.assistantFixAddStop)));
    await tester.pumpAndSettle();

    expect(
      _container(tester).read(plannerControllerProvider).waypoints,
      hasLength(3),
    );
    // The stop lies a few metres off the line, so the line hardly changes:
    // the camera goes to the stop, clear of the sheet.
    expect(harness.map.movedTo, const LatLng(48.0502, 11.0501));
    final sheetTop = tester.getRect(find.byKey(assistantSheetSurfaceKey)).top;
    expect(harness.map.movedPadding!.bottom, greaterThan(2000 - sheetTop));
  });

  testWidgets('a stop the router cannot reach is taken back, and the '
      'finding says so', (tester) async {
    final harness = await _openSheet(
      tester,
      relay: _answering(),
      route: _route(),
    );
    await _ask(tester, l10n.assistantRouteExampleCoffee);
    harness.backend.error = const RoutingException(
      kind: RoutingErrorKind.noRoute,
      message: 'target island',
    );

    await tester.ensureVisible(_inSheet(find.text(l10n.assistantFixAddStop)));
    await tester.tap(_inSheet(find.text(l10n.assistantFixAddStop)));
    await tester.pumpAndSettle();

    final plan = _container(tester).read(plannerControllerProvider);
    expect(plan.waypoints.map((w) => w.pos), <LatLng>[_start, _end]);
    expect(plan.result, isNotNull);
    expect(_inSheet(find.text(l10n.assistantFixRoutingFailed)), findsOneWidget);
    expect(_inSheet(find.text(l10n.assistantFixApplied)), findsNothing);
    // It can be tried again.
    expect(_inSheet(find.text(l10n.assistantFixAddStop)), findsOneWidget);
  });
}

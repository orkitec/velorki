// Add as stop on a real plan: routed on the oracle's Madeira tile, its digest
// built from the live route and the committed gazetteer, and an answer that
// names a café of that digest, as the relay would.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/geo/track_surface.dart';
import 'package:velorki/core/permissions/location_permission.dart';
import 'package:velorki/core/plus/plus_gate.dart';
import 'package:velorki/features/assistant/application/route_advice_controller.dart';
import 'package:velorki/features/assistant/application/route_digest_service.dart';
import 'package:velorki/features/assistant/data/ai_consent_controller.dart';
import 'package:velorki/features/assistant/domain/ai_consent.dart';
import 'package:velorki/features/assistant/presentation/assistant_sheet.dart';
import 'package:velorki/features/integrations/common/data/relay_client_provider.dart';
import 'package:velorki/features/map/data/position_provider.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/presentation/planner_screen.dart';
import 'package:velorki/features/search/data/gazetteer_store.dart';
import 'package:velorki/features/shared/presentation/stat_tile.dart';
import 'package:velorki_api/velorki_api.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';
import '../integrations/support/fakes.dart';
import '../planner/support/fakes.dart';
import '../planner/support/pump.dart';
import 'support/fakes.dart';

/// The on-device router behind the harness' backend.
class _Real extends FakeRoutingBackend {
  _Real(this.inner);
  final RoutingBackend inner;
  @override
  Future<RouteResult> route(RouteQuery q, {CancelToken? cancel}) {
    queries.add(q);
    return inner.route(q, cancel: cancel);
  }
}

Finder _inSheet(Finder f) =>
    find.descendant(of: find.byType(AssistantSheet), matching: f);

void main() {
  testWidgets('Add as stop on a route planned on Madeira puts the café on '
      'the route and shows it on the map', (tester) async {
    late LocalRoutingBackend local;
    late CompositeRoutingBackend composite;
    late GazetteerStore gaz;
    await tester.runAsync(() async {
      local = LocalRoutingBackend(
        segmentsDir: '../tools/brouter-oracle/tiles',
        profilesDir: '../brouter/profiles',
      );
      composite = CompositeRoutingBackend(
        local: local,
        localTiles: local.availableTiles,
      );
      gaz = GazetteerStore(Directory('../tools/gazetteer/fixtures'));
      await gaz.refresh();
    });
    final service = RouteDigestService(
      surfaces: TrackSurfaceService(local: local, decide: composite.decide),
      gazetteer: () async => gaz,
    );
    final relay = FakeRelayClient();
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1000, 2000);
    addTearDown(tester.view.reset);
    final harness = await pumpScreen(
      tester,
      const PlannerScreen(),
      harness: PlannerHarness(backend: _Real(composite)),
      extraOverrides: [
        relayClientProvider.overrideWithValue(relay),
        routeDigestServiceProvider.overrideWithValue(service),
        locationPermissionGatewayProvider.overrideWithValue(
          const GrantedLocationPermission(),
        ),
        positionSourceProvider.overrideWithValue(
          const FixedPositionSource(LatLng(32.6475, -16.9087)),
        ),
      ],
    );
    final c = ProviderScope.containerOf(
      tester.element(find.byType(PlannerScreen)),
    );
    c.read(plusEntitledProvider.notifier).value = true;
    await c.read(aiConsentControllerProvider.notifier).set(AiConsent.textOnly);
    c.read(plannerControllerProvider.notifier)
      ..addWaypoint(const LatLng(32.6475, -16.9087))
      ..addWaypoint(const LatLng(32.7167, -16.7667));
    // Real files and isolates: the event loop has to run, which pumping
    // alone does not do.
    Future<void> settle(bool Function() done) async {
      for (var i = 0; i < 100 && !done(); i++) {
        await tester.pump(const Duration(milliseconds: 400));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
      await tester.pump();
      expect(done(), isTrue);
    }

    bool routed() {
      final plan = c.read(plannerControllerProvider);
      return plan.result != null && !plan.isRouting;
    }

    await settle(routed);
    final route = c.read(plannerControllerProvider).result!;
    final digest = (await tester.runAsync(
      () => service.digestOfTrack(
        geometry: route.geometry,
        distanceM: route.lengthM,
        profile: 'trekking',
        messages: route.messages,
        keepEmpty: true,
      ),
    ))!;
    final cafe = digest.places.firstWhere((p) => p.kind == 'cafe');
    relay.planEvents = [
      RouteAdviceEvent(
        RouteAdvice(
          answer: 'There is ${cafe.name}.',
          findings: [
            RouteFinding(
              kind: FindingKind.food,
              text: 'cafe here',
              placeId: cafe.id,
              fix: AddStopFix(cafe.id),
            ),
          ],
        ),
      ),
      const DoneEvent(),
    ];
    await tester.tap(
      find.widgetWithText(LabeledIconButton, l10n.assistantAction),
    );
    await tester.pumpAndSettle();
    await tester.enterText(_inSheet(find.byType(TextField)), 'coffee?');
    await tester.tap(
      _inSheet(find.widgetWithText(FilledButton, l10n.assistantSend)),
    );
    await settle(
      () =>
          c.read(routeAdviceControllerProvider).phase ==
          RouteAdvicePhase.answered,
    );
    // The digest the relay was sent holds the café the answer names.
    expect(
      relay.planCalls.single.routeSummary!.digest!.places.map((p) => p.id),
      contains(cafe.id),
    );
    final button = _inSheet(find.text(l10n.assistantFixAddStop));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    harness.map.movedTo = null;
    await tester.tap(button);
    await tester.pump();
    await settle(routed);

    final plan = c.read(plannerControllerProvider);
    expect(plan.waypoints.map((w) => w.name), [null, cafe.name, null]);
    expect(plan.waypoints[1].pos, LatLng(cafe.at.lat, cafe.at.lon));
    expect(plan.result, isNotNull);
    expect(plan.error, isNull);
    // The café is a few metres off the line, so the line hardly moves: the
    // map goes to the new stop, clear of the sheet, for the rider to see.
    expect(plan.result!.lengthM, closeTo(route.lengthM, 200));
    expect(harness.map.movedTo, LatLng(cafe.at.lat, cafe.at.lon));
    expect(_inSheet(find.text(l10n.assistantFixApplied)), findsOneWidget);
    expect(c.read(routeAdviceControllerProvider).failures, isEmpty);
    await tester.runAsync(() async {
      gaz.close();
      await local.dispose();
    });
  });
}

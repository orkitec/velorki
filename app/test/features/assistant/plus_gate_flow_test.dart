// A rider without Velorki Plus still gets the sheet: the Plan tab's Ask and
// the route detail's Describe open it with Subscribe where their button
// would be when the store has said so, and the button is back once they
// return subscribed. Not known yet, the sheet opens as usual and the relay
// decides; a "part of Plus" error the sheet shows is said at the top and
// goes once Plus is active.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/core/db/tables/routes.dart' show RouteSource;
import 'package:velorki/core/permissions/location_permission.dart';
import 'package:velorki/core/plus/plus_gate.dart';
import 'package:velorki/features/assistant/application/assistant_controller.dart';
import 'package:velorki/features/assistant/application/route_description_controller.dart';
import 'package:velorki/features/assistant/application/route_digest_service.dart';
import 'package:velorki/features/assistant/data/ai_consent_controller.dart';
import 'package:velorki/features/assistant/domain/ai_consent.dart';
import 'package:velorki/features/assistant/domain/assistant_state.dart';
import 'package:velorki/features/assistant/presentation/assistant_sheet.dart';
import 'package:velorki/features/assistant/presentation/describe_route_sheet.dart';
import 'package:velorki/features/integrations/common/data/relay_client_provider.dart';
import 'package:velorki/features/map/data/position_provider.dart';
import 'package:velorki/features/planner/domain/route_profile.dart';
import 'package:velorki/features/planner/domain/routing_options.dart';
import 'package:velorki/features/planner/domain/saved_route.dart';
import 'package:velorki/features/planner/domain/waypoint.dart';
import 'package:velorki/features/planner/presentation/planner_screen.dart';
import 'package:velorki/features/shared/presentation/stat_tile.dart';
import 'package:velorki/features/subscription/data/subscription_service.dart';
import 'package:velorki/features/subscription/domain/plus_subscription.dart';
import 'package:velorki/features/subscription/presentation/paywall_screen.dart';
import 'package:velorki_api/velorki_api.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';
import '../integrations/support/fakes.dart';
import '../planner/support/pump.dart';
import '../subscription/support/fake_subscription_service.dart';
import 'support/fakes.dart';

/// What the store has said about the rider's Plus.
enum _Store {
  /// It answered: nothing owned.
  saysNo,

  /// It has not answered yet.
  silent,
}

List<Override> _storeOverrides(_Store store) => [
  subscriptionServiceProvider.overrideWithValue(
    FakeSubscriptionService(offering: defaultOffering),
  ),
  if (store == _Store.silent)
    plusCustomerInfoProvider.overrideWith(
      (ref) => StreamController<PlusCustomerInfo>().stream,
    ),
];

/// Listens to the store's answers from the start, as `startSubscriptions`
/// does in the app.
void _followStore(ProviderContainer container) =>
    container.listen(plusCustomerInfoProvider, (_, _) {});

Finder _inSheet(Finder finder) =>
    find.descendant(of: find.byType(AssistantSheet), matching: finder);

ProviderContainer _plannerContainer(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(PlannerScreen)));

/// The Plan tab, without Plus, with a relay that answers [relay].
Future<ProviderContainer> _planner(
  WidgetTester tester, {
  required _Store store,
  FakeRelayClient? relay,
}) async {
  await pumpApp(
    tester,
    initialLocation: plannerRoute,
    extraOverrides: [
      relayClientProvider.overrideWithValue(relay ?? FakeRelayClient()),
      locationPermissionGatewayProvider.overrideWithValue(
        const GrantedLocationPermission(),
      ),
      positionSourceProvider.overrideWithValue(
        const FixedPositionSource(LatLng(48.137, 11.575)),
      ),
      ..._storeOverrides(store),
    ],
  );
  await tester.pumpAndSettle();
  final container = _plannerContainer(tester);
  _followStore(container);
  await tester.pumpAndSettle();
  await container
      .read(aiConsentControllerProvider.notifier)
      .set(AiConsent.textOnly);
  return container;
}

Future<void> _tapAsk(WidgetTester tester) async {
  await tester.tap(
    find.widgetWithText(LabeledIconButton, l10n.assistantAction),
  );
  await tester.pumpAndSettle();
}

Future<void> _closePaywall(WidgetTester tester) async {
  await tester.tap(find.byType(BackButton));
  await tester.pumpAndSettle();
}

SavedRoute _route() => SavedRoute(
  id: 'r1',
  name: 'Isar loop',
  source: RouteSource.planned,
  profile: RouteProfile.trekking,
  createdAt: DateTime(2026, 9, 1),
  updatedAt: DateTime(2026, 9, 1),
  distanceM: 13400,
  ascentM: 80,
  descentM: 80,
  bounds: const BoundingBox(south: 48, west: 11, north: 48.1, east: 11.1),
  geometryBlob: PackedTrack.encode(const [
    TrackPoint(LatLng(48, 11)),
    TrackPoint(LatLng(48.1, 11.1)),
  ]),
  waypoints: const [
    Waypoint(pos: LatLng(48, 11)),
    Waypoint(pos: LatLng(48.1, 11.1)),
  ],
  options: const RoutingOptions(),
);

/// A route detail stand-in: the Describe button, with the paywall routed.
Future<ProviderContainer> _describe(
  WidgetTester tester, {
  required _Store store,
}) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Center(child: DescribeRouteButton(route: _route())),
        ),
      ),
      GoRoute(
        path: paywallRoute,
        builder: (context, state) => const PaywallScreen(),
      ),
    ],
  );
  addTearDown(router.dispose);
  final h = PlannerHarness();
  addTearDown(h.db.close);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...h.overrides(prefs),
        relayClientProvider.overrideWithValue(
          FakeRelayClient(
            planEvents: const <PlanEvent>[
              TextEvent('A gentle loop.'),
              DoneEvent(),
            ],
          ),
        ),
        routeDigestServiceProvider.overrideWithValue(FakeRouteDigestService()),
        ..._storeOverrides(store),
      ],
      child: testRouterApp(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(DescribeRouteButton)),
  );
  _followStore(container);
  await tester.pumpAndSettle();
  await container
      .read(aiConsentControllerProvider.notifier)
      .set(AiConsent.textOnly);
  return container;
}

void main() {
  group('the Plan tab\'s Ask', () {
    testWidgets('without Plus opens the sheet to look around in, with '
        'Subscribe where Ask would be; Subscribe opens the paywall over the '
        'sheet, and back subscribed Ask is there with what was typed', (
      tester,
    ) async {
      final relay = FakeRelayClient();
      final container = await _planner(
        tester,
        store: _Store.saysNo,
        relay: relay,
      );

      await _tapAsk(tester);
      expect(find.byType(PaywallScreen), findsNothing);
      expect(find.byType(AssistantSheet), findsOneWidget);
      expect(_inSheet(find.text(l10n.assistantPlusRequired)), findsOneWidget);
      expect(
        _inSheet(find.widgetWithText(FilledButton, l10n.assistantSend)),
        findsNothing,
      );
      // The field and the examples work.
      await tester.ensureVisible(
        _inSheet(find.text(l10n.assistantExampleFlatLoop)),
      );
      await tester.pumpAndSettle();
      await tester.tap(_inSheet(find.text(l10n.assistantExampleFlatLoop)));
      await tester.pumpAndSettle();
      final field = _inSheet(find.byType(TextField));
      expect(
        tester.widget<TextField>(field).controller!.text,
        l10n.assistantExampleFlatLoop,
      );
      expect(tester.widget<TextField>(field).readOnly, isFalse);

      // Subscribe, and back without buying: still the banner.
      await tester.tap(_inSheet(find.text(l10n.plusSubscribe)));
      await tester.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsOneWidget);
      await _closePaywall(tester);
      expect(find.byType(AssistantSheet), findsOneWidget);
      expect(_inSheet(find.text(l10n.assistantPlusRequired)), findsOneWidget);

      // Subscribe, bought: Ask, and what was typed is still there.
      await tester.tap(_inSheet(find.text(l10n.plusSubscribe)));
      await tester.pumpAndSettle();
      container.read(plusEntitledProvider.notifier).value = true;
      await tester.pumpAndSettle();
      await _closePaywall(tester);
      expect(find.byType(AssistantSheet), findsOneWidget);
      expect(_inSheet(find.text(l10n.assistantPlusRequired)), findsNothing);
      expect(
        _inSheet(find.widgetWithText(FilledButton, l10n.assistantSend)),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(_inSheet(find.byType(TextField)))
            .controller!
            .text,
        l10n.assistantExampleFlatLoop,
      );
      expect(relay.planCalls, isEmpty);
    });

    testWidgets('opens the sheet while the store has not answered, and the '
        'relay\'s answer is said at the top of it', (tester) async {
      final relay = FakeRelayClient(
        planFailure: const RelayException(
          RelayError(code: RelayErrorCode.notEntitled, message: 'no plus'),
          statusCode: 403,
        ),
      );
      final container = await _planner(
        tester,
        store: _Store.silent,
        relay: relay,
      );
      await _tapAsk(tester);
      expect(find.byType(PaywallScreen), findsNothing);
      expect(find.byType(AssistantSheet), findsOneWidget);

      // The phone does not know either, so the request is sent and the
      // relay's "no" stands in for it.
      container.read(plusEntitledProvider.notifier).value = true;
      await tester.enterText(_inSheet(find.byType(TextField)), 'a flat loop');
      await tester.tap(
        _inSheet(find.widgetWithText(FilledButton, l10n.assistantSend)),
      );
      await tester.pumpAndSettle();
      expect(relay.planCalls, hasLength(1));
      final problem = _inSheet(find.text(l10n.assistantNotEntitled));
      expect(problem, findsOneWidget);
      // Above the field, where the rider looks, not under it.
      expect(
        tester.getRect(problem).top,
        lessThan(tester.getRect(_inSheet(find.byType(TextField))).top),
      );
    });
  });

  group('inside the sheet', () {
    testWidgets('See details opens the paywall over the sheet; back from it '
        'subscribed, the error is gone and the question is still there', (
      tester,
    ) async {
      final container = await _planner(tester, store: _Store.silent);
      await _tapAsk(tester);

      await tester.enterText(_inSheet(find.byType(TextField)), 'a flat loop');
      await tester.tap(
        _inSheet(find.widgetWithText(FilledButton, l10n.assistantSend)),
      );
      await tester.pumpAndSettle();
      expect(_inSheet(find.text(l10n.assistantNotEntitled)), findsOneWidget);

      await tester.tap(_inSheet(find.text(l10n.plusSeeDetails)));
      await tester.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsOneWidget);
      container.read(plusEntitledProvider.notifier).value = true;
      await tester.pumpAndSettle();
      await _closePaywall(tester);

      expect(find.byType(AssistantSheet), findsOneWidget);
      expect(_inSheet(find.text(l10n.assistantNotEntitled)), findsNothing);
      final field = tester.widget<TextField>(_inSheet(find.byType(TextField)));
      expect(field.controller!.text, 'a flat loop');
      expect(container.read(assistantControllerProvider).problem, isNull);
      expect(container.read(assistantControllerProvider).prompt, 'a flat loop');
    });
  });

  group('the route detail\'s Describe', () {
    testWidgets('without Plus opens the sheet with Subscribe instead of '
        'writing; back subscribed, it writes', (tester) async {
      final container = await _describe(tester, store: _Store.saysNo);

      await tester.tap(find.text(l10n.describeAction));
      await tester.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsNothing);
      expect(find.byType(DescribeRouteSheet), findsOneWidget);
      expect(find.text(l10n.assistantPlusRequired), findsOneWidget);
      expect(find.text('A gentle loop.'), findsNothing);
      expect(find.text(l10n.describeSave), findsNothing);

      await tester.tap(find.text(l10n.plusSubscribe));
      await tester.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsOneWidget);
      container.read(plusEntitledProvider.notifier).value = true;
      await tester.pumpAndSettle();
      await _closePaywall(tester);

      expect(find.byType(DescribeRouteSheet), findsOneWidget);
      expect(find.text(l10n.assistantPlusRequired), findsNothing);
      expect(find.text('A gentle loop.'), findsOneWidget);
    });

    testWidgets('opens the sheet while the store has not answered', (
      tester,
    ) async {
      await _describe(tester, store: _Store.silent);

      await tester.tap(find.text(l10n.describeAction));
      await tester.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsNothing);
      expect(find.byType(DescribeRouteSheet), findsOneWidget);
      // Here it is the phone's own check that says no.
      expect(
        find.text(l10n.describeFailed(l10n.assistantNotEntitled)),
        findsOneWidget,
      );
    });
  });

  group('a "part of Plus" error goes once Plus is active', () {
    test('in every assistant controller, keeping what was asked', () async {
      final container = ProviderContainer(
        overrides: [relayClientProvider.overrideWithValue(null)],
      );
      addTearDown(container.dispose);
      container.listen(routeDescriptionControllerProvider, (_, _) {});

      await container
          .read(assistantControllerProvider.notifier)
          .submit('a flat loop');
      await container
          .read(routeDescriptionControllerProvider.notifier)
          .describe(_route());
      const notEntitled = AssistantFailure.notEntitled;
      expect(
        container.read(assistantControllerProvider).problem?.failure,
        notEntitled,
      );
      expect(
        container.read(routeDescriptionControllerProvider).problem?.failure,
        notEntitled,
      );

      container.read(plusEntitledProvider.notifier).value = true;
      expect(container.read(assistantControllerProvider).problem, isNull);
      expect(container.read(assistantControllerProvider).prompt, 'a flat loop');
      expect(
        container.read(routeDescriptionControllerProvider).problem,
        isNull,
      );
    });
  });
}

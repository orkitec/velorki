import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/permissions/location_permission.dart';
import 'package:velorki/core/plus/plus_gate.dart';
import 'package:velorki/features/assistant/data/ai_consent_controller.dart';
import 'package:velorki/features/assistant/data/place_geocoder.dart';
import 'package:velorki/features/assistant/domain/ai_consent.dart';
import 'package:velorki/features/assistant/domain/intent_resolver.dart';
import 'package:velorki/features/assistant/presentation/assistant_sheet.dart';
import 'package:velorki/features/integrations/common/data/relay_client_provider.dart';
import 'package:velorki/features/map/data/position_provider.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/presentation/planner_screen.dart';
import 'package:velorki/features/shared/presentation/stat_tile.dart';
import 'package:velorki_api/velorki_api.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../integrations/support/fakes.dart';
import '../planner/support/pump.dart';
import 'support/fakes.dart';

const LatLng _here = LatLng(48.137213, 11.575612);

/// The provider container behind the planner under test.
ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(PlannerScreen)));

Finder _inSheet(Finder finder) =>
    find.descendant(of: find.byType(AssistantSheet), matching: finder);

Future<PlannerHarness> _openSheet(
  WidgetTester tester, {
  required FakeRelayClient relay,
  FakeGeocoder? geocoder,
  AiConsent? consent,
  bool entitled = true,
}) async {
  final harness = await pumpScreen(
    tester,
    const PlannerScreen(),
    extraOverrides: [
      relayClientProvider.overrideWithValue(relay),
      intentResolverProvider.overrideWithValue(
        IntentResolver(geocoder: geocoder ?? FakeGeocoder()),
      ),
      locationPermissionGatewayProvider.overrideWithValue(
        const GrantedLocationPermission(),
      ),
      positionSourceProvider.overrideWithValue(
        const FixedPositionSource(_here),
      ),
    ],
  );
  final container = _container(tester);
  container.read(plusEntitledProvider.notifier).value = entitled;
  if (consent != null) {
    await container.read(aiConsentControllerProvider.notifier).set(consent);
  }
  await tester.tap(find.widgetWithText(LabeledIconButton, 'Ask'));
  await tester.pumpAndSettle();
  return harness;
}

void main() {
  testWidgets('the planner opens the assistant with its examples', (
    tester,
  ) async {
    await _openSheet(
      tester,
      relay: FakeRelayClient(),
      consent: AiConsent.textOnly,
    );

    expect(find.text('Ask for a route'), findsOneWidget);
    expect(_inSheet(find.byType(TextField)), findsOneWidget);
    expect(_inSheet(find.text('A flat 30 km loop from here')), findsOneWidget);
  });

  testWidgets('the first request asks for consent and says what is sent', (
    tester,
  ) async {
    final relay = FakeRelayClient(
      planEvents: <PlanEvent>[
        RouteRequestEvent(routeRequest(distanceKm: 30)),
        const DoneEvent(),
      ],
    );
    await _openSheet(tester, relay: relay);

    await tester.enterText(_inSheet(find.byType(TextField)), 'a 30 km loop');
    await tester.tap(_inSheet(find.widgetWithText(FilledButton, 'Ask')));
    await tester.pumpAndSettle();

    expect(find.text('Before the assistant asks'), findsOneWidget);
    expect(
      find.textContaining('forwards it to our AI provider'),
      findsOneWidget,
    );
    expect(relay.planCalls, isEmpty);

    await tester.tap(find.text('Allow, text only'));
    await tester.pumpAndSettle();

    // Consent given, request sent, and the loop search was handed the result.
    expect(relay.planCalls.single.prompt, 'a 30 km loop');
    expect(
      _container(tester).read(aiConsentControllerProvider),
      AiConsent.textOnly,
    );
  });

  testWidgets('refusing consent sends nothing and leaves the sheet open', (
    tester,
  ) async {
    final relay = FakeRelayClient();
    await _openSheet(tester, relay: relay);

    await tester.enterText(_inSheet(find.byType(TextField)), 'a 30 km loop');
    await tester.tap(_inSheet(find.widgetWithText(FilledButton, 'Ask')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(relay.planCalls, isEmpty);
    expect(find.byType(AssistantSheet), findsOneWidget);
    expect(
      _container(tester).read(aiConsentControllerProvider),
      AiConsent.denied,
    );
  });

  testWidgets('an ambiguous name is offered as chips', (tester) async {
    final relay = FakeRelayClient(
      planEvents: <PlanEvent>[
        RouteRequestEvent(routeRequest(via: ['Neustadt'])),
        const DoneEvent(),
      ],
    );
    await _openSheet(
      tester,
      relay: relay,
      consent: AiConsent.withLocation,
      geocoder: FakeGeocoder({
        'Neustadt': [
          place('Neustadt', 49.35, 8.14, city: 'Rheinland-Pfalz'),
          place('Neustadt', 50.73, 10.90, city: 'Thüringen'),
        ],
      }),
    );

    await tester.enterText(_inSheet(find.byType(TextField)), 'past Neustadt');
    await tester.tap(_inSheet(find.widgetWithText(FilledButton, 'Ask')));
    await tester.pumpAndSettle();

    expect(_inSheet(find.text('Which Neustadt?')), findsOneWidget);
    expect(_inSheet(find.text('Neustadt, Rheinland-Pfalz')), findsOneWidget);

    await tester.ensureVisible(_inSheet(find.text('Neustadt, Thüringen')));
    await tester.pumpAndSettle();
    await tester.tap(_inSheet(find.text('Neustadt, Thüringen')));
    await tester.pumpAndSettle();

    // The sheet closed onto the planner: a loop past a place is that place
    // plotted and the route closed behind it.
    expect(find.byType(AssistantSheet), findsNothing);
    final planner = _container(tester).read(plannerControllerProvider);
    expect(planner.positions, <LatLng>[
      _here,
      const LatLng(50.73, 10.90),
      _here,
    ]);
    expect(planner.options.differentWayBack, isTrue);
  });

  testWidgets('without Velorki Plus the sheet points at the paywall', (
    tester,
  ) async {
    final relay = FakeRelayClient();
    await _openSheet(
      tester,
      relay: relay,
      consent: AiConsent.textOnly,
      entitled: false,
    );

    await tester.enterText(_inSheet(find.byType(TextField)), 'a 30 km loop');
    await tester.tap(_inSheet(find.widgetWithText(FilledButton, 'Ask')));
    await tester.pumpAndSettle();

    expect(
      _inSheet(find.text('The AI assistant is part of Velorki Plus.')),
      findsOneWidget,
    );
    expect(_inSheet(find.text('See Velorki Plus')), findsOneWidget);
    expect(relay.planCalls, isEmpty);
  });

  testWidgets('a rate limit tells the rider how long to wait', (tester) async {
    final relay = FakeRelayClient(
      planFailure: const RelayException(
        RelayError(
          code: RelayErrorCode.rateLimited,
          message: 'too many requests',
          retryAfterS: 90,
        ),
        statusCode: 429,
      ),
    );
    await _openSheet(tester, relay: relay, consent: AiConsent.textOnly);

    await tester.enterText(_inSheet(find.byType(TextField)), 'a 30 km loop');
    await tester.tap(_inSheet(find.widgetWithText(FilledButton, 'Ask')));
    await tester.pumpAndSettle();

    expect(
      _inSheet(find.textContaining('Try again in 90 seconds')),
      findsOneWidget,
    );
  });
}

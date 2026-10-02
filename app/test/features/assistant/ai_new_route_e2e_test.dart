// "New route" end to end, against the relay mocked at the HTTP layer: the
// app's RelayClient parses real SSE bytes from the documented contract, and
// the controller, the sheet, the Plus gate and the planner above it are the
// app's own. What the app sent is read back off the mock.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/core/permissions/location_permission.dart';
import 'package:velorki/core/plus/plus_gate.dart';
import 'package:velorki/features/assistant/application/assistant_controller.dart';
import 'package:velorki/features/assistant/data/ai_consent_controller.dart';
import 'package:velorki/features/assistant/data/place_geocoder.dart';
import 'package:velorki/features/assistant/domain/ai_consent.dart';
import 'package:velorki/features/assistant/domain/assistant_state.dart';
import 'package:velorki/features/assistant/domain/intent_resolver.dart';
import 'package:velorki/features/assistant/presentation/assistant_sheet.dart';
import 'package:velorki/features/map/data/position_provider.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/domain/route_profile.dart';
import 'package:velorki/features/planner/presentation/planner_screen.dart';
import 'package:velorki/features/shared/presentation/stat_tile.dart';
import 'package:velorki/features/subscription/data/subscription_service.dart';
import 'package:velorki/features/subscription/domain/plus_subscription.dart';
import 'package:velorki/features/subscription/presentation/paywall_screen.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';
import '../planner/support/pump.dart';
import '../subscription/support/fake_subscription_service.dart';
import 'support/ai_e2e.dart';
import 'support/fakes.dart';

/// Zürich, where the documented `plan` request starts: rounded to two
/// decimals it is the example's `context.start`.
const LatLng _zurich = LatLng(47.37689, 8.54169);

/// The place the documented `propose_route` rides past.
const LatLng _uetliberg = LatLng(47.34966, 8.49181);

const String _prompt =
    'Eine hügelige Runde von etwa 65 km mit einem Kaffeehalt.';

List<Override> _overrides(MockRelay relay) => [
  ...mockRelayOverrides(relay),
  intentResolverProvider.overrideWithValue(
    IntentResolver(
      geocoder: FakeGeocoder({
        'Uetliberg': [place('Uetliberg', _uetliberg.lat, _uetliberg.lon)],
      }),
    ),
  ),
  locationPermissionGatewayProvider.overrideWithValue(
    const GrantedLocationPermission(),
  ),
  positionSourceProvider.overrideWithValue(const FixedPositionSource(_zurich)),
];

/// The Plan tab with Plus and consent, the assistant open.
Future<(PlannerHarness, ProviderContainer)> _openSheet(
  WidgetTester tester,
  MockRelay relay, {
  AiConsent consent = AiConsent.textOnly,
}) async {
  final harness = await pumpScreen(
    tester,
    const PlannerScreen(),
    extraOverrides: _overrides(relay),
  );
  final c = ProviderScope.containerOf(
    tester.element(find.byType(PlannerScreen)),
  );
  c.read(plusEntitledProvider.notifier).value = true;
  await c.read(aiConsentControllerProvider.notifier).set(consent);
  await _tapAsk(tester);
  return (harness, c);
}

Future<void> _tapAsk(WidgetTester tester) async {
  await tester.tap(
    find.widgetWithText(LabeledIconButton, l10n.assistantAction),
  );
  await tester.pumpAndSettle();
}

/// Types [prompt] and sends it, and lets the reply arrive.
Future<void> _send(WidgetTester tester, {String prompt = _prompt}) async {
  await tester.enterText(inSheet(find.byType(TextField)), prompt);
  await tester.tap(
    inSheet(find.widgetWithText(FilledButton, l10n.assistantSend)),
  );
  await tester.pump();
  await tester.pump();
}

/// The problem row saying [text].
Finder _problem(String text) => inSheet(find.text(text));

void main() {
  final spec = OpenApi.load();

  testWidgets('1 · a prompt comes back as the documented route_request and '
      'lands on the planner map as a loop past the place it names', (
    tester,
  ) async {
    final relay = MockRelay(schemas: spec.check);
    final (harness, c) = await _openSheet(
      tester,
      relay,
      consent: AiConsent.withLocation,
    );

    await _send(tester);
    await tester.pumpAndSettle();

    // What went out: the documented request, in the app's language and
    // units, the rider's consent and position rounded to ~1 km with it.
    final sent = relay.requests.single;
    expect(sent.step, 'plan');
    expect(sent.prompt, _prompt);
    expect(sent.locale, appLanguageTag);
    expect(sent.units, 'metric');
    expect(sent.context, {
      'start': {'lat': 47.38, 'lon': 8.54},
    });
    expect(sent.routeSummary, isNull);
    expect(sent.consented, isTrue);
    expect(sent.headers['authorization'], 'Bearer ${MockRelay.appUserId}');
    expect(sent.headers['x-velorki-client'], 'test/1.0.0+1');
    expect(sent.headers['accept'], 'text/event-stream');

    // What came back is on the map: from here past Uetliberg and home, the
    // loop the documented answer asks for, and the sheet made way for it.
    expect(find.byType(AssistantSheet), findsNothing);
    final plan = c.read(plannerControllerProvider);
    expect(plan.waypoints.map((w) => w.pos), [_zurich, _uetliberg, _zurich]);
    expect(plan.waypoints[1].name, 'Uetliberg');
    expect(plan.isClosedLoop, isTrue);
    expect(plan.options.profile, RouteProfile.trekking);
    expect(plan.result, isNotNull);
    // Drawn: the start, which is also the finish, and the place.
    expect(harness.map.waypoints.map((w) => w.position), [_zurich, _uetliberg]);
    expect(harness.backend.queries, isNotEmpty);
    expect(c.read(assistantControllerProvider).phase, AssistantPhase.ready);
  });

  testWidgets('1 · text-only consent sends no position at all', (tester) async {
    final relay = MockRelay(schemas: spec.check);
    await _openSheet(tester, relay);
    await _send(tester);
    await tester.pumpAndSettle();
    expect(relay.requests.single.body.containsKey('context'), isFalse);
  });

  group('4 · without Plus', () {
    testWidgets('known missing, Ask opens the sheet with Subscribe in its '
        'place; subscribed, Ask sends and the request goes with the bearer', (
      tester,
    ) async {
      final relay = MockRelay(schemas: spec.check);
      await pumpApp(
        tester,
        initialLocation: plannerRoute,
        extraOverrides: [
          ..._overrides(relay),
          subscriptionServiceProvider.overrideWithValue(
            FakeSubscriptionService(offering: defaultOffering),
          ),
        ],
      );
      await tester.pumpAndSettle();
      final c = ProviderScope.containerOf(
        tester.element(find.byType(PlannerScreen)),
      );
      c.listen(plusCustomerInfoProvider, (_, _) {});
      await tester.pumpAndSettle();
      await c
          .read(aiConsentControllerProvider.notifier)
          .set(AiConsent.textOnly);

      await _tapAsk(tester);
      expect(find.byType(PaywallScreen), findsNothing);
      expect(find.byType(AssistantSheet), findsOneWidget);
      expect(inSheet(find.text(l10n.assistantPlusRequired)), findsOne);
      await tester.tap(inSheet(find.text(l10n.plusSubscribe)));
      await tester.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsOneWidget);
      c.read(plusEntitledProvider.notifier).value = true;
      await tester.pumpAndSettle();
      await tapBack(tester);
      expect(find.byType(AssistantSheet), findsOneWidget);
      expect(relay.requests, isEmpty);

      await _send(tester);
      await tester.pumpAndSettle();
      expect(relay.requests.single.step, 'plan');
      expect(find.byType(AssistantSheet), findsNothing);
      expect(c.read(plannerControllerProvider).waypoints, hasLength(3));
      await unmountApp(tester);
    });

    testWidgets('the relay\'s not_entitled is said above the field; See '
        'details opens the paywall over the sheet, and once Plus is active '
        'the error goes and what was typed is still there', (tester) async {
      final relay = MockRelay(schemas: spec.check)
        ..reply(const RelayReply.error(notEntitled));
      await pumpApp(
        tester,
        initialLocation: plannerRoute,
        extraOverrides: [
          ..._overrides(relay),
          subscriptionServiceProvider.overrideWithValue(
            FakeSubscriptionService(offering: defaultOffering),
          ),
          // The store has not answered: the phone thinks Plus is active
          // (bought on another device, say) and the relay knows better.
          plusCustomerInfoProvider.overrideWith(
            (ref) => StreamController<PlusCustomerInfo>().stream,
          ),
        ],
      );
      await tester.pumpAndSettle();
      final c = ProviderScope.containerOf(
        tester.element(find.byType(PlannerScreen)),
      );
      c.read(plusEntitledProvider.notifier).value = true;
      await c
          .read(aiConsentControllerProvider.notifier)
          .set(AiConsent.textOnly);
      await _tapAsk(tester);

      await _send(tester);
      await tester.pumpAndSettle();
      expect(relay.requests, hasLength(1));
      final problem = inSheet(find.text(l10n.assistantNotEntitled));
      expect(problem, findsOneWidget);
      expect(
        tester.getRect(problem).top,
        lessThan(tester.getRect(inSheet(find.byType(TextField))).top),
      );
      expect(sheetUnlocked(tester), isTrue);

      await tapInSheet(tester, find.text(l10n.plusSeeDetails));
      await tester.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsOneWidget);
      // The store catches up: no Plus, then bought.
      c.read(plusEntitledProvider.notifier).value = false;
      await tester.pumpAndSettle();
      c.read(plusEntitledProvider.notifier).value = true;
      await tester.pumpAndSettle();
      await tapBack(tester);

      expect(find.byType(AssistantSheet), findsOneWidget);
      expect(inSheet(find.text(l10n.assistantNotEntitled)), findsNothing);
      expect(sheetField(tester).controller!.text, _prompt);

      // And now the relay says yes.
      await tester.tap(
        inSheet(find.widgetWithText(FilledButton, l10n.assistantSend)),
      );
      await tester.pumpAndSettle();
      expect(relay.requests, hasLength(2));
      expect(find.byType(AssistantSheet), findsNothing);
      await unmountApp(tester);
    });
  });

  group('5 · the relay says no', () {
    final cases = <(String, RelayReply, String Function(AppLocalizations))>[
      (
        '429 rate_limited with its retry-after',
        const RelayReply.error(rateLimited),
        (l) => l.assistantRateLimited(6),
      ),
      (
        '403 consent_required',
        const RelayReply.error(consentRequired),
        (l) => l.assistantConsentNeeded,
      ),
      (
        '503 unavailable, in the uniform error body',
        const RelayReply.error(unavailable),
        (l) => l.assistantFailed('Strava is not configured on this server.'),
      ),
      (
        'an error event after the stream opened (the documented failure)',
        RelayReply.documented('failure'),
        (l) => l.assistantFailed(
          'The proposed route was not usable: distance_km Too small: '
          'expected number to be >=5',
        ),
      ),
      (
        'an upstream_error event mid-stream, after a keep-alive',
        RelayReply.stream([
          SseFrame.ping,
          SseFrame.error('upstream_error', 'The model provider failed.'),
        ], gap: const Duration(seconds: 1)),
        (l) => l.assistantFailed('The model provider failed.'),
      ),
      (
        'a 502 from a proxy in front of the relay, as HTML',
        const RelayReply.proxyError(502, '<html><body>Bad gateway</body>'),
        (l) => l.assistantFailed(
          'The Velorki relay answered 502: <html><body>Bad gateway</body>',
        ),
      ),
    ];
    for (final (name, reply, message) in cases) {
      testWidgets('$name: said in the sheet, the sheet unlocks, Try again '
          'keeps the prompt and the next answer goes through', (tester) async {
        final relay = MockRelay(schemas: spec.check)..reply(reply);
        final (_, c) = await _openSheet(tester, relay);

        await _send(tester);
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();

        expect(_problem(message(l10n)), findsOneWidget);
        expect(sheetUnlocked(tester), isTrue);
        expect(relay.openStreams, 0);

        await tapInSheet(tester, find.text(l10n.assistantRetry));
        await tester.pumpAndSettle();
        expect(_problem(message(l10n)), findsNothing);
        expect(sheetField(tester).controller!.text, _prompt);

        await tester.tap(
          inSheet(find.widgetWithText(FilledButton, l10n.assistantSend)),
        );
        await tester.pumpAndSettle();
        expect(relay.requests, hasLength(2));
        expect(c.read(plannerControllerProvider).waypoints, hasLength(3));
      });
    }

    testWidgets('events it does not know, stray fields and frames split '
        'anywhere are passed over, and the answer still lands', (tester) async {
      final answer = SseFrame.routeRequest().wire;
      final cut = answer.indexOf('"via"');
      final relay = MockRelay(schemas: spec.check)
        ..reply(
          RelayReply.stream([
            SseFrame.event('thinking', {'step': 1}),
            SseFrame.raw('data: a message with no event name\n\n'),
            SseFrame.raw('id: 7\nretry: 1000\n\n'),
            SseFrame.raw('nonsense without a colon\n\n'),
            SseFrame.ping,
            SseFrame.raw(answer.substring(0, cut)),
            SseFrame.raw(answer.substring(cut)),
            SseFrame.done(),
          ], gap: const Duration(milliseconds: 300)),
        );
      final (_, c) = await _openSheet(tester, relay);

      await _send(tester);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(find.byType(AssistantSheet), findsNothing);
      expect(c.read(plannerControllerProvider).waypoints, hasLength(3));
    });

    testWidgets('a known event whose data is not JSON fails the request '
        'rather than the app, and the sheet unlocks', (tester) async {
      final relay = MockRelay(schemas: spec.check)
        ..reply(
          RelayReply.stream([
            SseFrame.raw('event: route_request\ndata: {"distance_km":\n\n'),
          ]),
        );
      final (_, c) = await _openSheet(tester, relay);

      await _send(tester);
      await tester.pumpAndSettle();

      final problem = c.read(assistantControllerProvider).problem;
      expect(problem?.failure, AssistantFailure.relay);
      expect(inSheet(find.text(l10n.assistantRetry)), findsOneWidget);
      expect(sheetUnlocked(tester), isTrue);
    });
  });

  group('6 · a relay that goes quiet', () {
    testWidgets('a stream that opens and then says nothing is given up '
        'after the idle timeout; the sheet unlocks and Try again works', (
      tester,
    ) async {
      final relay = MockRelay(schemas: spec.check)..reply(RelayReply.stall());
      final (_, c) = await _openSheet(tester, relay);

      await _send(tester);
      await tester.pump(const Duration(seconds: 44));
      expect(sheetUnlocked(tester), isFalse);
      expect(
        inSheet(find.widgetWithText(FilledButton, l10n.assistantThinking)),
        findsOneWidget,
      );

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(
        _problem(
          l10n.assistantFailed(
            'The Velorki relay stopped '
            'answering.',
          ),
        ),
        findsOneWidget,
      );
      expect(sheetUnlocked(tester), isTrue);
      // The app hung up, so the relay stops paying for tokens.
      expect(relay.cancelledStreams, 1);
      expect(relay.openStreams, 0);

      await tapInSheet(tester, find.text(l10n.assistantRetry));
      await tester.pumpAndSettle();
      await tester.tap(
        inSheet(find.widgetWithText(FilledButton, l10n.assistantSend)),
      );
      await tester.pumpAndSettle();
      expect(relay.requests, hasLength(2));
      expect(find.byType(AssistantSheet), findsNothing);
      expect(c.read(plannerControllerProvider).waypoints, hasLength(3));
    });

    testWidgets('the relay\'s keep-alives hold a slow answer open past the '
        'idle timeout', (tester) async {
      final relay = MockRelay(schemas: spec.check)
        ..reply(
          RelayReply.stream([
            SseFrame.ping,
            SseFrame.ping,
            SseFrame.ping,
            SseFrame.routeRequest(),
            SseFrame.done(),
          ], gap: const Duration(seconds: 20)),
        );
      final (_, c) = await _openSheet(tester, relay);

      await _send(tester);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(seconds: 10));
      }
      await tester.pumpAndSettle();
      expect(c.read(assistantControllerProvider).problem, isNull);
      expect(c.read(plannerControllerProvider).waypoints, hasLength(3));
    });

    testWidgets('the relay\'s own deadline arrives as an error event and is '
        'said like any other', (tester) async {
      final relay = MockRelay(schemas: spec.check)
        ..reply(
          RelayReply.stream([
            SseFrame.ping,
            SseFrame.error('upstream_error', relayDeadlineMessage),
          ], gap: const Duration(seconds: 20)),
        );
      await _openSheet(tester, relay);

      await _send(tester);
      await tester.pump(const Duration(seconds: 41));
      await tester.pumpAndSettle();
      expect(
        _problem(l10n.assistantFailed(relayDeadlineMessage)),
        findsOneWidget,
      );
      expect(sheetUnlocked(tester), isTrue);
    });
  });

  group('7 · the sheet remembers', () {
    testWidgets('closed and opened again it keeps the prompt and the error; '
        'Start over clears both', (tester) async {
      final relay = MockRelay(schemas: spec.check)
        ..reply(const RelayReply.error(rateLimited));
      final (_, c) = await _openSheet(tester, relay);
      await _send(tester);
      await tester.pumpAndSettle();
      expect(_problem(l10n.assistantRateLimited(6)), findsOneWidget);

      // Swiped away by a tap on the map above it.
      await tester.tapAt(const Offset(500, 40));
      await tester.pumpAndSettle();
      expect(find.byType(AssistantSheet), findsNothing);

      await _tapAsk(tester);
      expect(sheetField(tester).controller!.text, _prompt);
      expect(_problem(l10n.assistantRateLimited(6)), findsOneWidget);

      await tapInSheet(tester, find.text(l10n.assistantStartOver));
      await tester.pumpAndSettle();
      expect(sheetField(tester).controller!.text, isEmpty);
      expect(_problem(l10n.assistantRateLimited(6)), findsNothing);
      expect(c.read(assistantControllerProvider), const AssistantState());
      expect(inSheet(find.text(l10n.assistantStartOver)), findsNothing);
    });
  });
}

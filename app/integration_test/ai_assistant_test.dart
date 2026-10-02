// The AI assistant on the device, against the relay mocked at the HTTP layer
// inside the test process: no relay, no model, no server of any kind. The
// app's own RelayClient parses the SSE bytes the mock writes, which are the
// relay's documented contract (test/support/relay_contract.dart, held to
// web/openapi.yaml by the widget suite); the controllers, sheets, gazetteer,
// on-device router and the map above it are the real app.
//
//   flutter test integration_test/ai_assistant_test.dart -d <device> \
//     --dart-define=VELORKI_BROUTER_URL= \
//     --dart-define=VELORKI_SEGMENTS_URL=http://10.0.2.2:8000 \
//     --dart-define=VELORKI_API_URL= --dart-define=VELORKI_ITEST_REGION=madeira
//
// VELORKI_API_URL may stay empty: the relay client is overridden either way.
// --dart-define=VELORKI_ITEST_HOLD=12 holds each pose worth a photograph that
// many seconds, for `xcrun simctl io <udid> screenshot` from outside: the
// in-test screenshot cannot see the map.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/core/permissions/location_permission.dart';
import 'package:velorki/core/plus/plus_gate.dart';
import 'package:velorki/features/assistant/application/ai_request_settings.dart';
import 'package:velorki/features/assistant/application/route_advice_controller.dart';
import 'package:velorki/features/assistant/data/ai_consent_controller.dart';
import 'package:velorki/features/assistant/data/place_geocoder.dart';
import 'package:velorki/features/assistant/domain/ai_consent.dart';
import 'package:velorki/features/assistant/domain/intent_resolver.dart';
import 'package:velorki/features/assistant/presentation/assistant_sheet.dart';
import 'package:velorki/features/assistant/presentation/describe_route_sheet.dart';
import 'package:velorki/features/integrations/common/data/relay_client_provider.dart';
import 'package:velorki/features/map/data/position_provider.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/planner/domain/route_profile.dart';
import 'package:velorki/features/planner/presentation/planner_screen.dart';
import 'package:velorki/features/planner/presentation/route_format.dart';
import 'package:velorki/features/search/data/gazetteer_store.dart';
import 'package:velorki/features/search/domain/search_result.dart';
import 'package:velorki/features/shared/presentation/stat_tile.dart';
import 'package:velorki/features/smart_loop/application/smart_loop_controller.dart';
import 'package:velorki/features/subscription/application/plus_access.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';
import 'package:velorki_geo/velorki_geo.dart';

// The one file shared with the widget suite: it has no Flutter in it and
// drags none of that harness along.
import '../test/support/mock_relay.dart';
import 'support/fakes.dart';
import 'support/harness.dart';
import 'support/region.dart';
import 'support/tiles.dart';

/// How long the device's relay client waits on a silent stream: the app's
/// 45 s, cut so a test can sit through it.
const Duration _idle = Duration(seconds: 3);

/// How long a pose worth a photograph is held; nothing by default.
const Duration _hold = Duration(
  seconds: int.fromEnvironment('VELORKI_ITEST_HOLD'),
);

/// A place of the region's gazetteer away from the start, for the model to
/// ride past.
String get _via => region.name == 'madeira' ? 'Machico' : 'Brooklyn';

/// Names resolved by the region's offline gazetteer, the search the device
/// has without a network.
class _GazetteerGeocoder implements PlaceGeocoder {
  _GazetteerGeocoder(this.store);
  final Future<GazetteerStore> Function() store;

  @override
  Future<List<SearchResult>> lookup(
    String query, {
    LatLng? bias,
    int limit = 5,
  }) async => (await store()).search(query, near: bias, limit: limit);
}

List<Override> _overrides(MockRelay relay) => [
  relayClientProvider.overrideWith((ref) {
    final client = relay.client(planIdleTimeout: _idle);
    ref.onDispose(client.close);
    return client;
  }),
  intentResolverProvider.overrideWith(
    (ref) => IntentResolver(
      geocoder: _GazetteerGeocoder(
        () => ref.read(gazetteerStoreProvider.future),
      ),
    ),
  ),
  locationPermissionGatewayProvider.overrideWithValue(
    const GrantedLocationPermission(),
  ),
  positionSourceProvider.overrideWithValue(FixedPositionSource(region.start)),
];

/// Boots the app on the Plan tab, the tile there, Plus and consent given,
/// and an empty plan.
Future<ProviderContainer> _boot(WidgetTester tester, MockRelay relay) async {
  final c = await pumpApp(tester, overrides: _overrides(relay));
  await ensureRegionTile(tester, c);
  await (await c.read(gazetteerStoreProvider.future)).refresh();
  c.read(plusEntitledProvider.notifier).value = true;
  await c.read(aiConsentControllerProvider.notifier).set(AiConsent.textOnly);
  c.read(plannerControllerProvider.notifier).clear();
  await pumpFor(tester, const Duration(milliseconds: 300));
  return c;
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(PlannerScreen)));

Finder _inSheet(Finder f) =>
    find.descendant(of: find.byType(AssistantSheet), matching: f);

bool _routed(ProviderContainer c) {
  final plan = c.read(plannerControllerProvider);
  if (plan.route.hasError) fail('routing failed: ${plan.route.error}');
  return plan.result != null && !plan.isRouting;
}

Future<void> _waitRouted(
  WidgetTester tester,
  ProviderContainer c,
  String what,
) => waitUntil(
  tester,
  () => _routed(c),
  describe: what,
  timeout: const Duration(seconds: 90),
  onTimeout: () => '${c.read(plannerControllerProvider)}',
);

Future<void> _planRoute(WidgetTester tester, ProviderContainer c) async {
  c.read(plannerControllerProvider.notifier)
    ..addWaypoint(region.start)
    ..addWaypoint(region.end);
  await pumpFor(tester, const Duration(milliseconds: 400));
  await _waitRouted(tester, c, 'the route');
}

Future<void> _openAssistant(WidgetTester tester) async {
  await tapAndPump(
    tester,
    find.widgetWithText(LabeledIconButton, _l10n(tester).assistantAction),
  );
  await waitForWidget(tester, find.byType(AssistantSheet));
  await pumpFor(tester, const Duration(milliseconds: 500));
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(_inSheet(find.byType(TextField)), text);
  await pumpFor(tester, const Duration(milliseconds: 300));
  // The keyboard would cover the button.
  FocusManager.instance.primaryFocus?.unfocus();
  await pumpFor(tester, const Duration(milliseconds: 600));
}

Future<void> _send(WidgetTester tester) => tapAndPump(
  tester,
  _inSheet(find.widgetWithText(FilledButton, _l10n(tester).assistantSend)),
);

Future<void> _closeSheet(WidgetTester tester) async {
  await tester.tapAt(const Offset(40, 120));
  await pumpFor(tester, const Duration(milliseconds: 800));
  expect(find.byType(AssistantSheet), findsNothing);
}

/// The first café, else any place, of the digest [request] carries.
Map<String, Object?> _stopOf(RecordedPlanRequest request) {
  final places = (request.digest!['places']! as List<Object?>)
      .cast<Map<String, Object?>>();
  return places.firstWhere(
    (p) => p['kind'] == 'cafe',
    orElse: () => places.first,
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('1 · a prompt comes back as a route_request and lands on the '
      'map as a loop past the place it names', (tester) async {
    final relay = MockRelay()
      ..reply(
        RelayReply.stream([
          SseFrame.routeRequest({
            'via': [_via],
          }),
          SseFrame.done(),
        ], gap: const Duration(milliseconds: 400)),
      );
    final c = await _boot(tester, relay);
    await _openAssistant(tester);
    await _type(tester, 'A hilly loop past $_via with a coffee stop');
    await _send(tester);

    await waitUntil(
      tester,
      () => find.byType(AssistantSheet).evaluate().isEmpty,
      describe: 'the sheet to make way for the plan',
    );
    await _waitRouted(tester, c, 'the loop');
    final plan = c.read(plannerControllerProvider);
    expect(plan.waypoints.first.pos, region.start);
    expect(plan.waypoints[1].name, _via);
    expect(plan.isClosedLoop, isTrue);

    final sent = relay.requests.single;
    expect(sent.step, 'plan');
    expect(sent.locale, c.read(aiLocaleTagProvider));
    expect(sent.units, 'metric');
    expect(sent.consented, isTrue);
    expect(sent.body.containsKey('context'), isFalse);
    debugPrint(
      'VELORKI_AI plan past ${plan.waypoints[1].name} '
      '${plan.result!.lengthM.round()} m',
    );
    await screenshot(tester, 'ai-new-route');
    await unmountApp(tester);
  });

  testWidgets('2 · a question about the planned route goes with its digest; '
      'Add as stop, Avoid and the bike change the route, and Undo offers the '
      'fix again', (tester) async {
    final relay = MockRelay()
      ..reply(
        RelayReply.answering((request) {
          final stop = _stopOf(request);
          final length = request.routeSummary!['distance_km']! as num;
          final from = (length * 0.45).toDouble();
          final to = (length * 0.55).toDouble();
          return RelayReply.stream([
            SseFrame.ping,
            SseFrame.routeAdvice({
              'answer': '${stop['name'] ?? 'A place'} is by the road.',
              'findings': [
                {
                  'kind': 'food',
                  'place_id': stop['id'],
                  'text': 'Stop here.',
                  'fix': {'type': 'add_stop', 'place_id': stop['id']},
                },
                {
                  'kind': 'traffic',
                  'from_km': from,
                  'to_km': to,
                  'text': 'A busy road.',
                  'fix': {'type': 'avoid', 'from_km': from, 'to_km': to},
                },
                {
                  'kind': 'profile',
                  'text': 'Mostly asphalt.',
                  'fix': {'type': 'profile', 'profile': 'fastbike'},
                },
              ],
            }),
            SseFrame.done(),
          ], gap: const Duration(milliseconds: 300));
        }),
      );
    final c = await _boot(tester, relay);
    await _planRoute(tester, c);
    final l10n = _l10n(tester);

    await _openAssistant(tester);
    expect(_inSheet(find.text(l10n.assistantRouteTitle)), findsOneWidget);
    await _type(tester, 'Coffee? Traffic?');
    await _send(tester);
    await waitUntil(
      tester,
      () =>
          c.read(routeAdviceControllerProvider).phase ==
          RouteAdvicePhase.answered,
      describe: 'the answer',
      onTimeout: () => '${c.read(routeAdviceControllerProvider).problem}',
    );
    final sent = relay.requests.single;
    expect(sent.step, 'route');
    expect(sent.body.containsKey('context'), isFalse);
    expect(sent.digest!['stretches'], isNotEmpty);
    expect(sent.placeIds, isNotEmpty);
    final stop = _stopOf(sent);

    Future<void> apply(String label) async {
      await tapAndPump(
        tester,
        _inSheet(find.widgetWithText(FilledButton, label)),
      );
      await _waitRouted(tester, c, 'the route with "$label"');
      await pumpFor(tester, const Duration(milliseconds: 500));
    }

    await apply(l10n.assistantFixAddStop);
    expect(c.read(plannerControllerProvider).waypoints[1].name, stop['name']);
    await apply(l10n.assistantFixAvoid);
    expect(c.read(plannerControllerProvider).avoid, hasLength(1));
    await apply(
      l10n.assistantFixProfile(profileLabel(l10n, RouteProfile.fastbike)),
    );
    expect(
      c.read(plannerControllerProvider).options.profile,
      RouteProfile.fastbike,
    );
    expect(c.read(routeAdviceControllerProvider).failures, isEmpty);
    expect(c.read(routeAdviceControllerProvider).applied, {0, 1, 2});
    await screenshot(tester, 'ai-route-fixes');

    await _closeSheet(tester);
    final undo = find.widgetWithText(LabeledIconButton, l10n.plannerUndo);
    for (var i = 0; i < 3; i++) {
      await tapAndPump(tester, undo);
      await _waitRouted(tester, c, 'undo ${i + 1}');
    }
    final plan = c.read(plannerControllerProvider);
    expect(plan.waypoints, hasLength(2));
    expect(plan.avoid, isEmpty);
    expect(plan.options.profile, RouteProfile.trekking);
    expect(c.read(routeAdviceControllerProvider).applied, isEmpty);

    // 7 · opened again, the answer is still there.
    await _openAssistant(tester);
    expect(
      _inSheet(find.widgetWithText(FilledButton, l10n.assistantFixAddStop)),
      findsOneWidget,
    );
    await _closeSheet(tester);
    await unmountApp(tester);
  });

  testWidgets('8 · a loop the assistant made is asked about: Show marks the '
      'place, Add as stop and Avoid change the loop, and a chip far down '
      'brings the field back into view', (tester) async {
    final relay = MockRelay()
      ..reply(
        RelayReply.stream([
          SseFrame.routeRequest({
            'distance_km': 12,
            'loop': true,
            'via': <String>[],
            'stops': <String>[],
          }),
          SseFrame.done(),
        ]),
      )
      ..reply(
        RelayReply.answering((request) {
          final stop = _stopOf(request);
          final length = request.routeSummary!['distance_km']! as num;
          final from = (length * 0.6).toDouble();
          final to = (length * 0.7).toDouble();
          return RelayReply.stream([
            SseFrame.routeAdvice({
              'answer': '${stop['name'] ?? 'A place'} is by the road.',
              'findings': [
                {'kind': 'food', 'place_id': stop['id'], 'text': 'Stop here.'},
                {
                  'kind': 'traffic',
                  'from_km': from,
                  'to_km': to,
                  'text': 'A busy road.',
                  'fix': {'type': 'avoid', 'from_km': from, 'to_km': to},
                },
              ],
            }),
            SseFrame.done(),
          ]);
        }),
      );
    final c = await _boot(tester, relay);
    final l10n = _l10n(tester);
    await _openAssistant(tester);
    await _type(tester, 'A 12 km loop from here');
    await _send(tester);
    await waitUntil(
      tester,
      () =>
          find.byType(AssistantSheet).evaluate().isEmpty &&
          !c.read(smartLoopControllerProvider).running,
      describe: 'the loop search',
      timeout: const Duration(seconds: 120),
    );
    await _waitRouted(tester, c, 'the loop');
    // The loop sheet over the planner goes; the loop stays.
    await tester.tapAt(const Offset(40, 120));
    await pumpFor(tester, const Duration(milliseconds: 800));
    expect(c.read(plannerControllerProvider).isRoutable, isFalse);

    await _openAssistant(tester);
    expect(_inSheet(find.text(l10n.assistantRouteTitle)), findsOneWidget);
    await _type(tester, 'Coffee? Traffic?');
    await _send(tester);
    await waitUntil(
      tester,
      () =>
          c.read(routeAdviceControllerProvider).phase ==
          RouteAdvicePhase.answered,
      describe: 'the answer',
      onTimeout: () => '${c.read(routeAdviceControllerProvider).problem}',
    );

    await tapAndPump(
      tester,
      _inSheet(find.widgetWithText(TextButton, l10n.assistantFindingShow))
          .first,
    );
    expect(c.read(routeAdviceControllerProvider).shown, isNotNull);
    expect(c.read(plannerControllerProvider).pois, isEmpty);
    await pumpFor(tester, _hold);
    await screenshot(tester, 'ai-show-place');

    for (final label in [l10n.assistantFixAddStop, l10n.assistantFixAvoid]) {
      await tapAndPump(
        tester,
        _inSheet(find.widgetWithText(FilledButton, label)),
      );
      await _waitRouted(tester, c, 'the loop with "$label"');
      await pumpFor(tester, const Duration(milliseconds: 500));
    }
    expect(c.read(routeAdviceControllerProvider).failures, isEmpty);
    expect(c.read(routeAdviceControllerProvider).applied, {0, 1});
    expect(c.read(routeAdviceControllerProvider).shown, isNull);
    final plan = c.read(plannerControllerProvider);
    expect(plan.avoid, hasLength(1));
    expect(
      haversineMeters(
        plan.result!.positions.first,
        plan.result!.positions.last,
      ),
      lessThan(300),
    );

    // A chip far down fills the field, which comes back into view.
    final chip = _inSheet(
      find.widgetWithText(ActionChip, l10n.assistantRouteExampleRoadBike),
    );
    await tester.ensureVisible(chip);
    await pumpFor(tester, const Duration(milliseconds: 500));
    await tapAndPump(tester, chip, settle: const Duration(seconds: 1));
    final field = _inSheet(find.byType(TextField));
    expect(
      tester.widget<TextField>(field).controller!.text,
      l10n.assistantRouteExampleRoadBike,
    );
    final viewport = tester.getRect(
      find.ancestor(of: field, matching: find.byType(Scrollable)).first,
    );
    final at = tester.getRect(field);
    expect(at.top, greaterThanOrEqualTo(viewport.top - 1));
    expect(at.bottom, lessThanOrEqualTo(viewport.bottom + 1));
    await pumpFor(tester, _hold);
    await screenshot(tester, 'ai-chip-field');

    await _closeSheet(tester);
    c.read(plannerControllerProvider.notifier).clear();
    await unmountApp(tester);
  });

  testWidgets('5 · known to be without Plus, the sheet opens with Subscribe '
      'where Ask would be, and the field still takes a question', (
    tester,
  ) async {
    final relay = MockRelay();
    final c = await pumpApp(
      tester,
      overrides: [
        ..._overrides(relay),
        plusAccessProvider.overrideWith((ref, _) => PlusAccess.missing),
      ],
    );
    final l10n = _l10n(tester);
    await _openAssistant(tester);
    expect(_inSheet(find.text(l10n.assistantPlusRequired)), findsOneWidget);
    expect(
      _inSheet(find.widgetWithText(FilledButton, l10n.assistantSend)),
      findsNothing,
    );
    await _type(tester, 'A flat loop');
    expect(
      tester
          .widget<TextField>(_inSheet(find.byType(TextField)))
          .controller!
          .text,
      'A flat loop',
    );
    await pumpFor(tester, _hold);
    await screenshot(tester, 'ai-plus-banner');
    expect(relay.requests, isEmpty);
    await _closeSheet(tester);
    expect(
      c.read(plusAccessProvider(PlusFeature.aiAssistant)),
      PlusAccess.missing,
    );
    await unmountApp(tester);
  });

  testWidgets('3 · Describe this route streams the text into the sheet and '
      'Save keeps it on the route', (tester) async {
    const parts = ['A ride ', 'along the coast ', 'and back.'];
    final relay = MockRelay()
      ..reply(
        RelayReply.stream([
          for (final p in parts) SseFrame.text(p),
          SseFrame.done(),
        ], gap: const Duration(milliseconds: 700)),
      );
    final c = await _boot(tester, relay);
    await _planRoute(tester, c);
    final l10n = _l10n(tester);
    final route = c.read(plannerControllerProvider).result!;
    final saved = await c
        .read(routeRepositoryProvider)
        .savePlannedRoute(
          name: 'AI itest ${DateTime.now().millisecondsSinceEpoch}',
          route: route,
          waypoints: c.read(plannerControllerProvider).waypoints,
          options: c.read(plannerControllerProvider).options,
        );
    c.read(routerProvider).go(routeDetailLocation(saved.id));
    await pumpFor(tester, const Duration(seconds: 2));

    await tapAndPump(tester, find.text(l10n.describeAction));
    await waitForWidget(tester, find.byType(DescribeRouteSheet));
    // The text grows while the sheet says it is writing.
    await waitUntil(
      tester,
      () => find.text(parts.first).evaluate().isNotEmpty,
      describe: 'the first delta',
      timeout: const Duration(seconds: 60),
    );
    expect(
      find.widgetWithText(FilledButton, l10n.describeRunning),
      findsOneWidget,
    );
    await waitForWidget(tester, find.text(parts.join()));
    await waitForWidget(
      tester,
      find.widgetWithText(FilledButton, l10n.describeSave),
    );
    final sent = relay.requests.single;
    expect(sent.step, 'describe');
    expect(sent.digest, isNotNull);

    await tapAndPump(
      tester,
      find.widgetWithText(FilledButton, l10n.describeSave),
    );
    await waitUntil(
      tester,
      () => find.byType(DescribeRouteSheet).evaluate().isEmpty,
      describe: 'the sheet to close',
    );
    final stored = await c.read(routeRepositoryProvider).routeById(saved.id);
    expect(stored!.description, parts.join().trim());
    expect(stored.aiDescriptionGenerated, isTrue);
    await screenshot(tester, 'ai-describe');
    await c.read(routeRepositoryProvider).delete(saved.id);
    c.read(routerProvider).go(plannerRoute);
    await pumpFor(tester, const Duration(milliseconds: 500));
    await unmountApp(tester);
  });

  testWidgets('6 · a relay that opens the stream and goes silent is given up '
      'after the idle timeout; the sheet unlocks and Try again works', (
    tester,
  ) async {
    final relay = MockRelay()
      ..reply(RelayReply.stall())
      ..reply(
        RelayReply.stream([
          SseFrame.routeRequest({
            'via': [_via],
          }),
          SseFrame.done(),
        ]),
      );
    final c = await _boot(tester, relay);
    final l10n = _l10n(tester);
    await _openAssistant(tester);
    await _type(tester, 'A loop past $_via');
    await _send(tester);

    final retry = _inSheet(find.text(l10n.assistantRetry));
    await waitForWidget(tester, retry, timeout: _idle * 4);
    expect(
      _inSheet(
        find.text(l10n.assistantFailed('The Velorki relay stopped answering.')),
      ),
      findsOneWidget,
    );
    expect(relay.cancelledStreams, 1);

    await tapAndPump(tester, retry);
    await _send(tester);
    await waitUntil(
      tester,
      () => find.byType(AssistantSheet).evaluate().isEmpty,
      describe: 'the second answer to land',
    );
    expect(relay.requests, hasLength(2));
    await _waitRouted(tester, c, 'the loop');
    await unmountApp(tester);
  });
}

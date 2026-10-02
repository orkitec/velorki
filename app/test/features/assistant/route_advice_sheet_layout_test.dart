// The assistant sheet in the app's shell: where it opens, upright and
// sideways, how it is pulled up and away, and what it keeps when it goes.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/app/shell_layout.dart';
import 'package:velorki/core/db/tables/routes.dart' show RouteSource;
import 'package:velorki/core/plus/plus_gate.dart';
import 'package:velorki/features/assistant/application/route_digest_service.dart';
import 'package:velorki/features/assistant/data/ai_consent_controller.dart';
import 'package:velorki/features/assistant/domain/ai_consent.dart';
import 'package:velorki/features/assistant/presentation/assistant_sheet.dart';
import 'package:velorki/features/integrations/common/data/relay_client_provider.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/domain/route_profile.dart';
import 'package:velorki/features/planner/domain/routing_options.dart';
import 'package:velorki/features/planner/domain/saved_route.dart';
import 'package:velorki/features/planner/domain/waypoint.dart';
import 'package:velorki/features/planner/presentation/planner_screen.dart';
import 'package:velorki/features/shared/presentation/docking_sheet.dart';
import 'package:velorki/features/shared/presentation/stat_tile.dart';
import 'package:velorki_api/velorki_api.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';
import '../integrations/support/fakes.dart';
import '../recording/support/pump.dart';
import 'support/fakes.dart';

const LatLng _start = LatLng(48, 11);
const LatLng _end = LatLng(48.1, 11.1);

const Size _upright = Size(402, 874);
const Size _sideways = Size(874, 402);

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

/// A long answer, so there is something to pull the sheet up for.
const RouteAdvice _advice = RouteAdvice(
  answer:
      'The Kiosk at 6.7 km is about halfway. The first stretch runs along '
      'the river on a quiet path, the second climbs a little through the '
      'woods, and the last kilometres are on a calm road into Grünwald.',
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
  ],
);

Finder _inSheet(Finder finder) =>
    find.descendant(of: find.byType(AssistantSheet), matching: finder);

Finder get _surface => find.byKey(assistantSheetSurfaceKey);

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(PlannerScreen)));

/// Puts the test view at [size] points, at three pixels a point, with the
/// safe areas an iPhone has that way up.
Future<void> _screen(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = size * 3;
  final sideways = size.width > size.height;
  tester.view.viewPadding = FakeViewPadding(
    left: sideways ? 62 * 3 : 0,
    right: sideways ? 62 * 3 : 0,
    top: sideways ? 0 : 62 * 3,
    bottom: 21 * 3,
  );
  tester.view.padding = tester.view.viewPadding;
  addTearDown(() {
    tester.view
      ..resetPhysicalSize()
      ..resetDevicePixelRatio()
      ..resetViewPadding()
      ..resetPadding();
  });
}

/// Tells the app the phone's bottom edge went to [side].
void _railOn(WidgetTester tester, RailSide side) {
  const channel = MethodChannel(ScreenSideChannel.channelName);
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    channel,
    (call) async => call.method == 'side' ? side.name : null,
  );
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
}

/// The app on the Plan tab with [_route] on the map; answers [_advice].
Future<FakeRelayClient> _app(WidgetTester tester, Size size) async {
  await _screen(tester, size);
  final relay = FakeRelayClient(
    planEvents: const <PlanEvent>[RouteAdviceEvent(_advice), DoneEvent()],
  );
  await pumpRecordingApp(
    tester,
    initialLocation: plannerRoute,
    surfaceSize: size,
    expectTextFits: false,
    extraOverrides: [
      relayClientProvider.overrideWithValue(relay),
      routeDigestServiceProvider.overrideWithValue(
        FakeRouteDigestService(digest: _digest),
      ),
    ],
  );
  await tester.pumpAndSettle();
  final container = _container(tester);
  container.read(plusEntitledProvider.notifier).value = true;
  await container
      .read(aiConsentControllerProvider.notifier)
      .set(AiConsent.textOnly);
  container.read(plannerControllerProvider.notifier).loadSavedRoute(_route());
  await tester.pumpAndSettle();
  return relay;
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(
    find.widgetWithText(LabeledIconButton, l10n.assistantAction),
  );
  await tester.pumpAndSettle();
}

Future<void> _ask(WidgetTester tester, String question) async {
  await tester.enterText(_inSheet(find.byType(TextField)), question);
  await tester.tap(
    _inSheet(find.widgetWithText(FilledButton, l10n.assistantSend)),
  );
  await tester.pumpAndSettle();
}

/// Swipes the sheet away by its handle.
Future<void> _dismiss(
  WidgetTester tester, {
  Offset towards = const Offset(0, 1),
}) async {
  final handle = find.descendant(
    of: _surface,
    matching: find.byType(SheetHandle),
  );
  await tester.fling(handle, towards * 600, 2000);

  await tester.pumpAndSettle();
  expect(find.byType(AssistantSheet), findsNothing);
}

String _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(_inSheet(find.byType(TextField))).controller!.text;

void main() {
  setUp(() => debugShellLayoutOverride = null);

  testWidgets('upright, the sheet opens as high as the planner\'s card '
      'rests, is pulled up to read and scrolls, and the button stays in '
      'reach', (tester) async {
    await _app(tester, _upright);
    final card = tester.getRect(find.byType(DockingSheetShell));

    await _open(tester);
    final sheet = tester.getRect(_surface);
    expect(sheet.top, closeTo(card.top, 1));
    expect(sheet.bottom, closeTo(_upright.height, 1));

    await _ask(tester, l10n.assistantRouteExampleCoffee);
    expect(tester.takeException(), isNull);
    // The answer does not grow the sheet over the route.
    expect(tester.getRect(_surface).top, closeTo(card.top, 1));
    final button = tester.getRect(
      _inSheet(find.widgetWithText(FilledButton, l10n.assistantSend)),
    );
    expect(button.bottom, lessThanOrEqualTo(_upright.height - 21));

    // Pulled up by its handle, it reaches the safe area at the top.
    await tester.drag(
      find.descendant(of: _surface, matching: find.byType(SheetHandle)),
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(_surface).top, lessThan(62 + 20));
    expect(tester.getRect(_surface).top, greaterThanOrEqualTo(62));
    await tester.scrollUntilVisible(
      _inSheet(find.text(l10n.assistantFixAddStop)),
      100,
      scrollable: _inSheet(find.byType(Scrollable)).first,
    );
    expect(tester.takeException(), isNull);
  });

  for (final side in RailSide.values) {
    testWidgets('sideways, rail on the ${side.name}: the sheet comes out from '
        'the rail\'s side as far as the planner\'s card rests, and its '
        'answer fits', (tester) async {
      _railOn(tester, side);
      await _app(tester, _sideways);
      final card = tester.getRect(find.byType(DockingSheetShell));

      await _open(tester);
      final sheet = tester.getRect(_surface);
      expect(sheet.height, closeTo(_sideways.height, 1));
      if (side == RailSide.left) {
        expect(sheet.left, closeTo(0, 1));
        expect(sheet.right, closeTo(card.right, 1));
      } else {
        expect(sheet.right, closeTo(_sideways.width, 1));
        expect(sheet.left, closeTo(card.left, 1));
      }
      // The content reads across, upright.
      final title = tester.getRect(
        _inSheet(find.text(l10n.assistantRouteTitle)),
      );
      expect(title.width, greaterThan(title.height));

      await _ask(tester, l10n.assistantRouteExampleCheck);
      expect(tester.takeException(), isNull);
      final button = tester.getRect(
        _inSheet(find.widgetWithText(FilledButton, l10n.assistantSend)),
      );
      expect(button.bottom, lessThanOrEqualTo(_sideways.height));
      expect(sheet.contains(button.center), isTrue);

      await tester.scrollUntilVisible(
        _inSheet(find.text(l10n.assistantFixAddStop)),
        100,
        scrollable: _inSheet(find.byType(Scrollable)).first,
      );
      await tester.tap(_inSheet(find.text(l10n.assistantFixAddStop)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(_inSheet(find.text(l10n.assistantFixApplied)), findsOneWidget);

      await _dismiss(
        tester,
        towards: Offset(side == RailSide.left ? -1 : 1, 0),
      );
    });
  }

  /// The list the answer is in: the sheet's content.
  Finder content() => find
      .ancestor(
        of: _inSheet(find.text(_advice.answer)),
        matching: find.byType(Scrollable),
      )
      .first;

  double contentOffset(WidgetTester tester) =>
      tester.state<ScrollableState>(content()).position.pixels;

  testWidgets('upright, a drag on the content scrolls it at the height the '
      'sheet rests at, and only the handle moves the sheet', (tester) async {
    await _app(tester, _upright);
    await _open(tester);
    await _ask(tester, l10n.assistantRouteExampleCoffee);
    final rest = tester.getRect(_surface);
    final before = contentOffset(tester);

    await tester.drag(content(), const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(tester.getRect(_surface), rest);
    expect(contentOffset(tester), greaterThan(before + 100));

    // Down again, past the top: the list stops, the sheet stays.
    await tester.drag(content(), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(tester.getRect(_surface), rest);
    expect(contentOffset(tester), 0);

    await tester.drag(
      find.descendant(of: _surface, matching: find.byType(SheetHandle)),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(_surface).top, closeTo(rest.top - 200, 2));
    // The Start over and Ask row stays at the bottom, in reach.
    final button = tester.getRect(
      _inSheet(find.widgetWithText(FilledButton, l10n.assistantSend)),
    );
    expect(button.bottom, lessThanOrEqualTo(_upright.height - 21));
  });

  testWidgets('sideways, a drag on the content scrolls it and leaves the '
      'sheet where it is; the handle moves it', (tester) async {
    _railOn(tester, RailSide.right);
    await _app(tester, _sideways);
    await _open(tester);
    await _ask(tester, l10n.assistantRouteExampleCoffee);
    final rest = tester.getRect(_surface);
    final before = contentOffset(tester);

    await tester.drag(content(), const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(tester.getRect(_surface), rest);
    expect(contentOffset(tester), greaterThan(before + 100));
    final button = tester.getRect(
      _inSheet(find.widgetWithText(FilledButton, l10n.assistantSend)),
    );
    expect(rest.contains(button.center), isTrue);

    await tester.drag(
      find.descendant(of: _surface, matching: find.byType(SheetHandle)),
      const Offset(-150, 0),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(_surface).left, lessThan(rest.left - 50));
  });

  testWidgets('swiped away and opened again, the sheet shows the same '
      'question, answer and applied fixes; Start over clears them and keeps '
      'the mode', (tester) async {
    final relay = await _app(tester, _upright);
    await _open(tester);
    await _ask(tester, l10n.assistantRouteExampleCoffee);
    await tester.ensureVisible(_inSheet(find.text(l10n.assistantFixAddStop)));
    await tester.tap(_inSheet(find.text(l10n.assistantFixAddStop)));
    await tester.pumpAndSettle();
    await _dismiss(tester);

    await _open(tester);
    expect(_fieldText(tester), l10n.assistantRouteExampleCoffee);
    expect(_inSheet(find.text(_advice.answer)), findsOneWidget);
    expect(_inSheet(find.text(l10n.assistantFixApplied)), findsOneWidget);
    expect(relay.planCalls, hasLength(1));

    await tester.tap(_inSheet(find.text(l10n.assistantStartOver)));
    await tester.pumpAndSettle();
    expect(_fieldText(tester), isEmpty);
    expect(_inSheet(find.text(_advice.answer)), findsNothing);
    expect(_inSheet(find.text(l10n.assistantRouteTitle)), findsOneWidget);
    expect(_inSheet(find.text(l10n.assistantStartOver)), findsNothing);
    // Nothing of it comes back with the next opening.
    await _dismiss(tester);
    await _open(tester);
    expect(_fieldText(tester), isEmpty);
    expect(_inSheet(find.text(_advice.answer)), findsNothing);
  });

  testWidgets('the new route\'s prompt and mode are kept too, and a cleared '
      'plan forgets the answer about it', (tester) async {
    await _app(tester, _upright);
    await _open(tester);
    await _ask(tester, l10n.assistantRouteExampleCoffee);
    // The field was scrolled into view in the card at rest; the modes are
    // above it.
    await tester.ensureVisible(find.text(l10n.assistantModeNew));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.assistantModeNew));
    await tester.pumpAndSettle();
    await tester.enterText(_inSheet(find.byType(TextField)), 'A flat loop');
    await tester.pump();
    await _dismiss(tester);

    await _open(tester);
    expect(_inSheet(find.text(l10n.assistantTitle)), findsOneWidget);
    expect(_fieldText(tester), 'A flat loop');
    await tester.tap(find.text(l10n.assistantModeRoute));
    await tester.pumpAndSettle();
    expect(_inSheet(find.text(_advice.answer)), findsOneWidget);
    await _dismiss(tester);

    // Another route: the answer about the old one goes, the mode with it
    // as soon as there is no route to ask about.
    _container(tester).read(plannerControllerProvider.notifier).clear();
    await tester.pumpAndSettle();
    _container(tester)
        .read(plannerControllerProvider.notifier)
        .loadSavedRoute(_route());
    await tester.pumpAndSettle();
    await _open(tester);
    await tester.tap(find.text(l10n.assistantModeRoute));
    await tester.pumpAndSettle();
    expect(_inSheet(find.text(_advice.answer)), findsNothing);
    expect(_fieldText(tester), isEmpty);
  });

  testWidgets('over the keyboard the sheet keeps its height and the button '
      'stays in reach, and it rests where it was once the keyboard goes', (
    tester,
  ) async {
    await _app(tester, _upright);
    await _open(tester);
    final rest = tester.getRect(_surface);

    // The keyboard comes up over a few frames, and goes again.
    for (final inset in [100.0, 200.0, 300.0, 336.0]) {
      tester.view.viewInsets = FakeViewPadding(bottom: inset * 3);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    final up = tester.getRect(_surface);
    expect(up.height, closeTo(rest.height, 1));
    expect(up.bottom, closeTo(_upright.height - 336, 1));
    final button = tester.getRect(
      _inSheet(find.widgetWithText(FilledButton, l10n.assistantSend)),
    );
    expect(button.bottom, lessThanOrEqualTo(_upright.height - 336));

    for (final inset in [300.0, 200.0, 100.0, 0.0]) {
      tester.view.viewInsets = FakeViewPadding(bottom: inset * 3);
      await tester.pump();
    }
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(tester.getRect(_surface).top, closeTo(rest.top, 1));
  });
}

// The assistant sheet in the app's shell: where it opens, upright and
// sideways, how it is pulled up and away, and what it keeps when it goes.
import 'package:flutter/gestures.dart' show HitTestTarget;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/app/shell_layout.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/core/db/tables/routes.dart' show RouteSource;
import 'package:velorki/core/plus/plus_gate.dart';
import 'package:velorki/features/assistant/application/route_digest_service.dart';
import 'package:velorki/features/assistant/data/ai_consent_controller.dart';
import 'package:velorki/features/assistant/domain/ai_consent.dart';
import 'package:velorki/features/assistant/presentation/assistant_sheet.dart';
import 'package:velorki/features/integrations/common/data/relay_client_provider.dart';
import 'package:velorki/features/map/presentation/map_controls.dart';
import 'package:velorki/features/map/presentation/shared_map_host.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/domain/route_profile.dart';
import 'package:velorki/features/planner/domain/routing_options.dart';
import 'package:velorki/features/planner/domain/saved_route.dart';
import 'package:velorki/features/planner/domain/waypoint.dart';
import 'package:velorki/features/planner/presentation/planner_screen.dart';
import 'package:velorki/features/shared/presentation/ai_mark.dart';
import 'package:velorki/features/search/presentation/search_field.dart';
import 'package:velorki/features/shared/presentation/docking_sheet.dart';
import 'package:velorki/features/shared/presentation/floating_bar.dart';
import 'package:velorki/features/shared/presentation/stat_tile.dart';
import 'package:velorki_api/velorki_api.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';
import '../integrations/support/fakes.dart';
import '../planner/support/fakes.dart' show TestMapController;
import '../planner/support/pump.dart' show TestMapView;
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

/// What the floating bar covers at the screen's bottom upright.
const double _barInset = 21 + floatingBarBottomGap + floatingBarHeight;

/// Whether [target] is a render object under [ancestor].
bool _inside(HitTestTarget target, RenderObject ancestor) {
  if (target is! RenderObject) return false;
  for (RenderObject? node = target; node != null; node = node.parent) {
    if (node == ancestor) return true;
  }
  return false;
}

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
    // Above the floating bar, which lies over the card's end as over the
    // planner's card.
    expect(button.bottom, lessThanOrEqualTo(_upright.height - _barInset));

    // Pulled up by its handle, it opens as far as the planner's card does.
    await tester.drag(
      find.descendant(of: _surface, matching: find.byType(SheetHandle)),
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getRect(_surface).top,
      closeTo(_upright.height * (1 - sheetMaxExtent), 0.5),
    );
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
    await tester.drag(content(), const Offset(0, 800));
    await tester.pumpAndSettle();
    expect(tester.getRect(_surface), rest);
    expect(contentOffset(tester), 0);

    // Pulled past halfway to the top, it snaps all the way open.
    await tester.drag(
      find.descendant(of: _surface, matching: find.byType(SheetHandle)),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getRect(_surface).top,
      closeTo(_upright.height * (1 - sheetMaxExtent), 0.5),
    );
    // The Start over and Ask row stays at the bottom, in reach.
    final button = tester.getRect(
      _inSheet(find.widgetWithText(FilledButton, l10n.assistantSend)),
    );
    expect(button.bottom, lessThanOrEqualTo(_upright.height - _barInset));
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

  for (final sideways in [false, true]) {
    testWidgets('${sideways ? 'sideways' : 'upright'}, a chip far down the '
        'list fills the field and scrolls it back into view', (tester) async {
      if (sideways) _railOn(tester, RailSide.right);
      await _app(tester, sideways ? _sideways : _upright);
      await _open(tester);
      await _ask(tester, l10n.assistantRouteExampleCoffee);
      final chip = _inSheet(
        find.widgetWithText(ActionChip, l10n.assistantRouteExampleRoadBike),
      );
      await tester.scrollUntilVisible(chip, 100, scrollable: content());
      await tester.pumpAndSettle();
      final viewport = tester.getRect(content());
      Rect field() => tester.getRect(_inSheet(find.byType(TextField)));
      expect(
        field().bottom,
        lessThan(viewport.top),
        reason: 'the field is out of view above the chip',
      );

      await tester.tap(chip);
      await tester.pump();
      // Scrolled, not jumped.
      await tester.pump(const Duration(milliseconds: 100));
      expect(field().bottom, lessThan(viewport.top + field().height));
      await tester.pumpAndSettle();
      expect(_fieldText(tester), l10n.assistantRouteExampleRoadBike);
      expect(field().top, greaterThanOrEqualTo(viewport.top - 0.5));
      expect(field().bottom, lessThanOrEqualTo(viewport.bottom + 0.5));
      expect(tester.takeException(), isNull);
    });
  }

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
    // The field is in view at rest; the modes are above it.
    await tester.ensureVisible(find.text(l10n.assistantModeRoute));
    await tester.pumpAndSettle();
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
    await tester.ensureVisible(find.text(l10n.assistantModeRoute));
    await tester.pumpAndSettle();
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
    await tester.tap(_inSheet(find.byType(TextField)));
    await tester.pump();

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

  testWidgets('the keyboard of the planner\'s search, above the card, leaves '
      'the card where it is, under the keyboard', (tester) async {
    await _app(tester, _upright);
    await _open(tester);
    final rest = tester.getRect(_surface);
    final search = find.descendant(
      of: find.byType(SearchField),
      matching: find.byType(TextField),
    );
    await tester.tap(search);
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding(bottom: 336.0 * 3);
    await tester.pumpAndSettle();
    expect(tester.getRect(_surface), rest);
    expect(find.byType(AssistantSheet), findsOneWidget);
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(tester.getRect(_surface), rest);
  });

  for (final side in <RailSide?>[null, RailSide.right]) {
    final size = side == null ? _upright : _sideways;
    final name = side == null ? 'upright' : 'sideways';
    testWidgets('$name: with the AI card up the map beside it is the map: '
        'no barrier, a drag and a pinch reach the map, a tap puts a waypoint '
        'there as with the planner\'s card, and back closes the card onto '
        'the planner\'s card as it was', (tester) async {
      if (side != null) _railOn(tester, side);
      await _app(tester, size);
      final container = _container(tester);
      final map =
          container.read(sharedMapControllerProvider)! as TestMapController;
      final card = tester.getRect(find.byType(DockingSheetShell));

      await _open(tester);
      final sheet = tester.getRect(_surface);
      expect(find.byType(DockingSheetShell), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      // A point of the map clear of the card, the chrome and the column.
      final at = side == null
          ? Offset(size.width / 3, sheet.top - 120)
          : Offset(sheet.left - 150, size.height / 2 + 40);
      final view = tester.renderObject(find.byType(TestMapView));
      bool reachesMap(Offset point) =>
          tester.hitTestOnBinding(point).path.any((e) => e.target == view);
      expect(reachesMap(at), isTrue, reason: 'nothing over the map');

      // A drag pans, two fingers pinch.
      await tester.dragFrom(at, const Offset(0, 80));
      await tester.pumpAndSettle();
      expect(map.dragged.dy, greaterThan(70));
      final a = await tester.startGesture(at - const Offset(30, 0));
      final b = await tester.startGesture(at + const Offset(30, 0));
      await a.moveBy(const Offset(-40, 0));
      await b.moveBy(const Offset(40, 0));
      await a.up();
      await b.up();
      await tester.pumpAndSettle();
      expect(map.mostFingers, 2);
      expect(tester.getRect(_surface), sheet);

      // A tap puts a waypoint, the card stays.
      map.tapsAreTaps = true;
      await tester.tapAt(at);
      await tester.pumpAndSettle();
      expect(container.read(plannerControllerProvider).waypoints, hasLength(3));
      expect(find.byType(AssistantSheet), findsOneWidget);
      expect(tester.getRect(_surface), sheet);

      // Upright the control column stands above the card, and takes its
      // taps; sideways it lies under the card at rest, as under the
      // planner's.
      if (side == null) {
        final column = tester.getRect(find.byType(MapControls));
        expect(column.bottom, lessThan(sheet.top));
        final button = tester.renderObject(find.byType(MapControls));
        expect(
          tester
              .hitTestOnBinding(column.center)
              .path
              .any((e) => e.target == button || _inside(e.target, button)),
          isTrue,
        );
      }

      // Back closes it, onto the planner's card as it was.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AssistantSheet), findsNothing);
      expect(tester.getRect(find.byType(DockingSheetShell)), card);
      // And the next back is the app's again.
      expect(
        Navigator.of(tester.element(find.byType(PlannerScreen))).canPop(),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    });
  }

  /// How far the sheet reaches out from its end of the screen, along its
  /// travel: up from the bottom upright, out from the rail's side sideways.
  double travel(WidgetTester tester, Size size, RailSide? side) {
    final sheet = tester.getRect(_surface);
    return switch (side) {
      null => size.height - sheet.top,
      RailSide.right => size.width - sheet.left,
      RailSide.left => sheet.right,
    };
  }

  for (final side in <RailSide?>[null, RailSide.right, RailSide.left]) {
    final size = side == null ? _upright : _sideways;
    final name = side == null ? 'upright' : 'sideways, rail ${side.name}';
    testWidgets('$name: let go anywhere, the card settles exactly at the '
        'planner card\'s resting or full height, and only a swipe away '
        'closes it', (tester) async {
      if (side != null) _railOn(tester, side);
      await _app(tester, size);
      // The planner's own card, resting.
      final card = tester.getRect(find.byType(DockingSheetShell));
      final planRest = switch (side) {
        null => size.height - card.top,
        RailSide.right => size.width - card.left,
        RailSide.left => card.right,
      };
      await _open(tester);
      await _ask(tester, l10n.assistantRouteExampleCoffee);
      final length = side == null ? size.height : size.width;
      final full = length * sheetMaxExtent;
      final rest = travel(tester, size, side);
      expect(rest, closeTo(planRest, 0.5));
      // Out, along the sheet's travel.
      final out = switch (side) {
        null => const Offset(0, -1),
        RailSide.right => const Offset(-1, 0),
        RailSide.left => const Offset(1, 0),
      };
      final handle = find.descendant(
        of: _surface,
        matching: find.byType(SheetHandle),
      );

      Future<void> expectAtStop(String what, {double? at}) async {
        await tester.pumpAndSettle();
        expect(find.byType(AssistantSheet), findsOneWidget, reason: what);
        final now = travel(tester, size, side);
        if (at != null) {
          expect(now, closeTo(at, 0.5), reason: what);
        } else {
          expect(
            (now - rest).abs() < 0.5 || (now - full).abs() < 0.5,
            isTrue,
            reason: '$what: $now is neither rest $rest nor full $full',
          );
        }
      }

      // Slowly a little way out, a long way out, quickly some way, and
      // back in from wherever it settled.
      await tester.timedDrag(handle, out * 40, const Duration(seconds: 1));
      await expectAtStop('a little out', at: rest);
      await tester.timedDrag(handle, out * 37, const Duration(seconds: 2));
      await expectAtStop('a little out, slowly');
      await tester.drag(handle, out * 230);
      await expectAtStop('far out', at: full);
      await tester.timedDrag(handle, -out * 90, const Duration(seconds: 1));
      await expectAtStop('a little in from the top');
      await tester.drag(handle, out * 400);
      await expectAtStop('all the way out', at: full);
      // Flung in from the top, it stops at rest rather than going away.
      await tester.fling(handle, -out * 200, 1500);
      await expectAtStop('flung in from the top', at: rest);
      // A little in from rest, and let go: back to rest.
      await tester.timedDrag(handle, -out * 50, const Duration(seconds: 1));
      await expectAtStop('a little in from rest', at: rest);

      await _dismiss(tester, towards: -out);
    });
  }

  for (final side in <RailSide?>[null, RailSide.right]) {
    final size = side == null ? _upright : _sideways;
    final name = side == null ? 'upright' : 'sideways';
    testWidgets('$name: the answer arrives marked with the AI\'s sparkle, is '
        'scrolled to the top of what the card shows, and the scrollbar shows '
        'there is more', (tester) async {
      if (side != null) _railOn(tester, side);
      await _app(tester, size);
      await _open(tester);
      // Before the answer the scrollbar is there but not shown.
      final scrollbar = _inSheet(find.byType(Scrollbar));
      expect(scrollbar, findsOneWidget);

      await tester.enterText(
        _inSheet(find.byType(TextField)),
        l10n.assistantRouteExampleCoffee,
      );
      await tester.tap(
        _inSheet(find.widgetWithText(FilledButton, l10n.assistantSend)),
      );
      await tester.pump();
      await tester.pump();
      // Scrolled, not jumped.
      final first = contentOffset(tester);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(contentOffset(tester), greaterThan(first));
      await tester.pumpAndSettle();

      final answer = _inSheet(find.text(_advice.answer));
      final mark = find.ancestor(of: answer, matching: find.byType(AiAnswer));
      expect(mark, findsOneWidget);
      expect(
        find.descendant(of: mark, matching: find.byType(AiSparkle)),
        findsOneWidget,
      );
      final viewport = tester.getRect(content());
      expect(tester.getRect(mark).top, closeTo(viewport.top + 12, 1));
      // The sparkle sits beside the answer's first line, before it.
      final sparkle = tester.getRect(
        find.descendant(of: mark, matching: find.byType(AiSparkle)),
      );
      expect(sparkle.right, lessThan(tester.getRect(answer).left));

      // More below: the scrollbar shows for a moment, then fades.
      final position = tester.state<ScrollableState>(content()).position;
      expect(position.maxScrollExtent, greaterThan(position.pixels));
      expect(tester.widget<Scrollbar>(scrollbar).thumbVisibility, isTrue);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(tester.widget<Scrollbar>(scrollbar).thumbVisibility, isNot(true));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('an error that arrives is scrolled into view too', (
    tester,
  ) async {
    final relay = await _app(tester, _upright);
    relay.planFailure = const RelayException(
      RelayError(
        code: RelayErrorCode.rateLimited,
        message: 'too many requests',
        retryAfterS: 90,
      ),
      statusCode: 429,
    );
    await _open(tester);
    await tester.enterText(
      _inSheet(find.byType(TextField)),
      l10n.assistantRouteExampleCoffee,
    );
    await tester.tap(
      _inSheet(find.widgetWithText(FilledButton, l10n.assistantSend)),
    );
    await tester.pumpAndSettle();
    final problem = _inSheet(
      find.textContaining(l10n.assistantRateLimited(90)),
    );
    expect(problem, findsOneWidget);
    final viewport = tester.getRect(
      find
          .ancestor(
            of: _inSheet(find.byType(TextField)),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    final row = tester.getRect(problem);
    expect(row.top, greaterThanOrEqualTo(viewport.top));
    expect(row.bottom, lessThanOrEqualTo(viewport.bottom));
  });

  for (final dark in [false, true]) {
    testWidgets('${dark ? 'dark' : 'light'}: the card\'s top edge is drawn in '
        'the AI\'s colours, whatever the accent', (tester) async {
      await _screen(tester, _upright);
      await pumpRecordingApp(
        tester,
        initialLocation: plannerRoute,
        surfaceSize: _upright,
        expectTextFits: false,
        theme: dark
            ? buildDarkTheme(AccentPreset.berry)
            : buildLightTheme(AccentPreset.berry),
        extraOverrides: [
          relayClientProvider.overrideWithValue(FakeRelayClient()),
        ],
      );
      await tester.pumpAndSettle();
      // The planner's button that opens it has the AI's sparkle.
      expect(
        find.descendant(
          of: find.widgetWithText(LabeledIconButton, l10n.assistantAction),
          matching: find.byType(AiSparkle),
        ),
        findsOneWidget,
      );
      await _open(tester);
      final edge = tester.widget<CustomPaint>(
        find.byKey(assistantSheetEdgeKey),
      );
      final painter = edge.foregroundPainter! as AiEdgePainter;
      expect(painter.gradient.colors, [
        dark ? velorkiAiDark : velorkiAiLight,
        dark ? velorkiAiMidDark : velorkiAiMidLight,
        dark ? velorkiAiEndDark : velorkiAiEndLight,
      ]);
      final theme = Theme.of(tester.element(_surface));
      expect(theme.brightness, dark ? Brightness.dark : Brightness.light);
      expect(painter.gradient.colors, isNot(contains(theme.velorki.accent)));
      // The edge lies along the card's top, inside its rounded corners.
      expect(
        tester.getRect(find.byKey(assistantSheetEdgeKey)).top,
        closeTo(tester.getRect(_surface).top, 0.5),
      );
    });
  }
}

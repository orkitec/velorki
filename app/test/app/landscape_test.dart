import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/app/shell_layout.dart';
import 'package:velorki/features/map/presentation/map_controls.dart';
import 'package:velorki/features/map/presentation/shared_map_host.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/domain/route_profile.dart';
import 'package:velorki/features/planner/presentation/profile_chip_row.dart';
import 'package:velorki/features/planner/presentation/route_format.dart';
import 'package:velorki/features/recording/application/recording_controller.dart';
import 'package:velorki/features/recording/domain/recording_snapshot.dart';
import 'package:velorki/features/recording/presentation/live_figures_view.dart';
import 'package:velorki/features/recording/presentation/recording_screen.dart';
import 'package:velorki/features/search/presentation/search_field.dart';
import 'package:velorki/features/shared/application/nav_bar_docking.dart';
import 'package:velorki/features/shared/presentation/docking_sheet.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../features/recording/support/pump.dart';
import '../support/app.dart';

/// A phone held sideways: 874 by 402 points, the island's safe area on both
/// sides and the home indicator's at the bottom, as an iPhone reports it.
const Size _sideways = Size(874, 402);

/// The smallest phone sideways, with no safe areas at all.
const Size _smallSideways = Size(667, 375);

/// The largest phone sideways.
const Size _wideSideways = Size(956, 440);

const Size _upright = Size(402, 874);

/// Puts the test view at [size] logical pixels, at three pixels a point,
/// with the safe areas an iPhone has that way up.
Future<void> _screen(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = size * 3;
  final sideways = size.width > size.height;
  final notch = size.height > 380;
  tester.view.viewPadding = FakeViewPadding(
    left: sideways && notch ? 62 * 3 : 0,
    right: sideways && notch ? 62 * 3 : 0,
    top: sideways ? 0 : 62 * 3,
    bottom: notch ? 21 * 3 : 0,
  );
  tester.view.padding = tester.view.viewPadding;
  await tester.pumpAndSettle();
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

RecordingSnapshot _snapshot() => RecordingSnapshot(
  rideId: 'ride-1',
  status: RecordingStatus.active,
  startedAt: DateTime.utc(2026, 9, 12, 10),
  autoPaused: false,
  distanceM: 12345,
  elapsed: const Duration(minutes: 42, seconds: 7),
  moving: const Duration(minutes: 40),
  speedMps: 6,
  avgSpeedMps: 5,
  ascentM: 210,
  descentM: 190,
  lastPosition: const LatLng(48.1, 11.2),
  accuracyM: 4,
  pointCount: 120,
  newPoints: const [LatLng(48.0, 11.0), LatLng(48.1, 11.2)],
);

Rect _rect(WidgetTester tester, Finder finder) => tester.getRect(finder);

/// The sheet's box as it shows on screen, turned or not.
Rect _sheet(WidgetTester tester) =>
    _rect(tester, find.byType(DockingSheetShell));

/// The rail as it shows: its glass, not the turned frame it finds its
/// place in, which is the whole screen.
Rect _rail(WidgetTester tester) => _rect(
  tester,
  find
      .descendant(
        of: find.byType(FloatingNavigationBar),
        matching: find.byType(ClipRRect),
      )
      .first,
);

bool _railOnLeft(WidgetTester tester, Size size) =>
    _rail(tester).center.dx < size.width / 2;

/// Drags the sheet by its handle towards the rail, all the way.
Future<void> _dockSheet(
  WidgetTester tester,
  Size size, {
  required bool left,
}) async {
  await tester.dragFrom(
    tester.getCenter(find.byType(SheetHandle)),
    Offset((left ? -1 : 1) * size.width, 0),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapRail(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationRail),
      matching: find.text(label),
    ),
  );
  await tester.pumpAndSettle();
}

// The test font draws every glyph a full em wide, so at a phone's width
// sideways the search hint counts as cut off where the app's own font fits
// it: these tests leave the text check out, and the fit is checked on the
// simulator at 874 and 667 points.
void main() {
  setUp(() => debugShellLayoutOverride = null);
  tearDown(() {
    // What a test left of the phone's shape goes with it.
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view
      ..resetPhysicalSize()
      ..resetDevicePixelRatio()
      ..resetViewPadding()
      ..resetPadding();
  });

  for (final size in [_wideSideways, _sideways, _smallSideways]) {
    group('sideways at $size', () {
      for (final side in RailSide.values) {
        testWidgets('Plan, rail on the ${side.name}: the sheet is the upright '
            'one turned, out from the rail\'s side and as tall as the screen, '
            'with its content upright, and the chrome over the map beside it', (
          tester,
        ) async {
          _railOn(tester, side);
          await _screen(tester, size);
          await pumpRecordingApp(
            tester,
            initialLocation: plannerRoute,
            surfaceSize: size,
            expectTextFits: false,
          );
          await tester.pumpAndSettle();

          expect(find.byType(NavigationRail), findsOneWidget);
          expect(find.byType(DraggableScrollableSheet), findsOneWidget);
          expect(
            find.ancestor(
              of: find.byType(DraggableScrollableSheet),
              matching: find.byType(RotatedBox),
            ),
            findsWidgets,
          );
          final sheet = _sheet(tester);
          final rail = _rail(tester);
          final left = _railOnLeft(tester, size);
          expect(left, side == RailSide.left);
          // As tall as the screen, from the rail's edge of it, under the rail.
          expect(sheet.height, closeTo(size.height, 1));
          if (left) {
            expect(sheet.left, closeTo(0, 1));
          } else {
            expect(sheet.right, closeTo(size.width, 1));
          }
          expect(sheet.contains(rail.center), isTrue);
          // The content reads across, as upright: its title is wider than tall.
          final title = _rect(tester, find.text(l10n.plannerEmptyState));
          expect(title.width, greaterThan(title.height));

          expect(find.byType(ProfileChipRow), findsNothing);
          // The profile menu is a button at the end of the search field.
          final search = _rect(tester, find.byType(SearchField));
          final menu = _rect(tester, find.byType(ProfileDropdown));
          expect(
            find.descendant(
              of: find.byType(SearchField),
              matching: find.byType(ProfileDropdown),
            ),
            findsOneWidget,
          );
          expect(search.intersect(menu), menu);
          // Full size where the field has the room, smaller on the SE.
          expect(
            tester
                .widget<ProfileDropdown>(find.byType(ProfileDropdown))
                .compact,
            size == _smallSideways,
          );
          // Its far end, 16 points from the screen's edge whatever that
          // edge's safe area.
          expect(
            left ? size.width - search.right : search.left,
            closeTo(16, 0.5),
          );
          // At rest the search stands beside the sheet, the one thing of the
          // row at the top in reach: whole, menu and all.
          expect(search.overlaps(sheet), isFalse);
          expect(
            left ? search.left - sheet.right : sheet.left - search.right,
            closeTo(12, 1),
          );
          expect(search.top, lessThan(size.height * 0.3));
          await unmountApp(tester);
        });
      }

      for (final side in RailSide.values) {
        testWidgets('Plan docked, rail on the ${side.name}: the search, with '
            'the profile menu in it, and the controls in one row at the top, '
            'as tall as each other, the search at the far end', (tester) async {
          _railOn(tester, side);
          await _screen(tester, size);
          await pumpRecordingApp(
            tester,
            initialLocation: plannerRoute,
            surfaceSize: size,
            expectTextFits: false,
          );
          await tester.pumpAndSettle();
          final left = side == RailSide.left;
          expect(_railOnLeft(tester, size), left);

          await _dockSheet(tester, size, left: left);
          final sheet = _sheet(tester);
          final rail = _rail(tester);
          final search = _rect(tester, find.byType(SearchField));
          final controls = _rect(tester, find.byType(MapControls));
          expect(controls.width, greaterThan(controls.height));
          // One row at the top: the controls as tall as the search, and
          // level with it.
          expect(controls.height, closeTo(search.height, 1));
          expect(controls.center.dy, closeTo(search.center.dy, 0.5));
          expect(search.top, lessThan(size.height * 0.3));
          // In the mirrored order, from the rail to the far edge.
          if (left) {
            expect(controls.right, lessThanOrEqualTo(search.left));
          } else {
            expect(search.right, lessThanOrEqualTo(controls.left));
          }
          // The far end 16 points from the screen's edge, past the safe
          // area there.
          expect(
            left ? size.width - search.right : search.left,
            closeTo(16, 0.5),
          );
          // The menu inside the search.
          final menu = _rect(tester, find.byType(ProfileDropdown));
          expect(search.intersect(menu), menu);
          for (final (a, b) in [
            (sheet, search),
            (sheet, controls),
            (rail, search),
            (rail, controls),
            (search, controls),
          ]) {
            expect(a.overlaps(b), isFalse, reason: '$a over $b');
          }
          await unmountApp(tester);
        });
      }

      testWidgets('Record: a ride hides the rail, and the sheet docked shows '
          'the ride\'s figures in the rail\'s place', (tester) async {
        await _screen(tester, size);
        final h = await pumpRecordingApp(
          tester,
          surfaceSize: size,
          expectTextFits: false,
        );
        await tester.pumpAndSettle();
        expect(find.byType(NavigationRail), findsOneWidget);
        final left = _railOnLeft(tester, size);

        await emitSnapshot(tester, h, _snapshot());
        await tester.pumpAndSettle();
        expect(find.byType(NavigationRail), findsNothing);
        expect(find.byType(FiguresBar), findsNothing);

        await _dockSheet(tester, size, left: left);
        // The bar's glass, not the turned frame it finds its place in.
        final figures = _rect(
          tester,
          find
              .descendant(
                of: find.byType(FiguresBar),
                matching: find.byType(ClipRRect),
              )
              .first,
        );
        expect(
          tester.widget<FiguresBar>(find.byType(FiguresBar)).railSide,
          isNotNull,
        );
        // Turned with the rail: tall, on the rail's side.
        expect(figures.height, greaterThan(figures.width));
        expect(figures.center.dx < size.width / 2, left);
        // The map's controls stand at the top beside the docked sheet, as
        // beside the rail before the ride.
        final controls = _rect(tester, find.byType(MapControls));
        final sheet = _sheet(tester);
        expect(controls.width, greaterThan(controls.height));
        expect(controls.top, lessThan(size.height * 0.3));
        expect(controls.overlaps(figures), isFalse);
        expect(controls.overlaps(sheet), isFalse);
        expect(
          left ? controls.left - sheet.right : sheet.left - controls.right,
          closeTo(12, 1),
        );
        await unmountApp(tester);
      });

      testWidgets('the glance view fits the screen sideways', (tester) async {
        await _screen(tester, size);
        final h = await pumpRecordingApp(
          tester,
          surfaceSize: size,
          expectTextFits: false,
          preferences: const <String, Object>{'recording.saver': true},
        );
        await tester.pump();
        await emitSnapshot(tester, h, _snapshot());
        await tester.pump(glanceAfter + const Duration(seconds: 1));
        // An overflow would have failed the test already.
        expect(find.byType(DraggableScrollableSheet), findsNothing);
        await unmountApp(tester);
      });
    });
  }

  testWidgets('the profile menu in the search field picks a profile', (
    tester,
  ) async {
    await _screen(tester, _sideways);
    await pumpRecordingApp(
      tester,
      initialLocation: plannerRoute,
      surfaceSize: _sideways,
      expectTextFits: false,
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ProfileDropdown)),
    );
    // In the search field, in reach with the sheet at rest.
    await tester.tap(
      find.descendant(
        of: find.byType(SearchField),
        matching: find.byType(ProfileDropdown),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(profileLabel(l10n, RouteProfile.fastbike)).last);
    await tester.pumpAndSettle();
    expect(
      container.read(plannerControllerProvider).options.profile,
      RouteProfile.fastbike,
    );
    await unmountApp(tester);
  });

  testWidgets('on the smallest phone the field is compact: the menu stays in '
      'it, smaller, the short hint and no magnifier, and the menu steps '
      'aside while the rider types', (tester) async {
    await _screen(tester, _smallSideways);
    await pumpRecordingApp(
      tester,
      initialLocation: plannerRoute,
      surfaceSize: _smallSideways,
      expectTextFits: false,
    );
    await tester.pumpAndSettle();
    final inField = find.descendant(
      of: find.byType(SearchField),
      matching: find.byType(ProfileDropdown),
    );
    expect(inField, findsOneWidget);
    expect(tester.widget<ProfileDropdown>(inField).compact, isTrue);
    final search = _rect(tester, find.byType(SearchField));
    final menu = _rect(tester, inField);
    expect(search.intersect(menu), menu);
    expect(menu.height, greaterThanOrEqualTo(40));
    final decoration = tester
        .widget<TextField>(find.byType(TextField))
        .decoration!;
    expect(decoration.hintText, l10n.searchHintShort);
    expect(decoration.prefixIcon, isNull);
    // At rest beside the sheet, whole.
    expect(search.overlaps(_sheet(tester)), isFalse);

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(inField, findsNothing);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(inField, findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('upright, the profiles stay a row of chips under the search, '
      'and the controls a column', (tester) async {
    await _screen(tester, _upright);
    await pumpRecordingApp(
      tester,
      initialLocation: plannerRoute,
      surfaceSize: _upright,
      expectTextFits: false,
    );
    await tester.pumpAndSettle();
    expect(find.byType(ProfileDropdown), findsNothing);
    final search = _rect(tester, find.byType(SearchField));
    final chips = _rect(tester, find.byType(ProfileChipRow));
    expect(chips.top, closeTo(search.bottom + 10, 0.5));
    expect(chips.height, 44);
    expect(chips.width, closeTo(search.width, 0.5));
    final controls = _rect(tester, find.byType(MapControls));
    expect(controls.height, greaterThan(controls.width));
    expect(controls.width, mapControlButtonSize + 6);
    await unmountApp(tester);
  });

  testWidgets('a drag towards the rail docks the sheet into it, as into the '
      'bar upright, and the next tab\'s sheet comes back to rest', (
    tester,
  ) async {
    await _screen(tester, _sideways);
    await pumpRecordingApp(
      tester,
      initialLocation: plannerRoute,
      surfaceSize: _sideways,
      expectTextFits: false,
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SharedMapHost)),
    );
    final open = _sheet(tester);

    await _dockSheet(tester, _sideways, left: _railOnLeft(tester, _sideways));
    expect(container.read(navBarDockingProvider), {plannerRoute});
    expect(
      tester
          .widget<FloatingNavigationBar>(find.byType(FloatingNavigationBar))
          .docked,
      isTrue,
    );
    // Only the handle strip is left beside the rail.
    expect(_sheet(tester).width, lessThan(open.width / 2));

    // As upright, the next tab's sheet starts where this one is and comes
    // back up to rest.
    await _tapRail(tester, l10n.tabRecord);
    expect(container.read(navBarDockingProvider), isEmpty);
    expect(_sheet(tester).width, closeTo(open.width, 1));
    await unmountApp(tester);
  });

  testWidgets('turning the phone during a ride keeps the ride and the map', (
    tester,
  ) async {
    await _screen(tester, _upright);
    final h = await pumpRecordingApp(
      tester,
      surfaceSize: _upright,
      expectTextFits: false,
    );
    await tester.pump();
    await emitSnapshot(tester, h, _snapshot());
    await tester.pumpAndSettle();
    final map = tester.element(find.byType(SharedMapHost));
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);

    await _screen(tester, _sideways);
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    expect(_sheet(tester).height, closeTo(_sideways.height, 1));

    await _screen(tester, _upright);
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    expect(_sheet(tester).width, closeTo(_upright.width, 1));
    expect(tester.element(find.byType(SharedMapHost)), same(map));
    final container = ProviderScope.containerOf(map);
    expect(container.read(recordingControllerProvider).isRecording, isTrue);
    await unmountApp(tester);
  });
}

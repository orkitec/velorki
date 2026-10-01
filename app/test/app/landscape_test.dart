import 'dart:math' as math;

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

/// The camera island's safe area at each side of a [size] screen, as
/// [_screen] sets it.
EdgeInsets _island(Size size) {
  final inset = size.height > 380 ? 62.0 : 0.0;
  return EdgeInsets.only(left: inset, right: inset);
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
      testWidgets('Plan: the sheet is the upright one turned, out from the '
          'rail\'s side and as tall as the screen, with its content upright, '
          'and the chrome over the map beside it', (tester) async {
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
        expect(find.byType(ProfileDropdown), findsOneWidget);
        // At rest the search stands beside the sheet, the one thing of the
        // row at the top in reach: no narrower than the strip the sheet
        // leaves, less the air at its ends.
        final island = left ? _island(size).right : _island(size).left;
        final strip = left
            ? size.width - island - sheet.right
            : sheet.left - island;
        final search = _rect(tester, find.byType(SearchField));
        final visible = left
            ? search.right - math.max(search.left, sheet.right)
            : math.min(search.right, sheet.left) - search.left;
        expect(visible, greaterThanOrEqualTo(strip - 2 * 12 - 1));
        expect(search.top, lessThan(size.height * 0.3));
        await unmountApp(tester);
      });

      for (final side in RailSide.values) {
        testWidgets('Plan docked, rail on the ${side.name}: search, profile '
            'menu and controls in one row at the top, the search at the far '
            'end', (tester) async {
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
          final dropdown = _rect(tester, find.byType(ProfileDropdown));
          final controls = _rect(tester, find.byType(MapControls));
          expect(controls.width, greaterThan(controls.height));
          // One row: the three centred on one line, at the top.
          for (final r in [dropdown, controls]) {
            expect(r.center.dy, closeTo(search.center.dy, 3));
          }
          expect(search.top, lessThan(size.height * 0.3));
          // In the mirrored order, from the far edge to the rail.
          final inOrder = left
              ? [controls, dropdown, search]
              : [search, dropdown, controls];
          for (var i = 0; i + 1 < inOrder.length; i++) {
            expect(
              inOrder[i].right,
              lessThanOrEqualTo(inOrder[i + 1].left),
              reason: '${inOrder[i]} before ${inOrder[i + 1]}',
            );
          }
          // Inside the far edge's safe area.
          final island = _island(size);
          expect(search.left, greaterThanOrEqualTo(island.left));
          expect(search.right, lessThanOrEqualTo(size.width - island.right));
          for (final (a, b) in [
            (sheet, search),
            (sheet, dropdown),
            (sheet, controls),
            (rail, search),
            (rail, dropdown),
            (rail, controls),
            (search, controls),
            (dropdown, controls),
            (search, dropdown),
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

  testWidgets('the profile menu picks a profile', (tester) async {
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
    // At rest the menu lies under the sheet; docked it is in reach.
    await _dockSheet(tester, _sideways, left: _railOnLeft(tester, _sideways));
    await tester.tap(find.byType(ProfileDropdown));
    await tester.pumpAndSettle();
    await tester.tap(find.text(profileLabel(l10n, RouteProfile.fastbike)).last);
    await tester.pumpAndSettle();
    expect(
      container.read(plannerControllerProvider).options.profile,
      RouteProfile.fastbike,
    );
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

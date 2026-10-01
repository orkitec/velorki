import 'package:flutter/material.dart';
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
import 'package:velorki/features/recording/domain/recording_snapshot.dart';
import 'package:velorki/features/recording/application/recording_controller.dart';
import 'package:velorki/features/recording/presentation/live_figures_view.dart';
import 'package:velorki/features/recording/presentation/recording_screen.dart';
import 'package:velorki/features/search/presentation/search_field.dart';
import 'package:velorki/features/shared/presentation/adaptive_docking_sheet.dart';
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

/// The side panel's box as it shows, which folded away is its grip.
Rect _panel(WidgetTester tester) {
  final panel = find.byType(SidePanel);
  final decorated = find
      .descendant(of: panel, matching: find.byType(DecoratedBox))
      .first;
  return _rect(tester, decorated);
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
      testWidgets('Plan: the sheet is a panel beside the rail, the search '
          'and the profile menu over the map beside it', (tester) async {
        await _screen(tester, size);
        await pumpRecordingApp(
          tester,
          initialLocation: plannerRoute,
          surfaceSize: size,
          expectTextFits: false,
        );
        await tester.pumpAndSettle();

        expect(find.byType(DraggableScrollableSheet), findsNothing);
        expect(find.byType(SidePanel), findsOneWidget);
        expect(find.byType(ProfileChipRow), findsNothing);
        expect(find.byType(ProfileDropdown), findsOneWidget);

        final rail = _rect(tester, find.byType(FloatingNavigationBar));
        final panel = _panel(tester);
        final search = _rect(tester, find.byType(SearchField));
        final dropdown = _rect(tester, find.byType(ProfileDropdown));
        final controls = _rect(tester, find.byType(MapControls));
        // Rail, panel, then the map with its chrome, left to right or right
        // to left, none over another.
        for (final (a, b) in [
          (rail, panel),
          (panel, search),
          (panel, controls),
          (rail, controls),
          (search, dropdown),
        ]) {
          expect(a.overlaps(b), isFalse, reason: '$a over $b');
        }
        // Beside the open panel the map is too narrow for both in one row,
        // on every phone: the menu is under the search, at the end of its
        // row.
        expect(dropdown.top, greaterThan(search.bottom));
        expect(
          (dropdown.right - search.right).abs() <= 1 ||
              (dropdown.left - search.left).abs() <= 1,
          isTrue,
        );
        // The column stands right beside the panel.
        final gap = panel.center.dx < controls.center.dx
            ? controls.left - panel.right
            : panel.left - controls.right;
        expect(gap, lessThan(20));
        await unmountApp(tester);
      });

      testWidgets('Record and the Library have their panels too, and a ride '
          'puts its figures in the rail\'s place', (tester) async {
        await _screen(tester, size);
        final h = await pumpRecordingApp(tester, surfaceSize: size);
        await tester.pumpAndSettle();
        expect(find.byType(SidePanel), findsOneWidget);
        expect(find.byType(NavigationRail), findsOneWidget);

        await emitSnapshot(tester, h, _snapshot());
        await tester.pumpAndSettle();
        expect(find.byType(NavigationRail), findsNothing);
        final figures = tester.widget<FiguresBar>(find.byType(FiguresBar));
        expect(figures.railSide, isNotNull);
        expect(find.byType(FiguresBar), findsOneWidget);
        expect(
          _panel(tester).overlaps(_rect(tester, find.byType(FiguresBar))),
          isFalse,
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
        expect(find.byType(SidePanel), findsNothing);
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

  testWidgets('a drag towards the rail folds the panel down to its grip, the '
      'column follows, the other tabs agree, and a tap on the grip opens it', (
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
    final open = _panel(tester);
    final controlsOpen = _rect(tester, find.byType(MapControls));
    final rail = _rect(tester, find.byType(FloatingNavigationBar));
    final towardsRail = rail.center.dx < open.center.dx ? -1.0 : 1.0;

    await tester.dragFrom(open.center, Offset(towardsRail * 400, 0));
    await tester.pumpAndSettle();
    final folded = _panel(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SidePanel)),
    );
    expect(container.read(sidePanelOpenProvider), isFalse);
    // Only the grip shows beside the rail.
    final shown = towardsRail < 0
        ? folded.right - rail.right
        : rail.left - folded.left;
    expect(shown, lessThan(sidePanelGripWidth + 20));
    // Folded, the map beside it is wide enough for the search and the menu
    // in one row.
    expect(
      _rect(tester, find.byType(SearchField)).center.dy,
      closeTo(_rect(tester, find.byType(ProfileDropdown)).center.dy, 1),
    );
    final controlsFolded = _rect(tester, find.byType(MapControls));
    expect(
      (controlsFolded.center.dx - rail.center.dx).abs(),
      lessThan((controlsOpen.center.dx - rail.center.dx).abs()),
    );

    await _tapRail(tester, l10n.tabRecord);
    expect(container.read(sidePanelOpenProvider), isFalse);

    // The grip is what shows of the folded panel: its edge on the map side.
    final folds = _panel(tester);
    final grip = towardsRail < 0
        ? Offset(folds.right - sidePanelGripWidth / 2, folds.center.dy)
        : Offset(folds.left + sidePanelGripWidth / 2, folds.center.dy);
    await tester.tapAt(grip);
    await tester.pumpAndSettle();
    expect(container.read(sidePanelOpenProvider), isTrue);
    await unmountApp(tester);
  });

  testWidgets('turning the phone during a ride keeps the ride and the map', (
    tester,
  ) async {
    await _screen(tester, _upright);
    final h = await pumpRecordingApp(tester, surfaceSize: _upright);
    await tester.pump();
    await emitSnapshot(tester, h, _snapshot());
    await tester.pumpAndSettle();
    final map = tester.element(find.byType(SharedMapHost));
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);

    await _screen(tester, _sideways);
    expect(find.byType(SidePanel), findsOneWidget);
    expect(
      tester.widget<FiguresBar>(find.byType(FiguresBar)).railSide,
      isNotNull,
    );

    await _screen(tester, _upright);
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    expect(find.byType(SidePanel), findsNothing);
    expect(tester.element(find.byType(SharedMapHost)), same(map));
    final container = ProviderScope.containerOf(map);
    expect(container.read(recordingControllerProvider).isRecording, isTrue);
    await unmountApp(tester);
  });
}

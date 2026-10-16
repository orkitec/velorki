import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/app/shell_layout.dart';
import 'package:velorki/features/map/presentation/map_chrome.dart';
import 'package:velorki/features/map/presentation/map_controls.dart';
import 'package:velorki/features/map/presentation/shared_map_host.dart';
import 'package:velorki/features/map/presentation/visible_map_padding.dart';
import 'package:velorki/features/planner/presentation/profile_chip_row.dart';
import 'package:velorki/features/recording/domain/recording_snapshot.dart';
import 'package:velorki/features/recording/presentation/live_figures_view.dart';
import 'package:velorki/features/search/presentation/search_field.dart';
import 'package:velorki/features/settings/presentation/settings_screen.dart';
import 'package:velorki/features/shared/presentation/docking_sheet.dart';
import 'package:velorki/features/shared/presentation/floating_bar.dart';
import 'package:velorki/features/shared/presentation/wide_panel.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../features/recording/support/pump.dart';
import '../support/app.dart';

// The wide layout is a phone placed in a column over a full-window map:
// what is in the column runs the phone's own code, which the rest of the
// suite tests. This file tests the placing.

/// An iPad Air 11" upright and on its side, and an iPad Pro 13".
const Size _air = Size(820, 1180);
const Size _airSideways = Size(1180, 820);
const Size _pro = Size(1032, 1376);
const Size _proSideways = Size(1376, 1032);

/// A foldable's inner screen, upright and on its side.
const Size _fold = Size(626, 890);
const Size _foldSideways = Size(890, 626);

/// Puts the test view at [size] points, at two pixels a point, with the
/// status bar's and the home indicator's safe areas, and [left] and [right]
/// for a system bar standing on one side.
Future<void> _window(
  WidgetTester tester,
  Size size, {
  double left = 0,
  double right = 0,
}) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = size * 2;
  tester.view.viewPadding = FakeViewPadding(
    top: 24 * 2,
    bottom: 20 * 2,
    left: left * 2,
    right: right * 2,
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

/// The tab's sheet's box.
Rect _sheet(WidgetTester tester) =>
    _rect(tester, find.byType(DockingSheetShell));

/// A bar's glass: the clip inside it, not the slot it stands in.
Rect _glass(WidgetTester tester, Finder bar) => _rect(
  tester,
  find.descendant(of: bar, matching: find.byType(ClipRRect)).first,
);

Rect _bar(WidgetTester tester) =>
    _glass(tester, find.byType(FloatingNavigationBar));

/// Where the column of a window of [size] stands on [side], with system
/// bars [left] and [right].
Rect _column(
  Size size, {
  WideColumnSide side = WideColumnSide.left,
  double left = 0,
  double right = 0,
}) {
  final width = widePanelWidth(size.width);
  final x = switch (side) {
    WideColumnSide.left => left + widePanelMargin,
    WideColumnSide.right => size.width - right - widePanelMargin - width,
    WideColumnSide.centre => left + (size.width - left - right - width) / 2,
  };
  return Rect.fromLTWH(x, 0, width, size.height);
}

/// The phone in [column]: the tab's sheet as wide as the column, reaching
/// the window's bottom behind the bar, which stands at the column's bottom
/// with a phone's margins.
void _expectPhoneIn(WidgetTester tester, Rect column) {
  final sheet = _sheet(tester);
  final bar = _bar(tester);
  expect(sheet.left, closeTo(column.left, 1));
  expect(sheet.width, closeTo(column.width, 1));
  expect(sheet.bottom, closeTo(column.bottom, 1));
  expect(bar.left, closeTo(column.left + floatingBarSideMargin, 1));
  expect(bar.right, closeTo(column.right - floatingBarSideMargin, 1));
  expect(bar.bottom, lessThan(column.bottom));
}

/// The map's controls right beside [column] on the map's side, at the
/// top below the safe area, as a phone has them at its right edge.
void _expectControlsAtEdge(
  WidgetTester tester,
  Size size,
  WideColumnSide side, {
  double left = 0,
  double right = 0,
}) {
  final controls = _rect(tester, find.byType(MapControls));
  // At the window's edge on the column's side, 12 from its safe area.
  if (side == WideColumnSide.right) {
    expect(controls.right, closeTo(size.width - right - 12, 1));
  } else {
    expect(controls.left, closeTo(left + 12, 1));
  }
  // Under the chips, down towards the sheet, as on a phone: a sheet pulled
  // up lies over them there too.
  expect(
    controls.top,
    greaterThan(_rect(tester, find.byType(ProfileChipRow)).bottom),
  );
  expect(controls.top, lessThan(_sheet(tester).top));
}

Future<void> _pumpPlan(WidgetTester tester, Size size) =>
    pumpRecordingApp(tester, initialLocation: plannerRoute, surfaceSize: size);

void main() {
  setUp(() => debugShellLayoutOverride = null);
  tearDown(() {
    testWideColumnSide = WideColumnSide.left;
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view
      ..resetPhysicalSize()
      ..resetDevicePixelRatio()
      ..resetViewPadding()
      ..resetPadding();
  });

  for (final side in [WideColumnSide.left, WideColumnSide.right]) {
    for (final size in [
      _air,
      _airSideways,
      _pro,
      _proSideways,
      _fold,
      _foldSideways,
    ]) {
      testWidgets('a wide window of $size, the column on the ${side.name}: '
          'the phone in it, the map full-window, the controls at its edge '
          'between the chips and the sheet', (tester) async {
        testWideColumnSide = side;
        await _window(tester, size);
        await _pumpPlan(tester, size);
        await tester.pumpAndSettle();
        final column = _column(size, side: side);
        expect(find.byType(NavigationRail), findsNothing);
        _expectPhoneIn(tester, column);
        for (final chrome in [
          _rect(tester, find.byType(SearchField)),
          _rect(tester, find.byType(ProfileChipRow)),
        ]) {
          expect(chrome.left, greaterThanOrEqualTo(column.left));
          expect(chrome.right, lessThanOrEqualTo(column.right + 1));
        }
        expect(_rect(tester, find.byType(SharedMapHost)), Offset.zero & size);
        _expectControlsAtEdge(tester, size, side);
        // The camera keeps a target in the map beside the column.
        final padding = visibleMapPadding(
          tester.element(find.byType(SearchField)),
          chromeTop: defaultMapControlsTop,
        );
        // Only the column and the controls beside it on its side, the safe
        // areas elsewhere, and a margin: the sheet, the search and the
        // chips, all in the column, add nothing.
        final besideColumn = column.width + widePanelMargin + 24;
        expect(
          padding,
          side == WideColumnSide.left
              ? EdgeInsets.fromLTRB(besideColumn, 24 + 24, 24, 20 + 24)
              : EdgeInsets.fromLTRB(24, 24 + 24, besideColumn, 20 + 24),
        );
        // Whatever the sheet's extent or the chrome's height.
        expect(
          visibleMapPadding(
            tester.element(find.byType(SearchField)),
            chromeTop: 300,
            sheetExtent: 0.9,
          ),
          padding,
        );
        await unmountApp(tester);
      });
    }
  }

  testWidgets('the column in the middle, should it be wanted', (tester) async {
    testWideColumnSide = WideColumnSide.centre;
    await _window(tester, _proSideways);
    await _pumpPlan(tester, _proSideways);
    await tester.pumpAndSettle();
    final column = _column(_proSideways, side: WideColumnSide.centre);
    expect(column.center.dx, closeTo(_proSideways.width / 2, 1));
    _expectPhoneIn(tester, column);
    await unmountApp(tester);
  });

  for (final side in [WideColumnSide.left, WideColumnSide.right]) {
    testWidgets('a modal sheet and a dialog open in the column on the '
        '${side.name}, as on a phone', (tester) async {
      testWideColumnSide = side;
      await _window(tester, _air);
      await _pumpPlan(tester, _air);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(l10n.mapLayers));
      await tester.pumpAndSettle();
      final column = _column(_air, side: side);
      final sheet = _rect(
        tester,
        find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(sheet.left, closeTo(column.left, 1));
      expect(sheet.width, closeTo(column.width, 1));
      // Up from the window's bottom, over the bar, as on a phone.
      expect(sheet.bottom, closeTo(_air.height, 1));
      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await tester.pumpAndSettle();

      unawaited(
        showDialog<void>(
          context: tester.element(find.byType(SearchField)),
          useRootNavigator: true,
          builder: (_) => const AlertDialog(content: Text('dialog')),
        ),
      );
      await tester.pumpAndSettle();
      final dialog = _rect(tester, find.byType(AlertDialog));
      expect(dialog.center.dx, closeTo(column.center.dx, 1));
      expect(dialog.width, lessThanOrEqualTo(column.width + 0.5));
      await unmountApp(tester);
    });
  }

  for (final (name, size, wide) in const [
    ('in a wide window, in the column, the map beside it', _airSideways, true),
    ('on a phone, as wide as the screen', Size(402, 874), false),
  ]) {
    testWidgets('a page pushed over the shell, $name', (tester) async {
      await _window(tester, size);
      await pumpRecordingApp(
        tester,
        initialLocation: settingsRoute,
        surfaceSize: size,
        // The test font's labels do not fit a phone's accent tiles; the
        // app's own do.
        expectTextFits: false,
      );
      await tester.pumpAndSettle();
      const page = Key('pushed page');
      unawaited(
        Navigator.of(
          tester.element(find.byType(SettingsScreen)),
          rootNavigator: true,
        ).push(
          ColumnPageRoute<void>(builder: (_) => const Scaffold(key: page)),
        ),
      );
      await tester.pumpAndSettle();
      final rect = _rect(tester, find.byKey(page));
      final column = wide ? _column(size) : Offset.zero & size;
      expect(rect.left, closeTo(column.left, 1));
      expect(rect.width, closeTo(column.width, 1));
      expect(rect.height, closeTo(size.height, 1));
      // In a wide window the map is still painted beside the page, where
      // it was: not slid aside by the page's transition, Apple's parallax
      // (iOS, and a browser on a Mac) included.
      final route = ModalRoute.of(tester.element(find.byKey(page)))!;
      expect(route.opaque, !wide);
      if (wide) {
        expect(_rect(tester, find.byType(SharedMapHost)), Offset.zero & size);
      }
      await unmountApp(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  }

  group('a full page in the column', () {
    /// Pushes a page on [navigator] and checks it mid-way in: in a wide
    /// window it fades, standing still in the column; on a phone it slides
    /// in from the side as the platform has it.
    Future<void> walk(
      WidgetTester tester,
      Future<void> Function() push,
      Finder page, {
      required Rect column,
      required bool wide,
    }) async {
      unawaited(push());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final rect = tester.getRect(page);
      final fades = find.ancestor(
        of: page,
        matching: find.byType(FadeTransition),
      );
      if (wide) {
        expect(rect.left, closeTo(column.left, 1));
        expect(
          tester
              .widgetList<FadeTransition>(fades)
              .any((f) => f.opacity.value > 0 && f.opacity.value < 1),
          isTrue,
        );
      } else {
        // Apple's page slides in from the right.
        expect(rect.left, greaterThan(column.left + 10));
      }
      await tester.pumpAndSettle();
      expect(tester.getRect(page).left, closeTo(column.left, 1));
      Navigator.of(tester.element(page)).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      if (wide) expect(tester.getRect(page).left, closeTo(column.left, 1));
      await tester.pumpAndSettle();
      expect(page, findsNothing);
    }

    for (final (size, wide) in const [(_air, true), (Size(402, 874), false)]) {
      testWidgets(
        wide
            ? 'in a wide window fades in and out, as a tab does'
            : 'on a phone slides as the platform has it',
        (tester) async {
          debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          await _window(tester, size);
          await _pumpPlan(tester, size);
          await tester.pumpAndSettle();
          final column = wide ? _column(size) : Offset.zero & size;
          const page = Key('pushed page');
          // On a tab's navigator, as the offline data from the planner.
          await walk(
            tester,
            () => Navigator.of(tester.element(find.byType(SearchField))).push(
              ColumnPageRoute<void>(builder: (_) => const Scaffold(key: page)),
            ),
            find.byKey(page),
            column: column,
            wide: wide,
          );
          // On the app's own, as a page over a sheet.
          await walk(
            tester,
            () =>
                Navigator.of(
                  tester.element(find.byType(SearchField)),
                  rootNavigator: true,
                ).push(
                  ColumnPageRoute<void>(
                    builder: (_) => const Scaffold(key: page),
                  ),
                ),
            find.byKey(page),
            column: column,
            wide: wide,
          );
          await unmountApp(tester);
          debugDefaultTargetPlatformOverride = null;
        },
      );
    }
  });

  testWidgets('a page a tab pushes is over the map beside the column: the '
      'map takes no touch until it goes', (tester) async {
    await _window(tester, _air);
    await _pumpPlan(tester, _air);
    await tester.pumpAndSettle();
    bool mapIgnored() => tester
        .widget<IgnorePointer>(
          find
              .ancestor(
                of: find.byType(SharedMapHost),
                matching: find.byType(IgnorePointer),
              )
              .first,
        )
        .ignoring;
    expect(mapIgnored(), isFalse);
    const page = Key('pushed page');
    unawaited(
      Navigator.of(
        tester.element(find.byType(SearchField)),
      ).push(ColumnPageRoute<void>(builder: (_) => const Scaffold(key: page))),
    );
    await tester.pumpAndSettle();
    final rect = _rect(tester, find.byKey(page));
    expect(rect.left, closeTo(_column(_air).left, 1));
    expect(rect.width, closeTo(_column(_air).width, 1));
    expect(mapIgnored(), isTrue);
    Navigator.of(tester.element(find.byKey(page))).pop();
    await tester.pumpAndSettle();
    expect(mapIgnored(), isFalse);
    await unmountApp(tester);
  });

  for (final (size, wide) in const [(_air, true), (Size(402, 874), false)]) {
    testWidgets(
      'Settings ${wide ? 'in the column, offering' : 'on a phone, '
                'without'} the column\'s side',
      (tester) async {
        await _window(tester, size);
        await pumpRecordingApp(
          tester,
          initialLocation: settingsRoute,
          surfaceSize: size,
          expectTextFits: false,
        );
        await tester.pumpAndSettle();
        final page = _rect(tester, find.byType(SettingsScreen));
        final column = wide ? _column(size) : Offset.zero & size;
        expect(page.left, closeTo(column.left, 1));
        expect(page.width, closeTo(column.width, 1));
        await tester.scrollUntilVisible(
          find.text(l10n.appearanceRadarStyle),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          find.text(l10n.appearanceColumnSide),
          wide ? findsOneWidget : findsNothing,
        );
        await unmountApp(tester);
      },
    );
  }

  testWidgets('the sheet docks into the column\'s bar, and a ride folds it '
      'into the figures bar at the column\'s bottom, as on a phone', (
    tester,
  ) async {
    await _window(tester, _air);
    final h = await pumpRecordingApp(tester, surfaceSize: _air);
    await tester.pumpAndSettle();
    final column = _column(_air);
    _expectPhoneIn(tester, column);
    await tester.dragFrom(
      tester.getCenter(find.byType(SheetHandle)),
      const Offset(0, 1000),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FloatingNavigationBar>(find.byType(FloatingNavigationBar))
          .docked,
      isTrue,
    );

    await emitSnapshot(tester, h, _snapshot());
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);
    await tester.dragFrom(
      tester.getCenter(find.byType(SheetHandle)),
      const Offset(0, 1000),
    );
    await tester.pumpAndSettle();
    final figures = _glass(tester, find.byType(FiguresBar));
    expect(figures.left, closeTo(column.left + floatingBarSideMargin, 1));
    expect(figures.right, closeTo(column.right - floatingBarSideMargin, 1));
    expect(figures.bottom, greaterThan(_air.height - 60));
    await unmountApp(tester);
  });

  for (final (name, size) in const [
    ('a third of Split View', Size(507, 1180)),
    ('Slide Over', Size(320, 1100)),
    ('a foldable\'s outer screen', Size(466, 678)),
  ]) {
    testWidgets('$name: the upright phone layout, the bar at the '
        'bottom and the sheet across the window', (tester) async {
      await _window(tester, size);
      await pumpRecordingApp(
        tester,
        initialLocation: plannerRoute,
        surfaceSize: size,
        // The test font is wider than the app's: at a phone's width the
        // hint counts as cut off; checked on the simulator.
        expectTextFits: size.width > 500,
      );
      await tester.pumpAndSettle();
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);
      _expectPhoneIn(tester, Offset.zero & size);
      await unmountApp(tester);
    });
  }

  testWidgets('a window resized across the line changes layout and back, the '
      'plan and its sheet kept', (tester) async {
    await _window(tester, _airSideways);
    await _pumpPlan(tester, _airSideways);
    await tester.pumpAndSettle();
    _expectPhoneIn(tester, _column(_airSideways));
    final sheetState = tester.state(find.byType(DraggableScrollableSheet));

    await _window(tester, const Size(507, 820));
    _expectPhoneIn(tester, Offset.zero & const Size(507, 820));
    expect(find.byType(NavigationRail), findsNothing);

    await _window(tester, _airSideways);
    _expectPhoneIn(tester, _column(_airSideways));
    expect(tester.state(find.byType(DraggableScrollableSheet)), sheetState);
    await unmountApp(tester);
  });

  testWidgets('a foldable\'s outer screen on its side is a phone on its '
      'side: the rail, and the sheet turned with it', (tester) async {
    const size = Size(678, 466);
    await _window(tester, size);
    await pumpRecordingApp(
      tester,
      initialLocation: plannerRoute,
      surfaceSize: size,
      expectTextFits: false,
    );
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(
      find.ancestor(
        of: find.byType(DraggableScrollableSheet),
        matching: find.byWidgetPredicate(
          (w) => w is RotatedBox && w.quarterTurns.isOdd,
        ),
      ),
      findsWidgets,
    );
    await unmountApp(tester);
  });

  for (final side in [WideColumnSide.left, WideColumnSide.right]) {
    for (final (left, right) in const [(0.0, 44.0), (44.0, 0.0)]) {
      testWidgets('a system bar on one side, $left left and $right right, '
          'the column on the ${side.name}: each side keeps its own inset', (
        tester,
      ) async {
        testWideColumnSide = side;
        await _window(tester, _foldSideways, left: left, right: right);
        await _pumpPlan(tester, _foldSideways);
        await tester.pumpAndSettle();
        _expectPhoneIn(
          tester,
          _column(_foldSideways, side: side, left: left, right: right),
        );
        _expectControlsAtEdge(
          tester,
          _foldSideways,
          side,
          left: left,
          right: right,
        );
        await unmountApp(tester);
      });
    }
  }

  testWidgets('a window resized during a ride, unfolded, folded and turned: '
      'the layout follows live, the ride and its sheet carry over', (
    tester,
  ) async {
    await _window(tester, _foldSideways);
    final h = await pumpRecordingApp(
      tester,
      surfaceSize: _foldSideways,
      expectTextFits: false,
    );
    await tester.pumpAndSettle();
    await emitSnapshot(tester, h, _snapshot());
    await tester.pumpAndSettle();
    final sheetState = tester.state(find.byType(DraggableScrollableSheet));
    expect(_sheet(tester).width, closeTo(widePanelWidth(890), 1));

    for (final (size, wide) in const [
      (Size(466, 678), false),
      (Size(678, 466), false),
      (_fold, true),
      (_proSideways, true),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await _window(tester, size);
      expect(find.byType(NavigationBar), findsNothing, reason: '$size');
      expect(find.byType(NavigationRail), findsNothing, reason: '$size');
      expect(find.byType(DraggableScrollableSheet), findsOneWidget);
      expect(
        tester.state(find.byType(DraggableScrollableSheet)),
        sheetState,
        reason: '$size',
      );
      if (wide) {
        expect(_sheet(tester).width, closeTo(widePanelWidth(size.width), 1));
      }
    }
    await unmountApp(tester);
  });
}

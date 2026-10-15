import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/app/shell_layout.dart';
import 'package:velorki/features/assistant/presentation/assistant_sheet.dart';
import 'package:velorki/features/integrations/common/data/relay_client_provider.dart';
import 'package:velorki/features/map/presentation/map_controls.dart';
import 'package:velorki/features/planner/presentation/profile_chip_row.dart';
import 'package:velorki/features/recording/domain/recording_snapshot.dart';
import 'package:velorki/features/recording/presentation/live_figures_view.dart';
import 'package:velorki/features/search/presentation/search_field.dart';
import 'package:velorki/features/settings/presentation/settings_screen.dart';
import 'package:velorki/features/shared/presentation/ai_mark.dart';
import 'package:velorki/features/shared/presentation/docking_sheet.dart';
import 'package:velorki/features/shared/presentation/stat_tile.dart';
import 'package:velorki/features/shared/presentation/wide_panel.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../features/integrations/support/fakes.dart';
import '../features/recording/support/pump.dart';
import '../support/app.dart';

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

/// The sheet's box as it shows: a wide window's panel, or a phone's sheet.
Rect _sheet(WidgetTester tester) {
  final panel = find.descendant(
    of: find.byType(PanelSheet),
    matching: find.byType(HeightReporter),
  );
  return _rect(
    tester,
    panel.evaluate().isNotEmpty ? panel : find.byType(DockingSheetShell),
  );
}

/// A bar's glass: the clip inside it, not the slot it stands in.
Rect _glass(WidgetTester tester, Finder bar) => _rect(
  tester,
  find.descendant(of: bar, matching: find.byType(ClipRRect)).first,
);

Rect _bar(WidgetTester tester) =>
    _glass(tester, find.byType(FloatingNavigationBar));

/// No sheet anywhere is turned.
void _expectUpright(WidgetTester tester) {
  for (final box in tester.widgetList<RotatedBox>(
    find.ancestor(
      of: find.byType(DraggableScrollableSheet),
      matching: find.byType(RotatedBox),
    ),
  )) {
    expect(box.quarterTurns % 4, 0);
  }
}

/// The panel's place in a window of [size]: [widePanelMargin] from the left
/// edge's safe area [left], [widePanelWidth] wide, above the bar with the
/// margin between, and clear of the window's middle. It stands still: no
/// handle, no sheet's chrome.
void _expectPanel(WidgetTester tester, Size size, {double left = 0}) {
  final sheet = _sheet(tester);
  final bar = _bar(tester);
  expect(find.byType(PanelSheet), findsOneWidget);
  expect(find.byType(SheetHandle), findsNothing);
  expect(find.byType(DockingSheetShell), findsNothing);
  expect(sheet.left, closeTo(left + widePanelMargin, 1));
  expect(sheet.right, lessThan(size.width / 2 + 100));
  expect(sheet.width, closeTo(widePanelWidth(size.width), 1));
  expect(sheet.bottom, closeTo(bar.top - widePanelMargin, 1));
}

void main() {
  setUp(() => debugShellLayoutOverride = null);
  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view
      ..resetPhysicalSize()
      ..resetDevicePixelRatio()
      ..resetViewPadding()
      ..resetPadding();
  });

  for (final size in [
    _air,
    _airSideways,
    _pro,
    _proSideways,
    _fold,
    _foldSideways,
  ]) {
    group('a wide window of $size', () {
      testWidgets('Plan: the bar centred at the bottom, the sheet an upright '
          'panel on the left under the search and the chips, the controls '
          'at the right over the map', (tester) async {
        await _window(tester, size);
        await pumpRecordingApp(
          tester,
          initialLocation: plannerRoute,
          surfaceSize: size,
        );
        await tester.pumpAndSettle();

        expect(find.byType(NavigationRail), findsNothing);
        expect(find.byType(NavigationBar), findsOneWidget);
        _expectUpright(tester);
        final bar = _bar(tester);
        expect(bar.center.dx, closeTo(size.width / 2, 1));
        expect(bar.width, closeTo(wideBarWidth, 1));
        expect(bar.bottom, lessThan(size.height));
        _expectPanel(tester, size);

        // The search and the chips at the panel's top, above the sheet.
        final sheet = _sheet(tester);
        final search = _rect(tester, find.byType(SearchField));
        final chips = _rect(tester, find.byType(ProfileChipRow));
        for (final chrome in [search, chips]) {
          expect(chrome.left, greaterThanOrEqualTo(sheet.left));
          expect(chrome.right, lessThanOrEqualTo(sheet.right + 1));
          expect(chrome.bottom, lessThanOrEqualTo(sheet.top));
        }
        // As tall as the hint and the buttons of an empty plan, with map
        // between the chips and the panel where the window is tall enough.
        expect(sheet.height, lessThan(420));
        if (size.height > 800) {
          expect(sheet.top, greaterThan(chips.bottom + 100));
        }
        // A drag on it moves nothing.
        await tester.drag(find.byType(PanelSheet), const Offset(0, 300));
        await tester.pumpAndSettle();
        expect(_sheet(tester), sheet);

        // The controls at the window's right edge, clear of the panel.
        final controls = _rect(tester, find.byType(MapControls));
        expect(controls.height, greaterThan(controls.width));
        expect(controls.left, greaterThan(sheet.right));
        expect(controls.right, closeTo(size.width - 12, 1));
        await unmountApp(tester);
      });

      testWidgets('Library: the card is the panel', (tester) async {
        await _window(tester, size);
        await pumpRecordingApp(
          tester,
          initialLocation: libraryRoute,
          surfaceSize: size,
        );
        await tester.pumpAndSettle();
        _expectUpright(tester);
        _expectPanel(tester, size);
        await unmountApp(tester);
      });

      testWidgets('Record: the sheet is the panel; a ride hides the bar, and '
          'the panel stays, as tall as the figures, a margin above the '
          'window\'s bottom', (tester) async {
        await _window(tester, size);
        final h = await pumpRecordingApp(tester, surfaceSize: size);
        await tester.pumpAndSettle();
        _expectUpright(tester);
        _expectPanel(tester, size);

        await emitSnapshot(tester, h, _snapshot());
        await tester.pumpAndSettle();
        expect(find.byType(NavigationBar), findsNothing);
        expect(find.byType(FiguresBar), findsNothing);
        // In the panel's column, its corners clear of the window's: the
        // margin above the home indicator's safe area.
        final open = _sheet(tester);
        expect(find.byType(SheetHandle), findsNothing);
        expect(open.left, closeTo(widePanelMargin, 1));
        expect(open.width, closeTo(widePanelWidth(size.width), 1));
        expect(open.bottom, closeTo(size.height - 20 - widePanelMargin, 1));
        expect(open.top, greaterThanOrEqualTo(24 + widePanelMargin - 1));
        expect(
          find.text(l10n.recordingStatusRecording.toUpperCase()),
          findsOneWidget,
        );
        // A drag on it folds nothing away.
        await tester.drag(find.byType(PanelSheet), Offset(0, size.height));
        await tester.pumpAndSettle();
        expect(_sheet(tester), open);
        expect(find.byType(FiguresBar), findsNothing);
        // The map's controls stay where they were, clear of it all.
        final controls = _rect(tester, find.byType(MapControls));
        expect(controls.overlaps(open), isFalse);
        await unmountApp(tester);
      });

      testWidgets('Plan: the AI\'s card is a panel too, closed by its '
          'button', (tester) async {
        await _window(tester, size);
        await pumpRecordingApp(
          tester,
          initialLocation: plannerRoute,
          surfaceSize: size,
          extraOverrides: [
            relayClientProvider.overrideWithValue(FakeRelayClient()),
          ],
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithIcon(LabeledIconButton, Icons.auto_awesome_rounded),
        );
        await tester.pumpAndSettle();
        final card = _rect(tester, find.byKey(assistantSheetSurfaceKey));
        expect(find.byType(SheetHandle), findsNothing);
        expect(card.left, closeTo(widePanelMargin, 1));
        expect(card.width, closeTo(widePanelWidth(size.width), 1));
        expect(card.bottom, closeTo(_bar(tester).top - widePanelMargin, 1));
        // Its AI edge goes all the way round: its lower edge is in view.
        final edge = tester.widget<CustomPaint>(
          find.byKey(assistantSheetEdgeKey),
        );
        expect((edge.foregroundPainter! as AiEdgePainter).closed, isTrue);
        // Below the search and the chips, as the planner's panel.
        expect(
          card.top,
          greaterThan(_rect(tester, find.byType(ProfileChipRow)).bottom),
        );
        final close = find.byTooltip(
          MaterialLocalizations.of(
            tester.element(find.byKey(assistantSheetSurfaceKey)),
          ).closeButtonTooltip,
        );
        await tester.tap(close);
        await tester.pumpAndSettle();
        expect(find.byKey(assistantSheetSurfaceKey), findsNothing);
        _expectPanel(tester, size);
        await unmountApp(tester);
      });

      testWidgets('Settings: a column of readable width in the middle', (
        tester,
      ) async {
        await _window(tester, size);
        await pumpRecordingApp(
          tester,
          initialLocation: settingsRoute,
          surfaceSize: size,
        );
        await tester.pumpAndSettle();
        final page = _rect(tester, find.byType(SettingsScreen));
        expect(
          page.width,
          closeTo(math.min(WideReadingColumn.maxWidth, size.width), 1),
        );
        expect(page.center.dx, closeTo(size.width / 2, 1));
        await unmountApp(tester);
      });

      testWidgets('the layers sheet is no wider than a sheet should be', (
        tester,
      ) async {
        await _window(tester, size);
        await pumpRecordingApp(
          tester,
          initialLocation: plannerRoute,
          surfaceSize: size,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip(l10n.mapLayers));
        await tester.pumpAndSettle();
        final sheet = _rect(
          tester,
          find
              .descendant(
                of: find.byType(BottomSheet),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(sheet.width, lessThanOrEqualTo(640));
        expect(sheet.center.dx, closeTo(size.width / 2, 1));
        // The tab's panel stays where it was beside it.
        _expectPanel(tester, size);
        await unmountApp(tester);
      });
    });
  }

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
      _expectUpright(tester);
      final sheet = _sheet(tester);
      expect(sheet.left, closeTo(0, 1));
      expect(sheet.width, closeTo(size.width, 1));
      expect(find.byType(ProfileChipRow), findsOneWidget);
      await unmountApp(tester);
    });
  }

  for (final (name, size, width) in const [
    ('in a wide window, at a readable width', _airSideways, 720.0),
    ('on a phone, as wide as the screen', Size(402, 874), 402.0),
  ]) {
    testWidgets('a page pushed over the shell, $name', (tester) async {
      await _window(tester, size);
      await pumpRecordingApp(
        tester,
        initialLocation: settingsRoute,
        surfaceSize: size,
        // The test font's labels do not fit a phone's accent tiles; the
        // app's own do.
        expectTextFits: size.width > 500,
      );
      await tester.pumpAndSettle();
      const page = Key('pushed page');
      unawaited(
        Navigator.of(
          tester.element(find.byType(SettingsScreen)),
          rootNavigator: true,
        ).push(
          MaterialPageRoute<void>(builder: (_) => const Scaffold(key: page)),
        ),
      );
      await tester.pumpAndSettle();
      final rect = _rect(tester, find.byKey(page));
      expect(rect.width, closeTo(width, 1));
      expect(rect.height, closeTo(size.height, 1));
      expect(rect.center.dx, closeTo(size.width / 2, 1));
      await unmountApp(tester);
    });
  }

  group('a panel sheet', () {
    Future<void> pumpPanel(
      WidgetTester tester, {
      required int rows,
      double height = 600,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: height,
            child: PanelSheet(
              child: Builder(
                builder: (context) => ListView(
                  controller: SheetContentScroll.maybeOf(context),
                  shrinkWrap: SheetContentScroll.shrinkWrapOf(context),
                  padding: EdgeInsets.zero,
                  children: [
                    for (var i = 0; i < rows; i++)
                      SizedBox(height: 50, child: Text('row $i')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    Rect panel(WidgetTester tester) => _rect(
      tester,
      find.descendant(
        of: find.byType(PanelSheet),
        matching: find.byType(HeightReporter),
      ),
    );

    testWidgets('is as tall as its content, at the bottom of its room', (
      tester,
    ) async {
      await pumpPanel(tester, rows: 3);
      final rect = panel(tester);
      expect(rect.height, closeTo(3 * 50 + panelSheetTopDp, 0.5));
      final room = tester.getRect(find.byType(SizedBox).first);
      expect(rect.bottom, closeTo(room.bottom, 0.5));

      // Grows with it.
      await pumpPanel(tester, rows: 6);
      expect(panel(tester).height, closeTo(6 * 50 + panelSheetTopDp, 0.5));
    });

    testWidgets('beyond its room, as tall as the room, the content '
        'scrolling inside', (tester) async {
      await pumpPanel(tester, rows: 40, height: 500);
      expect(panel(tester).height, closeTo(500, 0.5));
      expect(find.text('row 39'), findsNothing);
      await tester.drag(find.text('row 2'), const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(find.text('row 39'), findsOneWidget);
      expect(panel(tester).height, closeTo(500, 0.5));
    });

    testWidgets('reports its height', (tester) async {
      final heights = <double>[];
      await tester.pumpWidget(
        MaterialApp(
          home: PanelSheet(
            onHeight: heights.add,
            child: const SizedBox(height: 120),
          ),
        ),
      );
      await tester.pump();
      expect(heights, [120 + panelSheetTopDp]);
    });
  });

  testWidgets('a window resized across the line changes layout and back, the '
      'plan and its sheet kept', (tester) async {
    await _window(tester, _airSideways);
    await pumpRecordingApp(
      tester,
      initialLocation: plannerRoute,
      surfaceSize: _airSideways,
    );
    await tester.pumpAndSettle();
    _expectPanel(tester, _airSideways);
    final sheetState = tester.state(find.byType(DraggableScrollableSheet));

    await _window(tester, const Size(507, 820));
    expect(_sheet(tester).width, closeTo(507, 1));
    // At rest, where a sheet starts, not all the way open as the panel's
    // column was.
    expect(find.byType(SheetHandle), findsOneWidget);
    expect(_sheet(tester).height, lessThan(820 * 0.7));
    expect(find.byType(NavigationRail), findsNothing);

    await _window(tester, _airSideways);
    _expectPanel(tester, _airSideways);
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

  for (final (left, right) in const [(0.0, 44.0), (44.0, 0.0)]) {
    testWidgets('a system bar on one side, $left left and $right right: each '
        'side keeps its own inset', (tester) async {
      await _window(tester, _foldSideways, left: left, right: right);
      await pumpRecordingApp(
        tester,
        initialLocation: plannerRoute,
        surfaceSize: _foldSideways,
      );
      await tester.pumpAndSettle();
      _expectPanel(tester, _foldSideways, left: left);
      // The bar centred between the two insets, the controls clear of the
      // right one.
      final bar = _bar(tester);
      expect(
        bar.center.dx,
        closeTo(left + (_foldSideways.width - left - right) / 2, 1),
      );
      final controls = _rect(tester, find.byType(MapControls));
      expect(controls.right, closeTo(_foldSideways.width - right - 12, 1));
      await unmountApp(tester);
    });
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

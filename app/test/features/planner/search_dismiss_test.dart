import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show HitTestResult;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/app/shell_layout.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/presentation/planner_screen.dart';
import 'package:velorki/features/planner/presentation/waypoint_edit_sheet.dart';
import 'package:velorki/features/search/presentation/search_field.dart';
import 'package:velorki/features/shared/presentation/adaptive_docking_sheet.dart';

import '../../support/app.dart';
import '../recording/support/pump.dart';
import 'support/pump.dart';

/// A phone and a tablet the way the search is used on them: upright, on
/// its side with the rail, and an iPad's wide window with the column.
enum _Layout {
  upright(Size(402, 874), 3, FakeViewPadding(top: 62 * 3, bottom: 34 * 3)),
  sideways(
    Size(874, 402),
    3,
    FakeViewPadding(left: 62 * 3, right: 62 * 3, bottom: 21 * 3),
  ),
  wide(Size(820, 1180), 2, FakeViewPadding(top: 24 * 2, bottom: 20 * 2));

  const _Layout(this.size, this.ratio, this.safe);

  final Size size;
  final double ratio;
  final FakeViewPadding safe;
}

/// How tall the keyboard is, in points.
const double _keyboard = 300;

Future<RecordingHarness> _pumpPlan(WidgetTester tester, _Layout layout) async {
  if (layout == _Layout.sideways) {
    const channel = MethodChannel(ScreenSideChannel.channelName);
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'side' ? RailSide.left.name : null,
    );
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  }
  await tester.binding.setSurfaceSize(layout.size);
  tester.view
    ..devicePixelRatio = layout.ratio
    ..physicalSize = layout.size * layout.ratio
    ..viewPadding = layout.safe
    ..padding = layout.safe;
  addTearDown(tester.view.reset);
  final h = await pumpRecordingApp(
    tester,
    initialLocation: plannerRoute,
    surfaceSize: layout.size,
    // The test font draws every glyph a full em wide: the search's hint
    // counts as cut off at a phone's width sideways and in a compact
    // column, where the app's own font fits.
    expectTextFits: false,
  );
  h.planner.map.tapsAreTaps = true;
  await tester.pumpAndSettle();
  return h;
}

/// The keyboard comes up over [layout]'s window, or goes ([up] false), the
/// way the phone reports it: the inset grows over a few frames, and the
/// safe area under it is spent.
Future<void> _keyboardTo(
  WidgetTester tester,
  _Layout layout, {
  required bool up,
}) async {
  const steps = 8;
  for (var i = 1; i <= steps; i++) {
    final inset = (up ? i : steps - i) / steps * _keyboard * layout.ratio;
    tester.view
      ..viewInsets = FakeViewPadding(bottom: inset)
      ..padding = FakeViewPadding(
        left: layout.safe.left,
        top: layout.safe.top,
        right: layout.safe.right,
        bottom: (layout.safe.bottom - inset).clamp(0, double.infinity),
      );
    await tester.pump(const Duration(milliseconds: 16));
  }
}

DraggableScrollableController _sheet(WidgetTester tester) => tester
    .widget<AdaptiveDockingSheet>(find.byType(AdaptiveDockingSheet).first)
    .controller;

SearchFieldState _search(WidgetTester tester) =>
    tester.state<SearchFieldState>(find.byType(SearchField));

int _points(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(PlannerScreen)))
        .read(plannerControllerProvider)
        .waypoints
        .length;

/// A point on the map that nothing over it takes: no sheet, no chrome, no
/// result list, and above where the keyboard would be.
Offset _onTheMap(WidgetTester tester, _Layout layout) {
  final map = tester.renderObject(
    find
        .descendant(
          of: find.byType(TestMapView),
          matching: find.byType(ColoredBox),
        )
        .first,
  );
  final size = layout.size;
  for (var y = 0.2; y <= 0.6; y += 0.05) {
    for (var x = 0.15; x <= 0.85; x += 0.05) {
      final point = Offset(size.width * x, size.height * y);
      if (point.dy > size.height - _keyboard) continue;
      final result = HitTestResult();
      tester.binding.hitTestInView(result, point, tester.view.viewId);
      if (result.path.first.target == map) return point;
    }
  }
  throw StateError('no free point on the map');
}

void main() {
  setUp(() => debugShellLayoutOverride = null);

  for (final layout in _Layout.values) {
    group('${layout.name}:', () {
      testWidgets('the sheet stays under the keyboard, however the keyboard '
          'comes', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        // The keyboard starts to come at every point of the sheet's way
        // down, and before and after it.
        for (final atMs in const [0, 48, 96, 144, 192, 320]) {
          await _pumpPlan(tester, layout);
          final sheet = _sheet(tester);
          final resting = sheet.size;
          await tester.tap(find.byType(TextField).first);
          await tester.pump();
          for (var t = 0; t < atMs; t += 16) {
            await tester.pump(const Duration(milliseconds: 16));
          }
          await _keyboardTo(tester, layout, up: true);
          await tester.pump(const Duration(milliseconds: 300));
          final parked = sheet.size;
          expect(parked, lessThan(resting - 0.1), reason: 'at $atMs ms');
          // A while with the keyboard up: nothing raises the sheet.
          for (var i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 100));
            expect(
              sheet.size,
              lessThanOrEqualTo(parked + 0.001),
              reason: 'keyboard at $atMs ms, ${i * 100 + 100} ms after',
            );
          }
          await tester.pumpAndSettle();
          expect(sheet.size, lessThanOrEqualTo(parked + 0.001));

          // The field lets go and the keyboard goes: the sheet comes back.
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pump();
          await _keyboardTo(tester, layout, up: false);
          await tester.pumpAndSettle();
          expect(sheet.size, closeTo(resting, 0.005), reason: 'at $atMs ms');
          await unmountApp(tester);
        }
        debugDefaultTargetPlatformOverride = null;
      });

      testWidgets('a tap on the map while searching only ends the search; '
          'the next one sets a point', (tester) async {
        await _pumpPlan(tester, layout);
        final sheet = _sheet(tester);
        final resting = sheet.size;

        await tester.tap(find.byType(TextField).first);
        await tester.pump();
        await _keyboardTo(tester, layout, up: true);
        await tester.enterText(find.byType(TextField).first, 'munich');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        // The results are open.
        expect(find.text(l10n.searchOnlineFor('munich')), findsOneWidget);
        expect(_search(tester).active, isTrue);

        final point = _onTheMap(tester, layout);
        await tester.tapAt(point);
        await tester.pump();
        expect(_points(tester), 0);
        expect(_search(tester).active, isFalse);
        expect(tester.testTextInput.isVisible, isFalse);
        await tester.pumpAndSettle();
        expect(find.text(l10n.searchOnlineFor('munich')), findsNothing);
        // What was typed stays.
        expect(find.text('munich'), findsOneWidget);
        // The keyboard goes, and the sheet comes back.
        await _keyboardTo(tester, layout, up: false);
        await tester.pumpAndSettle();
        expect(sheet.size, closeTo(resting, 0.005));

        // Wherever the map is free now the sheet is back.
        await tester.tapAt(_onTheMap(tester, layout));
        await tester.pumpAndSettle();
        expect(_points(tester), 1);

        // Back in the field, the results are back.
        await tester.tap(find.byType(TextField).first);
        await tester.pumpAndSettle();
        expect(find.text(l10n.searchOnlineFor('munich')), findsOneWidget);
        await unmountApp(tester);
      });

      testWidgets('a long press on the map while searching only ends the '
          'search', (tester) async {
        final h = await _pumpPlan(tester, layout);
        await tester.tap(find.byType(TextField).first);
        await tester.pump();
        await _keyboardTo(tester, layout, up: true);
        await tester.pumpAndSettle();
        expect(_search(tester).active, isTrue);

        // A press held: the native map reports it as one, and no tap
        // follows.
        final point = _onTheMap(tester, layout);
        final press = await tester.startGesture(point);
        await tester.pump(const Duration(milliseconds: 600));
        h.planner.map.onLongPress!(h.planner.map.positionAt(point));
        await press.cancel();
        await tester.pumpAndSettle();
        expect(find.byType(WaypointEditSheet), findsNothing);
        expect(_search(tester).active, isFalse);
        expect(_points(tester), 0);
        await _keyboardTo(tester, layout, up: false);
        await tester.pumpAndSettle();

        // Searching no more, the press marks a place.
        final again = await tester.startGesture(_onTheMap(tester, layout));
        await tester.pump(const Duration(milliseconds: 600));
        h.planner.map.onLongPress!(h.planner.map.positionAt(point));
        await again.cancel();
        await tester.pumpAndSettle();
        expect(find.byType(WaypointEditSheet), findsOneWidget);
        await unmountApp(tester);
      });
    });
  }

  testWidgets('the field letting go before the map hears of the tap still '
      'ends only the search', (tester) async {
    // A mouse's press outside the field takes its focus at once, before
    // the map reports the tap.
    final h = await _pumpPlan(tester, _Layout.upright);
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    final point = _onTheMap(tester, _Layout.upright);
    h.planner.map.tapsAreTaps = false;
    final press = await tester.startGesture(point);
    FocusManager.instance.primaryFocus?.unfocus();
    await press.up();
    await tester.pump();
    expect(_search(tester).active, isFalse);
    h.planner.map.onTap!(h.planner.map.positionAt(point));
    await tester.pumpAndSettle();
    expect(_points(tester), 0);

    h.planner.map.tapsAreTaps = true;
    await tester.tapAt(point);
    await tester.pumpAndSettle();
    expect(_points(tester), 1);
    await unmountApp(tester);
  });
}

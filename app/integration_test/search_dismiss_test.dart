// The search on the Plan tab with the phone's own keyboard: the sheet goes
// down under the keyboard and stays there while it is up, and a tap on the
// map while searching only ends the search; the next one sets a point.
//
// The touch on the map is a real pointer through Flutter, where the screen
// learns that the search was under way when the finger came down. What the
// native map makes of it differs: on iOS a synthesised pointer never reaches
// the native view, on Android it does. So the pointer is put down and taken
// back (cancelled, which no map reads as a tap), and the map's report of the
// tap is made in between through the handler the app gave the map, as the
// native view would make it.
//
// A simulator or emulator with a hardware keyboard connected shows no soft
// keyboard: the checks that need one are then skipped, and the log says so.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:velorki/features/map/presentation/map_view.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/presentation/planner_map_host.dart';
import 'package:velorki/features/planner/presentation/planner_screen.dart';
import 'package:velorki/features/planner/presentation/waypoint_edit_sheet.dart';
import 'package:velorki/features/search/presentation/search_field.dart';
import 'package:velorki/features/shared/presentation/adaptive_docking_sheet.dart';

import 'support/fakes.dart';
import 'support/harness.dart';
import 'support/region.dart';
import 'support/tiles.dart';

/// The Plan tab's sheet.
DraggableScrollableController _sheet(WidgetTester tester) => tester
    .widget<AdaptiveDockingSheet>(
      find
          .descendant(
            of: find.byType(PlannerScreen),
            matching: find.byType(AdaptiveDockingSheet),
          )
          .first,
    )
    .controller;

/// Whether the search field has the focus.
bool _fieldFocused() =>
    FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<SearchField>() !=
    null;

/// The keyboard's height, in logical pixels.
double _keyboard(WidgetTester tester) =>
    tester.view.viewInsets.bottom / tester.view.devicePixelRatio;

/// A point where the native map is the first thing a touch meets, above the
/// keyboard and away from the sheet and the chrome; `null` while there is
/// none.
Offset? _onTheMap(WidgetTester tester) {
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  for (var y = 0.3; y <= 0.6; y += 0.05) {
    for (var x = 0.2; x <= 0.8; x += 0.1) {
      final point = Offset(size.width * x, size.height * y);
      final result = HitTestResult();
      tester.binding.hitTestInView(result, point, tester.view.viewId);
      for (final entry in result.path) {
        final target = entry.target;
        if (target is PlatformViewRenderBox ||
            target is RenderDarwinPlatformView) {
          return point;
        }
        // Only what listens may lie over the map; anything else takes it.
        if (target is! RenderPointerListener && target is! RenderMouseRegion) {
          break;
        }
      }
    }
  }
  return null;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a tap on the map while searching only ends the search, and '
      'the sheet stays under the keyboard meanwhile', (tester) async {
    final maps = <RecordingMapController>[];
    final container = await pumpApp(
      tester,
      realMap: false,
      overrides: [
        mapViewBuilderProvider.overrideWithValue(
          (onReady) => MapView(
            onControllerReady: (controller) {
              final recorder = RecordingMapController(controller);
              maps.add(recorder);
              onReady(recorder);
            },
          ),
        ),
      ],
    );
    await ensureRegionTile(tester, container);
    final planner = container.read(plannerControllerProvider.notifier);
    // The device keeps the plan between runs and files.
    planner.clear();
    int points() => container.read(plannerControllerProvider).waypoints.length;

    final field = find.descendant(
      of: find.byType(SearchField),
      matching: find.byType(TextField),
    );
    await waitForWidget(tester, field);
    await waitUntil(
      tester,
      () => maps.isNotEmpty && maps.last.tapHandler != null,
      describe: 'the Plan tab on the map',
    );
    final sheet = _sheet(tester);

    /// Where the sheet is once it has kept still for a moment.
    Future<double> sheetAtRest() async {
      var last = -1.0;
      await waitUntil(tester, () {
        final now = sheet.size;
        final still = (now - last).abs() < 0.001;
        last = now;
        return still;
      }, describe: 'the sheet to keep still');
      return last;
    }

    /// The rider focuses the field: the sheet goes down, and stays down
    /// while the keyboard, if there is one, is up. Answers where the sheet
    /// was before.
    Future<double> focusField() async {
      final resting = await sheetAtRest();
      await tapAndPump(tester, field);
      expect(_fieldFocused(), isTrue);
      final clock = Stopwatch()..start();
      while (_keyboard(tester) <= 0 && clock.elapsed.inSeconds < 5) {
        await tester.pump(pumpStep);
      }
      final keyboard = _keyboard(tester);
      debugPrint(
        keyboard > 0
            ? 'VELORKI_SEARCH keyboard ${keyboard.round()} pt'
            : 'VELORKI_SEARCH no soft keyboard: a hardware keyboard is '
                  'connected; the checks under it are skipped',
      );
      await waitUntil(
        tester,
        () => sheet.size < resting - 0.1,
        describe: 'the sheet to go down for the search',
      );
      // Its way down ends within a few frames; then a while with the
      // keyboard up, and nothing brings the sheet back.
      await pumpFor(tester, const Duration(milliseconds: 400));
      final parked = sheet.size;
      for (var i = 0; i < 12; i++) {
        await tester.pump(pumpStep);
        expect(
          sheet.size,
          lessThanOrEqualTo(parked + 0.005),
          reason: 'the sheet came back while the field had the focus',
        );
      }
      expect(_fieldFocused(), isTrue);
      return resting;
    }

    /// A finger on the map, and the map's report of what it was.
    Future<void> touchMap(VoidCallback report) async {
      Offset? point;
      await waitUntil(
        tester,
        () => (point = _onTheMap(tester)) != null,
        describe: 'a free point on the map',
      );
      final finger = await tester.startGesture(point!);
      await tester.pump(pumpStep);
      report();
      await finger.cancel();
      await pumpFor(tester, const Duration(milliseconds: 300));
    }

    // ------------------------------------------- a tap ends only the search
    var resting = await focusField();
    final before = points();
    await touchMap(() => maps.last.tapHandler!(region.start));
    expect(
      points(),
      before,
      reason: 'the tap that ends a search sets no point',
    );
    expect(_fieldFocused(), isFalse);
    await waitUntil(
      tester,
      () => _keyboard(tester) <= 0,
      describe: 'the keyboard to go',
    );
    await waitUntil(
      tester,
      () => (sheet.size - resting).abs() < 0.01,
      describe: 'the sheet to come back',
      onTimeout: () => 'sheet at ${sheet.size}, resting at $resting',
    );

    // ---------------------------------------------- the next one sets a point
    await touchMap(() => maps.last.tapHandler!(region.start));
    await waitUntil(
      tester,
      () => points() == before + 1,
      describe: 'the next tap to set a point',
    );

    // ------------------------------------- a long press ends only the search
    resting = await focusField();
    await touchMap(() => maps.last.longPressHandler!(region.via));
    expect(_fieldFocused(), isFalse);
    await pumpFor(tester, const Duration(milliseconds: 600));
    expect(find.byType(WaypointEditSheet), findsNothing);
    expect(points(), before + 1);
    await waitUntil(
      tester,
      () => _keyboard(tester) <= 0 && (sheet.size - resting).abs() < 0.01,
      describe: 'the keyboard to go and the sheet to come back',
    );

    planner.clear();
    await unmountApp(tester);
  });
}

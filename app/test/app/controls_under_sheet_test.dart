import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/app/shell_layout.dart';
import 'package:velorki/features/map/presentation/map_controls.dart';
import 'package:velorki/features/shared/presentation/docking_sheet.dart';
import 'package:velorki/features/smart_loop/presentation/smart_loop_sheet.dart';

import '../features/recording/support/pump.dart';

/// How opaque the map's control column is drawn.
double _controlsOpacity(WidgetTester tester) => tester
    .widget<Opacity>(
      find
          .ancestor(
            of: find.byType(MapControls),
            matching: find.byType(Opacity),
          )
          .first,
    )
    .opacity;

/// The handle of the sheet on screen.
Finder get _handle => find.byType(SheetHandle).first;

/// The sheet on screen.
Rect _sheet(WidgetTester tester) => tester.getRect(
  find.ancestor(of: _handle, matching: find.byType(DockingSheetShell)).first,
);

/// The tab's sheet, pulled up by its handle by [dy].
Future<void> _pull(WidgetTester tester, double dy) async {
  await tester.drag(_handle, Offset(0, -dy));
  await tester.pumpAndSettle();
}

Future<void> _app(WidgetTester tester, Size size, String location) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = size * 2;
  tester.view.viewPadding = const FakeViewPadding(top: 48, bottom: 40);
  tester.view.padding = tester.view.viewPadding;
  addTearDown(tester.view.reset);
  await pumpRecordingApp(
    tester,
    initialLocation: location,
    surfaceSize: size,
    expectTextFits: false,
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => debugShellLayoutOverride = null);

  // Phones upright, small and large, and wide windows, short and tall.
  for (final size in const [
    Size(360, 640),
    Size(375, 667),
    Size(390, 844),
    Size(951, 669),
    Size(820, 1180),
  ]) {
    for (final location in [plannerRoute, libraryRoute]) {
      testWidgets('$size, $location: the controls stay in view over the '
          'sheet at rest and fade out, untouchable, under it pulled up', (
        tester,
      ) async {
        await _app(tester, size, location);
        // At rest, as before: a small phone's Plan sheet lies over the end
        // of the column's last button, and the column stays.
        expect(_controlsOpacity(tester), 1);

        await _pull(tester, size.height);
        final controls = tester.getRect(find.byType(MapControls));
        final sheet = _sheet(tester);
        expect(sheet.top, lessThan(controls.bottom));
        expect(_controlsOpacity(tester), 0);
        expect(
          tester
              .widget<IgnorePointer>(
                find
                    .ancestor(
                      of: find.byType(MapControls),
                      matching: find.byType(IgnorePointer),
                    )
                    .first,
              )
              .ignoring,
          isTrue,
        );

        // Back down, back in view.
        await _pull(tester, -size.height * 0.4);
        if (_sheet(tester).top > controls.bottom) {
          expect(_controlsOpacity(tester), 1);
        }
        await unmountApp(tester);
      });
    }
  }

  for (final size in const [Size(390, 844), Size(951, 669)]) {
    testWidgets('$size: the controls fade out under a modal sheet and come '
        'back when it closes', (tester) async {
      await _app(tester, size, plannerRoute);
      double modalOpacity() => tester
          .widget<AnimatedOpacity>(
            find
                .ancestor(
                  of: find.byType(MapControls),
                  matching: find.byType(AnimatedOpacity),
                )
                .first,
          )
          .opacity;
      expect(modalOpacity(), 1);
      unawaited(showSmartLoopSheet(tester.element(find.byType(MapControls))));
      await tester.pumpAndSettle();
      expect(modalOpacity(), 0);
      Navigator.of(tester.element(find.byType(SmartLoopSheet))).pop();
      await tester.pumpAndSettle();
      expect(modalOpacity(), 1);
      await unmountApp(tester);
    });
  }
}

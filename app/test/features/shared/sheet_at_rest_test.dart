import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/app/shell_layout.dart';
import 'package:velorki/features/shared/presentation/docking_sheet.dart';

import '../recording/support/pump.dart';

// A sheet at rest is all sheet: its fold into the bar begins below where it
// rests. On a short window the full folding range began above it, and the
// sheet at rest was part glass, the map showing through.
void main() {
  setUp(() => debugShellLayoutOverride = null);

  for (final (name, size) in const [
    ('a foldable\'s inner screen on its side', Size(951, 669)),
    ('a small phone with a home indicator', Size(375, 667)),
    ('a phone', Size(402, 874)),
    ('an iPad on its side', Size(1180, 820)),
  ]) {
    for (final tab in [plannerRoute, recordingRoute, libraryRoute]) {
      testWidgets('$name, $tab: the sheet at rest has not begun to fold', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 3;
        tester.view.physicalSize = size * 3;
        tester.view.viewPadding = const FakeViewPadding(
          top: 24 * 3,
          bottom: 20 * 3,
        );
        tester.view.padding = tester.view.viewPadding;
        addTearDown(tester.view.reset);
        await pumpRecordingApp(
          tester,
          initialLocation: tab,
          surfaceSize: size,
          expectTextFits: false,
        );
        await tester.pumpAndSettle();
        final shell = tester.widget<DockingSheetShell>(
          find.byType(DockingSheetShell),
        );
        expect(shell.docked, 0);
        await unmountApp(tester);
      });
    }
  }
}

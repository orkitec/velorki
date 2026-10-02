import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/features/shared/presentation/docking_sheet.dart';

import '../features/recording/support/pump.dart';
import '../support/app.dart';

// The Library's card reaches higher than the Record sheet does; a sheet
// that takes over where the last tab's was must not start above its own
// top.
void main() {
  for (final size in [const Size(375, 667), const Size(402, 874)]) {
    testWidgets('the Library card at its top, then Record: the Record sheet '
        'starts within its own reach, at $size', (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = size * 3;
      addTearDown(tester.view.resetPhysicalSize);
      await pumpRecordingApp(
        tester,
        initialLocation: libraryRoute,
        surfaceSize: size,
        expectTextFits: false,
      );
      await tester.pumpAndSettle();
      await tester.dragFrom(
        tester.getCenter(find.byType(SheetHandle)),
        const Offset(0, -2000),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(l10n.tabRecord),
        ),
      );
      await tester.pumpAndSettle();
      final sheet = tester.getRect(find.byType(DockingSheetShell));
      expect(sheet.top, greaterThanOrEqualTo(size.height * 0.15 - 1));
      await unmountApp(tester);
    });
  }
}

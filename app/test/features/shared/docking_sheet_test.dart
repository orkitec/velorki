import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/shared/presentation/docking_sheet.dart';

import '../../support/app.dart';

/// A shell in a 400 x 200 box at [extent] of the screen, collapsing at 0.1
/// with a docking range of 0.1 and 80 px of bar under it.
Widget _shell(double extent, {bool docks = true}) => testApp(
  home: Center(
    child: SizedBox(
      width: 400,
      height: 200,
      child: DockingSheetShell(
        extent: extent,
        collapsedExtent: 0.1,
        dockedRange: 0.1,
        docks: docks,
        dockedBottomInset: 80,
        handle: const SheetHandle(),
        child: const SizedBox.expand(),
      ),
    ),
  ),
);

void main() {
  test('the docked fraction runs over the range above the collapsed size', () {
    double at(double extent, {bool docks = true}) =>
        DockingSheetShell.dockedFraction(
          extent: extent,
          collapsedExtent: 0.1,
          dockedRange: 0.1,
          docks: docks,
        );
    expect(at(0.5), 0);
    expect(at(0.2), 0);
    expect(at(0.15), closeTo(0.5, 1e-9));
    expect(at(0.1), 1);
    // A stale extent below the collapsed size still counts as docked.
    expect(at(0.05), 1);
    expect(at(0.1, docks: false), 0);
  });

  testWidgets('the lower edge stays down until late, then lifts to the bar', (
    tester,
  ) async {
    Future<Rect> paintedBox(double extent, {bool docks = true}) async {
      await tester.pumpWidget(_shell(extent, docks: docks));
      return tester.getRect(find.byType(ClipRRect));
    }

    var rect = await paintedBox(0.3);
    final box = tester.getRect(find.byType(DockingSheetShell));
    // At rest and a third into the morph the sheet reaches the bottom.
    expect(rect, box);
    rect = await paintedBox(0.17);
    expect(rect.bottom, box.bottom);
    expect(rect.left, closeTo(box.left + 16 * 0.3, 0.01));
    // At 0.4 nothing has lifted yet; at 0.6 eleven per cent, at 0.75 a
    // third of the way: the lift eases in over the last three fifths.
    rect = await paintedBox(0.16);
    expect(rect.bottom, box.bottom);
    rect = await paintedBox(0.14);
    expect(rect.bottom, closeTo(box.bottom - (80 - 1) * (1 / 9), 0.01));
    rect = await paintedBox(0.125);
    expect(
      rect.bottom,
      closeTo(box.bottom - (80 - 1) * (0.35 / 0.6) * (0.35 / 0.6), 0.01),
    );
    // Docked: the bar's width, and a hair over the bar's top edge.
    rect = await paintedBox(0.1);
    expect(rect.left, box.left + 16);
    expect(rect.right, box.right - 16);
    expect(rect.bottom, box.bottom - 80 + sheetDockedOverlapDp);
    // No morph without a bar.
    rect = await paintedBox(0.1, docks: false);
    expect(rect, box);
  });
}

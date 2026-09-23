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
        controller: ScrollController(),
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

/// A [DraggableScrollableSheet] in a 400 x 600 box with a [DockingSheet]
/// body whose content is a long list of numbered rows, over 80 px of bar:
/// collapsed, the handle strip is what is left above the bar.
class _Sheet extends StatelessWidget {
  const _Sheet({required this.onExtent});

  final ValueChanged<double> onExtent;

  @override
  Widget build(BuildContext context) => testApp(
    home: Center(
      child: SizedBox(
        width: 400,
        height: 600,
        child: Stack(
          children: [
            DraggableScrollableSheet(
              initialChildSize: 0.5,
              minChildSize: (80 + sheetHandleDp) / 600,
              maxChildSize: 0.9,
              snap: true,
              snapSizes: const [0.5],
              builder: (context, controller) => DockingSheet(
                controller: controller,
                initialExtent: 0.5,
                collapsedExtent: (80 + sheetHandleDp) / 600,
                dockedRange: 0.2,
                docks: true,
                dockedBottomInset: 80,
                onExtent: onExtent,
                handle: const SheetHandle(),
                child: ListView(
                  primary: false,
                  padding: EdgeInsets.zero,
                  children: [
                    const SizedBox(height: sheetHandleDp),
                    for (var i = 0; i < 60; i++)
                      SizedBox(height: 40, child: Text('row $i')),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('the content scrolls on its own at any height, and only the '
      'handle moves the sheet', (tester) async {
    var extent = 0.0;
    await tester.pumpWidget(_Sheet(onExtent: (e) => extent = e));
    await tester.pumpAndSettle();
    expect(extent, 0.5);
    expect(find.text('row 0'), findsOneWidget);
    expect(find.text('row 30'), findsNothing);

    // A drag on the rows scrolls them; the sheet stays where it is.
    await tester.drag(find.text('row 3'), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(extent, 0.5);
    expect(find.text('row 0'), findsNothing);
    expect(find.text('row 20'), findsOneWidget);

    // A drag on the handle moves the sheet, up to its top.
    await tester.dragFrom(
      tester.getCenter(find.byType(SheetHandle)),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    expect(extent, closeTo(0.9, 0.001));

    // At the top the rows still scroll, and the sheet still stays.
    await tester.drag(find.text('row 20'), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(extent, closeTo(0.9, 0.001));
    expect(find.text('row 12'), findsOneWidget);

    // From the top the handle brings the sheet down, all the way.
    await tester.dragFrom(
      tester.getCenter(find.byType(SheetHandle)),
      const Offset(0, 700),
    );
    await tester.pumpAndSettle();
    expect(extent, closeTo((80 + sheetHandleDp) / 600, 0.001));
    // A pull on the docked handle brings it up again, to the resting snap.
    await tester.dragFrom(
      tester.getCenter(find.byType(SheetHandle)),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(extent, closeTo(0.5, 0.001));
  });

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

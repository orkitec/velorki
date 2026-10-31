import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/planner/presentation/planner_screen.dart';
import 'package:velorki/features/shared/presentation/adaptive_docking_sheet.dart';

import 'support/pump.dart';

void main() {
  /// Leaves the Plan sheet [fraction] of the way into its morph to the bar,
  /// the way a move of the app's own cut short would, and answers where it
  /// is once it has kept still for a while.
  Future<(double, AdaptiveDockingSheet)> leaveAt(
    WidgetTester tester,
    double fraction,
  ) async {
    await pumpScreen(tester, const PlannerScreen());
    await tester.pumpAndSettle();
    final sheet = tester.widget<AdaptiveDockingSheet>(
      find.byType(AdaptiveDockingSheet).first,
    );
    final controller = sheet.controller;
    controller.jumpTo(
      sheet.collapsedExtent + sheet.dockedRange * (1 - fraction),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    return (controller.size, sheet);
  }

  testWidgets('a sheet left mostly docked goes on down to the bar', (
    tester,
  ) async {
    final (size, sheet) = await leaveAt(tester, 0.7);
    expect(size, closeTo(sheet.collapsedExtent, 0.002));
  });

  testWidgets('a sheet left mostly open goes back up out of the morph', (
    tester,
  ) async {
    final (size, sheet) = await leaveAt(tester, 0.3);
    expect(
      size,
      greaterThanOrEqualTo(sheet.collapsedExtent + sheet.dockedRange - 0.002),
    );
  });

  testWidgets('a sheet held by a finger stays where it is', (tester) async {
    await pumpScreen(tester, const PlannerScreen());
    await tester.pumpAndSettle();
    final sheet = tester.widget<AdaptiveDockingSheet>(
      find.byType(AdaptiveDockingSheet).first,
    );
    final controller = sheet.controller;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(DraggableScrollableSheet).first),
    );
    final held = sheet.collapsedExtent + sheet.dockedRange * 0.5;
    controller.jumpTo(held);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(controller.size, closeTo(held, 0.002));
    await gesture.cancel();
    await tester.pumpAndSettle();
  });
}

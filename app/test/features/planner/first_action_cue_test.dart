import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/map/presentation/first_start_location.dart';
import 'package:velorki/features/map/presentation/visible_map_padding.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/presentation/first_action_cue.dart';
import 'package:velorki/features/planner/presentation/planner_screen.dart';
import 'package:velorki/features/planner/presentation/profile_chip_row.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';
import 'support/pump.dart';

final Finder _headlinePulse = find.byKey(firstActionCueHeadlinePulseKey);
final Finder _pulse = find.byKey(firstActionCuePulseKey);
final Finder _ring = find.byKey(firstActionCueRingKey);

/// How far the empty sheet's headline has faded in.
double _headlineOpacity(WidgetTester tester) {
  final opacity = find.ancestor(
    of: find.text(l10n.plannerEmptyState),
    matching: find.byType(Opacity),
  );
  if (opacity.evaluate().isEmpty) return 1;
  return tester.widget<Opacity>(opacity.first).opacity;
}

PlannerController _planner(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(PlannerScreen)))
        .read(plannerControllerProvider.notifier);

void main() {
  testWidgets('after a moment the headline fades in and its outline pulses, '
      'then the field\'s, then a ring spreads, once', (tester) async {
    await pumpScreen(tester, const PlannerScreen());
    await tester.pump(const Duration(milliseconds: 100));
    expect(_headlineOpacity(tester), 0);
    expect(_pulse, findsNothing);

    await tester.pump(const Duration(milliseconds: 800));
    expect(_headlineOpacity(tester), inExclusiveRange(0, 1));
    expect(_pulse, findsNothing);

    // The headline's outline, the headline in place.
    await tester.pump(const Duration(milliseconds: 600));
    expect(_headlineOpacity(tester), 1);
    expect(_headlinePulse, findsOneWidget);
    expect(_pulse, findsNothing);

    // Then the field's, the ring still to come.
    await tester.pump(const Duration(milliseconds: 1300));
    expect(_headlinePulse, findsNothing);
    expect(_pulse, findsOneWidget);
    expect(_ring, findsNothing);

    // Then the map, the field done.
    await tester.pump(const Duration(milliseconds: 1200));
    expect(_pulse, findsNothing);
    expect(_ring, findsOneWidget);

    // Finite: it settles, and does not come back while the plan stays empty.
    await tester.pumpAndSettle();
    expect(_pulse, findsNothing);
    expect(_ring, findsNothing);
    await tester.pump(const Duration(seconds: 5));
    expect(_pulse, findsNothing);
    expect(_ring, findsNothing);
    expect(find.text(l10n.plannerEmptyState), findsOneWidget);
  });

  testWidgets('a touch on the map ends it at once', (tester) async {
    await pumpScreen(tester, const PlannerScreen());
    await tester.pump(const Duration(milliseconds: 4000));
    expect(_ring, findsOneWidget);

    await tester.tapAt(const Offset(400, 600));
    await tester.pump();
    expect(_pulse, findsNothing);
    expect(_ring, findsNothing);
    expect(_headlineOpacity(tester), 1);
  });

  testWidgets('a tap on the search field ends it, the headline too', (
    tester,
  ) async {
    await pumpScreen(tester, const PlannerScreen());
    await tester.pump(const Duration(milliseconds: 100));
    expect(_headlineOpacity(tester), lessThan(1));

    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    expect(_headlineOpacity(tester), 1);
    expect(_pulse, findsNothing);
    expect(_ring, findsNothing);
    await tester.pumpAndSettle();
  });

  testWidgets('it comes back when the plan is cleared', (tester) async {
    await pumpScreen(tester, const PlannerScreen());
    await tester.pumpAndSettle();

    _planner(tester).addWaypoint(const LatLng(48.1, 11.5));
    await tester.pumpAndSettle();
    expect(find.text(l10n.plannerEmptyState), findsNothing);
    expect(_ring, findsNothing);

    _planner(tester).clear();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2800));
    expect(find.text(l10n.plannerEmptyState), findsOneWidget);
    expect(_pulse, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1200));
    expect(_ring, findsOneWidget);
    await tester.pumpAndSettle();
    expect(_ring, findsNothing);
  });

  testWidgets('with animations off the text is simply there', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpScreen(tester, const PlannerScreen());
    for (var i = 0; i < 4; i++) {
      expect(
        find.descendant(
          of: find.byType(FirstActionCueReveal),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );
      expect(_pulse, findsNothing);
      expect(_ring, findsNothing);
      await tester.pump(const Duration(milliseconds: 300));
    }
  });

  testWidgets('switched off, nothing moves', (tester) async {
    await pumpScreen(
      tester,
      const PlannerScreen(),
      extraOverrides: [firstActionCueEnabledProvider.overrideWithValue(false)],
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(_headlineOpacity(tester), 1);
    await tester.pump(const Duration(milliseconds: 400));
    expect(_pulse, findsNothing);
    expect(_ring, findsNothing);
  });

  testWidgets('the ring spreads from the middle of the map left visible', (
    tester,
  ) async {
    // The window as large as the screen the harness lays out in, as on a
    // phone, where the two are one.
    tester.view
      ..physicalSize = const Size(1000, 2000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpScreen(tester, const PlannerScreen());
    await tester.pump(const Duration(milliseconds: 4000));
    final painter =
        tester.widget<CustomPaint>(_ring).painter! as FirstActionCueRingPainter;
    final element = tester.element(find.byType(PlannerScreen));
    final width = tester.getSize(find.byType(PlannerScreen)).width;
    // Beside the control column at the right.
    expect(
      painter.centre.dx,
      closeTo((width - mapControlsWidth(element)) / 2, 0.5),
    );
    // Between the chrome and the resting sheet, halfway.
    final chromeBottom = tester.getBottomLeft(find.byType(ProfileChipRow)).dy;
    final sheetTop = tester.getTopLeft(find.byType(DraggableScrollableSheet));
    final sheet = tester.widget<DraggableScrollableSheet>(
      find.byType(DraggableScrollableSheet),
    );
    final height = tester.getSize(find.byType(PlannerScreen)).height;
    final top = sheetTop.dy + (1 - sheet.initialChildSize) * height;
    expect(painter.centre.dy, greaterThan(chromeBottom + 24));
    expect(painter.centre.dy, lessThan(top - 24));
    expect(painter.centre.dy, closeTo((chromeBottom + top) / 2, 10));
    await tester.pumpAndSettle();
  });

  testWidgets('after the first start\'s location question it runs once the '
      'dialog has gone, not skipped for it', (tester) async {
    await pumpScreen(
      tester,
      const PlannerScreen(),
      harness: PlannerHarness(locationQuestionDue: true),
    );
    final context = tester.element(find.byType(PlannerScreen));
    final asking = ProviderScope.containerOf(context)
        .read(firstStartLocationAskProvider.notifier);
    // The question's dialog, answered: it starts to close as the answer
    // comes, the way askLocationOnFirstStart ends.
    final navigator = Navigator.of(context, rootNavigator: true);
    final closed = showDialog<void>(
      context: context,
      builder: (_) => const AlertDialog(content: Text('?')),
    );
    await tester.pumpAndSettle();
    expect(_ring, findsNothing);
    navigator.pop();
    asking.done();
    await closed;
    // The wait for the dialog, then the cue up to its ring.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 3800));
    expect(_ring, findsOneWidget);
    await tester.pumpAndSettle();
  });
}

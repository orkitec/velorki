import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/router.dart' show FloatingNavigationBar;
import 'package:velorki/core/units/units.dart' as units;
import 'package:velorki/features/recording/domain/live_figures.dart';
import 'package:velorki/features/recording/presentation/live_figures_view.dart';
import 'package:velorki/features/shared/presentation/floating_bar.dart';

import '../../support/app.dart';

/// Where the glass of the bar [bar] lands at the bottom of an SE-sized
/// screen with a home indicator.
Future<Rect> _glass(WidgetTester tester, Widget bar) async {
  tester.view.physicalSize =
      const Size(375, 667) * tester.view.devicePixelRatio;
  tester.view.viewPadding = FakeViewPadding(
    bottom: 34 * tester.view.devicePixelRatio,
  );
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetViewPadding);
  await tester.pumpWidget(
    testApp(
      home: Scaffold(
        body: Align(alignment: Alignment.bottomCenter, child: bar),
      ),
    ),
  );
  await tester.pump();
  return tester.getRect(
    find
        .descendant(
          of: find.byType(FloatingBarShell),
          matching: find.byType(Container),
        )
        .first,
  );
}

void main() {
  for (final docked in [false, true]) {
    testWidgets('the figures bar sits exactly where the tab bar sits, '
        '${docked ? 'docked' : 'at rest'}', (tester) async {
      final tabs = await _glass(
        tester,
        FloatingNavigationBar(
          selectedIndex: 1,
          onDestinationSelected: (_) {},
          docked: docked,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.route), label: 'Plan'),
            NavigationDestination(icon: Icon(Icons.circle), label: 'Record'),
          ],
        ),
      );
      final figures = await _glass(
        tester,
        FiguresBar(
          docked: docked,
          paused: false,
          system: units.UnitSystem.metric,
          onOpen: () {},
          figures: const [
            LiveFigureReading(LiveFigure.distance, value: 1200),
            LiveFigureReading(LiveFigure.speed, value: 5),
            LiveFigureReading(LiveFigure.avgSpeed, value: 4),
            LiveFigureReading(LiveFigure.ascent, value: 20),
          ],
        ),
      );
      expect(figures, tabs);
      expect(figures.height, floatingBarHeight);
      expect(figures.bottom, 667 - 34 - floatingBarBottomGap);
      expect(figures.left, floatingBarSideMargin);
    });
  }
}

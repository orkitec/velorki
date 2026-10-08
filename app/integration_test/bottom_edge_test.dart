// A swipe up from the bottom edge is the system's: on an iPhone it opens
// the app switcher, and iOS hands the start of that touch to the app before
// taking it over, which flung the tab's sheet open. The real home gesture
// cannot be scripted; this drags from inside the home indicator's zone and
// checks the app's part: the sheet stays where it was.
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:velorki/features/map/presentation/map_attribution.dart';
import 'package:velorki/features/recording/presentation/recording_screen.dart';
import 'package:velorki/features/shared/presentation/docking_sheet.dart';
import 'package:velorki/features/shared/presentation/floating_bar.dart';
import 'package:velorki/features/shared/presentation/gesture_zone_guard.dart';

import 'support/harness.dart';

/// Where the sheet's top is and how far its content is scrolled.
(double, double) _sheetState(WidgetTester tester) {
  final content = tester.state<ScrollableState>(
    find
        .descendant(
          of: find.byType(SheetContentScroll),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  return (
    tester.getRect(find.byType(DockingSheetShell)).top,
    content.position.pixels,
  );
}

/// The bar's [index]th tab.
Finder _tab(int index) => find
    .descendant(
      of: find.byType(NavigationBar),
      matching: find.byType(NavigationDestination),
    )
    .at(index);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a drag from the bottom edge leaves the sheet where it was, '
      'one from above the edge still moves it, and the bar still taps', (
    tester,
  ) async {
    await pumpApp(tester);
    final zone = systemGestureZoneHeight(
      MediaQueryData.fromView(tester.view),
      defaultTargetPlatform,
    );
    debugPrint('VELORKI_ITEST bottom gesture zone $zone');
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final x = size.width / 2;

    // Plan's sheet at rest, with its content at the top.
    await tapAndPump(tester, _tab(0));
    final rest = _sheetState(tester);

    if (zone > 10) {
      // A quick swipe, as the home gesture is.
      await tester.timedDragFrom(
        Offset(x, size.height - 10),
        Offset(0, -size.height / 2),
        const Duration(milliseconds: 150),
      );
      await pumpFor(tester, const Duration(seconds: 1));
      expect(_sheetState(tester), rest);
    }

    await tester.timedDragFrom(
      Offset(x, size.height - zone - 4),
      Offset(0, -size.height / 2),
      const Duration(milliseconds: 150),
    );
    await pumpFor(tester, const Duration(seconds: 1));
    expect(_sheetState(tester), isNot(rest));

    // With the sheet docked into the bar, the map's attribution chip is in
    // view and opens its notice. With a zone it sits in the band under the
    // bar, in the zone, which lets its tap through; without one (a home
    // button, three-button navigation) that band is too low, and it stands
    // above the bar and the sheet's strip docked on it.
    await tester.dragFrom(
      tester.getCenter(find.byType(SheetHandle)),
      Offset(0, size.height),
    );
    await pumpFor(tester, const Duration(seconds: 1));
    final chip = find.byType(MapAttributionChip);
    final chipRect = tester.getRect(chip);
    if (zone > 0) {
      expect(chipRect.bottom, greaterThan(size.height - zone));
    } else {
      final bar = tester.getRect(
        find
            .descendant(
              of: find.byType(FloatingBarShell),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(chipRect.bottom, lessThanOrEqualTo(bar.top - sheetHandleDp));
      expect(
        chipRect.bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(DockingSheetShell)).top),
      );
    }
    await tapAndPump(tester, chip);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tapAt(const Offset(10, 120));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.byType(AlertDialog), findsNothing);

    await tapAndPump(tester, _tab(1));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.byType(RecordingScreen), findsOneWidget);
    await unmountApp(tester);
  });
}

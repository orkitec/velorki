import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/shared/presentation/chart_gestures.dart';

/// The badges of the chart cursors' handles on screen.
Finder get chartCursorHandles => find.byKey(chartCursorHandleKey);

/// Drags the cursor's [handle], the first on screen when left out, by [by],
/// a little at a time.
Future<void> dragChartCursor(
  WidgetTester tester,
  Offset by, {
  Finder? handle,
}) async {
  final finger = await tester.startGesture(
    tester.getCenter(handle ?? chartCursorHandles.first),
  );
  await tester.pump();
  const steps = 10;
  for (var i = 0; i < steps; i++) {
    await finger.moveBy(by / steps.toDouble());
    await tester.pump();
  }
  await finger.up();
  await tester.pump();
}

/// Taps the cursor's [handle], the first on screen when left out, twice in
/// quick succession.
Future<void> doubleTapChartCursor(WidgetTester tester, {Finder? handle}) async {
  final at = tester.getCenter(handle ?? chartCursorHandles.first);
  await tester.tapAt(at);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tapAt(at);
  await tester.pump();
}

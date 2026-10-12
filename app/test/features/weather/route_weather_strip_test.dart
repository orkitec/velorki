import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/shared/presentation/metric_chart.dart';
import 'package:velorki/features/weather/presentation/route_weather_strip.dart';

import '../../support/app.dart';
import '../../support/chart_cursor.dart';
import 'support/weather_fixtures.dart';

/// The weather along ten kilometres.
final _weather = weatherAlong(
  straightRoute(),
  earliest: DateTime.utc(2026, 10, 11, 8),
).weather;

/// Where [share] of the way across the strip's plot is on screen.
Offset _at(WidgetTester tester, double share) {
  final rect = tester.getRect(find.byType(RouteWeatherStrip));
  final left = rect.left + weatherStripLeftInset;
  final right = rect.right - weatherStripRightInset;
  return Offset(left + (right - left) * share, rect.center.dy);
}

RouteWeatherStripPainter _painter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.descendant(
                of: find.byType(RouteWeatherStrip),
                matching: find.byType(CustomPaint),
              ),
            )
            .painter!
        as RouteWeatherStripPainter;

Future<void> _pump(
  WidgetTester tester, {
  DistanceWindow? window,
  ValueChanged<DistanceWindow?>? onWindow,
  ValueNotifier<double?>? cursor,
}) async {
  await tester.binding.setSurfaceSize(const Size(440, 400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    testApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: RouteWeatherStrip(
            weather: _weather,
            semanticsLabel: 'weather',
            window: window,
            onWindow: onWindow,
            cursor: cursor,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// A cursor for the test, gone with it.
ValueNotifier<double?> _cursor() {
  final cursor = ValueNotifier<double?>(null);
  addTearDown(cursor.dispose);
  return cursor;
}

void main() {
  testWidgets('a tap and a sweep put the cursor where along the route the '
      'finger is, and it stays once the finger lifts', (tester) async {
    final cursor = _cursor();
    await _pump(tester, cursor: cursor);
    expect(chartCursorHandles, findsNothing);

    await tester.tapAt(_at(tester, 0.25));
    await tester.pump();
    expect(cursor.value, closeTo(2500, 10));
    expect(chartCursorHandles, findsOneWidget);
    expect(
      tester.getCenter(chartCursorHandles).dx,
      closeTo(_at(tester, 0.25).dx, 1),
    );

    final finger = await tester.startGesture(_at(tester, 0.35));
    await tester.pump();
    for (final share in <double>[0.5, 0.65, 0.75]) {
      await finger.moveTo(_at(tester, share));
      await tester.pump();
    }
    await finger.up();
    await tester.pump(const Duration(seconds: 2));
    expect(cursor.value, closeTo(7500, 10));
    expect(chartCursorHandles, findsOneWidget);
  });

  testWidgets('a cursor set elsewhere, on the profile sharing it, shows on '
      'the strip; its handle moves it and a double tap hides it', (
    tester,
  ) async {
    final cursor = _cursor();
    await _pump(tester, cursor: cursor);

    cursor.value = 5000;
    await tester.pump();
    expect(
      tester.getCenter(chartCursorHandles).dx,
      closeTo(_at(tester, 0.5).dx, 1),
    );

    final tenth = (_at(tester, 1).dx - _at(tester, 0).dx) / 10;
    await dragChartCursor(tester, Offset(tenth, 0));
    expect(cursor.value, closeTo(6000, 10));

    await doubleTapChartCursor(tester);
    expect(cursor.value, isNull);
    expect(chartCursorHandles, findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('draws the window it is given, and puts the cursor inside it', (
    tester,
  ) async {
    final cursor = _cursor();
    await _pump(
      tester,
      window: (start: 2000, end: 6000),
      onWindow: (_) {},
      cursor: cursor,
    );

    expect(_painter(tester).window, (start: 2000.0, end: 6000.0));
    await tester.tapAt(_at(tester, 0.5));
    await tester.pump(const Duration(milliseconds: 400));
    expect(cursor.value, closeTo(4000, 10));
  });

  testWidgets('a pinch on the strip asks for a narrower window', (
    tester,
  ) async {
    final asked = <DistanceWindow?>[];
    await _pump(tester, onWindow: asked.add);

    final centre = _at(tester, 0.5);
    final a = await tester.createGesture();
    final b = await tester.createGesture();
    await a.down(centre - const Offset(50, 0));
    await b.down(centre + const Offset(50, 0));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await a.moveBy(const Offset(-10, 0));
      await b.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pump(const Duration(milliseconds: 400));

    expect(asked, isNotEmpty);
    final last = asked.last!;
    expect(last.end - last.start, lessThan(6000));
    expect(last.start, greaterThan(1000));
    expect(last.end, lessThan(9000));
  });
}

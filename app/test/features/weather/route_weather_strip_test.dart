import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/shared/presentation/metric_chart.dart';
import 'package:velorki/features/weather/presentation/route_weather_strip.dart';

import '../../support/app.dart';
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
  ValueChanged<double?>? onCursor,
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
            onCursor: onCursor,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('a finger on the strip says how far along the route it is, '
      'and null once it lifts', (tester) async {
    final cursor = <double?>[];
    await _pump(tester, onCursor: cursor.add);

    final finger = await tester.startGesture(_at(tester, 0.25));
    await tester.pump();
    for (final share in <double>[0.35, 0.5, 0.65, 0.75]) {
      await finger.moveTo(_at(tester, share));
      await tester.pump();
    }
    await finger.up();
    await tester.pump(const Duration(milliseconds: 400));

    expect(cursor.first, closeTo(2500, 10));
    expect(cursor[cursor.length - 2], closeTo(7500, 10));
    expect(cursor.last, isNull);
  });

  testWidgets('draws the window it is given, and reads out inside it', (
    tester,
  ) async {
    final cursor = <double?>[];
    await _pump(
      tester,
      window: (start: 2000, end: 6000),
      onWindow: (_) {},
      onCursor: cursor.add,
    );

    expect(_painter(tester).window, (start: 2000.0, end: 6000.0));
    await tester.tapAt(_at(tester, 0.5));
    await tester.pump(const Duration(milliseconds: 400));
    expect(cursor.first, closeTo(4000, 10));
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

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/shared/presentation/metric_chart.dart';

import '../../support/app.dart';

void main() {
  testWidgets('the axes label their steps, not their uneven ends', (
    tester,
  ) async {
    // 13.6 km of a climb from below sea level (the elevation model's noise
    // at the shore) to 848 m.
    final spots = [
      for (var i = 0; i <= 136; i++) FlSpot(i / 10, -40 + i * 6.53),
    ];
    await tester.pumpWidget(
      testApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            child: MetricChart(
              title: 'Elevation',
              spots: spots,
              readoutAt: (_) => '',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final labels = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(LineChart),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data)
        .toList();
    expect(labels, contains('0'));
    expect(labels, isNot(contains('13.6')), reason: 'the end of the x axis');
    for (final label in labels) {
      expect(label, isNot(contains('.')), reason: '"$label" is an axis end');
    }
  });

  testWidgets('the height axis steps in round numbers on a short chart', (
    tester,
  ) async {
    // The planner's profile: 140 high, a climb from the shore to 792 m.
    final spots = [
      for (var i = 0; i <= 240; i++)
        FlSpot(i / 10, 792 * math.sin(math.pi * i / 240) - 66),
    ];
    await tester.pumpWidget(
      testApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            child: MetricChart(
              title: 'Elevation',
              spots: spots,
              height: 140,
              readoutAt: (_) => '',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final left = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(LineChart),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data!)
        .where((label) => double.parse(label) > 30)
        .toList();
    expect(left, isNotEmpty);
    for (final label in left) {
      expect(double.parse(label) % 100, 0, reason: '"$label" is not round');
    }
  });

  test('axis steps are 1, 2 or 5 times a power of ten', () {
    expect(niceAxisStep(858, 3), 500);
    expect(niceAxisStep(35, 4), 10);
    expect(niceAxisStep(60, 4), 20);
    expect(niceAxisStep(0.8, 4), 0.2);
    expect(niceAxisStep(0, 4), 1);
  });
}

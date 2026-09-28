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
}

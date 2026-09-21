import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/core/geo/ride_analysis.dart';
import 'package:velorki/features/recording/domain/ride_range.dart';
import 'package:velorki/features/recording/presentation/ride_charts.dart';
import 'package:velorki/features/shared/presentation/metric_chart.dart';

import '../../support/app.dart';
import '../../support/units.dart';

/// A sample every 100 m; the heart rate is there for the first kilometre,
/// gone for the next ten, back for the last two.
List<ChartSample> _samples() => <ChartSample>[
  for (var m = 0; m <= 13000; m += 100)
    ChartSample(
      distanceM: m.toDouble(),
      speedMps: 6,
      heartRateBpm: m <= 1000 || m >= 11000 ? 140 + (m ~/ 100) % 10 : null,
    ),
];

void main() {
  testWidgets('the heart-rate line breaks where the reading was lost, and '
      'the caption says how much of the ride had one', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: testApp(
          home: Scaffold(body: RideHeartRateChart(samples: _samples())),
        ),
      ),
    );
    await tester.pump();

    final chart = tester.widget<MetricChart>(find.byType(MetricChart));
    expect(chart.spots.where((s) => s.isNull()), hasLength(1));
    expect(chart.spots.first.isNull(), isFalse);
    expect(chart.spots.last.isNull(), isFalse);
    // 11 + 21 of the 131 samples carry a reading.
    expect(
      find.text(l10n.rideHeartRateCoverage(24).toUpperCase()),
      findsOneWidget,
    );
  });

  test('the highlight reaches the chart in the axis unit', () {
    const range = RideRange(
      startM: 1000,
      endM: 2000,
      source: RideRangeSource.split,
      index: 1,
    );
    expect(chartHighlight(UnitSystem.metric, range), (start: 1.0, end: 2.0));
    final imperial = chartHighlight(UnitSystem.imperial, range)!;
    expect(imperial.start, closeTo(1000 / 1609.344, 1e-9));
    expect(imperial.end, closeTo(2000 / 1609.344, 1e-9));
    expect(chartHighlight(UnitSystem.metric, null), isNull);
  });

  testWidgets('the speed chart shades the highlight behind its line', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          metricUnits,
        ],
        child: testApp(
          home: Scaffold(
            body: RideSpeedChart(
              samples: _samples(),
              highlight: const RideRange(
                startM: 500,
                endM: 2500,
                source: RideRangeSource.climb,
                index: 0,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final chart = tester.widget<MetricChart>(find.byType(MetricChart));
    expect(chart.highlight, (start: 0.5, end: 2.5));
    // The axis still runs the whole ride.
    expect(chart.spots.first.x, 0);
    expect(chart.spots.last.x, 13);
  });
}

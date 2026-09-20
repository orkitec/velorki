import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/core/geo/ride_analysis.dart';
import 'package:velorki/features/recording/presentation/ride_charts.dart';
import 'package:velorki/features/shared/presentation/metric_chart.dart';

import '../../support/app.dart';

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
}

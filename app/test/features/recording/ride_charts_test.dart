import 'package:fl_chart/fl_chart.dart';
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

/// The samples of an eleven-point chart, one every unit of x, all at the
/// same height, so a read-out names its index plainly.
List<FlSpot> _elevenSpots() => <FlSpot>[
  for (var x = 0; x <= 10; x++) FlSpot(x.toDouble(), 100),
];

/// The x axis the chart draws.
({double min, double max}) _axis(WidgetTester tester, [Finder? within]) {
  final finder = within == null
      ? find.byType(LineChart)
      : find.descendant(of: within, matching: find.byType(LineChart));
  final data = tester.widget<LineChart>(finder).data;
  return (min: data.minX, max: data.maxX);
}

/// Zooms in on the chart with two fingers, a hundred pixels apart at its
/// middle and moving apart by twenty a step: with ten [steps] the span
/// triples. The scale recognizer accepts at a twentieth of that and counts
/// from there, so the window comes out somewhat wider than a third.
Future<void> _pinchOut(
  WidgetTester tester, {
  Finder? within,
  int steps = 10,
}) async {
  final finder = within == null
      ? find.byType(LineChart)
      : find.descendant(of: within, matching: find.byType(LineChart));
  final centre = tester.getRect(finder).center;
  final a = await tester.createGesture();
  final b = await tester.createGesture();
  await a.down(centre - const Offset(50, 0));
  await b.down(centre + const Offset(50, 0));
  await tester.pump();
  for (var i = 0; i < steps; i++) {
    await a.moveBy(const Offset(-10, 0));
    await b.moveBy(const Offset(10, 0));
    await tester.pump();
  }
  await a.up();
  await b.up();
  await tester.pump();
}

/// Two taps at [at], a tenth of a second apart.
Future<void> _doubleTap(WidgetTester tester, Offset at) async {
  await tester.tapAt(at);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tapAt(at);
  await tester.pump();
}

/// Where sample [x] of a chart whose axis runs [axis] is on screen.
Offset _pixelOf(
  WidgetTester tester,
  ({double min, double max}) axis,
  double x, {
  Finder? within,
}) {
  final finder = within == null
      ? find.byType(LineChart)
      : find.descendant(of: within, matching: find.byType(LineChart));
  final rect = tester.getRect(finder);
  final chart = tester.widget<MetricChart>(
    within == null
        ? find.byType(MetricChart)
        : find.descendant(of: within, matching: find.byType(MetricChart)),
  );
  final left = rect.left + chart.leftReservedSize;
  final share = (x - axis.min) / (axis.max - axis.min);
  return Offset(left + (rect.right - left) * share, rect.center.dy);
}

Future<void> _pumpZoomable(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1000, 600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    testApp(
      home: Scaffold(
        body: MetricChart(
          title: 'Test',
          spots: _elevenSpots(),
          readoutAt: (index) => 'sample $index',
          zoomable: true,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('a pinch narrows the window around the fingers, never below a '
      'twentieth of the line, and a double tap shows the whole line again', (
    tester,
  ) async {
    await _pumpZoomable(tester);
    expect(_axis(tester), (min: 0.0, max: 10.0));
    expect(find.text(l10n.chartResetZoom), findsNothing);

    await _pinchOut(tester);

    var axis = _axis(tester);
    // The span tripled, so the window is roughly a third of the line, and
    // the fingers closed on the middle of the plot, so it lies around there.
    expect(axis.max - axis.min, inInclusiveRange(3, 5));
    expect(axis.min, greaterThan(2));
    expect(axis.max, lessThan(8));
    expect(find.text(l10n.chartResetZoom), findsOneWidget);

    // Pinching on and on stops at a twentieth of the line.
    await _pinchOut(tester, steps: 40);
    await _pinchOut(tester, steps: 40);
    axis = _axis(tester);
    expect(axis.max - axis.min, closeTo(0.5, 1e-6));

    await _doubleTap(tester, tester.getRect(find.byType(LineChart)).center);

    expect(_axis(tester), (min: 0.0, max: 10.0));
    expect(find.text(l10n.chartResetZoom), findsNothing);
    await tester.pumpAndSettle();
  });

  testWidgets('the "Whole ride" button shows the whole line again', (
    tester,
  ) async {
    await _pumpZoomable(tester);
    await _pinchOut(tester);
    expect(_axis(tester).max - _axis(tester).min, lessThan(10));

    await tester.tap(find.text(l10n.chartResetZoom));
    await tester.pumpAndSettle();

    expect(_axis(tester), (min: 0.0, max: 10.0));
  });

  testWidgets('one finger dragging sweeps the read-out over the whole line, '
      'and pans once zoomed', (tester) async {
    await _pumpZoomable(tester);

    // Over the whole line fl_chart's own pan keeps the finger: the read-out
    // follows it, and the axis stays put.
    final gesture = await tester.startGesture(
      _pixelOf(tester, _axis(tester), 2),
    );
    await tester.pump();
    expect(find.text('sample 2'), findsOneWidget);
    await gesture.moveTo(_pixelOf(tester, _axis(tester), 5));
    await tester.pump();
    expect(find.text('sample 5'), findsOneWidget);
    await gesture.up();
    await tester.pump();
    expect(_axis(tester), (min: 0.0, max: 10.0));

    await _pinchOut(tester);
    final zoomed = _axis(tester);

    // Zoomed, the same drag moves the window with the finger — dragging
    // left shows what lies to the right — and leaves no read-out behind.
    await tester.drag(find.byType(LineChart), const Offset(-200, 0));
    await tester.pump();
    final panned = _axis(tester);
    expect(panned.min, greaterThan(zoomed.min));
    expect(panned.max - panned.min, closeTo(zoomed.max - zoomed.min, 1e-6));
    expect(find.textContaining('sample'), findsNothing);

    // A tap still reads out the sample under the finger.
    final sample = panned.min.ceilToDouble() + 1;
    await tester.tapAt(_pixelOf(tester, panned, sample));
    await tester.pump();
    expect(find.text('sample ${sample.toInt()}'), findsOneWidget);
    // The double-tap recognizer waits for a second tap that never comes.
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('a ride chart hands the window on in metres and shows the one '
      'it is given', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final asked = <RideWindow?>[];
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
              window: (start: 2000, end: 8000),
              onWindow: asked.add,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Two to eight kilometres, on an axis in kilometres; the speed axis
    // still starts at zero.
    expect(_axis(tester), (min: 2.0, max: 8.0));
    final data = tester.widget<LineChart>(find.byType(LineChart)).data;
    expect(data.minY, 0);

    await _pinchOut(tester);

    // The chart asked for roughly a third of six kilometres, in metres, and
    // drew none of it: the window is the caller's.
    expect(asked, isNotEmpty);
    final last = asked.last!;
    expect(last.end - last.start, inInclusiveRange(1800, 3000));
    expect(last.start, greaterThan(2000));
    expect(_axis(tester), (min: 2.0, max: 8.0));

    await _doubleTap(tester, tester.getRect(find.byType(LineChart)).center);
    expect(asked.last, isNull);
    await tester.pumpAndSettle();
  });

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

  testWidgets('the elevation chart carries the marks in the axis unit and '
      'drops one beyond the line', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final samples = <ChartSample>[
      for (var m = 0; m <= 2000; m += 100)
        ChartSample(distanceM: m.toDouble(), speedMps: 6, elevationM: 400),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          metricUnits,
        ],
        child: testApp(
          home: Scaffold(
            body: RideElevationChart(
              samples: samples,
              marks: const <({double alongM, String label})>[
                (alongM: 500, label: 'Fountain'),
                (alongM: 5000, label: 'Beyond the ride'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final chart = tester.widget<MetricChart>(find.byType(MetricChart));
    expect(chart.marks, <ChartMark>[
      (x: 0.5, label: 'Fountain'),
      (x: 5, label: 'Beyond the ride'),
    ]);
    // Only the one on the line is drawn, and the axis still ends at the
    // ride's end.
    final data = tester.widget<LineChart>(find.byType(LineChart)).data;
    expect(data.extraLinesData.verticalLines.map((l) => l.x), <double>[0.5]);
    expect(data.maxX, 2);
  });

  testWidgets('the read-out names the mark under the finger', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      testApp(
        home: Scaffold(
          body: MetricChart(
            title: 'Test',
            spots: <FlSpot>[
              for (var x = 0; x <= 10; x++) FlSpot(x.toDouble(), 100),
            ],
            readoutAt: (index) => 'sample $index',
            marks: const <ChartMark>[(x: 5, label: 'Café')],
          ),
        ),
      ),
    );
    await tester.pump();

    // The plot runs from the reserved axis width to the right edge; the
    // middle of it is the sixth sample, right on the mark.
    final rect = tester.getRect(find.byType(LineChart));
    final chart = tester.widget<MetricChart>(find.byType(MetricChart));
    final left = rect.left + chart.leftReservedSize;
    await tester.tapAt(Offset((left + rect.right) / 2, rect.center.dy));
    await tester.pump();
    expect(find.text('sample 5 · Café'), findsOneWidget);

    // A sample well away from the mark reads plainly.
    await tester.tapAt(
      Offset(left + (rect.right - left) * 0.2, rect.center.dy),
    );
    await tester.pump();
    expect(find.text('sample 2'), findsOneWidget);
  });
}

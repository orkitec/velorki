import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/shared/presentation/metric_chart.dart';

import 'package:velorki/features/shared/presentation/adaptive_docking_sheet.dart';
import 'package:velorki/features/shared/presentation/swipe_pages.dart';

import '../../support/app.dart';

/// The samples of an eleven-point chart, one every unit of x.
List<FlSpot> _elevenSpots() => <FlSpot>[
  for (var x = 0; x <= 10; x++) FlSpot(x.toDouble(), 100 + x * 3.0),
];

/// Where sample [x] of the chart, on an axis running [min] to [max], is on
/// screen.
Offset _pixelOf(
  WidgetTester tester,
  double x, {
  double min = 0,
  double max = 10,
}) {
  final rect = tester.getRect(find.byType(LineChart));
  final chart = tester.widget<MetricChart>(find.byType(MetricChart));
  final left = rect.left + chart.leftReservedSize;
  return Offset(
    left + (rect.right - left) * (x - min) / (max - min),
    rect.center.dy,
  );
}

/// Two fingers a hundred pixels apart at the chart's middle, moving apart.
Future<void> _pinchOut(WidgetTester tester) async {
  final centre = tester.getRect(find.byType(LineChart)).center;
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
  await tester.pump();
}

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

  group('the finger on the line', () {
    Future<List<int?>> pumpChart(
      WidgetTester tester, {
      Widget Function(Widget chart)? around,
    }) async {
      final touched = <int?>[];
      final chart = MetricChart(
        title: 'Elevation',
        spots: _elevenSpots(),
        readoutAt: (i) => 'sample $i',
        zoomable: true,
        onTouched: touched.add,
      );
      await tester.binding.setSurfaceSize(const Size(500, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        testApp(home: Scaffold(body: around?.call(chart) ?? chart)),
      );
      await tester.pump();
      return touched;
    }

    testWidgets('reports the sample a finger lands and sweeps on, and null '
        'once it lifts; the read-out stays', (tester) async {
      final touched = await pumpChart(tester);

      final finger = await tester.startGesture(_pixelOf(tester, 2));
      await tester.pump();
      for (final x in <double>[3, 4, 5, 6]) {
        await finger.moveTo(_pixelOf(tester, x));
        await tester.pump();
      }
      expect(touched, <int?>[2, 3, 4, 5, 6]);
      await finger.up();
      await tester.pump();
      expect(touched.last, isNull);
      expect(find.text('sample 6'), findsOneWidget);
      // The double tap waits for a second tap that never comes.
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('a pinch takes the sample away and reports so', (tester) async {
      final touched = await pumpChart(tester);

      await _pinchOut(tester);

      expect(touched, isNotEmpty);
      expect(touched.last, isNull);
      expect(find.textContaining('sample'), findsNothing);
      expect(find.text(l10n.chartResetZoom), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('a vertical drag on the chart scrolls the page it is on', (
      tester,
    ) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final touched = await pumpChart(
        tester,
        around: (chart) => ListView(
          controller: scroll,
          children: [chart, const SizedBox(height: 2000)],
        ),
      );

      // A finger moves a little at a time: the scroll view's drag clears
      // its slop long before the chart's scale recognizer clears its own.
      final finger = await tester.startGesture(_pixelOf(tester, 4));
      for (var i = 0; i < 15; i++) {
        await finger.moveBy(const Offset(0, -10));
        await tester.pump();
      }
      await finger.up();
      await tester.pump();

      expect(scroll.offset, greaterThan(100));
      // The landing read out where the finger came down, and nothing swept.
      expect(touched.whereType<int>().toSet(), hasLength(1));
      expect(touched.last, isNull);
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('in a sheet turned sideways, whose drag runs along the x '
        'axis, a sweep still reads out', (tester) async {
      final touched = await pumpChart(
        tester,
        // The landscape sheet: turned a quarter, its content turned back.
        around: (chart) => QuarterTurnedFrame(
          quarterTurns: 1,
          child: ListView(
            children: [
              SizedBox(
                height: 450,
                child: QuarterTurnedFrame(quarterTurns: 3, child: chart),
              ),
              const SizedBox(height: 2000),
            ],
          ),
        ),
      );

      final finger = await tester.startGesture(_pixelOf(tester, 2));
      await tester.pump();
      for (var i = 0; i < 20; i++) {
        await finger.moveBy(const Offset(8, 0));
        await tester.pump();
      }
      await finger.up();
      await tester.pump(const Duration(milliseconds: 400));

      expect(touched.whereType<int>().toSet().length, greaterThan(2));
      expect(touched.last, isNull);
    });

    testWidgets('on a page that swipes sideways, a zoomed chart pans with one '
        'finger instead of turning the page', (tester) async {
      var page = 0;
      await pumpChart(
        tester,
        around: (chart) => StatefulBuilder(
          builder: (context, setState) => SwipePages(
            page: page,
            onPage: (next) => setState(() => page = next),
            children: [chart, const Text('second')],
          ),
        ),
      );
      await _pinchOut(tester);
      final zoomed = tester.widget<LineChart>(find.byType(LineChart)).data;

      await tester.fling(find.byType(LineChart), const Offset(-200, 0), 800);
      await tester.pumpAndSettle();

      expect(page, 0);
      final panned = tester.widget<LineChart>(find.byType(LineChart)).data;
      expect(panned.minX, greaterThan(zoomed.minX));
    });
  });
}

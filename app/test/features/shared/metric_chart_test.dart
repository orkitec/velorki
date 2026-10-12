import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/shared/presentation/metric_chart.dart';

import 'package:velorki/features/shared/presentation/adaptive_docking_sheet.dart';
import 'package:velorki/features/shared/presentation/swipe_pages.dart';

import '../../support/app.dart';
import '../../support/chart_cursor.dart';

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

  group('the cursor', () {
    Future<ValueNotifier<double?>> pumpChart(
      WidgetTester tester, {
      Widget Function(Widget chart)? around,
    }) async {
      final cursor = ValueNotifier<double?>(null);
      addTearDown(cursor.dispose);
      final chart = MetricChart(
        title: 'Elevation',
        spots: _elevenSpots(),
        readoutAt: (i) => 'sample $i',
        zoomable: true,
        cursor: cursor,
      );
      await tester.binding.setSurfaceSize(const Size(500, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        testApp(home: Scaffold(body: around?.call(chart) ?? chart)),
      );
      await tester.pump();
      return cursor;
    }

    /// The window the chart shows.
    ({double minX, double maxX}) shown(WidgetTester tester) {
      final data = tester.widget<LineChart>(find.byType(LineChart)).data;
      return (minX: data.minX, maxX: data.maxX);
    }

    testWidgets('a tap puts it there, with its handle and the read-out, and '
        'it stays after the finger lifts', (tester) async {
      final cursor = await pumpChart(tester);
      expect(chartCursorHandles, findsNothing);

      await tester.tapAt(_pixelOf(tester, 3));
      await tester.pump();
      expect(cursor.value, closeTo(3, 0.01));
      expect(find.text('sample 3'), findsOneWidget);
      expect(chartCursorHandles, findsOneWidget);
      // The handle sits on the cursor's x, over the plot.
      expect(
        tester.getCenter(chartCursorHandles).dx,
        closeTo(_pixelOf(tester, 3).dx, 0.5),
      );
      expect(
        tester.getRect(chartCursorHandles).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(LineChart)).top),
      );

      await tester.pump(const Duration(seconds: 5));
      expect(cursor.value, closeTo(3, 0.01));
      expect(find.text('sample 3'), findsOneWidget);
    });

    testWidgets('unzoomed, one finger sweeping the plot moves it', (
      tester,
    ) async {
      final cursor = await pumpChart(tester);

      final finger = await tester.startGesture(_pixelOf(tester, 2));
      await tester.pump();
      for (final x in <double>[3, 4, 5, 6]) {
        await finger.moveTo(_pixelOf(tester, x));
        await tester.pump();
      }
      await finger.up();
      await tester.pump(const Duration(milliseconds: 400));

      expect(cursor.value, closeTo(6, 0.01));
      expect(find.text('sample 6'), findsOneWidget);
      expect(chartCursorHandles, findsOneWidget);
    });

    testWidgets('zoomed, one finger on the plot pans while the handle moves '
        'the cursor', (tester) async {
      final cursor = await pumpChart(tester);
      await _pinchOut(tester);
      await tester.pump(const Duration(milliseconds: 400));
      final zoomed = shown(tester);
      expect(zoomed.maxX - zoomed.minX, lessThan(10));

      final middle = (zoomed.minX + zoomed.maxX) / 2;
      await tester.tapAt(
        _pixelOf(tester, middle, min: zoomed.minX, max: zoomed.maxX),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(cursor.value, closeTo(middle, 0.01));

      // A drag on the plot pans; the cursor stays on its place on the line.
      final plot = _pixelOf(tester, middle, min: zoomed.minX, max: zoomed.maxX);
      await tester.dragFrom(plot + const Offset(0, 30), const Offset(-60, 0));
      await tester.pump(const Duration(milliseconds: 400));
      final panned = shown(tester);
      expect(panned.minX, greaterThan(zoomed.minX));
      expect(cursor.value, closeTo(middle, 0.01));

      // The handle drags it like a slider, by as much of the window as the
      // finger moves across the plot.
      final before = cursor.value!;
      final perPixel =
          (panned.maxX - panned.minX) /
          (_pixelOf(
                tester,
                panned.maxX,
                min: panned.minX,
                max: panned.maxX,
              ).dx -
              _pixelOf(
                tester,
                panned.minX,
                min: panned.minX,
                max: panned.maxX,
              ).dx);
      await dragChartCursor(tester, const Offset(40, 0));
      expect(cursor.value, closeTo(before + 40 * perPixel, 0.02));
      expect(shown(tester), panned, reason: 'the handle does not pan');
    });

    testWidgets('a pan that leaves it outside the window takes it to the '
        'nearest edge', (tester) async {
      final cursor = await pumpChart(tester);
      await _pinchOut(tester);
      await tester.pump(const Duration(milliseconds: 400));
      final zoomed = shown(tester);
      await tester.tapAt(
        _pixelOf(tester, zoomed.minX + 0.1, min: zoomed.minX, max: zoomed.maxX),
      );
      await tester.pump(const Duration(milliseconds: 400));

      // The line moves left under the finger: the window moves right, past
      // the cursor.
      final plot = _pixelOf(
        tester,
        (zoomed.minX + zoomed.maxX) / 2,
        min: zoomed.minX,
        max: zoomed.maxX,
      );
      await tester.dragFrom(plot + const Offset(0, 30), const Offset(-120, 0));
      await tester.pump(const Duration(milliseconds: 400));

      final panned = shown(tester);
      expect(panned.minX, greaterThan(zoomed.minX + 0.1));
      expect(cursor.value, closeTo(panned.minX, 1e-9));
      expect(chartCursorHandles, findsOneWidget);
    });

    testWidgets('a pinch zooms and leaves it where it was', (tester) async {
      final cursor = await pumpChart(tester);
      await tester.tapAt(_pixelOf(tester, 5));
      await tester.pump(const Duration(milliseconds: 400));

      await _pinchOut(tester);
      await tester.pump(const Duration(milliseconds: 400));

      expect(shown(tester).maxX - shown(tester).minX, lessThan(10));
      expect(cursor.value, closeTo(5, 0.01));
      expect(find.text(l10n.chartResetZoom), findsOneWidget);
    });

    testWidgets('a double tap on the handle hides it', (tester) async {
      final cursor = await pumpChart(tester);
      await tester.tapAt(_pixelOf(tester, 4));
      await tester.pump(const Duration(milliseconds: 400));

      await doubleTapChartCursor(tester);

      expect(cursor.value, isNull);
      expect(chartCursorHandles, findsNothing);
      expect(find.textContaining('sample'), findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('a screen reader steps it by a hundredth of the window', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final cursor = await pumpChart(tester);
      await tester.tapAt(_pixelOf(tester, 4));
      await tester.pump(const Duration(milliseconds: 400));

      final handle = find.semantics.byLabel(l10n.chartCursor);
      expect(handle, findsOne);
      expect(
        tester.getSemantics(find.bySemanticsLabel(l10n.chartCursor)),
        matchesSemantics(
          label: l10n.chartCursor,
          value: 'sample 4',
          isSlider: true,
          hasIncreaseAction: true,
          hasDecreaseAction: true,
        ),
      );
      tester.semantics.performAction(handle, SemanticsAction.increase);
      await tester.pump();
      expect(cursor.value, closeTo(4.1, 1e-6));
      tester.semantics.performAction(handle, SemanticsAction.decrease);
      tester.semantics.performAction(handle, SemanticsAction.decrease);
      await tester.pump();
      expect(cursor.value, closeTo(3.9, 1e-6));
      semantics.dispose();
    });

    testWidgets('a vertical drag on the chart scrolls the page it is on, and '
        'puts no cursor on the line', (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final cursor = await pumpChart(
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
      await tester.pump(const Duration(milliseconds: 400));

      expect(scroll.offset, greaterThan(100));
      expect(cursor.value, isNull);
    });

    testWidgets('in a sheet turned sideways, whose drag runs along the x '
        'axis, a sweep still moves it', (tester) async {
      final cursor = await pumpChart(
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

      expect(cursor.value, greaterThan(3));
      // And the handle, turned with the sheet, drags it too.
      final before = cursor.value!;
      await dragChartCursor(tester, const Offset(-40, 0));
      expect(cursor.value, lessThan(before - 0.5));
    });

    testWidgets('on a page that swipes sideways, a zoomed chart pans with one '
        'finger and the handle moves the cursor, neither turning the page', (
      tester,
    ) async {
      var page = 0;
      final cursor = await pumpChart(
        tester,
        around: (chart) => StatefulBuilder(
          builder: (context, setState) => SwipePages(
            page: page,
            onPage: (next) => setState(() => page = next),
            children: [chart, const Text('second')],
          ),
        ),
      );
      await tester.tapAt(_pixelOf(tester, 5));
      await tester.pump(const Duration(milliseconds: 400));
      await dragChartCursor(tester, const Offset(-60, 0));
      await tester.pumpAndSettle();
      expect(page, 0);
      expect(cursor.value, lessThan(4.5));

      await _pinchOut(tester);
      final zoomed = tester.widget<LineChart>(find.byType(LineChart)).data;

      await tester.fling(find.byType(LineChart), const Offset(-200, 0), 800);
      await tester.pumpAndSettle();

      expect(page, 0);
      final panned = tester.widget<LineChart>(find.byType(LineChart)).data;
      expect(panned.minX, greaterThan(zoomed.minX));
    });

    testWidgets('without a cursor handed in, the chart keeps its own', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(
          home: Scaffold(
            body: MetricChart(
              title: 'Elevation',
              spots: _elevenSpots(),
              readoutAt: (i) => 'sample $i',
            ),
          ),
        ),
      );
      await tester.tapAt(_pixelOf(tester, 7));
      await tester.pump();
      expect(find.text('sample 7'), findsOneWidget);
      expect(chartCursorHandles, findsOneWidget);
    });
  });
}

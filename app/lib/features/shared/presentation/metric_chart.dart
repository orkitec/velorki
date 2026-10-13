import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/units/units.dart' as units;
import '../../../l10n/generated/app_localizations.dart';
import 'chart_gestures.dart';
import 'stat_tile.dart';

/// One measurement over the distance: the elevation of a route, the speed of a
/// ride. An upper-case caption, an accent line over a soft fill, and a read-out
/// of whatever the finger rests on.
///
/// The samples are thinned before they get here — fl_chart draws every point it
/// is given — and the axes carry bare numbers, because the unit belongs in the
/// caller's own labels.
///
/// A [zoomable] chart shows a [window] of its x axis: a horizontal pinch
/// zooms around the fingers, a drag while zoomed pans, a double tap or the
/// [resetLabel] button at the top right shows everything again. With
/// [onWindow] the caller owns the window and several charts can share one;
/// without it the chart keeps its own.
///
/// A tap or a sweep puts the cursor on the line, a handle on top drags it,
/// and the read-out says the sample nearest to it. With [cursor] the caller
/// owns it, in metres, and several charts can share one, as the rider badge
/// on the map does.
///
/// The touches are [ChartGestures]', with fl_chart's own off; its doc says
/// why.
class MetricChart extends StatelessWidget {
  /// Creates the chart.
  const MetricChart({
    required this.title,
    required this.spots,
    required this.readoutAt,
    super.key,
    this.height = 160,
    this.yAxis = paddedYAxis,
    this.leftReservedSize = 40,
    this.highlight,
    this.marks = const <ChartMark>[],
    this.bands = const <ChartBand>[],
    this.zoomable = false,
    this.window,
    this.onWindow,
    this.cursor,
    this.metresPerUnit = 1,
    this.cursorLabel,
    this.resetLabel,
  });

  /// The caption above the chart; upper-cased by [SectionCaption].
  final String title;

  /// The line, x in the rider's distance unit and y in the value's.
  final List<FlSpot> spots;

  /// What to show next to the caption while the finger rests on the sample
  /// [index].
  final String Function(int index) readoutAt;

  /// Height of the chart area, caption excluded.
  final double height;

  /// The y axis to draw for a line whose visible part runs from [lowest] to
  /// [highest]; asked again whenever the window changes, so the line fills
  /// the height. [paddedYAxis] when left out.
  final ChartAxis Function(double lowest, double highest) yAxis;

  /// How much room the y axis labels get.
  final double leftReservedSize;

  /// A stretch of the x axis to shade behind the line, in the axis' unit:
  /// the split or the climb the rider picked. Clipped to the line; `null`
  /// shades nothing.
  final ChartWindow? highlight;

  /// Named places along the x axis, each drawn as a thin dashed line with
  /// its name at the top: the points of interest a ride passed. Marks
  /// outside the line are not drawn; none of them widens the axis.
  final List<ChartMark> marks;

  /// Stretches of the x axis, in the axis' unit, each with the colour the
  /// fill under the line takes there: how steep the road is, the wind or
  /// the rain along it, as the route on the map is coloured. Where no band
  /// lies the fill is the usual one; none at all leaves it whole.
  final List<ChartBand> bands;

  /// Whether a pinch zooms the x axis.
  final bool zoomable;

  /// The stretch of the x axis shown, in the axis' unit; `null` for all of
  /// it. Only read while [onWindow] is set.
  final ChartWindow? window;

  /// Called with the window a pinch, a drag or a double tap asks for, `null`
  /// for the whole line. With it the chart shows [window] and nothing else;
  /// without it the chart keeps its own window.
  final ValueChanged<ChartWindow?>? onWindow;

  /// Where the cursor stands, in metres along the line, `null` while it is
  /// hidden; see [ChartGestures.cursor]. The chart keeps its own when left
  /// out.
  final ValueNotifier<double?>? cursor;

  /// How many metres one unit of the x axis is; see
  /// [ChartGestures.metresPerUnit].
  final double metresPerUnit;

  /// What a screen reader calls the cursor's handle, "Position on the ride"
  /// when left out.
  final String? cursorLabel;

  /// The label of the button that shows the whole line again while zoomed,
  /// "Whole ride" when left out.
  final String? resetLabel;

  /// The height of the x axis labels under the plot.
  static const double _bottomReservedSize = 24;

  @override
  Widget build(BuildContext context) {
    if (spots.length < 2) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return ChartGestures(
      extent: (start: spots.first.x, end: spots.last.x),
      zoomable: zoomable,
      window: window,
      onWindow: onWindow,
      leftInset: leftReservedSize,
      bottomInset: _bottomReservedSize,
      cursor: cursor,
      metresPerUnit: metresPerUnit,
      cursorLabel: cursorLabel ?? l10n.chartCursor,
      cursorValue: (x) {
        final index = _nearest(x);
        return index == null ? '' : readoutAt(index);
      },
      resetLabel: resetLabel ?? l10n.chartResetZoom,
      header: _header,
      builder: _plot,
    );
  }

  /// The sample nearest to [x] on the axis; `null` when every sample is a
  /// gap.
  int? _nearest(double x) {
    int? nearest;
    var distance = double.infinity;
    for (final (i, spot) in spots.indexed) {
      if (spot.isNull()) continue;
      final d = (spot.x - x).abs();
      if (d < distance) {
        distance = d;
        nearest = i;
      }
    }
    return nearest;
  }

  /// What the window shows of the x axis, and the marks inside it.
  ({double minX, double maxX, List<ChartMark> marks}) _visible(
    ChartWindow? window,
  ) {
    final minX = window?.start ?? spots.first.x;
    final maxX = window?.end ?? spots.last.x;
    return (
      minX: minX,
      maxX: maxX,
      marks: <ChartMark>[
        for (final mark in marks)
          if (mark.x >= minX && mark.x <= maxX) mark,
      ],
    );
  }

  /// The y axis for the samples in the window, so a zoomed line fills the
  /// height; a window between two samples falls back to the whole line.
  ChartAxis _yAxis(ChartWindow? window, double minX, double maxX) {
    double? lowest;
    double? highest;
    for (final spot in spots) {
      if (spot.isNull()) continue;
      if (window != null && (spot.x < minX || spot.x > maxX)) continue;
      if (lowest == null || spot.y < lowest) lowest = spot.y;
      if (highest == null || spot.y > highest) highest = spot.y;
    }
    if (lowest == null || highest == null) {
      for (final spot in spots) {
        if (spot.isNull()) continue;
        if (lowest == null || spot.y < lowest) lowest = spot.y;
        if (highest == null || spot.y > highest) highest = spot.y;
      }
    }
    return yAxis(lowest ?? 0, highest ?? 0);
  }

  /// The caption, and the read-out of the sample nearest to the [cursor].
  Widget _header(BuildContext context, ChartWindow? window, double? cursor) {
    final theme = Theme.of(context);
    final colors = theme.velorki;
    final (:minX, :maxX, :marks) = _visible(window);
    final touched = cursor == null ? null : _nearest(cursor);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: SectionCaption(title)),
            if (touched != null && touched < spots.length)
              Flexible(
                child: Text(
                  _readout(touched, marks, maxX - minX),
                  style: theme.textTheme.statMedium.copyWith(
                    color: colors.accent,
                  ),
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  /// The plot of the window shown.
  Widget _plot(BuildContext context, ChartWindow? window) {
    final theme = Theme.of(context);
    final colors = theme.velorki;
    final (:minX, :maxX, :marks) = _visible(window);
    final axis = _yAxis(window, minX, maxX);
    // The band never widens the axis: it is cut to the window, and a stretch
    // that lies wholly outside it is not drawn at all.
    final band = highlight;
    final bandStart = band?.start.clamp(minX, maxX);
    final bandEnd = band?.end.clamp(minX, maxX);
    final markLabelStyle = theme.textTheme.labelSmall?.copyWith(
      color: colors.accent,
    );
    return SizedBox(
      height: height,
      child: LineChart(
        // A pinch wants the axis where the fingers are, not on its
        // way there.
        duration: zoomable ? Duration.zero : const Duration(milliseconds: 150),
        LineChartData(
          minY: axis.min,
          maxY: axis.max,
          minX: minX,
          maxX: maxX,
          // A windowed line runs on past both edges; it is cut
          // there rather than drawn over the axis labels.
          clipData: window == null
              ? const FlClipData.none()
              : const FlClipData.all(),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          extraLinesData: ExtraLinesData(
            verticalLines: [
              for (final mark in marks)
                VerticalLine(
                  x: mark.x,
                  color: colors.accent.withValues(alpha: 0.6),
                  strokeWidth: 1,
                  dashArray: const <int>[4, 3],
                  label: VerticalLineLabel(
                    show: true,
                    // The name hangs off the line towards the
                    // middle of the chart, so it never runs off
                    // the edge.
                    alignment: mark.x - minX > (maxX - minX) * 0.7
                        ? Alignment.topLeft
                        : Alignment.topRight,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    style: markLabelStyle,
                    labelResolver: (_) => mark.label,
                  ),
                ),
            ],
          ),
          rangeAnnotations: RangeAnnotations(
            verticalRangeAnnotations: [
              if (bandStart != null && bandEnd != null && bandEnd > bandStart)
                VerticalRangeAnnotation(
                  x1: bandStart,
                  x2: bandEnd,
                  color: colors.accent.withValues(alpha: 0.18),
                ),
            ],
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                // Only the evenly spaced steps: the ends of the axis
                // are rarely round and sit on top of the step
                // beside them ("13" over "13.6").
                minIncluded: false,
                maxIncluded: false,
                getTitlesWidget: (_, meta) => _axisLabel(context, meta),
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: leftReservedSize,
                // Round steps, about one per 40 points of height;
                // left to itself fl_chart halves the range
                // ("429.1").
                interval: niceAxisStep(
                  axis.max - axis.min,
                  math.max(2, height ~/ 40),
                ),
                // Only the evenly spaced steps: the ends of the axis
                // are rarely round and sit on top of the step
                // beside them ("13" over "13.6").
                minIncluded: false,
                maxIncluded: false,
                getTitlesWidget: (_, meta) => _axisLabel(context, meta),
              ),
            ),
          ),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: false,
              barWidth: 2.5,
              color: colors.accent,
              dotData: const FlDotData(show: false),
              belowBarData: _fill(colors.chartFill),
            ),
          ],
        ),
      ),
    );
  }

  /// The fill under the line: [bands] where there are some, the usual
  /// [plain] fill elsewhere.
  BarAreaData _fill(Color plain) {
    double? first;
    double? last;
    for (final spot in spots) {
      if (spot.isNull()) continue;
      if (first == null || spot.x < first) first = spot.x;
      if (last == null || spot.x > last) last = spot.x;
    }
    final gradient = first == null || last == null
        ? null
        : chartBandsGradient(start: first, end: last, bands: bands, gap: plain);
    return gradient == null
        ? BarAreaData(show: true, color: plain)
        : BarAreaData(show: true, gradient: gradient);
  }

  /// The read-out for the sample [index], with the name of a mark the finger
  /// is on — within [chartMarkReadoutShare] of the axis [width] — after it.
  String _readout(int index, List<ChartMark> marks, double width) {
    final text = readoutAt(index);
    final x = spots[index].x;
    for (final mark in marks) {
      if ((mark.x - x).abs() <= width * chartMarkReadoutShare) {
        return '$text · ${mark.label}';
      }
    }
    return text;
  }

  /// One axis number, in the quiet label style the rest of the app uses.
  Widget _axisLabel(BuildContext context, TitleMeta meta) {
    final theme = Theme.of(context);
    return SideTitleWidget(
      meta: meta,
      child: Text(
        meta.formattedValue,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// One mark on a [MetricChart]: where on the x axis, and what to call it.
typedef ChartMark = ({double x, String label});

/// A stretch of a [MetricChart]'s x axis, in the axis' unit.
typedef ChartWindow = ({double start, double end});

/// A stretch of a [MetricChart]'s x axis, in the axis' unit, and the colour
/// of the fill under the line there.
typedef ChartBand = ({double start, double end, Color colour});

/// A stretch of a route or a ride in metres from the start, and the colour
/// the charts along it fill it with.
typedef DistanceBand = ({double start, double end, Color colour});

/// How opaque a band's colour is under the line: enough to read the colour,
/// little enough that the line on top stays the thing read.
const double chartBandAlpha = 0.5;

/// The fill of a line from [start] to [end] on the x axis in [bands]'
/// colours, as a left-to-right gradient with hard stops, [gap] where no
/// band lies; `null` without bands.
///
/// The stops are placed along the line's own extent, from its first point
/// to its last, as that is the box fl_chart spreads a fill's gradient over.
/// The box is laid out by the same scale as the line, so the colours stay
/// on their stretches of the line however the chart is zoomed or panned.
LinearGradient? chartBandsGradient({
  required double start,
  required double end,
  required List<ChartBand> bands,
  required Color gap,
}) {
  final width = end - start;
  if (bands.isEmpty || width <= 0) return null;
  final colours = <Color>[];
  final stops = <double>[];
  void add(double from, double to, Color colour) {
    colours
      ..add(colour)
      ..add(colour);
    stops
      ..add((from - start) / width)
      ..add((to - start) / width);
  }

  final sorted = List<ChartBand>.of(bands)
    ..sort((a, b) => a.start.compareTo(b.start));
  var at = start;
  for (final band in sorted) {
    final from = band.start.clamp(at, end);
    final to = band.end.clamp(from, end);
    if (to <= from) continue;
    if (from > at) add(at, from, gap);
    add(from, to, band.colour.withValues(alpha: chartBandAlpha));
    at = to;
  }
  if (colours.isEmpty) return null;
  if (at < end) add(at, end, gap);
  return LinearGradient(colors: colours, stops: stops);
}

/// [bands] on a chart's x axis, which runs in the rider's distance unit,
/// converted as the samples are.
List<ChartBand> chartBands(units.UnitSystem system, List<DistanceBand> bands) =>
    <ChartBand>[
      for (final band in bands)
        (
          start: units.distanceToDisplay(system, band.start),
          end: units.distanceToDisplay(system, band.end),
          colour: band.colour,
        ),
    ];

/// Where a [MetricChart]'s y axis runs from and to.
typedef ChartAxis = ({double min, double max});

/// A stretch of a route or a ride the charts along it are zoomed to, in
/// metres from the start; one for all of them, so a pinch on one zooms the
/// others to the same road.
typedef DistanceWindow = ({double start, double end});

/// [window] on a chart's x axis, which runs in the rider's distance unit,
/// converted as the samples are; `null` for the whole line.
ChartWindow? chartWindow(units.UnitSystem system, DistanceWindow? window) =>
    window == null
    ? null
    : (
        start: units.distanceToDisplay(system, window.start),
        end: units.distanceToDisplay(system, window.end),
      );

/// [onWindow] as a [MetricChart] calls it: with the window in the axis'
/// unit, handed on in metres. `null` when there is nobody to hand it to, so
/// the chart keeps its own window.
ValueChanged<ChartWindow?>? distanceWindowCallback(
  units.UnitSystem system,
  ValueChanged<DistanceWindow?>? onWindow,
) => onWindow == null
    ? null
    : (window) => onWindow(
        window == null
            ? null
            : (
                start: units.displayToMeters(system, window.start),
                end: units.displayToMeters(system, window.end),
              ),
      );

/// How close to a mark, as a share of the axis width, the touched sample
/// has to be for the mark's name to join the read-out.
const double chartMarkReadoutShare = 0.01;

/// The narrowest window a pinch can reach, as a share of the whole line.
const double chartMinWindowShare = 0.05;

/// A tenth of the range of air above and below the line; a flat line still
/// needs an axis to sit in the middle of.
ChartAxis paddedYAxis(double lowest, double highest) {
  final padding = ((highest - lowest) * 0.1).clamp(0.5, double.infinity);
  return (min: lowest - padding, max: highest + padding);
}

/// A step for an axis spanning [range] that lands on round numbers: 1, 2 or
/// 5 times a power of ten, giving at most about [count] steps.
double niceAxisStep(double range, int count) {
  if (range <= 0 || count < 1) return 1;
  final raw = range / count;
  final magnitude = math
      .pow(10, (math.log(raw) / math.ln10).floor())
      .toDouble();
  final norm = raw / magnitude;
  final nice = norm <= 1
      ? 1
      : norm <= 2
      ? 2
      : norm <= 5
      ? 5
      : 10;
  return nice * magnitude;
}

/// The y axis of a height chart: five to a hundred metres of air around a
/// line running from [lowest] to [highest], said in the height unit of
/// [system].
ChartAxis elevationAxis(
  units.UnitSystem system,
  double lowest,
  double highest,
) {
  final padding = ((highest - lowest) * 0.1).clamp(
    units.elevationToDisplay(system, 5),
    units.elevationToDisplay(system, 100),
  );
  return (min: lowest - padding, max: highest + padding);
}

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
/// The touches are [ChartGestures]', with fl_chart's own off; its doc says
/// why. While a finger is on the line, [onTouched] tells the caller which
/// sample it is on, for the rider dot on the map.
class MetricChart extends StatefulWidget {
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
    this.zoomable = false,
    this.window,
    this.onWindow,
    this.onTouched,
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

  /// Whether a pinch zooms the x axis.
  final bool zoomable;

  /// The stretch of the x axis shown, in the axis' unit; `null` for all of
  /// it. Only read while [onWindow] is set.
  final ChartWindow? window;

  /// Called with the window a pinch, a drag or a double tap asks for, `null`
  /// for the whole line. With it the chart shows [window] and nothing else;
  /// without it the chart keeps its own window.
  final ValueChanged<ChartWindow?>? onWindow;

  /// Called with the index of the sample a finger lands or sweeps on, and
  /// with `null` once no finger is on one: lifted, or taken by a pinch or a
  /// pan. The read-out itself stays after a lift; this does not.
  final ValueChanged<int?>? onTouched;

  /// The label of the button that shows the whole line again while zoomed,
  /// "Whole ride" when left out.
  final String? resetLabel;

  @override
  State<MetricChart> createState() => _MetricChartState();
}

/// One mark on a [MetricChart]: where on the x axis, and what to call it.
typedef ChartMark = ({double x, String label});

/// A stretch of a [MetricChart]'s x axis, in the axis' unit.
typedef ChartWindow = ({double start, double end});

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

/// [onCursor] as a [MetricChart] calls it: with a sample's index, handed on
/// as the sample's distance along the line, [distanceOf] it; `null` when
/// there is nobody to hand it to.
ValueChanged<int?>? cursorCallback(
  ValueChanged<double?>? onCursor,
  double Function(int index) distanceOf,
) => onCursor == null
    ? null
    : (index) => onCursor(index == null ? null : distanceOf(index));

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

class _MetricChartState extends State<MetricChart> {
  int? _touched;

  // Whether a finger is on the sample [_touched], as against a read-out
  // that stayed after the finger lifted.
  bool _held = false;

  @override
  void didUpdateWidget(MetricChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.spots, widget.spots) && _touched != null) {
      _touched = null;
      _report(null);
    }
  }

  @override
  void dispose() {
    // A chart that goes while a finger is on it still owes its caller the
    // lift; the caller only draws with it, it does not build.
    if (_held) widget.onTouched?.call(null);
    super.dispose();
  }

  void _report(int? index) {
    _held = index != null;
    widget.onTouched?.call(index);
  }

  /// Reads out the sample nearest to [x] on the axis.
  void _readAt(double x) {
    int? nearest;
    var distance = double.infinity;
    for (final (i, spot) in widget.spots.indexed) {
      if (spot.isNull()) continue;
      final d = (spot.x - x).abs();
      if (d < distance) {
        distance = d;
        nearest = i;
      }
    }
    if (nearest == null || (nearest == _touched && _held)) return;
    if (nearest != _touched) setState(() => _touched = nearest);
    _report(nearest);
  }

  void _endRead({required bool lifted}) {
    // A lifted finger leaves its read-out; a pinch or a pan takes it.
    if (!lifted && _touched != null) setState(() => _touched = null);
    if (_held) _report(null);
  }

  @override
  Widget build(BuildContext context) {
    final spots = widget.spots;
    if (spots.length < 2) return const SizedBox.shrink();
    return ChartGestures(
      extent: (start: spots.first.x, end: spots.last.x),
      zoomable: widget.zoomable,
      window: widget.window,
      onWindow: widget.onWindow,
      leftInset: widget.leftReservedSize,
      onRead: _readAt,
      onReadEnd: _endRead,
      resetLabel:
          widget.resetLabel ?? AppLocalizations.of(context).chartResetZoom,
      header: _header,
      builder: _plot,
    );
  }

  /// What the window shows of the x axis, and the marks inside it.
  ({double minX, double maxX, List<ChartMark> marks}) _visible(
    ChartWindow? window,
  ) {
    final spots = widget.spots;
    final minX = window?.start ?? spots.first.x;
    final maxX = window?.end ?? spots.last.x;
    return (
      minX: minX,
      maxX: maxX,
      marks: <ChartMark>[
        for (final mark in widget.marks)
          if (mark.x >= minX && mark.x <= maxX) mark,
      ],
    );
  }

  /// The y axis for the samples in the window, so a zoomed line fills the
  /// height; a window between two samples falls back to the whole line.
  ChartAxis _yAxis(ChartWindow? window, double minX, double maxX) {
    final spots = widget.spots;
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
    return widget.yAxis(lowest ?? 0, highest ?? 0);
  }

  /// The caption, and the read-out of the sample touched.
  Widget _header(BuildContext context, ChartWindow? window) {
    final theme = Theme.of(context);
    final colors = theme.velorki;
    final spots = widget.spots;
    final (:minX, :maxX, :marks) = _visible(window);
    final touched = _touched;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: SectionCaption(widget.title)),
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
    final spots = widget.spots;
    final (:minX, :maxX, :marks) = _visible(window);
    final axis = _yAxis(window, minX, maxX);
    // The band never widens the axis: it is cut to the window, and a stretch
    // that lies wholly outside it is not drawn at all.
    final band = widget.highlight;
    final bandStart = band?.start.clamp(minX, maxX);
    final bandEnd = band?.end.clamp(minX, maxX);
    final markLabelStyle = theme.textTheme.labelSmall?.copyWith(
      color: colors.accent,
    );
    return SizedBox(
      height: widget.height,
      child: LineChart(
        // A pinch wants the axis where the fingers are, not on its
        // way there.
        duration: widget.zoomable
            ? Duration.zero
            : const Duration(milliseconds: 150),
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
                reservedSize: widget.leftReservedSize,
                // Round steps, about one per 40 points of height;
                // left to itself fl_chart halves the range
                // ("429.1").
                interval: niceAxisStep(
                  axis.max - axis.min,
                  math.max(2, widget.height ~/ 40),
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
              belowBarData: BarAreaData(show: true, color: colors.chartFill),
            ),
          ],
        ),
      ),
    );
  }

  /// The read-out for the sample [index], with the name of a mark the finger
  /// is on — within [chartMarkReadoutShare] of the axis [width] — after it.
  String _readout(int index, List<ChartMark> marks, double width) {
    final text = widget.readoutAt(index);
    final x = widget.spots[index].x;
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

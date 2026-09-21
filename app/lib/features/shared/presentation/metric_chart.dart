import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/units/units.dart' as units;
import '../../../l10n/generated/app_localizations.dart';
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
/// "Whole ride" button at the top right shows everything again. With
/// [onWindow] the caller owns the window and several charts can share one;
/// without it the chart keeps its own.
///
/// The touches are the chart's own rather than fl_chart's: its tap and pan
/// recognizers would sit inside ours and reach the pointer router first,
/// and a pinch clears the scale slop on the very move the pan clears its
/// own, so the pan would win every pinch on registration order. With
/// fl_chart's touch off, one [Listener] reads out the sample under a
/// landing finger at once, and one scale recognizer tells a sweep, a pan
/// and a pinch apart by how many fingers it has.
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

  @override
  State<MetricChart> createState() => _MetricChartState();
}

/// One mark on a [MetricChart]: where on the x axis, and what to call it.
typedef ChartMark = ({double x, String label});

/// A stretch of a [MetricChart]'s x axis, in the axis' unit.
typedef ChartWindow = ({double start, double end});

/// Where a [MetricChart]'s y axis runs from and to.
typedef ChartAxis = ({double min, double max});

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

  // The window last asked for; `null` for the whole line. The chart's own
  // when it keeps it, and a step ahead of [widget.window] when the caller
  // does, so two finger moves in one frame build on each other.
  ChartWindow? _window;

  // The window a pinch started from and where the fingers were, so the
  // stretch under them stays under them as they move.
  ChartWindow? _pinchFrom;
  double _pinchFocalX = 0;

  // How many fingers are on the chart: the first reads out, the second
  // takes the read-out away again.
  int _fingers = 0;

  // How wide the plot is on screen, as of the last build, for turning a
  // finger's pixels into the axis' unit.
  double _plotWidth = 0;

  bool get _controlled => widget.onWindow != null;

  @override
  void initState() {
    super.initState();
    _window = widget.window;
  }

  @override
  void didUpdateWidget(MetricChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.spots, widget.spots)) _touched = null;
    if (_controlled) _window = widget.window;
  }

  /// The whole line, from the first sample to the last.
  ChartWindow get _extent =>
      (start: widget.spots.first.x, end: widget.spots.last.x);

  /// The window as asked for, cut to the line; `null` when it is the whole
  /// line anyway.
  ChartWindow? _clamp(ChartWindow? window) {
    if (window == null) return null;
    final extent = _extent;
    final full = extent.end - extent.start;
    final width = (window.end - window.start).clamp(
      full * chartMinWindowShare,
      full,
    );
    if (width >= full || full <= 0) return null;
    final start = window.start.clamp(extent.start, extent.end - width);
    return (start: start, end: start + width);
  }

  /// The window drawn.
  ChartWindow? get _shown => _clamp(_controlled ? widget.window : _window);

  /// The window the fingers work from: the one last asked for.
  ChartWindow? get _current => _clamp(_window);

  void _setWindow(ChartWindow? window) {
    final next = _clamp(window);
    if (next == _current) return;
    _window = next;
    if (_controlled) {
      widget.onWindow!(next);
    } else {
      setState(() {});
    }
  }

  /// The plot's x of a pixel [dx] in the chart, 0 to 1 across the plot.
  double _plotShare(double dx) =>
      _plotWidth <= 0 ? 0 : (dx - widget.leftReservedSize) / _plotWidth;

  void _onPointerDown(PointerDownEvent event) {
    _fingers++;
    if (_fingers == 1) {
      _readAt(event.localPosition.dx);
    } else if (_touched != null) {
      // A second finger is a pinch on its way, not a place to read out.
      setState(() => _touched = null);
    }
  }

  void _onPointerUp(PointerEvent event) {
    if (_fingers > 0) _fingers--;
  }

  /// Reads out the sample nearest to the pixel [dx] in the chart, in the
  /// window shown.
  void _readAt(double dx) {
    final shown = _current;
    final minX = shown?.start ?? widget.spots.first.x;
    final maxX = shown?.end ?? widget.spots.last.x;
    final x = minX + _plotShare(dx) * (maxX - minX);
    int? nearest;
    var distance = double.infinity;
    for (final (i, spot) in widget.spots.indexed) {
      if (spot.isNull()) continue;
      if (shown != null && (spot.x < minX || spot.x > maxX)) continue;
      final d = (spot.x - x).abs();
      if (d < distance) {
        distance = d;
        nearest = i;
      }
    }
    if (nearest == null || nearest == _touched) return;
    setState(() => _touched = nearest);
  }

  void _onScaleStart(ScaleStartDetails details) {
    _pinchFrom = _current ?? _extent;
    _pinchFocalX = details.localFocalPoint.dx;
    // A pinch or a pan moves the line under the finger: whatever it landed
    // on is not what the rider is after.
    final moves =
        details.pointerCount >= 2 || (widget.zoomable && _current != null);
    if (moves && _touched != null) setState(() => _touched = null);
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount < 2) {
      // One finger: a sweep of the read-out over the whole line, a pan of
      // the window once zoomed.
      if (widget.zoomable && _current != null) {
        _pan(details.focalPointDelta.dx);
      } else {
        _readAt(details.localFocalPoint.dx);
      }
      return;
    }
    if (!widget.zoomable) return;
    final from = _pinchFrom;
    if (from == null || _plotWidth <= 0) return;
    final extent = _extent;
    final full = extent.end - extent.start;
    final fromWidth = from.end - from.start;
    final width = (fromWidth / details.horizontalScale).clamp(
      full * chartMinWindowShare,
      full,
    );
    // The point of the line the fingers closed on stays under them.
    final anchor = from.start + _plotShare(_pinchFocalX) * fromWidth;
    final start = anchor - _plotShare(details.localFocalPoint.dx) * width;
    _setWindow((start: start, end: start + width));
  }

  void _onScaleEnd(ScaleEndDetails details) => _pinchFrom = null;

  /// Moves the window by a finger's [dx] pixels, the line following the
  /// finger.
  void _pan(double dx) {
    final current = _current;
    if (current == null || _plotWidth <= 0) return;
    final shift = -dx / _plotWidth * (current.end - current.start);
    _setWindow((start: current.start + shift, end: current.end + shift));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.velorki;
    final spots = widget.spots;
    if (spots.length < 2) return const SizedBox.shrink();

    final window = _shown;
    final minX = window?.start ?? spots.first.x;
    final maxX = window?.end ?? spots.last.x;
    // The axis fits the samples in the window, so a zoomed line fills the
    // height; a window between two samples falls back to the whole line.
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
    final axis = widget.yAxis(lowest ?? 0, highest ?? 0);
    final touched = _touched;
    // The band never widens the axis: it is cut to the window, and a stretch
    // that lies wholly outside it is not drawn at all.
    final band = widget.highlight;
    final bandStart = band?.start.clamp(minX, maxX);
    final bandEnd = band?.end.clamp(minX, maxX);
    final marks = <ChartMark>[
      for (final mark in widget.marks)
        if (mark.x >= minX && mark.x <= maxX) mark,
    ];
    final markLabelStyle = theme.textTheme.labelSmall?.copyWith(
      color: colors.accent,
    );

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
        SizedBox(
          height: widget.height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              _plotWidth = constraints.maxWidth - widget.leftReservedSize;
              final chart = LineChart(
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
                      if (bandStart != null &&
                          bandEnd != null &&
                          bandEnd > bandStart)
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
                        getTitlesWidget: (_, meta) => _axisLabel(context, meta),
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: widget.leftReservedSize,
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
                      belowBarData: BarAreaData(
                        show: true,
                        color: colors.chartFill,
                      ),
                    ),
                  ],
                ),
              );
              // The read-out lands with the finger, before any arena is
              // decided; the sweep, the pan and the pinch are one scale
              // recognizer's, which a scrollable around the chart beats
              // on a vertical drag as it would beat a pan. The double tap
              // holds the arena for a moment, which only a zoomable chart
              // pays for.
              final touchable = Listener(
                onPointerDown: _onPointerDown,
                onPointerUp: _onPointerUp,
                onPointerCancel: _onPointerUp,
                child: GestureDetector(
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: _onScaleUpdate,
                  onScaleEnd: _onScaleEnd,
                  onDoubleTap: widget.zoomable ? () => _setWindow(null) : null,
                  child: chart,
                ),
              );
              if (!widget.zoomable) return touchable;
              return Stack(
                children: [
                  touchable,
                  if (window != null)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: theme.textTheme.labelSmall,
                        ),
                        onPressed: () => _setWindow(null),
                        child: Text(
                          AppLocalizations.of(context).chartResetZoom,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
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

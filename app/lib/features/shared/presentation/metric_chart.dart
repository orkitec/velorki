import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import 'stat_tile.dart';

/// One measurement over the distance: the elevation of a route, the speed of a
/// ride. An upper-case caption, an accent line over a soft fill, and a read-out
/// of whatever the finger rests on.
///
/// The samples are thinned before they get here — fl_chart draws every point it
/// is given — and the axes carry bare numbers, because the unit belongs in the
/// caller's own labels.
class MetricChart extends StatefulWidget {
  /// Creates the chart.
  const MetricChart({
    required this.title,
    required this.spots,
    required this.readoutAt,
    super.key,
    this.height = 160,
    this.minY,
    this.maxY,
    this.leftReservedSize = 40,
    this.highlight,
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

  /// Bottom of the y axis; a tenth of the range below the lowest point when
  /// left out.
  final double? minY;

  /// Top of the y axis, same rule.
  final double? maxY;

  /// How much room the y axis labels get.
  final double leftReservedSize;

  /// A stretch of the x axis to shade behind the line, in the axis' unit:
  /// the split or the climb the rider picked. Clipped to the line; `null`
  /// shades nothing.
  final ({double start, double end})? highlight;

  @override
  State<MetricChart> createState() => _MetricChartState();
}

class _MetricChartState extends State<MetricChart> {
  int? _touched;

  @override
  void didUpdateWidget(MetricChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.spots, widget.spots)) _touched = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.velorki;
    final spots = widget.spots;
    if (spots.length < 2) return const SizedBox.shrink();

    var lowest = spots.first.y;
    var highest = spots.first.y;
    for (final spot in spots) {
      if (spot.y < lowest) lowest = spot.y;
      if (spot.y > highest) highest = spot.y;
    }
    // A flat line still needs an axis to sit in the middle of.
    final padding = ((highest - lowest) * 0.1).clamp(0.5, double.infinity);
    final touched = _touched;
    // The band never widens the axis: it is cut to the line, and a stretch
    // that lies wholly outside it is not drawn at all.
    final band = widget.highlight;
    final bandStart = band?.start.clamp(spots.first.x, spots.last.x);
    final bandEnd = band?.end.clamp(spots.first.x, spots.last.x);

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
                  widget.readoutAt(touched),
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
          child: LineChart(
            LineChartData(
              minY: widget.minY ?? lowest - padding,
              maxY: widget.maxY ?? highest + padding,
              minX: spots.first.x,
              maxX: spots.last.x,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
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
              lineTouchData: LineTouchData(
                handleBuiltInTouches: false,
                touchCallback: _onTouch,
              ),
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
          ),
        ),
      ],
    );
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

  void _onTouch(FlTouchEvent event, LineTouchResponse? response) {
    final spot = response?.lineBarSpots?.firstOrNull;
    if (spot == null) {
      if (event is FlTapUpEvent || event is FlPointerExitEvent) {
        setState(() => _touched = null);
      }
      return;
    }
    final index = spot.spotIndex;
    if (index < 0 || index >= widget.spots.length) return;
    if (index == _touched) return;
    setState(() => _touched = index);
  }
}

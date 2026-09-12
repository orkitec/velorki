import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../domain/elevation_profile.dart';
import 'route_format.dart';

/// The elevation profile of a route: height over distance.
///
/// The samples are thinned by [elevationProfile] before they get here, so the
/// chart never draws more than [elevationProfileMaxPoints] points no matter
/// how long the route is. Touching the line reads out that point.
class ElevationProfileChart extends StatefulWidget {
  /// Creates the chart.
  const ElevationProfileChart({
    required this.samples,
    this.height = 140,
    super.key,
  });

  /// The profile, already downsampled.
  final List<ElevationSample> samples;

  /// Height of the chart area.
  final double height;

  @override
  State<ElevationProfileChart> createState() => _ElevationProfileChartState();
}

class _ElevationProfileChartState extends State<ElevationProfileChart> {
  ElevationSample? _touched;

  @override
  void didUpdateWidget(ElevationProfileChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.samples, widget.samples)) _touched = null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (widget.samples.length < 2) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          l10n.elevationUnavailable,
          style: theme.textTheme.bodySmall,
        ),
      );
    }

    final spots = widget.samples
        .map((s) => FlSpot(s.distanceM / 1000, s.elevationM))
        .toList(growable: false);
    var minY = spots.first.y;
    var maxY = spots.first.y;
    for (final s in spots) {
      if (s.y < minY) minY = s.y;
      if (s.y > maxY) maxY = s.y;
    }
    final padding = ((maxY - minY) * 0.1).clamp(5.0, 100.0);
    final touched = _touched;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(l10n.elevationTitle, style: theme.textTheme.titleSmall),
            if (touched != null)
              Text(
                l10n.elevationPoint(
                  formatDistance(l10n, touched.distanceM),
                  formatHeight(l10n, touched.elevationM),
                ),
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: widget.height,
          child: LineChart(
            LineChartData(
              minY: minY - padding,
              maxY: maxY + padding,
              minX: spots.first.x,
              maxX: spots.last.x,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: const FlTitlesData(
                topTitles: AxisTitles(),
                rightTitles: AxisTitles(),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: true, reservedSize: 22),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: true, reservedSize: 40),
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
                  barWidth: 2,
                  color: theme.colorScheme.primary,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: theme.colorScheme.primary.withValues(alpha: 0.15),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
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
    if (index < 0 || index >= widget.samples.length) return;
    final sample = widget.samples[index];
    if (sample == _touched) return;
    setState(() => _touched = sample);
  }
}

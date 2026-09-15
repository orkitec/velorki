import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/units/units.dart' as units;
import '../../../l10n/generated/app_localizations.dart';
import '../../settings/data/units.dart';
import '../../shared/presentation/stat_tile.dart';
import '../domain/elevation_profile.dart';
import 'route_format.dart';

/// The elevation profile of a route: height over distance.
///
/// The samples are thinned by [elevationProfile] before they get here, so the
/// chart never draws more than [elevationProfileMaxPoints] points no matter
/// how long the route is. Touching the line reads out that point. The axes
/// carry bare numbers, in kilometres and metres or in miles and feet.
class ElevationProfileChart extends ConsumerStatefulWidget {
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
  ConsumerState<ElevationProfileChart> createState() =>
      _ElevationProfileChartState();
}

class _ElevationProfileChartState extends ConsumerState<ElevationProfileChart> {
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

    final system = ref.watch(unitSystemProvider);
    final spots = widget.samples
        .map(
          (s) => FlSpot(
            units.distanceToDisplay(system, s.distanceM),
            units.elevationToDisplay(system, s.elevationM),
          ),
        )
        .toList(growable: false);
    var minY = spots.first.y;
    var maxY = spots.first.y;
    for (final s in spots) {
      if (s.y < minY) minY = s.y;
      if (s.y > maxY) maxY = s.y;
    }
    // The breathing room around the line is five to a hundred metres, said in
    // whatever the axis counts in.
    final padding = ((maxY - minY) * 0.1).clamp(
      units.elevationToDisplay(system, 5),
      units.elevationToDisplay(system, 100),
    );
    final touched = _touched;

    final colors = theme.velorki;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: SectionCaption(l10n.elevationTitle)),
            if (touched != null)
              Flexible(
                child: Text(
                  l10n.elevationPoint(
                    formatDistance(l10n, system, touched.distanceM),
                    formatHeight(l10n, system, touched.elevationM),
                  ),
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
              minY: minY - padding,
              maxY: maxY + padding,
              minX: spots.first.x,
              maxX: spots.last.x,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
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
                    reservedSize: 40,
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
    if (index < 0 || index >= widget.samples.length) return;
    final sample = widget.samples[index];
    if (sample == _touched) return;
    setState(() => _touched = sample);
  }
}

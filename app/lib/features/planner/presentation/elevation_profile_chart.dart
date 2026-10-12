import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/units/units.dart' as units;
import '../../../l10n/generated/app_localizations.dart';
import '../../settings/data/units.dart';
import '../../shared/presentation/metric_chart.dart';
import '../domain/elevation_profile.dart';
import 'route_format.dart';

/// The elevation profile of a route: height over distance.
///
/// The samples are thinned by [elevationProfile] before they get here, so the
/// chart never draws more than [elevationProfileMaxPoints] points no matter
/// how long the route is. A tap, a sweep or the cursor's handle reads out a
/// point, and a pinch zooms it. The axes carry bare numbers, in kilometres and metres or
/// in miles and feet.
class ElevationProfileChart extends ConsumerWidget {
  /// Creates the chart.
  const ElevationProfileChart({
    required this.samples,
    this.height = 140,
    this.window,
    this.onWindow,
    this.cursor,
    this.bands = const <DistanceBand>[],
    super.key,
  });

  /// The profile, already downsampled.
  final List<ElevationSample> samples;

  /// Height of the chart area.
  final double height;

  /// The stretch of the route the chart is zoomed to, or `null` for all of
  /// it; see [MetricChart.window]. Only read while [onWindow] is set.
  final DistanceWindow? window;

  /// Called with the stretch a pinch, a drag or a double tap asks for; see
  /// [MetricChart.onWindow]. Without it the chart keeps its own.
  final ValueChanged<DistanceWindow?>? onWindow;

  /// Where the cursor stands, in metres along the route; see
  /// [MetricChart.cursor].
  final ValueNotifier<double?>? cursor;

  /// What the fill under the line is coloured by, in metres along the
  /// route: what the route on the map is coloured by. See
  /// [MetricChart.bands].
  final List<DistanceBand> bands;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (samples.length < 2) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          l10n.elevationUnavailable,
          style: theme.textTheme.bodySmall,
        ),
      );
    }

    final system = ref.watch(unitSystemProvider);
    final spots = samples
        .map(
          (s) => FlSpot(
            units.distanceToDisplay(system, s.distanceM),
            units.elevationToDisplay(system, s.elevationM),
          ),
        )
        .toList(growable: false);
    return MetricChart(
      title: l10n.elevationTitle,
      spots: spots,
      height: height,
      yAxis: (lowest, highest) => elevationAxis(system, lowest, highest),
      zoomable: true,
      window: chartWindow(system, window),
      onWindow: distanceWindowCallback(system, onWindow),
      cursor: cursor,
      bands: chartBands(system, bands),
      metresPerUnit: units.displayToMeters(system, 1),
      cursorLabel: l10n.chartCursorRoute,
      resetLabel: l10n.chartResetZoomRoute,
      readoutAt: (index) => l10n.elevationPoint(
        formatDistance(l10n, system, samples[index].distanceM),
        formatHeight(l10n, system, samples[index].elevationM),
      ),
    );
  }
}

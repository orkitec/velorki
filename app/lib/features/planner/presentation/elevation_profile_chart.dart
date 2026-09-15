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
/// how long the route is. Touching the line reads out that point. The axes
/// carry bare numbers, in kilometres and metres or in miles and feet.
class ElevationProfileChart extends ConsumerWidget {
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

    return MetricChart(
      title: l10n.elevationTitle,
      spots: spots,
      height: height,
      minY: minY - padding,
      maxY: maxY + padding,
      readoutAt: (index) => l10n.elevationPoint(
        formatDistance(l10n, system, samples[index].distanceM),
        formatHeight(l10n, system, samples[index].elevationM),
      ),
    );
  }
}

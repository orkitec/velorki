import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/geo/ride_analysis.dart';
import '../../../core/units/units.dart' as units;
import '../../../l10n/generated/app_localizations.dart';
import '../../planner/presentation/route_format.dart';
import '../../settings/data/units.dart';
import '../../shared/presentation/metric_chart.dart';
import '../../shared/presentation/stat_tile.dart';
import 'recording_format.dart';

/// How tall the two ride charts are.
const double rideChartHeight = 160;

/// The height a recorded ride was ridden at, over its distance.
///
/// Draws nothing at all when the track carried no heights — an indoor ride, or
/// a phone whose GPS never reported one — rather than an empty frame.
class RideElevationChart extends ConsumerWidget {
  /// Creates the chart.
  const RideElevationChart({required this.samples, super.key});

  /// The analysed samples of the ride.
  final List<ChartSample> samples;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final system = ref.watch(unitSystemProvider);
    // Only the samples that have a height; a gap in the middle simply closes.
    final withElevation = <ChartSample>[
      for (final sample in samples)
        if (sample.elevationM != null) sample,
    ];
    if (withElevation.length < 2) return const SizedBox.shrink();

    final spots = <FlSpot>[
      for (final sample in withElevation)
        FlSpot(
          units.distanceToDisplay(system, sample.distanceM),
          units.elevationToDisplay(system, sample.elevationM!),
        ),
    ];
    var minY = spots.first.y;
    var maxY = spots.first.y;
    for (final spot in spots) {
      if (spot.y < minY) minY = spot.y;
      if (spot.y > maxY) maxY = spot.y;
    }
    // Five to a hundred metres of air around the line, as the planner's
    // profile has.
    final padding = ((maxY - minY) * 0.1).clamp(
      units.elevationToDisplay(system, 5),
      units.elevationToDisplay(system, 100),
    );

    return MetricChart(
      title: l10n.rideElevation,
      spots: spots,
      height: rideChartHeight,
      minY: minY - padding,
      maxY: maxY + padding,
      readoutAt: (index) => l10n.rideChartPoint(
        formatDistance(l10n, system, withElevation[index].distanceM),
        formatHeight(l10n, system, withElevation[index].elevationM!),
      ),
    );
  }
}

/// How fast a recorded ride was ridden, over its distance.
class RideSpeedChart extends ConsumerWidget {
  /// Creates the chart.
  const RideSpeedChart({required this.samples, super.key});

  /// The analysed samples of the ride.
  final List<ChartSample> samples;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final system = ref.watch(unitSystemProvider);
    if (samples.length < 2) return const SizedBox.shrink();

    final spots = <FlSpot>[
      for (final sample in samples)
        FlSpot(
          units.distanceToDisplay(system, sample.distanceM),
          units.formatSpeed(system, sample.speedMps).value,
        ),
    ];
    var fastest = spots.first.y;
    for (final spot in spots) {
      if (spot.y > fastest) fastest = spot.y;
    }

    return MetricChart(
      title: l10n.rideSpeed,
      spots: spots,
      height: rideChartHeight,
      // A speed axis starts at a standstill: a chart that begins at 18 km/h
      // turns an even ride into a mountain range.
      minY: 0,
      maxY: fastest * 1.1,
      readoutAt: (index) => l10n.rideChartPoint(
        formatDistance(l10n, system, samples[index].distanceM),
        formatSpeed(l10n, system, samples[index].speedMps),
      ),
    );
  }
}

/// How hard a recorded ride was ridden, over its distance.
///
/// Draws nothing when the track carried no heart rate — no sensor was paired,
/// or it was paired halfway through and never reported twice.
class RideHeartRateChart extends ConsumerWidget {
  /// Creates the chart.
  const RideHeartRateChart({required this.samples, super.key});

  /// The analysed samples of the ride.
  final List<ChartSample> samples;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final system = ref.watch(unitSystemProvider);
    // Only the samples that have a reading; a gap in the middle simply closes.
    final withHeartRate = <ChartSample>[
      for (final sample in samples)
        if (sample.heartRateBpm != null) sample,
    ];
    if (withHeartRate.length < 2) return const SizedBox.shrink();

    final spots = <FlSpot>[
      for (final sample in withHeartRate)
        FlSpot(
          units.distanceToDisplay(system, sample.distanceM),
          sample.heartRateBpm!.toDouble(),
        ),
    ];
    var lowest = spots.first.y;
    var highest = spots.first.y;
    for (final spot in spots) {
      if (spot.y < lowest) lowest = spot.y;
      if (spot.y > highest) highest = spot.y;
    }
    // Five to twenty beats of air around the line: a resting heart rate is
    // nowhere near zero, so an axis that starts there would draw a flat line.
    final padding = ((highest - lowest) * 0.1).clamp(5.0, 20.0);

    return MetricChart(
      title: l10n.rideHeartRate,
      spots: spots,
      height: rideChartHeight,
      minY: lowest - padding,
      maxY: highest + padding,
      readoutAt: (index) => l10n.rideChartPoint(
        formatDistance(l10n, system, withHeartRate[index].distanceM),
        formatHeartRate(l10n, withHeartRate[index].heartRateBpm),
      ),
    );
  }
}

/// What the colours of the track under it mean: slow at one end of the ramp,
/// fast at the other. No numbers — the classes are the ride's own quantiles,
/// so the only thing worth saying is which way round they run.
class RideSpeedLegend extends StatelessWidget {
  /// Creates the legend.
  const RideSpeedLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).velorki;
    return Row(
      children: [
        SectionCaption(l10n.rideSpeedSlow),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                gradient: LinearGradient(
                  colors: <Color>[colors.trackSlow, colors.trackFast],
                ),
              ),
              child: const SizedBox(height: 6),
            ),
          ),
        ),
        SectionCaption(l10n.rideSpeedFast),
      ],
    );
  }
}

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
import '../domain/ride_range.dart';
import 'recording_format.dart';

/// How tall the two ride charts are.
const double rideChartHeight = 160;

/// The height a recorded ride was ridden at, over its distance.
///
/// Draws nothing at all when the track carried no heights — an indoor ride, or
/// a phone whose GPS never reported one — rather than an empty frame.
class RideElevationChart extends ConsumerWidget {
  /// Creates the chart.
  const RideElevationChart({
    required this.samples,
    super.key,
    this.highlight,
    this.marks = const <({double alongM, String label})>[],
    this.window,
    this.onWindow,
  });

  /// The analysed samples of the ride.
  final List<ChartSample> samples;

  /// The stretch of the ride shaded behind the line, or `null`.
  final RideRange? highlight;

  /// Named places along the ride, in metres from the start: the points of
  /// interest of the route the ride followed, where it passed them.
  final List<({double alongM, String label})> marks;

  /// The stretch of the ride the chart is zoomed to, or `null` for all of
  /// it; see [MetricChart.window].
  final RideWindow? window;

  /// Called with the stretch a pinch, a drag or a double tap asks for; see
  /// [MetricChart.onWindow].
  final ValueChanged<RideWindow?>? onWindow;

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
    return MetricChart(
      title: l10n.rideElevation,
      spots: spots,
      height: rideChartHeight,
      yAxis: (lowest, highest) => elevationAxis(system, lowest, highest),
      highlight: chartHighlight(system, highlight),
      zoomable: true,
      window: chartWindow(system, window),
      onWindow: rideWindowCallback(system, onWindow),
      marks: <ChartMark>[
        for (final mark in marks)
          (x: units.distanceToDisplay(system, mark.alongM), label: mark.label),
      ],
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
  const RideSpeedChart({
    required this.samples,
    super.key,
    this.highlight,
    this.window,
    this.onWindow,
  });

  /// The analysed samples of the ride.
  final List<ChartSample> samples;

  /// The stretch of the ride shaded behind the line, or `null`.
  final RideRange? highlight;

  /// The stretch of the ride the chart is zoomed to, or `null` for all of
  /// it; see [MetricChart.window].
  final RideWindow? window;

  /// Called with the stretch a pinch, a drag or a double tap asks for; see
  /// [MetricChart.onWindow].
  final ValueChanged<RideWindow?>? onWindow;

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
    return MetricChart(
      title: l10n.rideSpeed,
      spots: spots,
      height: rideChartHeight,
      // A speed axis starts at a standstill, zoomed or not: a chart that
      // begins at 18 km/h turns an even ride into a mountain range.
      yAxis: (_, fastest) => (min: 0, max: fastest * 1.1),
      highlight: chartHighlight(system, highlight),
      zoomable: true,
      window: chartWindow(system, window),
      onWindow: rideWindowCallback(system, onWindow),
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
  const RideHeartRateChart({
    required this.samples,
    super.key,
    this.highlight,
    this.window,
    this.onWindow,
  });

  /// The analysed samples of the ride.
  final List<ChartSample> samples;

  /// The stretch of the ride shaded behind the line, or `null`.
  final RideRange? highlight;

  /// The stretch of the ride the chart is zoomed to, or `null` for all of
  /// it; see [MetricChart.window].
  final RideWindow? window;

  /// Called with the stretch a pinch, a drag or a double tap asks for; see
  /// [MetricChart.onWindow].
  final ValueChanged<RideWindow?>? onWindow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final system = ref.watch(unitSystemProvider);
    // Only the samples that have a reading. Where the reading was lost for
    // a stretch of road the line breaks rather than bridging the gap: a
    // straight line across ten kilometres would be a heart rate nobody had.
    final measured = <ChartSample>[
      for (final sample in samples)
        if (sample.heartRateBpm != null) sample,
    ];
    if (measured.length < 2) return const SizedBox.shrink();

    final withHeartRate = <ChartSample>[];
    final spots = <FlSpot>[];
    for (final sample in measured) {
      final previous = withHeartRate.lastOrNull;
      if (previous != null &&
          sample.distanceM - previous.distanceM > heartRateGapM) {
        withHeartRate.add(previous);
        spots.add(FlSpot.nullSpot);
      }
      withHeartRate.add(sample);
      spots.add(
        FlSpot(
          units.distanceToDisplay(system, sample.distanceM),
          sample.heartRateBpm!.toDouble(),
        ),
      );
    }
    // How much of the ride had a reading at all; said in the caption when
    // it was not most of it, so an average over a few minutes is not read
    // as the ride's.
    final coverage = measured.length / samples.length;
    final title = coverage < heartRateCoverageWorthSaying
        ? l10n.rideHeartRateCoverage((coverage * 100).round())
        : l10n.rideHeartRate;
    return MetricChart(
      title: title,
      spots: spots,
      height: rideChartHeight,
      // Five to twenty beats of air around the line: a resting heart rate
      // is nowhere near zero, so an axis that starts there would draw a
      // flat line.
      yAxis: (lowest, highest) {
        final padding = ((highest - lowest) * 0.1).clamp(5.0, 20.0);
        return (min: lowest - padding, max: highest + padding);
      },
      highlight: chartHighlight(system, highlight),
      zoomable: true,
      window: chartWindow(system, window),
      onWindow: rideWindowCallback(system, onWindow),
      readoutAt: (index) => l10n.rideChartPoint(
        formatDistance(l10n, system, withHeartRate[index].distanceM),
        formatHeartRate(l10n, withHeartRate[index].heartRateBpm),
      ),
    );
  }
}

/// [range] on the charts' x axis, which runs in the rider's distance unit,
/// converted exactly as the samples are; `null` for no range.
({double start, double end})? chartHighlight(
  UnitSystem system,
  RideRange? range,
) => range == null
    ? null
    : (
        start: units.distanceToDisplay(system, range.startM),
        end: units.distanceToDisplay(system, range.endM),
      );

/// A stretch of a ride the charts are zoomed to, in metres from the start;
/// one for all of them, so a pinch on one zooms the others to the same road.
typedef RideWindow = ({double start, double end});

/// [window] on the charts' x axis, converted as the samples are; `null` for
/// the whole ride.
ChartWindow? chartWindow(UnitSystem system, RideWindow? window) =>
    window == null
    ? null
    : (
        start: units.distanceToDisplay(system, window.start),
        end: units.distanceToDisplay(system, window.end),
      );

/// [onWindow] as a [MetricChart] calls it: with the window in the axis'
/// unit, handed on in metres. `null` when there is nobody to hand it to, so
/// the chart keeps its own window.
ValueChanged<ChartWindow?>? rideWindowCallback(
  UnitSystem system,
  ValueChanged<RideWindow?>? onWindow,
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

/// A stretch of road this long without a reading breaks the heart-rate line.
const double heartRateGapM = 300;

/// Below this share of the ride with a reading, the chart's caption says
/// how much of the ride it is.
const double heartRateCoverageWorthSaying = 0.9;

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

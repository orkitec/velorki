import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/geo/climbs.dart';
import '../../../core/units/units.dart' as units;
import '../../../l10n/generated/app_localizations.dart';
import '../../planner/domain/elevation_profile.dart';
import '../../planner/presentation/route_format.dart';
import '../../settings/data/units.dart';
import '../../shared/presentation/stat_tile.dart';

/// The followed route as a profile: the second page of the record sheet.
///
/// The road ahead as height over distance,
/// the part already ridden filled in the accent, the rider as a line across
/// it, and above it what is left — the distance and the climbing. A swipe on
/// the figures brings it up; the same swipe back brings the figures back.
class RideProfileView extends ConsumerWidget {
  /// Creates the page.
  const RideProfileView({
    required this.samples,
    required this.alongM,
    this.etaAt,
    this.height = 150,
    super.key,
  });

  /// When the rider will reach the end at their average so far, or `null`
  /// while there is no average yet.
  final DateTime? etaAt;

  /// The followed route's profile, already downsampled; fewer than two
  /// samples means there is no route to draw.
  final List<ElevationSample> samples;

  /// How far along the route the rider is, in metres.
  final double alongM;

  /// Height of the chart area.
  final double height;

  /// The climbing left from [alongM] to the end: the positive steps between
  /// the samples ahead.
  double get ascentLeftM {
    var ascent = 0.0;
    ElevationSample? previous;
    for (final sample in samples) {
      if (sample.distanceM < alongM) continue;
      if (previous != null && sample.elevationM > previous.elevationM) {
        ascent += sample.elevationM - previous.elevationM;
      }
      previous = sample;
    }
    return ascent;
  }

  /// The grade of the road at [alongM], in percent, over the stretch around
  /// the rider; `null` with too little route to measure.
  double? get gradePercent {
    if (samples.length < 2) return null;
    ElevationSample? before;
    ElevationSample? after;
    for (final s in samples) {
      if (s.distanceM <= alongM - climbWindowM / 2) before = s;
      if (after == null && s.distanceM >= alongM + climbWindowM / 2) after = s;
    }
    before ??= samples.first;
    after ??= samples.last;
    final run = after.distanceM - before.distanceM;
    if (run < 20) return null;
    return (after.elevationM - before.elevationM) / run * 100;
  }

  /// The climbing left to the top of the climb the rider is on: up to where
  /// the road next drops by more than [climbEndDropM]. Zero on the flat.
  double get toTopM {
    var ascent = 0.0;
    ElevationSample? previous;
    var high = double.negativeInfinity;
    for (final s in samples) {
      if (s.distanceM < alongM) continue;
      if (previous != null) {
        if (s.elevationM > previous.elevationM) {
          ascent += s.elevationM - previous.elevationM;
        }
        if (s.elevationM > high) high = s.elevationM;
        if (high - s.elevationM > climbEndDropM) break;
      } else {
        high = s.elevationM;
      }
      previous = s;
    }
    return ascent;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final system = ref.watch(unitSystemProvider);
    if (samples.length < 2) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            l10n.recordingProfileNoRoute,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: SectionCaption(l10n.elevationTitle)),
            Flexible(
              child: Text(
                l10n.recordingProfileLeft(
                  formatDistance(
                    l10n,
                    system,
                    (samples.last.distanceM - alongM).clamp(0, double.infinity),
                  ),
                  formatHeight(l10n, system, ascentLeftM),
                ),
                style: theme.textTheme.statMedium.copyWith(
                  color: theme.velorki.accent,
                ),
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        _secondLine(context, l10n, system),
        const SizedBox(height: 10),
        SizedBox(height: height, child: _chart(context, system)),
      ],
    );
  }

  /// The climb the rider is on and the arrival time, when there is either.
  Widget _secondLine(
    BuildContext context,
    AppLocalizations l10n,
    units.UnitSystem system,
  ) {
    final theme = Theme.of(context);
    final parts = <String>[];
    final grade = gradePercent;
    if (grade != null && grade >= climbGradeMinPercent) {
      parts.add(
        l10n.recordingProfileClimb(
          grade.round().toString(),
          formatHeight(l10n, system, toTopM),
        ),
      );
    }
    final eta = etaAt;
    if (eta != null) {
      final time = MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay.fromDateTime(eta),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      );
      parts.add(l10n.recordingEta(time));
    }
    if (parts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        parts.join('  ·  '),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _chart(BuildContext context, units.UnitSystem system) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = theme.velorki.accent;
    final spots = <FlSpot>[
      for (final s in samples)
        FlSpot(
          units.distanceToDisplay(system, s.distanceM),
          units.elevationToDisplay(system, s.elevationM),
        ),
    ];
    final alongX = units.distanceToDisplay(
      system,
      alongM.clamp(samples.first.distanceM, samples.last.distanceM),
    );
    // The ridden part ends at the rider; the part ahead starts there. Both
    // share the rider's own spot so the fills meet without a gap.
    final ridden = <FlSpot>[
      for (final s in spots)
        if (s.x <= alongX) s,
    ];
    final ahead = <FlSpot>[
      for (final s in spots)
        if (s.x >= alongX) s,
    ];
    final here = _interpolate(spots, alongX);
    if (ridden.isEmpty || ridden.last.x < alongX) ridden.add(here);
    if (ahead.isEmpty || ahead.first.x > alongX) ahead.insert(0, here);

    var minY = spots.first.y;
    var maxY = spots.first.y;
    for (final s in spots) {
      if (s.y < minY) minY = s.y;
      if (s.y > maxY) maxY = s.y;
    }
    final padding = ((maxY - minY) * 0.1).clamp(
      units.elevationToDisplay(system, 5),
      units.elevationToDisplay(system, 100),
    );
    // Bare numbers on both axes; heights as whole figures rather than the
    // chart's own "2.5K".
    Widget label(String text) => Padding(
      padding: const EdgeInsets.all(4),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
    );

    return LineChart(
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
              getTitlesWidget: (value, meta) => label(meta.formattedValue),
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) => label(value.round().toString()),
            ),
          ),
        ),
        lineTouchData: const LineTouchData(enabled: false),
        extraLinesData: ExtraLinesData(
          verticalLines: [
            VerticalLine(x: alongX, color: accent, strokeWidth: 2),
          ],
        ),
        lineBarsData: [
          if (ridden.length >= 2)
            LineChartBarData(
              spots: ridden,
              barWidth: 2.5,
              color: accent,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: accent.withValues(alpha: 0.35),
              ),
            ),
          LineChartBarData(
            spots: ahead,
            barWidth: 2.5,
            color: scheme.onSurfaceVariant,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.15),
            ),
          ),
        ],
      ),
      duration: Duration.zero,
    );
  }

  /// The height of the line at [x], between the two spots around it.
  static FlSpot _interpolate(List<FlSpot> spots, double x) {
    for (var i = 1; i < spots.length; i++) {
      final a = spots[i - 1];
      final b = spots[i];
      if (x >= a.x && x <= b.x) {
        final t = b.x == a.x ? 0.0 : (x - a.x) / (b.x - a.x);
        return FlSpot(x, a.y + (b.y - a.y) * t);
      }
    }
    return x <= spots.first.x ? spots.first : spots.last;
  }
}

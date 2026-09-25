import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/units/units.dart' as units;
import '../../../l10n/generated/app_localizations.dart';
import '../../planner/presentation/route_format.dart';
import '../../shared/presentation/stat_tile.dart';
import '../domain/live_figures.dart';
import 'recording_format.dart';

/// How many figures the docked bar shows: the first of the ride's list.
const int figuresBarCount = 4;

/// The height of the docked bar's glass, the tab bar's own.
const double figuresBarHeight = 72;

/// The air under the docked bar and the tab bar, above the safe area.
const double figuresBarBottomGap = 12;

/// A figure's caption, as the grid and the bar write it.
String liveFigureLabel(LiveFigure figure, AppLocalizations l10n) =>
    switch (figure) {
      LiveFigure.distance => l10n.statDistance,
      LiveFigure.speed => l10n.statSpeed,
      LiveFigure.avgSpeed => l10n.statAvgSpeed,
      LiveFigure.ascent => l10n.statAscent,
      LiveFigure.descent => l10n.statDescent,
      LiveFigure.movingTime => l10n.statMovingTime,
      LiveFigure.heartRate => l10n.statHeartRate,
      LiveFigure.cadence => l10n.statCadence,
      LiveFigure.power => l10n.statPower,
      LiveFigure.remaining => l10n.statRemaining,
      LiveFigure.arrival => l10n.statArrival,
    };

/// A figure's value, unit included, in the rider's units.
String liveFigureValue(
  BuildContext context,
  LiveFigureReading reading,
  AppLocalizations l10n,
  units.UnitSystem system,
) {
  final value = reading.value ?? 0;
  return switch (reading.figure) {
    LiveFigure.distance ||
    LiveFigure.remaining => formatDistance(l10n, system, value),
    LiveFigure.speed || LiveFigure.avgSpeed => formatSpeed(l10n, system, value),
    LiveFigure.ascent ||
    LiveFigure.descent => formatHeight(l10n, system, value),
    LiveFigure.movingTime => formatClock(reading.duration ?? Duration.zero),
    LiveFigure.heartRate => formatHeartRate(l10n, value.round()),
    LiveFigure.cadence => formatCadence(l10n, value.round()),
    LiveFigure.power => formatPower(l10n, value.round()),
    LiveFigure.arrival => MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(reading.time!)),
  };
}

/// The tile the sheet's grid draws for the [index]th figure: the first row
/// in the grid's large size, the first figure in the accent while the ride
/// runs, the rest in the dense size; a silent sensor dimmed and marked.
Widget liveFigureTile(
  BuildContext context,
  LiveFigureReading reading, {
  required int index,
  required bool paused,
  required AppLocalizations l10n,
  required units.UnitSystem system,
}) {
  final average = reading.average;
  return StatTile(
    label: liveFigureLabel(reading.figure, l10n),
    value: liveFigureValue(context, reading, l10n, system),
    size: index < 3 ? StatSize.large : StatSize.medium,
    emphasize: index == 0 && !paused,
    icon: reading.lost ? Icons.link_off : null,
    muted: reading.lost,
    detail: reading.figure == LiveFigure.heartRate && average != null
        ? '${l10n.statAvgHeartRate} ${formatHeartRate(l10n, average.round())}'
        : null,
  );
}

/// What the Record sheet becomes when it is pulled all the way down during
/// a ride: a bar in the tab bar's place and shape, the ride's first
/// [figuresBarCount] figures on it, value over caption, and most of the map
/// above it.
///
/// Nothing on it stops or pauses the ride: a hand that brushes it opens the
/// sheet, nothing more. A tap does that, and so does a drag up. Paused, a
/// small dot in the tertiary colour says so, and the figures fade.
class FiguresBar extends StatelessWidget {
  /// Creates the bar.
  const FiguresBar({
    required this.figures,
    required this.paused,
    required this.system,
    required this.onOpen,
    this.docked = true,
    super.key,
  });

  /// The ride's figures, in order; the bar shows the first four.
  final List<LiveFigureReading> figures;

  /// Whether the ride is paused.
  final bool paused;

  /// The rider's units.
  final units.UnitSystem system;

  /// Opens the sheet again.
  final VoidCallback onOpen;

  /// Whether the sheet's strip rests on the bar's top edge, which is then
  /// straight, as the tab bar's is under a docked sheet.
  final bool docked;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.velorki;
    final shown = figures.take(figuresBarCount).toList();
    final radius = docked
        ? const BorderRadius.vertical(bottom: Radius.circular(30))
        : BorderRadius.circular(30);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        MediaQuery.viewPaddingOf(context).bottom + figuresBarBottomGap,
      ),
      child: Semantics(
        button: true,
        label: l10n.recordingFiguresBarOpen,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onOpen,
          onVerticalDragEnd: (details) {
            if ((details.primaryVelocity ?? 0) < 0) onOpen();
          },
          child: ClipRRect(
            borderRadius: radius,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.glass,
                borderRadius: radius,
                border: Border.all(color: colors.glassBorder, width: 0.5),
              ),
              child: SizedBox(
                height: figuresBarHeight,
                child: Stack(
                  children: [
                    Row(
                      children: [
                        for (final reading in shown)
                          Expanded(
                            child: _BarFigure(
                              label: liveFigureLabel(reading.figure, l10n),
                              value: liveFigureValue(
                                context,
                                reading,
                                l10n,
                                system,
                              ),
                              muted: paused || reading.lost,
                            ),
                          ),
                      ],
                    ),
                    if (paused)
                      Positioned(
                        top: 10,
                        right: 14,
                        child: Container(
                          key: const ValueKey('figures-bar-paused'),
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.tertiary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One figure on the bar: the value, scaled down to fit its quarter, over
/// its caption.
class _BarFigure extends StatelessWidget {
  const _BarFigure({
    required this.label,
    required this.value,
    required this.muted,
  });

  final String label;
  final String value;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = muted
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: theme.textTheme.statMedium.copyWith(
                fontSize: 20,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              style: theme.textTheme.overline.copyWith(
                fontSize: 9,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

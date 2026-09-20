import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../navigation/application/route_cues.dart';
import '../../navigation/presentation/turn_phrases.dart';
import '../../planner/domain/route_poi.dart';
import '../../settings/data/units.dart';
import '../../shared/presentation/stat_tile.dart';

/// The cue sheet: the third page of the record sheet.
///
/// What Ride with GPS prints for a race and what a rider reads at the start
/// line: the turns ahead in order, with the points of interest between them
/// and the finish at the end, each with how far away it is right now. The
/// first line is what the banner shows; the rest is what comes after it.
class RideCueSheet extends ConsumerWidget {
  /// Creates the page.
  const RideCueSheet({
    required this.cues,
    required this.alongM,
    this.maxLines = 8,
    super.key,
  });

  /// The route's cues in order; empty without a route.
  final List<RouteCue> cues;

  /// How far along the route the rider is, in metres.
  final double alongM;

  /// How many lines are shown: the sheet is read at a glance, not scrolled.
  final int maxLines;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final units = ref.watch(unitSystemProvider);
    // A cue a few metres behind is still the one the rider is at.
    final ahead = cues.where((c) => c.alongM - alongM >= -cuePassedM).toList();
    if (ahead.isEmpty) {
      return SizedBox(
        height: 150,
        child: Center(
          child: Text(
            l10n.recordingCuesNoRoute,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final shown = ahead.take(maxLines).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SectionCaption(l10n.recordingCuesTitle),
        const SizedBox(height: 8),
        for (var i = 0; i < shown.length; i++)
          _CueRow(
            cue: shown[i],
            distance: distanceLabel(
              (shown[i].alongM - alongM).clamp(0, double.infinity),
              l10n,
              units,
            ),
            first: i == 0,
          ),
        if (ahead.length > shown.length)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.recordingCuesMore(ahead.length - shown.length),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// How far past a cue the rider may be for it to still lead the sheet.
const double cuePassedM = 25;

class _CueRow extends StatelessWidget {
  const _CueRow({
    required this.cue,
    required this.distance,
    required this.first,
  });

  final RouteCue cue;
  final String distance;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = theme.velorki;
    final turn = cue.turn;
    final poi = cue.poi;
    final IconData icon;
    final String label;
    Color tint = first ? colors.accent : scheme.onSurfaceVariant;
    if (cue.isStart) {
      icon = Icons.play_arrow_rounded;
      label = l10n.cueSheetStart;
    } else if (poi != null) {
      icon = poiIcon(poi.kind);
      label = poiLabel(poi, l10n);
      if (poi.kind == PoiKind.danger) tint = colors.warning;
    } else if (turn != null) {
      icon = cue.isFinish ? Icons.flag : turnIcon(turn.kind);
      label = turnLabel(turn, l10n);
    } else {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: tint),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style:
                  (first
                          ? theme.textTheme.titleMedium
                          : theme.textTheme.bodyMedium)
                      ?.copyWith(
                        color: first
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                      ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            distance,
            style: theme.textTheme.statMedium.copyWith(
              color: tint,
              fontSize: first ? null : 15,
            ),
          ),
        ],
      ),
    );
  }
}

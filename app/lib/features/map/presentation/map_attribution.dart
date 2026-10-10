import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell_layout.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../shared/presentation/floating_bar.dart';
import '../../shared/presentation/stat_tile.dart';
import '../data/map_preferences.dart';
import 'map_chrome.dart';

/// How far above the bottom of a map view in [context] the attribution chip
/// and the native (i) button sit: [gap] over the bottom view padding the view
/// is given. The shell gives its shared map none, so the two stay in the
/// band under the floating bar whether that bar is shown or not; where the
/// safe area is not that band, the map's [MapChromeInsets.attributionFloor]
/// says where they go instead.
double mapAttributionBottom(BuildContext context, {double gap = 6}) =>
    (MapChromeInsets.maybeOf(context)?.attributionFloor ??
        MediaQuery.viewPaddingOf(context).bottom) +
    gap;

/// Where the attribution chip of the shell's map stands on [screen] (the
/// screen's own metrics, not a map's), in dp above its bottom edge; `null`
/// for the bottom of the map itself.
///
/// The chip sits in a band under the floating bar. Where the system has a
/// gesture zone at the bottom that band is the zone, and the map's bottom
/// is the screen's. Without one (an iPhone
/// with a home button, Android's three-button navigation) the bar stands
/// higher by [attributionBandHeight] ([floatingBarBottomGapFor]) and the
/// chip goes on the safe area's edge, under the bar, clear of Android's
/// navigation buttons. Turned sideways the bar is a rail at the side and
/// the band along the bottom is the map's, so nothing changes there.
double? shellAttributionFloor(
  MediaQueryData screen,
  ShellLayout layout,
  TargetPlatform platform,
) {
  if (layout.sideRail || !barRaisedForAttribution(screen, platform)) {
    return null;
  }
  return screen.viewPadding.bottom;
}

/// The attribution required by the OpenStreetMap licence, drawn by us rather
/// than by the native SDK so it survives our own map chrome.
///
/// Text only: it takes no touch, which goes through to the map, so a rider
/// reaching for the map's bottom edge does not open anything by accident.
/// The full credits, with their links, are in Settings → About.
class MapAttributionChip extends ConsumerWidget {
  const MapAttributionChip({
    super.key,
    this.cyclosmActive,
    this.extra = const <String>[],
  });

  /// Overrides the CyclOSM state; by default it follows the overlay toggle.
  final bool? cyclosmActive;

  /// Further credits, for what this map draws from other sources: the
  /// weather layers.
  final List<String> extra;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool cyclosm = cyclosmActive ?? ref.watch(cyclosmOverlayProvider);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final parts = <String>[
      l10n.osmAttribution,
      l10n.mapAttributionOpenFreeMap,
      if (cyclosm) l10n.mapAttributionCyclosm,
      ...extra,
    ];
    return IgnorePointer(
      child: GlassPanel(
        radius: 999,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(
            parts.join(' · '),
            // Centred when the weather credits make it wrap.
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall,
          ),
        ),
      ),
    );
  }
}

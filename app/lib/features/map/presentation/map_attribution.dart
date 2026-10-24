import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell_layout.dart';
import '../../../core/links/link_opener.dart';
import '../../../core/links/velorki_urls.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../settings/presentation/about_section.dart';
import '../../shared/application/covering_sheets.dart';
import '../../shared/presentation/gesture_zone_guard.dart';
import '../../shared/presentation/floating_bar.dart';
import '../../shared/presentation/stat_tile.dart';
import '../data/map_preferences.dart';
import 'map_chrome.dart';
import '../../shared/presentation/docking_sheet.dart';

/// How far above the bottom of a map view in [context] the attribution chip
/// sits: [gap] over the bottom view padding the view is given. The shell
/// gives its shared map none, so the chip stays in the
/// band under the floating bar whether that bar is shown or not; where the
/// safe area is not that band, the map's [MapChromeInsets.attributionFloor]
/// says where it goes instead.
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
/// the band along the bottom is the map's, so nothing changes there. In a
/// wide window the chip is centred on the map beside the column, where the
/// home indicator or Android's gesture handle crosses it, so it stands on
/// the safe area's edge there.
double? shellAttributionFloor(
  MediaQueryData screen,
  ShellLayout layout,
  TargetPlatform platform,
) {
  if (layout.widePanel) return screen.viewPadding.bottom;
  if (layout.sideRail || !barRaisedForAttribution(screen, platform)) {
    return null;
  }
  return screen.viewPadding.bottom;
}

/// Where each of the map's credits leads.
const String _openFreeMapUrl = 'https://openfreemap.org';
const String _openMapTilesUrl = 'https://www.openmaptiles.org/';
const String _cyclosmUrl = 'https://www.cyclosm.org';

/// The attribution required by the OpenStreetMap licence, drawn by us rather
/// than by the native SDK so it survives our own map chrome, followed by an
/// (i) in place of the native SDK's button, which is kept out of view.
///
/// It names the base map only; a round (i) beside it opens
/// [showMapCredits], which lists those credits with their links, the
/// weather layers' while they are drawn, and the way to every licence. Only
/// the (i) is tappable, against taps by accident: its target is 48 dp tall,
/// reaching up from the chip, whose bottom edge stays where it is placed;
/// the credit itself lets touches through to the map.
class MapAttributionChip extends ConsumerWidget {
  const MapAttributionChip({
    super.key,
    this.cyclosmActive,
    this.weatherCredits,
  });

  /// Overrides the CyclOSM state; by default it follows the overlay toggle.
  final bool? cyclosmActive;

  /// The weather layers' credits while they are drawn, for the sheet; the
  /// chip itself does not show them.
  final ValueListenable<List<String>>? weatherCredits;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool cyclosm = cyclosmActive ?? ref.watch(cyclosmOverlayProvider);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final parts = <String>[
      l10n.osmAttribution,
      l10n.mapAttributionOpenFreeMap,
      if (cyclosm) l10n.mapAttributionCyclosm,
    ];
    final style = theme.textTheme.labelSmall;
    void open() => unawaited(
      showMapCredits(
        context,
        cyclosmActive: cyclosmActive,
        weatherCredits: weatherCredits,
      ),
    );
    // The credit lets every touch through to the map; only the (i) beside
    // it takes a tap, so a pan that starts on the chip is not taken for one.
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(
          child: IgnorePointer(
            child: GlassPanel(
              radius: 999,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                child: Text(
                  parts.join(' · '),
                  // Centred should it wrap.
                  textAlign: TextAlign.center,
                  style: style,
                ),
              ),
            ),
          ),
        ),
        Semantics(
          button: true,
          label: l10n.mapCredits,
          onTap: open,
          excludeSemantics: true,
          // It stands in the system's gesture zone on a phone that has one;
          // it is only ever tapped, so the zone's guard lets it be.
          child: GestureZonePassThrough(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: open,
              // A finger's size, the clear part above and beside the button
              // included, its bottom on the chip's.
              child: SizedBox(
                width: _infoTargetWidth,
                height: kMinInteractiveDimension,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: GlassPanel(
                    radius: 999,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.info_outline,
                        size: 16,
                        color: style?.color ?? theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// How wide the (i)'s tap target is.
const double _infoTargetWidth = 40;

/// Opens the map's credits over the tab: the base map's sources with their
/// links, the weather layers' credits while [weatherCredits] has any, and
/// a row to every licence.
Future<void> showMapCredits(
  BuildContext context, {
  bool? cyclosmActive,
  ValueListenable<List<String>>? weatherCredits,
}) => coverTabSheet(
  context,
  () => showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => ScrolledUnderLine(
      child: MapCreditsSheet(
        cyclosmActive: cyclosmActive,
        weatherCredits: weatherCredits,
      ),
    ),
  ),
);

/// The map's credits: what [showMapCredits] shows.
class MapCreditsSheet extends ConsumerWidget {
  /// Creates the sheet.
  const MapCreditsSheet({super.key, this.cyclosmActive, this.weatherCredits});

  /// Overrides the CyclOSM state; by default it follows the overlay toggle.
  final bool? cyclosmActive;

  /// The weather layers' credits, `{year}` already filled.
  final ValueListenable<List<String>>? weatherCredits;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final bool cyclosm = cyclosmActive ?? ref.watch(cyclosmOverlayProvider);
    final open = ref.read(linkOpenerProvider);
    Widget link(String title, String url) => ListTile(
      title: Text(title),
      trailing: const Icon(Icons.open_in_new, size: 18),
      onTap: () => unawaited(open(Uri.parse(url))),
    );
    Widget caption(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: SectionCaption(text),
    );
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        bottom: 16 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: Text(l10n.mapCredits, style: theme.textTheme.titleMedium),
          ),
          caption(l10n.mapCreditsMap),
          link(l10n.osmAttribution, osmCopyrightUrl),
          link(l10n.mapAttributionOpenFreeMap, _openFreeMapUrl),
          link(l10n.mapAttributionOpenMapTiles, _openMapTilesUrl),
          if (cyclosm) link(l10n.mapAttributionCyclosm, _cyclosmUrl),
          ValueListenableBuilder<List<String>>(
            valueListenable: weatherCredits ?? _noWeather,
            builder: (context, credits, _) => credits.isEmpty
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      caption(l10n.mapCreditsWeather),
                      for (final credit in credits)
                        ListTile(title: Text(credit)),
                    ],
                  ),
          ),
          const Divider(height: 24),
          ListTile(
            leading: const Icon(Icons.article_outlined),
            title: Text(l10n.mapCreditsAllLicences),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showVelorkiLicenses(context, ref),
          ),
        ],
      ),
    );
  }
}

/// No weather credits.
final ValueListenable<List<String>> _noWeather = ValueNotifier<List<String>>(
  const <String>[],
);

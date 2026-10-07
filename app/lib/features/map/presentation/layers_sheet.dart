import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../navigation/application/navigation_controller.dart';
import '../../search/domain/search_group.dart';
import '../../search/presentation/search_field.dart'
    show poiKindIcon, gazetteerPoiKindLabel;
import '../../search/presentation/search_settings_screen.dart'
    show searchGroupLabel;
import '../../shared/presentation/stat_tile.dart';
import '../data/map_preferences.dart';
import 'map_chrome.dart';

/// The groups whose kinds the sheet offers as stops, in this order.
const List<SearchGroup> stopGroups = <SearchGroup>[
  SearchGroup.cyclingStops,
  SearchGroup.overnight,
  SearchGroup.landmarks,
];

/// The kinds of [group] the sheet offers: every kind of the group this
/// build has a label for, but a named building, which is no stop.
List<String> stopKindsOf(AppLocalizations l10n, SearchGroup group) => <String>[
  for (final entry in searchGroupOfPoiKind.entries)
    if (entry.value == group &&
        entry.key != 'building' &&
        gazetteerPoiKindLabel(l10n, entry.key) != null)
      entry.key,
];

/// Opens the map's Layers sheet: the cycle map, and where [offer] says so,
/// the stops.
Future<void> showLayersSheet(
  BuildContext context, {
  MapStopsOffer offer = MapStopsOffer.none,
}) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => LayersSheet(offer: offer),
);

/// What the map shows over its base: the cycle map overlay, and on the
/// shared map the stops, which kinds of them and, on a guided ride, from
/// where.
class LayersSheet extends ConsumerWidget {
  /// Creates the sheet.
  const LayersSheet({this.offer = MapStopsOffer.none, super.key});

  /// What the sheet offers about stops.
  final MapStopsOffer offer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cyclosm = ref.watch(cyclosmOverlayProvider);
    final stops = ref.watch(mapStopsPreferencesProvider);
    final preferences = ref.read(mapStopsPreferencesProvider.notifier);
    final guided =
        offer == MapStopsOffer.ride &&
        ref.watch(activeGuidedRouteProvider) != null;
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        bottom: 16 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(l10n.mapLayers, style: theme.textTheme.titleMedium),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.directions_bike),
            title: Text(l10n.mapLayersCycleMap),
            subtitle: Text(l10n.mapLayersCycleMapSubtitle),
            value: cyclosm,
            onChanged: (value) =>
                unawaited(ref.read(cyclosmOverlayProvider.notifier).set(value)),
          ),
          if (offer != MapStopsOffer.none) ...[
            SwitchListTile(
              secondary: const Icon(Icons.local_cafe_outlined),
              title: Text(l10n.mapLayersStops),
              subtitle: Text(
                offer == MapStopsOffer.plan
                    ? l10n.mapLayersStopsPlanHint
                    : l10n.mapLayersStopsRideHint,
              ),
              value: stops.shown,
              onChanged: (value) => unawaited(preferences.setShown(value)),
            ),
            if (guided)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                child: SegmentedButton<bool>(
                  segments: [
                    ButtonSegment<bool>(
                      value: true,
                      icon: const Icon(Icons.route),
                      label: Text(l10n.mapLayersAlongRoute),
                    ),
                    ButtonSegment<bool>(
                      value: false,
                      icon: const Icon(Icons.crop_free),
                      label: Text(l10n.mapLayersInArea),
                    ),
                  ],
                  selected: <bool>{stops.alongRoute},
                  showSelectedIcon: false,
                  onSelectionChanged: (value) =>
                      unawaited(preferences.setAlongRoute(value.first)),
                ),
              ),
            // Still there to pick while the stops are off, but plainly not
            // on the map.
            AnimatedOpacity(
              opacity: stops.shown ? 1 : 0.45,
              duration: const Duration(milliseconds: 150),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final group in stopGroups)
                    if (stopKindsOf(l10n, group) case final kinds
                        when kinds.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                        child: SectionCaption(searchGroupLabel(l10n, group)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final kind in kinds)
                              FilterChip(
                                // A selected chip is the accent colour:
                                // its icon goes with the label on it, not
                                // with Material's default for the state.
                                avatar: Icon(
                                  poiKindIcon(kind),
                                  size: 18,
                                  color: stops.kinds.contains(kind)
                                      ? Theme.of(context).colorScheme.onPrimary
                                      : null,
                                ),
                                label: Text(gazetteerPoiKindLabel(l10n, kind)!),
                                showCheckmark: false,
                                selected: stops.kinds.contains(kind),
                                onSelected: (value) => unawaited(
                                  preferences.setKind(kind, shown: value),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

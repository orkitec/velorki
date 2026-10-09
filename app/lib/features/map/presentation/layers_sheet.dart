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
import '../../shared/application/covering_sheets.dart';
import '../../shared/presentation/stat_tile.dart';
import '../data/cycle_map_layers.dart';
import '../data/map_preferences.dart';
import '../domain/cycle_map.dart';
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
}) => coverTabSheet(
  context,
  () => showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => LayersSheet(offer: offer),
  ),
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
    final cycleMap = ref.watch(cycleMapPreferencesProvider);
    final cycleMapPrefs = ref.read(cycleMapPreferencesProvider.notifier);
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
            value: cycleMap.shown,
            onChanged: (value) => unawaited(cycleMapPrefs.setShown(value)),
          ),
          // What the cycle map draws folds away with it, as the stops'
          // kinds do; each chip shows its line, so the chips are the legend.
          AnimatedSize(
            duration: const Duration(milliseconds: 350),
            reverseDuration: const Duration(milliseconds: 250),
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            child: !cycleMap.shown
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final part in CycleMapPart.values)
                          FilterChip(
                            avatar: CycleMapPartSample(part: part),
                            label: Text(cycleMapPartLabel(l10n, part)),
                            showCheckmark: false,
                            selected: cycleMap.parts.contains(part),
                            onSelected: (value) => unawaited(
                              cycleMapPrefs.setPart(part, shown: value),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.public),
            title: Text(l10n.mapLayersOnlineCycleMap),
            subtitle: Text(l10n.mapLayersOnlineCycleMapSubtitle),
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
            // The choices that only mean something with stops on fold away
            // with the switch, as dependent settings do; what was picked is
            // kept for the next time.
            AnimatedSize(
              // Unfolding a screenful of choices wants a moment; folding
              // them away may be quicker.
              duration: const Duration(milliseconds: 350),
              reverseDuration: const Duration(milliseconds: 250),
              curve: Curves.easeInOutCubic,
              alignment: Alignment.topCenter,
              child: !stops.shown
                  ? const SizedBox(width: double.infinity)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
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
                              onSelectionChanged: (value) => unawaited(
                                preferences.setAlongRoute(value.first),
                              ),
                            ),
                          ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final group in stopGroups)
                              if (stopKindsOf(l10n, group) case final kinds
                                  when kinds.isNotEmpty) ...[
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    16,
                                    20,
                                    8,
                                  ),
                                  child: SectionCaption(
                                    searchGroupLabel(l10n, group),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
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
                                                ? Theme.of(context)
                                                      .colorScheme
                                                      .onPrimary
                                                : null,
                                          ),
                                          label: Text(
                                            gazetteerPoiKindLabel(l10n, kind)!,
                                          ),
                                          showCheckmark: false,
                                          selected: stops.kinds.contains(kind),
                                          onSelected: (value) => unawaited(
                                            preferences.setKind(
                                              kind,
                                              shown: value,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                          ],
                        ),
                      ],
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

/// What [part] is called in the Layers sheet.
String cycleMapPartLabel(AppLocalizations l10n, CycleMapPart part) =>
    switch (part) {
      CycleMapPart.infrastructure => l10n.mapCyclePartInfrastructure,
      CycleMapPart.paths => l10n.mapCyclePartPaths,
      CycleMapPart.contraflow => l10n.mapCyclePartContraflow,
      CycleMapPart.directions => l10n.mapCyclePartDirections,
      CycleMapPart.routesNational => l10n.mapCyclePartRoutesNational,
      CycleMapPart.routesRegional => l10n.mapCyclePartRoutesRegional,
      CycleMapPart.routesLocal => l10n.mapCyclePartRoutesLocal,
      CycleMapPart.surface => l10n.mapCyclePartSurface,
      CycleMapPart.barriers => l10n.mapCyclePartBarriers,
      CycleMapPart.traffic => l10n.mapCyclePartTraffic,
      CycleMapPart.mtb => l10n.mapCyclePartMtb,
    };

/// A short stroke of how the cycle map draws [part], in the colours of the
/// map under the sheet: the chip's legend.
class CycleMapPartSample extends StatelessWidget {
  /// Creates the sample.
  const CycleMapPartSample({required this.part, super.key});

  /// The part drawn.
  final CycleMapPart part;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).brightness == Brightness.dark
        ? CycleMapColors.dark
        : CycleMapColors.light;
    return SizedBox.square(
      dimension: 18,
      child: CustomPaint(painter: _SamplePainter(part, colors)),
    );
  }
}

class _SamplePainter extends CustomPainter {
  _SamplePainter(this.part, this.colors);

  final CycleMapPart part;
  final CycleMapColors colors;

  static Color _hex(String hex) =>
      Color(int.parse('FF${hex.substring(1, 7)}', radix: 16));

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    void stroke(String color, double width, {double dash = 0, double gap = 0}) {
      line
        ..color = _hex(color)
        ..strokeWidth = width;
      if (dash == 0) {
        canvas.drawLine(Offset(1, y), Offset(size.width - 1, y), line);
        return;
      }
      for (var x = 1.0; x < size.width - 1; x += dash + gap) {
        canvas.drawLine(
          Offset(x, y),
          Offset((x + dash).clamp(0, size.width - 1), y),
          line,
        );
      }
    }

    switch (part) {
      case CycleMapPart.infrastructure:
        stroke(colors.infrastructure, 3);
      case CycleMapPart.paths:
        stroke(colors.shared, 2.5, dash: 4, gap: 3);
      case CycleMapPart.contraflow:
        stroke(colors.infrastructure, 2);
        final arrow = Paint()
          ..color = _hex(colors.infrastructure)
          ..style = PaintingStyle.fill;
        canvas
          ..drawPath(
            Path()
              ..moveTo(1, y)
              ..lineTo(6, y - 4)
              ..lineTo(6, y + 4)
              ..close(),
            arrow,
          )
          ..drawPath(
            Path()
              ..moveTo(size.width - 1, y)
              ..lineTo(size.width - 6, y - 4)
              ..lineTo(size.width - 6, y + 4)
              ..close(),
            arrow,
          );
      case CycleMapPart.directions:
        stroke(colors.infrastructure, 2);
        canvas.drawPath(
          Path()
            ..moveTo(size.width / 2 - 3, y - 5)
            ..lineTo(size.width / 2 + 3, y)
            ..lineTo(size.width / 2 - 3, y + 5),
          Paint()
            ..color = _hex(colors.infrastructure)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.6
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      case CycleMapPart.routesNational:
        stroke(colors.routeNational, 7);
      case CycleMapPart.routesRegional:
        stroke(colors.routeRegional, 6);
      case CycleMapPart.routesLocal:
        stroke(colors.routeLocal, 5);
      case CycleMapPart.surface:
        stroke(colors.unpaved, 2.5, dash: 3, gap: 3);
      case CycleMapPart.traffic:
        line
          ..color = _hex(colors.limit30).withValues(alpha: 0.5)
          ..strokeWidth = 9;
        canvas.drawLine(Offset(1, y), Offset(size.width - 1, y), line);
      case CycleMapPart.mtb:
        stroke(colors.mtbMedium, 6, dash: 1.2, gap: 3);
      case CycleMapPart.barriers:
        canvas
          ..drawCircle(
            Offset(size.width / 2, y),
            5,
            Paint()..color = _hex(colors.outline),
          )
          ..drawCircle(
            Offset(size.width / 2, y),
            4,
            Paint()..color = _hex(colors.barrier),
          );
    }
  }

  @override
  bool shouldRepaint(_SamplePainter old) =>
      old.part != part || old.colors != colors;
}

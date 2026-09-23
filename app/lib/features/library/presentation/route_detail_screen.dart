import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:velorki_api/velorki_api.dart' show ShareKind;
import 'package:velorki_geo/velorki_geo.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/files/track_exporter.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../assistant/presentation/describe_route_sheet.dart';
import '../../integrations/presentation/route_send_menu.dart';
import '../../map/domain/map_controller.dart';
import '../../map/presentation/shared_map_layers.dart';
import '../../planner/application/planner_controller.dart';
import '../../planner/data/route_repository.dart';
import '../../planner/domain/elevation_profile.dart';
import '../../planner/domain/saved_route.dart';
import '../../planner/domain/waypoint.dart';
import '../../planner/presentation/elevation_profile_chart.dart';
import '../../navigation/application/route_cues.dart';
import '../../navigation/presentation/cue_sheet_list.dart';
import '../../navigation/presentation/cue_sheet_map.dart';
import '../../navigation/presentation/turn_phrases.dart';
import '../../planner/presentation/route_format.dart';
import '../../planner/presentation/route_stats_row.dart';
import '../../planner/presentation/surface_stats_bar.dart';
import '../../settings/data/units.dart';
import '../../shared/presentation/docking_sheet.dart';
import '../../shared/presentation/placeholder_body.dart';
import '../../shared/presentation/sheet_header.dart';
import '../../sharing/presentation/share_link_button.dart';

/// Id of a saved route's line on the shared map, while its card shows.
const String libraryRouteLineId = 'library-route';

/// One saved route as the Library card's content: the route on the shared
/// map, and under the header the statistics, the actions, the elevation
/// profile and, for a route that has one, the cue sheet.
class RouteDetailScreen extends ConsumerStatefulWidget {
  /// Creates the detail for the route with [routeId].
  const RouteDetailScreen({required this.routeId, super.key});

  /// Id of the route in the `routes` table.
  final String routeId;

  @override
  ConsumerState<RouteDetailScreen> createState() => _RouteDetailScreenState();
}

class _RouteDetailScreenState extends ConsumerState<RouteDetailScreen>
    with SharedMapLayers<RouteDetailScreen> {
  String? _shownRouteId;

  /// How the camera fit keeps the route clear of the card: read off the
  /// screen once the dependencies are there.
  EdgeInsets _fitPadding = const EdgeInsets.all(48);
  bool _started = false;

  /// The cue sheet, to scroll it into view when a marker is tapped.
  final GlobalKey _cueSheetKey = GlobalKey();

  @override
  String get layersTab => libraryRoute;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _fitPadding = cardFitPadding(context);
    if (_started) return;
    _started = true;
    initLayers();
  }

  @override
  void dispose() {
    disposeLayers();
    super.dispose();
  }

  @override
  void drawLayers(MapController map) {
    _shownRouteId = null;
    final route = ref.read(savedRouteProvider(widget.routeId)).value;
    if (route != null) unawaited(_showOnMap(route));
  }

  @override
  void clearLayers(MapController map) {
    _shownRouteId = null;
    map.onPoiTapped = null;
    map.onTurnTapped = null;
    unawaited(map.removeRouteLine(libraryRouteLineId));
    unawaited(map.setWaypoints(const <MapWaypoint>[]));
    unawaited(map.setPois(const <MapPoi>[]));
    unawaited(map.setTurnMarkers(const <MapTurnMarker>[]));
    unawaited(map.setSearchPin(null));
  }

  Future<void> _showOnMap(SavedRoute route) async {
    final map = layersMap;
    if (map == null || _shownRouteId == route.id) return;
    _shownRouteId = route.id;
    final positions = route.geometry.map((p) => p.pos).toList(growable: false);
    if (positions.isEmpty) return;
    _cues = routeCuesFor(positions, turns: route.turns, pois: route.pois);
    _cuesRouteId = route.id;
    await map.setRouteLine(libraryRouteLineId, positions);
    showCuesOnMap(
      map,
      _cues,
      pois: route.pois,
      onCueTapped: (index) => _selectCue(index),
    );
    await map.fitBounds(
      BoundingBox.fromPoints(positions),
      padding: _fitPadding,
    );
  }

  /// The route's cue sheet, worked out once per route.
  List<RouteCue> _cues = const <RouteCue>[];
  String? _cuesRouteId;
  int? _selectedCue;

  List<RouteCue> _cuesFor(SavedRoute route) {
    if (_cuesRouteId != route.id) {
      _cues = routeCuesFor(
        route.geometry.map((p) => p.pos).toList(growable: false),
        turns: route.turns,
        pois: route.pois,
      );
      _cuesRouteId = route.id;
    }
    return _cues;
  }

  /// Selects a cue, from the list or from the map, takes the map there and
  /// brings the sheet's line into view.
  void _selectCue(int index) {
    if (!mounted || index < 0 || index >= _cues.length) return;
    setState(() => _selectedCue = index);
    final map = layersMap;
    if (map != null) {
      final cue = _cues[index];
      final l10n = AppLocalizations.of(context);
      final label =
          cue.poi?.name ?? (cue.turn == null ? '' : turnLabel(cue.turn!, l10n));
      unawaited(goToCue(map, cue, label));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _cueSheetKey.currentContext;
      if (context == null || !mounted) return;
      unawaited(
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 250),
          alignment: 0.1,
        ),
      );
    });
  }

  Future<void> _export(SavedRoute route, TrackFormat format) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(trackExporterProvider)
          .share(
            name: route.name,
            points: route.geometry,
            kind: TrackKind.route,
            format: format,
            // The route's own points, and every waypoint the rider named or
            // wrote a note on, so the file carries what the plan knew.
            pois: [...route.pois, ...waypointPois(route.waypoints)],
          );
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(l10n.exportFailed)));
    }
  }

  void _openInPlanner(SavedRoute route) {
    ref.read(plannerControllerProvider.notifier).loadSavedRoute(route);
    context.go(plannerRoute);
  }

  @override
  Widget build(BuildContext context) {
    listenLayers();
    final l10n = AppLocalizations.of(context);
    final units = ref.watch(unitSystemProvider);
    final route = ref.watch(savedRouteProvider(widget.routeId));

    return CustomScrollView(
      controller: SheetContentScroll.maybeOf(context),
      slivers: [
        SliverSheetHeader(
          leading: BackButton(onPressed: () => context.go(libraryRoute)),
          title: route.value?.name ?? l10n.tabLibrary,
        ),
        route.when(
          loading: () => const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => SliverFillRemaining(
            hasScrollBody: false,
            child: PlaceholderBody(
              icon: Icons.error_outline,
              message: error.toString(),
            ),
          ),
          data: (saved) {
            if (saved == null) {
              return SliverFillRemaining(
                hasScrollBody: false,
                child: PlaceholderBody(
                  icon: Icons.help_outline,
                  message: l10n.routeDetailNotFound,
                ),
              );
            }
            unawaited(_showOnMap(saved));
            final theme = Theme.of(context);
            final geometry = saved.geometry;
            final bottom = MediaQuery.paddingOf(context).bottom + 24;
            final cues = _cuesFor(saved);
            // Built whole rather than lazily: the actions are below the
            // fold, and they have to exist to be found.
            return SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, bottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.libraryRouteSubtitle(
                        formatDate(l10n, saved.createdAt),
                        profileLabel(l10n, saved.profile),
                        formatHeight(l10n, units, saved.ascentM),
                      ),
                      style: theme.textTheme.bodySmall,
                    ),
                    if (saved.description != null &&
                        saved.description!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        saved.description!,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                    const SizedBox(height: 20),
                    RouteStatsRow(
                      distanceM: saved.distanceM,
                      ascentM: saved.ascentM,
                      descentM: saved.descentM,
                      duration: saved.estimatedTime,
                    ),
                    const SizedBox(height: 20),
                    // The one thing a saved route is usually opened for gets
                    // the full-width pill, right under the figures so it is
                    // in view at the card's resting height; the rest wraps
                    // underneath, and the surfaces follow.
                    SizedBox(
                      height: primaryButtonHeight,
                      child: FilledButton.icon(
                        onPressed: () => _openInPlanner(saved),
                        icon: const Icon(Icons.route_outlined),
                        label: Text(l10n.routeDetailOpenInPlanner),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        // A route exports as a GPX <rte> or as a FIT course;
                        // the activity forms belong to a ride.
                        MenuAnchor(
                          builder: (context, controller, _) =>
                              OutlinedButton.icon(
                                onPressed: () => controller.isOpen
                                    ? controller.close()
                                    : controller.open(),
                                icon: const Icon(Icons.ios_share),
                                label: Text(l10n.routeDetailExport),
                              ),
                          menuChildren: [
                            MenuItemButton(
                              onPressed: () =>
                                  unawaited(_export(saved, TrackFormat.gpx)),
                              child: Text(l10n.exportGpxRoute),
                            ),
                            MenuItemButton(
                              onPressed: () =>
                                  unawaited(_export(saved, TrackFormat.fit)),
                              child: Text(l10n.exportFitCourse),
                            ),
                          ],
                        ),
                        RouteSendMenu(
                          route: saved,
                          onExportGpx: () => _export(saved, TrackFormat.gpx),
                        ),
                        ShareLinkButton(
                          name: saved.name,
                          points: geometry,
                          kind: ShareKind.route,
                          distanceM: saved.distanceM,
                          ascentM: saved.ascentM,
                          pois: saved.pois,
                        ),
                        DescribeRouteButton(route: saved),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SurfaceStatsBar(stats: saved.surfaceStats),
                    const SizedBox(height: 28),
                    ElevationProfileChart(
                      samples: elevationProfile(geometry),
                      height: 220,
                    ),
                    if (cues.length > 1) ...[
                      const SizedBox(height: 28),
                      CueSheetList(
                        key: _cueSheetKey,
                        cues: cues,
                        selected: _selectedCue,
                        onSelect: _selectCue,
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

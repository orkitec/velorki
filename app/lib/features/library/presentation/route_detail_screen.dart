import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:velorki_api/velorki_api.dart' show ShareKind;
import 'package:velorki_geo/velorki_geo.dart';

import '../../../app/router.dart';
import '../../../core/files/track_exporter.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../assistant/presentation/describe_route_sheet.dart';
import '../../integrations/presentation/route_send_menu.dart';
import '../../map/domain/map_controller.dart';
import '../../planner/application/planner_controller.dart';
import '../../planner/application/planner_map_binding.dart';
import '../../planner/data/route_repository.dart';
import '../../planner/domain/elevation_profile.dart';
import '../../planner/domain/saved_route.dart';
import '../../planner/presentation/elevation_profile_chart.dart';
import '../../planner/presentation/planner_map_host.dart';
import '../../planner/presentation/route_format.dart';
import '../../planner/presentation/route_stats_row.dart';
import '../../planner/presentation/surface_stats_bar.dart';
import '../../shared/presentation/placeholder_body.dart';
import '../../sharing/presentation/share_link_button.dart';

/// One saved route: map preview, statistics, elevation profile.
class RouteDetailScreen extends ConsumerStatefulWidget {
  /// Creates the detail screen for the route with [routeId].
  const RouteDetailScreen({required this.routeId, super.key});

  /// Id of the route in the `routes` table.
  final String routeId;

  @override
  ConsumerState<RouteDetailScreen> createState() => _RouteDetailScreenState();
}

class _RouteDetailScreenState extends ConsumerState<RouteDetailScreen> {
  MapController? _map;
  String? _shownRouteId;

  // Called from the map widget's build, so it must not call setState.
  void _onMapReady(MapController controller) {
    _map = controller;
    _shownRouteId = null;
    final route = ref.read(savedRouteProvider(widget.routeId)).value;
    if (route != null) unawaited(_showOnMap(route));
  }

  Future<void> _showOnMap(SavedRoute route) async {
    final map = _map;
    if (map == null || _shownRouteId == route.id) return;
    _shownRouteId = route.id;
    final positions = route.geometry.map((p) => p.pos).toList(growable: false);
    if (positions.isEmpty) return;
    await map.setRouteLine(mainRouteLineId, positions);
    await map.fitBounds(BoundingBox.fromPoints(positions));
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
    final l10n = AppLocalizations.of(context);
    final route = ref.watch(savedRouteProvider(widget.routeId));

    return Scaffold(
      appBar: AppBar(
        title: Text(route.value?.name ?? l10n.tabLibrary),
        leading: BackButton(onPressed: () => context.go(libraryRoute)),
      ),
      body: route.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => PlaceholderBody(
          icon: Icons.error_outline,
          message: error.toString(),
        ),
        data: (saved) {
          if (saved == null) {
            return PlaceholderBody(
              icon: Icons.help_outline,
              message: l10n.routeDetailNotFound,
            );
          }
          unawaited(_showOnMap(saved));
          final theme = Theme.of(context);
          final geometry = saved.geometry;
          return ListView(
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom + 24,
            ),
            children: [
              // Full-bleed hero: the route is the headline of this screen.
              SizedBox(
                height: 260,
                child: PlannerMapHost(onMapReady: _onMapReady, embedded: true),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.libraryRouteSubtitle(
                        formatDate(l10n, saved.createdAt),
                        profileLabel(l10n, saved.profile),
                        formatHeight(l10n, saved.ascentM),
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
                    const SizedBox(height: 24),
                    ElevationProfileChart(samples: elevationProfile(geometry)),
                    const SizedBox(height: 24),
                    SurfaceStatsBar(stats: saved.surfaceStats),
                    const SizedBox(height: 24),
                    // The one thing a saved route is usually opened for gets
                    // the full-width pill; the rest wraps underneath.
                    FilledButton.icon(
                      onPressed: () => _openInPlanner(saved),
                      icon: const Icon(Icons.route_outlined),
                      label: Text(l10n.routeDetailOpenInPlanner),
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
                        ),
                        DescribeRouteButton(route: saved),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

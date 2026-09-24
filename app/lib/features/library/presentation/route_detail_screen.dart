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
import '../../planner/domain/route_poi.dart';
import '../../planner/domain/route_waypoints.dart';
import '../../planner/domain/waypoint.dart';
import '../../planner/presentation/elevation_profile_chart.dart';
import '../../navigation/application/route_cues.dart';
import '../../navigation/application/route_geometry.dart';
import 'edit_text_dialog.dart';
import '../../planner/presentation/waypoint_edit_sheet.dart';
import '../../../core/db/database.dart' show RouteSource;
import '../../../core/links/link_opener.dart';
import '../../navigation/presentation/cue_sheet_list.dart';
import '../../navigation/presentation/cue_sheet_map.dart';
import '../../navigation/presentation/turn_phrases.dart';
import '../../planner/presentation/route_format.dart';
import '../../planner/presentation/route_stats_row.dart';
import '../../planner/presentation/surface_section.dart';
import '../application/route_surface.dart';
import '../../settings/data/units.dart';
import '../../map/presentation/map_chrome.dart';
import '../../map/presentation/visible_map_padding.dart';
import '../../shared/presentation/docking_sheet.dart';
import '../../shared/presentation/button_menu.dart';
import '../../shared/presentation/stat_tile.dart';
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
    // The card rests once the detail is on screen, so the fit aims there.
    _fitPadding = visibleMapPadding(context, chromeTop: defaultMapControlsTop);
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

  /// The draws, one after the other: the build asks for one on every
  /// route it sees and the layers mixin on every (re)draw, and two writes
  /// of the same line racing each other on the map lost one of them. A
  /// call for a route that a newer one has overtaken by the time its turn
  /// comes draws nothing.
  Future<void> _draws = Future<void>.value();
  String? _wantedVersion;

  /// The version a second draw is pending for, so a map that was not ready
  /// gets one more draw, not one per draw it missed.
  String? _retryFor;

  Future<void> _showOnMap(SavedRoute route) {
    final version = _versionOf(route);
    if (layersMap == null || _shownRouteId == version) {
      return Future<void>.value();
    }
    _wantedVersion = version;
    return _draws = _draws
        .then((_) => _draw(route, version))
        .catchError((Object _) {});
  }

  Future<void> _draw(SavedRoute route, String version) async {
    if (!mounted || _wantedVersion != version || _shownRouteId == version) {
      return;
    }
    final map = layersMap;
    if (map == null) return;
    _shownRouteId = version;
    final positions = route.geometry.map((p) => p.pos).toList(growable: false);
    if (positions.isEmpty) return;
    final pois = _poisOf(route);
    _cues = routeCuesFor(positions, turns: route.turns, pois: pois);
    _cuePois = pois;
    _cuesRouteId = route.id;
    final ready = map.isReady;
    await map.setRouteLine(libraryRouteLineId, positions);
    showCuesOnMap(
      map,
      _cues,
      pois: pois,
      onCueTapped: (index) => _selectCue(index),
    );
    await map.fitBounds(
      BoundingBox.fromPoints(positions),
      padding: _fitPadding,
    );
    // Drawn onto a map that was still loading its style: the map replays
    // what it remembers once the style is there, and this draws it once
    // more a moment later in case the replay lost the line.
    if ((!ready || !map.isReady) && _retryFor != version) {
      _retryFor = version;
      await Future<void>.delayed(const Duration(seconds: 1));
      if (_retryFor == version) _retryFor = null;
      if (!mounted || _wantedVersion != version) return;
      final again = layersMap;
      if (again == null || !again.isReady) return;
      await again.setRouteLine(libraryRouteLineId, positions);
      showCuesOnMap(
        again,
        _cues,
        pois: pois,
        onCueTapped: (index) => _selectCue(index),
      );
    }
  }

  /// What the Surface section shows: the router's own figures for a route
  /// planned here, otherwise the matching of its track.
  ///
  /// The answer is kept by the provider, not here. Kept in this State it was
  /// lost whenever the card's subtree was rebuilt from scratch, and the
  /// section went back to "matching" and forward to its answer over and
  /// over, each turn a different height.
  AsyncValue<TrackSurface> _surfaceOf(SavedRoute route) {
    final planned = route.surfaceStats;
    return planned != null
        ? AsyncData<TrackSurface>(TrackSurface.matched(planned))
        : ref.watch(routeSurfaceProvider(route.id));
  }

  /// The route's cue sheet, worked out once per route, and the points it
  /// refers to, which selecting a cue has to draw again.
  List<RouteCue> _cues = const <RouteCue>[];
  List<RoutePoi> _cuePois = const <RoutePoi>[];
  String? _cuesRouteId;
  int? _selectedCue;

  List<RouteCue> _cuesFor(SavedRoute route) {
    if (_cuesRouteId != _versionOf(route)) {
      _cuePois = _poisOf(route);
      _cues = routeCuesFor(
        route.geometry.map((p) => p.pos).toList(growable: false),
        turns: route.turns,
        pois: _cuePois,
      );
      _cuesRouteId = _versionOf(route);
    }
    return _cues;
  }

  /// Which version of a route the cues and the map layers were made from:
  /// the planner writes waypoint details back to a saved route while this
  /// card may be open, and the card has to show them.
  static String _versionOf(SavedRoute route) =>
      '${route.id}@${route.updatedAt.microsecondsSinceEpoch}';

  /// The route's own points of interest and every waypoint the rider named
  /// or wrote a note on: the cue sheet, the map and the export tell them
  /// apart no more than the rider does.
  static List<RoutePoi> _poisOf(SavedRoute route) => [
    ...route.pois,
    ...waypointPois(route.waypoints),
  ];

  /// Selects a cue, from the list or from the map, takes the map there and
  /// brings the sheet's line into view.
  void _selectCue(int index) {
    if (!mounted || index < 0 || index >= _cues.length) return;
    setState(() => _selectedCue = index);
    final map = layersMap;
    if (map != null) {
      final cue = _cues[index];
      final l10n = AppLocalizations.of(context);
      unawaited(
        goToCue(
          map,
          _cues,
          index,
          pois: _cuePois,
          onCueTapped: _selectCue,
          turnLabel: cue.turn == null ? '' : turnLabel(cue.turn!, l10n),
        ),
      );
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

  Future<void> _editDescription(SavedRoute route) async {
    final l10n = AppLocalizations.of(context);
    final text = await showEditTextDialog(
      context,
      title: l10n.routeDetailDescription,
      initial: route.description,
      maxLines: 5,
    );
    if (text == null || !mounted) return;
    await ref.read(routeRepositoryProvider).setDescription(route.id, text);
  }

  Future<void> _editLink(SavedRoute route) async {
    final l10n = AppLocalizations.of(context);
    final text = await showEditTextDialog(
      context,
      title: l10n.routeDetailLink,
      initial: route.link,
      hint: 'https://',
      keyboardType: TextInputType.url,
    );
    if (text == null || !mounted) return;
    await ref.read(routeRepositoryProvider).setLink(route.id, text);
  }

  Future<void> _openLink(String link) async {
    final url = Uri.tryParse(link.contains('://') ? link : 'https://$link');
    if (url == null) return;
    await ref.read(linkOpenerProvider)(url);
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
            pois: _poisOf(route),
            turns: route.turns,
            // A file that named no bike goes back out naming none.
            profile: route.profileKnown ? route.profile : null,
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
                    if (sourceLine(l10n, saved) case final source?) ...[
                      const SizedBox(height: 4),
                      Text(source, style: theme.textTheme.bodySmall),
                    ],
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
                        ButtonMenu<TrackFormat>(
                          icon: Icons.ios_share,
                          label: l10n.routeDetailExport,
                          onSelected: (format) =>
                              unawaited(_export(saved, format)),
                          entries: [
                            PopupMenuItem(
                              value: TrackFormat.gpx,
                              child: Text(l10n.exportGpxRoute),
                            ),
                            PopupMenuItem(
                              value: TrackFormat.fit,
                              child: Text(l10n.exportFitCourse),
                            ),
                            PopupMenuItem(
                              value: TrackFormat.tcx,
                              child: Text(l10n.exportTcxCourse),
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
                    const SizedBox(height: 16),
                    // The route's own words and where it came from, each
                    // a row the rider can change: a description typed
                    // here stands where the model's or the file's did.
                    _DetailRow(
                      icon: Icons.notes_outlined,
                      label: l10n.routeDetailDescription,
                      value: saved.description,
                      empty: l10n.routeDetailAddDescription,
                      onEdit: () => _editDescription(saved),
                    ),
                    _DetailRow(
                      icon: Icons.link,
                      label: l10n.routeDetailLink,
                      value: saved.link,
                      empty: l10n.routeDetailAddLink,
                      onTap: saved.link == null
                          ? null
                          : () => _openLink(saved.link!),
                      onEdit: () => _editLink(saved),
                    ),
                    const SizedBox(height: 16),
                    // One widget at this place whatever the answer is. A
                    // branch that swapped the bar for another widget when
                    // the figures arrived remounted the card's subtree, and
                    // the card draws the route on the shared map from its
                    // own build, so it went round that path again and again.
                    SurfaceSection(
                      surface: _surfaceOf(saved),
                      hideWithoutRouting: false,
                    ),
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
                    // The places the file knew that are not on the way:
                    // the cue sheet has the ones on the track, these are
                    // the rest, with what the file said about them.
                    if (offTrackPois(saved) case final beside
                        when beside.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      SectionCaption(l10n.routeDetailPois),
                      const SizedBox(height: 4),
                      for (final poi in beside)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(poiIcon(poi.kind)),
                          title: Text(
                            poi.name.isEmpty
                                ? poiKindLabel(l10n, poi.kind)
                                : poi.name,
                          ),
                          subtitle: Text(
                            [
                              poiKindLabel(l10n, poi.kind),
                              ?poi.description,
                            ].join(' · '),
                          ),
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

/// Where a route came from, for the line under its name: the format of the
/// file and who wrote it. Nothing for a route planned here.
String? sourceLine(AppLocalizations l10n, SavedRoute route) {
  final format = switch (route.source) {
    RouteSource.importedGpx => l10n.importFormatGpx,
    RouteSource.importedFit => l10n.importFormatFit,
    RouteSource.importedTcx => l10n.importFormatTcx,
    RouteSource.strava => 'Strava',
    RouteSource.rwgps => 'Ride with GPS',
    RouteSource.planned || RouteSource.loop => null,
  };
  if (format == null) return null;
  final creator = route.creator?.trim();
  return creator == null || creator.isEmpty
      ? l10n.cardImportedFrom(format)
      : l10n.cardImportedFromBy(format, creator);
}

/// The route's points of interest that are not on its track: the ones the
/// cue sheet leaves out.
List<RoutePoi> offTrackPois(SavedRoute route) {
  final line = route.geometry.map((p) => p.pos).toList(growable: false);
  if (line.length < 2) return route.pois;
  final cumulative = cumulativeDistances(line);
  return [
    for (final poi in route.pois)
      if (projectOnLine(line, poi.pos, cumulative: cumulative).distanceM >
          poiOnTrackM)
        poi,
  ];
}

/// One line of the card the rider can change: its label, its value or an
/// invitation, and a pencil.
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.empty,
    required this.onEdit,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? value;
  final String empty;
  final VoidCallback onEdit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final has = value != null && value!.trim().isNotEmpty;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label, style: theme.textTheme.bodySmall),
      subtitle: Text(
        has ? value!.trim() : empty,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: has ? null : theme.colorScheme.onSurfaceVariant,
        ),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        icon: const Icon(Icons.edit_outlined),
        onPressed: onEdit,
      ),
      onTap: onTap ?? onEdit,
    );
  }
}

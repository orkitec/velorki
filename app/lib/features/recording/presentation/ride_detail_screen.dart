import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:velorki_api/velorki_api.dart' show ShareKind;
import 'package:velorki_geo/velorki_geo.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/files/track_exporter.dart';
import '../../../core/geo/ride_analysis.dart';
import '../../../core/geo/ride_stats.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../integrations/common/domain/connected_account.dart';
import '../../integrations/presentation/integration_labels.dart';
import '../../integrations/presentation/ride_upload_menu.dart';
import '../../map/domain/map_controller.dart';
import '../../map/presentation/shared_map_layers.dart';
import '../../planner/domain/route_poi.dart';
import '../../planner/domain/saved_route.dart';
import '../../planner/presentation/poi_markers.dart';
import '../../planner/presentation/route_format.dart';
import '../../planner/presentation/surface_stats_bar.dart';
import '../../settings/data/units.dart';
import '../../map/presentation/map_chrome.dart';
import '../../map/presentation/visible_map_padding.dart';
import '../../shared/presentation/docking_sheet.dart';
import '../../shared/presentation/sheet_header.dart';
import '../../shared/presentation/stat_tile.dart';
import '../../shared/presentation/placeholder_body.dart';
import '../../sharing/presentation/share_link_button.dart';
import '../application/recording_controller.dart';
import '../application/ride_analysis_provider.dart';
import '../application/ride_highlight.dart';
import '../application/ride_route_provider.dart';
import '../application/ride_surface.dart';
import '../data/recording_settings.dart';
import '../data/recording_service.dart';
import '../data/ride_repository.dart';
import '../data/ride_view_settings.dart';
import '../data/rider_profile_settings.dart';
import '../domain/calories.dart';
import '../domain/poi_marks.dart';
import '../domain/power_defaults.dart';
import '../domain/ride.dart';
import '../domain/ride_range.dart';
import 'recording_format.dart';
import 'rename_ride_dialog.dart';
import 'ride_charts.dart';
import 'ride_climbs.dart';
import 'ride_heart_rate_zones.dart';
import 'ride_power_zones.dart';
import 'ride_splits.dart';

/// The id of the route line the picked split or climb is drawn as on the map.
const String rideHighlightLineId = 'ride-highlight';

/// The id of the route line the route the ride followed is drawn as, under
/// the track.
const String rideRouteLineId = 'ride-route';

/// One recorded ride as the Library card's content: the track on the shared
/// map, and under the header the numbers, the charts, the splits and the
/// climbs, and the way out to a GPX or FIT file.
class RideDetailScreen extends ConsumerStatefulWidget {
  /// Creates the detail for the ride with [rideId].
  const RideDetailScreen({required this.rideId, super.key});

  /// Id of the ride in the `rides` table.
  final String rideId;

  @override
  ConsumerState<RideDetailScreen> createState() => _RideDetailScreenState();
}

class _RideDetailScreenState extends ConsumerState<RideDetailScreen>
    with SharedMapLayers<RideDetailScreen> {
  String? _shownKey;
  // The analysis as the last build saw it, so the map can be drawn when it
  // comes, which is out of turn.
  RideAnalysis? _analysis;
  // The stretch the charts are zoomed to, in metres; one for all of them,
  // so a pinch on the speed chart zooms the elevation chart to the same
  // road. `null` for the whole ride.
  RideWindow? _window;
  // The range the map has on it, so a rebuild does not redraw the same line.
  RideRange? _shownRange;
  // The route the map has on it, by id; empty for none, which is also what
  // a fresh map has.
  String _shownRouteKey = '';
  // The chart marks as last worked out, and what they were worked out
  // from: a scroll rebuilds the page, and the marks walk the whole track.
  List<PoiMark> _marks = const <PoiMark>[];
  SavedRoute? _marksRoute;
  RideAnalysis? _marksAnalysis;

  /// How the camera fit keeps the track clear of the card: read off the
  /// screen once the dependencies are there.
  EdgeInsets _fitPadding = const EdgeInsets.all(48);
  bool _started = false;

  /// The split or climb picked, kept outside this state for the chip the
  /// card draws over the map; captured here for the clear on dispose.
  late final RideHighlight _highlight;

  @override
  String get layersTab => libraryRoute;

  @override
  void initState() {
    super.initState();
    _highlight = ref.read(rideHighlightProvider.notifier);
  }

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
    // Deferred: the tree is locked while a widget goes, and the card would
    // rebuild for the chip.
    final highlight = _highlight;
    scheduleMicrotask(() => highlight.set(null));
    super.dispose();
  }

  @override
  void drawLayers(MapController map) {
    _shownKey = null;
    _shownRange = null;
    _shownRouteKey = '';
    final ride = ref.read(rideProvider(widget.rideId)).value;
    if (ride != null) {
      unawaited(_showOnMap(ride, _analysis));
      unawaited(
        _showRangeOnMap(ride, _analysis, ref.read(rideHighlightProvider)),
      );
    }
    unawaited(
      _showRouteOnMap(
        ref.read(rideRouteProvider(widget.rideId)).value,
        ref.read(showRideRouteProvider),
      ),
    );
  }

  @override
  void clearLayers(MapController map) {
    _shownKey = null;
    _shownRange = null;
    _shownRouteKey = '';
    map.onPoiTapped = null;
    unawaited(map.setTrackLine(const <LatLng>[]));
    unawaited(map.removeRouteLine(rideRouteLineId));
    unawaited(map.removeRouteLine(rideHighlightLineId));
    unawaited(map.setPois(const <MapPoi>[]));
    unawaited(map.setSearchPin(null));
  }

  /// Draws the route the ride followed under the track, with its points of
  /// interest, or takes both off again when [show] is off or there is no
  /// route (any more).
  Future<void> _showRouteOnMap(SavedRoute? route, bool show) async {
    final map = layersMap;
    if (map == null) return;
    final shown = show ? route : null;
    final key = shown == null ? '' : '${shown.id}:${shown.updatedAt}';
    if (key == _shownRouteKey) return;
    _shownRouteKey = key;
    if (shown == null) {
      map.onPoiTapped = null;
      await map.removeRouteLine(rideRouteLineId);
      await map.setPois(const <MapPoi>[]);
      await map.setSearchPin(null);
      return;
    }
    final pois = shown.pois;
    map.onPoiTapped = (index) {
      if (index < pois.length) unawaited(_showPoi(map, pois, index));
    };
    final positions = shown.geometry.map((p) => p.pos).toList(growable: false);
    if (positions.length >= 2) {
      // The subdued style, and under the track: the ride is the subject.
      await map.setRouteLine(
        rideRouteLineId,
        positions,
        style: RouteLineStyle.alternative,
      );
    }
    await map.setPois(poiMarkers(pois));
  }

  /// Draws the place at [index] as the chosen one and takes the map there,
  /// as the route page does for a tapped marker.
  ///
  /// The marker itself carries the choice — a wider disc in the chosen
  /// colour, its icon and its one name — rather than a pin dropped on top,
  /// which hid the icon and wrote the name a second time.
  Future<void> _showPoi(
    MapController map,
    List<RoutePoi> pois,
    int index,
  ) async {
    await map.setPois(poiMarkers(pois, selected: index));
    await map.moveTo(pois[index].pos);
  }

  /// Where along the ride the route's points of interest were passed, for
  /// the elevation chart; worked out once per route and analysis.
  List<PoiMark> _marksFor(
    Ride ride,
    SavedRoute? route,
    RideAnalysis? analysis,
  ) {
    if (route == null || analysis == null) return const <PoiMark>[];
    if (!identical(route, _marksRoute) ||
        !identical(analysis, _marksAnalysis)) {
      _marksRoute = route;
      _marksAnalysis = analysis;
      _marks = poiMarks(route.pois, ride.points, analysis.distanceAt);
    }
    return _marks;
  }

  void _select(RideRange? range) => _highlight.set(range);

  void _setWindow(RideWindow? window) {
    if (window == _window) return;
    setState(() => _window = window);
  }

  /// Draws [range] over the track as a route line in the accent, or takes
  /// it off again; the line is separate from the track, so the track is
  /// never redrawn for it.
  Future<void> _showRangeOnMap(
    Ride ride,
    RideAnalysis? analysis,
    RideRange? range,
  ) async {
    final map = layersMap;
    if (map == null) return;
    if (range == _shownRange) return;
    _shownRange = range;
    if (range == null) {
      await map.removeRouteLine(rideHighlightLineId);
      return;
    }
    final points = trackSlice(
      ride.positions,
      analysis?.distanceAt ?? const <double>[],
      startM: range.startM,
      endM: range.endM,
    );
    if (points.length < 2) {
      await map.removeRouteLine(rideHighlightLineId);
      return;
    }
    await map.setRouteLine(rideHighlightLineId, points);
  }

  /// Draws the ride and fits the camera to it.
  ///
  /// The track goes on coloured by speed as soon as the analysis is there;
  /// until then, and for a ride whose fixes carry no times, it is the plain
  /// line the recorder draws.
  Future<void> _draws = Future<void>.value();
  String? _wantedKey;

  /// One draw after the other, as the route card does it: the build asks
  /// for one on every ride and analysis it sees, and a call overtaken by a
  /// newer one draws nothing.
  Future<void> _showOnMap(Ride ride, RideAnalysis? analysis) {
    if (layersMap == null) return Future<void>.value();
    final bands = analysis?.speedBands.segments ?? const <SpeedBandSegment>[];
    final key = '${ride.id}:${bands.length}';
    if (_shownKey == key) return Future<void>.value();
    _wantedKey = key;
    return _draws = _draws
        .then((_) => _draw(ride, bands, key))
        .catchError((Object _) {});
  }

  Future<void> _draw(
    Ride ride,
    List<SpeedBandSegment> bands,
    String key,
  ) async {
    if (!mounted || _wantedKey != key || _shownKey == key) return;
    final map = layersMap;
    if (map == null) return;
    _shownKey = key;
    final positions = ride.positions;
    if (positions.isEmpty) return;
    if (bands.isEmpty) {
      await map.setTrackLine(positions);
    } else {
      await map.setTrackSegments(<TrackSegment>[
        for (final band in bands) TrackSegment(points: band.points, t: band.t),
      ]);
    }
    final bounds = ride.bounds;
    if (bounds != null) await map.fitBounds(bounds, padding: _fitPadding);
  }

  Future<void> _rename(Ride ride) async {
    final name = await showRenameRideDialog(context, initialName: ride.name);
    if (name == null) return;
    await ref.read(rideRepositoryProvider).rename(ride.id, name);
  }

  Future<void> _delete(Ride ride) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final repository = ref.read(rideRepositoryProvider);
    await repository.delete(ride.id);
    router.go(libraryRoute);
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.rideDeleted(ride.name)),
        action: SnackBarAction(
          label: l10n.commonUndo,
          onPressed: () => unawaited(repository.save(ride)),
        ),
      ),
    );
  }

  /// Hands the ride back to the recorder and shows the record tab, where the
  /// live panel carries on from the ride's own figures.
  ///
  /// Only a recorder that is already busy needs a decision from the rider —
  /// that ride is finished and saved first — and so does a ride that has been
  /// sent somewhere, because continuing it means sending it again.
  Future<void> _continue(Ride ride) async {
    final l10n = AppLocalizations.of(context);
    final router = GoRouter.of(context);
    final controller = ref.read(recordingControllerProvider.notifier);
    final running = await ref.read(recordingServiceProvider).isRunning;
    if (!mounted) return;
    if ((running || ride.uploads.isNotEmpty) &&
        !await _confirmContinue(ride, running: running)) {
      return;
    }
    if (running) {
      await controller.stop(
        rideName: l10n.recordingRideName(formatDate(l10n, DateTime.now())),
      );
    }
    await controller.continueRide(
      ride,
      notificationTitle: l10n.recordingNotificationTitle,
    );
    router.go(recordingRoute);
  }

  Future<bool> _confirmContinue(Ride ride, {required bool running}) async {
    final l10n = AppLocalizations.of(context);
    final services = _uploadedServices(l10n, ride);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.rideContinue),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.rideContinueBody),
            if (running) ...[
              const SizedBox(height: 12),
              Text(l10n.rideContinueRunning),
            ],
            if (services != null) ...[
              const SizedBox(height: 12),
              Text(l10n.rideContinueUploaded(services)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.rideContinue),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  /// The services [ride] was sent to, as they are written in the UI, or `null`
  /// when it was never sent anywhere.
  static String? _uploadedServices(AppLocalizations l10n, Ride ride) {
    final names = ride.uploads.keys
        .map(IntegrationService.fromId)
        .nonNulls
        .map((service) => serviceLabel(l10n, service))
        .join(', ');
    return names.isEmpty ? null : names;
  }

  Future<void> _export(Ride ride, TrackFormat format) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(trackExporterProvider)
          .share(
            name: ride.name,
            points: ride.points,
            kind: TrackKind.ride,
            format: format,
            startTime: ride.startedAt,
            temperaturesC: ride.temperaturesC,
            lapEnds: [for (final lap in ride.laps) lap.endedAt],
          );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.rideDetailExportFailed(error.toString()))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    listenLayers();
    final l10n = AppLocalizations.of(context);
    final units = ref.watch(unitSystemProvider);
    final ride = ref.watch(rideProvider(widget.rideId));
    final range = ref.watch(rideHighlightProvider);
    final route = ref.watch(rideRouteProvider(widget.rideId)).value;
    final showRoute = ref.watch(showRideRouteProvider);
    final profile = ref.watch(riderProfileProvider);
    final year = DateTime.now().year;
    // The zones need the maximum; asked for only when they are switched on,
    // so the cache key stays put for everyone else.
    final maxHeartRateBpm = profile.zones
        ? profile.effectiveMaxHeartRate(year)
        : null;
    // The power zones need the threshold, the same way.
    final thresholdPowerW = profile.powerZones ? profile.thresholdPowerW : null;
    // The power estimate needs the rider's weight; without the switch or the
    // weight there is no model, and the key stays put for everyone else.
    final weightKg = profile.weightKg;
    final powerModel = profile.estimatePower && weightKg != null
        ? powerModelForBike(
            profile.bike,
            riderKg: weightKg,
            bikeKg: profile.bikeWeightKg,
          )
        : null;
    // Computed once per ride, split length and unit system, never on a
    // rebuild.
    final analysis = ref
        .watch(
          rideAnalysisProvider((
            rideId: widget.rideId,
            splitLength: ref.watch(recordingSettingsProvider).splitLength,
            system: units,
            maxHeartRateBpm: maxHeartRateBpm,
            thresholdPowerW: thresholdPowerW,
            powerModel: powerModel,
          )),
        )
        .value;
    // A new analysis (another unit, another split length) has other rows:
    // neither the pick nor the zoom carries over. The pick goes after the
    // frame, since a build may not write a provider.
    if (!identical(analysis, _analysis)) {
      _window = null;
      if (range != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _highlight.set(null);
        });
      }
    }
    _analysis = analysis;
    final effort = analysis?.effort;
    final calories = profile.calories && effort != null
        ? estimateCalories(profile, effort, year: year)
        : null;
    // Normalised over threshold: only with a meter, and only with a
    // threshold to hold it against.
    final normalizedPowerW = effort?.normalizedPowerW;
    final intensity = normalizedPowerW != null && thresholdPowerW != null
        ? normalizedPowerW / thresholdPowerW
        : null;

    return CustomScrollView(
      controller: SheetContentScroll.maybeOf(context),
      slivers: [
        SliverSheetHeader(
          leading: BackButton(onPressed: () => context.go(libraryRoute)),
          title: ride.value?.name ?? l10n.tabLibrary,
          actions: [
            if (ride.value != null) RideUploadMenu(ride: ride.value!),
            if (ride.value != null)
              PopupMenuButton<_RideAction>(
                onSelected: (action) => unawaited(switch (action) {
                  _RideAction.continueRide => _continue(ride.value!),
                  _RideAction.rename => _rename(ride.value!),
                  _RideAction.delete => _delete(ride.value!),
                  _RideAction.exportGpx => _export(
                    ride.value!,
                    TrackFormat.gpx,
                  ),
                  _RideAction.exportFit => _export(
                    ride.value!,
                    TrackFormat.fit,
                  ),
                  _RideAction.exportTcx => _export(
                    ride.value!,
                    TrackFormat.tcx,
                  ),
                }),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: _RideAction.exportGpx,
                    child: Text(l10n.rideDetailExportGpx),
                  ),
                  PopupMenuItem(
                    value: _RideAction.exportFit,
                    child: Text(l10n.rideDetailExportFit),
                  ),
                  PopupMenuItem(
                    value: _RideAction.exportTcx,
                    child: Text(l10n.rideDetailExportTcx),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: _RideAction.continueRide,
                    child: Text(l10n.rideContinue),
                  ),
                  PopupMenuItem(
                    value: _RideAction.rename,
                    child: Text(l10n.commonRename),
                  ),
                  PopupMenuItem(
                    value: _RideAction.delete,
                    child: Text(l10n.commonDelete),
                  ),
                ],
              ),
          ],
        ),
        ride.when(
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
                  message: l10n.rideDetailNotFound,
                ),
              );
            }
            unawaited(_showOnMap(saved, analysis));
            unawaited(_showRangeOnMap(saved, analysis, range));
            unawaited(_showRouteOnMap(route, showRoute));
            final marks = showRoute
                ? _marksFor(saved, route, analysis)
                : const <PoiMark>[];
            final theme = Theme.of(context);
            final stats = saved.stats;
            // Built whole rather than lazily: the actions are below the
            // fold, and they have to exist to be found.
            return SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  16,
                  20,
                  MediaQuery.paddingOf(context).bottom + 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (analysis != null &&
                        analysis.speedBands.segments.isNotEmpty) ...[
                      const RideSpeedLegend(),
                      const SizedBox(height: 16),
                    ],
                    Text(
                      formatDate(l10n, saved.startedAt),
                      style: theme.textTheme.bodySmall,
                    ),
                    if (rideSourceLine(l10n, saved) case final source?) ...[
                      const SizedBox(height: 4),
                      Text(source, style: theme.textTheme.bodySmall),
                    ],
                    const SizedBox(height: 20),
                    RideStatsGrid(
                      items: <RideStatItem>[
                        RideStatItem(
                          icon: Icons.straighten,
                          label: l10n.statDistance,
                          value: formatDistance(l10n, units, stats.distanceM),
                        ),
                        RideStatItem(
                          icon: Icons.schedule,
                          label: l10n.statMovingTime,
                          value: formatClock(stats.movingTime),
                        ),
                        RideStatItem(
                          icon: Icons.timelapse,
                          label: l10n.statElapsed,
                          value: formatClock(stats.elapsedTime),
                        ),
                        RideStatItem(
                          icon: Icons.speed,
                          label: l10n.statAvgSpeed,
                          value: formatSpeed(l10n, units, stats.avgSpeedMps),
                        ),
                        RideStatItem(
                          icon: Icons.bolt,
                          label: l10n.statMaxSpeed,
                          value: formatSpeed(l10n, units, stats.maxSpeedMps),
                        ),
                        RideStatItem(
                          icon: Icons.trending_up,
                          label: l10n.statAscent,
                          value: formatHeight(l10n, units, stats.ascentM),
                        ),
                        RideStatItem(
                          icon: Icons.trending_down,
                          label: l10n.statDescent,
                          value: formatHeight(l10n, units, stats.descentM),
                        ),
                        // Only what a sensor actually reported: an empty
                        // heart rate tile on every ride would say nothing.
                        if (stats.avgHeartRateBpm != null)
                          RideStatItem(
                            icon: Icons.favorite,
                            label: l10n.statAvgHeartRate,
                            value: formatHeartRate(l10n, stats.avgHeartRateBpm),
                          ),
                        if (stats.maxHeartRateBpm != null)
                          RideStatItem(
                            icon: Icons.favorite_border,
                            label: l10n.statMaxHeartRate,
                            value: formatHeartRate(l10n, stats.maxHeartRateBpm),
                          ),
                        if (stats.avgCadenceRpm != null)
                          RideStatItem(
                            icon: Icons.rotate_right,
                            label: l10n.statAvgCadence,
                            value: formatCadence(l10n, stats.avgCadenceRpm),
                          ),
                        if (effort?.maxCadenceRpm != null)
                          RideStatItem(
                            icon: Icons.rotate_right,
                            label: l10n.statMaxCadence,
                            value: formatCadence(l10n, effort!.maxCadenceRpm),
                          ),
                        if (stats.avgPowerW != null)
                          RideStatItem(
                            icon: Icons.electric_bolt,
                            label: l10n.statAvgPower,
                            value: formatPower(l10n, stats.avgPowerW),
                          ),
                        if (effort?.maxPowerW != null)
                          RideStatItem(
                            icon: Icons.electric_bolt,
                            label: l10n.statMaxPower,
                            value: formatPower(l10n, effort!.maxPowerW),
                          ),
                        // From the meter's readings alone: a ride without
                        // one has no normalised power, estimate or not.
                        if (normalizedPowerW != null)
                          RideStatItem(
                            icon: Icons.electric_bolt,
                            label: l10n.statNormalizedPower,
                            value: formatPower(l10n, normalizedPowerW),
                            detail: l10n.statNormalizedPowerDetail,
                          ),
                        if (intensity != null && thresholdPowerW != null)
                          RideStatItem(
                            icon: Icons.speed,
                            label: l10n.statIntensity,
                            value: formatIntensity(l10n, intensity),
                            detail: l10n.statIntensityDetail(
                              formatPower(l10n, thresholdPowerW),
                            ),
                          ),
                        // The estimate never stands beside a reading: a ride
                        // with a meter shows the meter and nothing else.
                        if (profile.estimatePower &&
                            stats.avgPowerW == null &&
                            effort?.estimatedAvgPowerW != null)
                          RideStatItem(
                            icon: Icons.electric_bolt,
                            label: l10n.statEstimatedPower,
                            value: formatPower(
                              l10n,
                              effort!.estimatedAvgPowerW,
                            ),
                            detail: l10n.statEstimatedDetail,
                          ),
                        // An estimate, and the tile says what it rests on.
                        if (calories != null)
                          RideStatItem(
                            icon: Icons.local_fire_department,
                            label: l10n.statCalories,
                            value: l10n.unitKcal('${calories.kcal}'),
                            detail: calorieSourceLabel(l10n, calories.source),
                          ),
                      ],
                    ),
                    // What the device itself summed up, beside the app's
                    // figures, only where the two disagree: the same number
                    // twice would say nothing.
                    if (saved.deviceTotals case final totals?
                        when deviceTotalsDiffer(totals, stats)) ...[
                      const SizedBox(height: 28),
                      SectionCaption(l10n.rideDeviceTotals),
                      const SizedBox(height: 12),
                      RideStatsGrid(
                        items: <RideStatItem>[
                          if (totals.distanceM != null)
                            RideStatItem(
                              icon: Icons.straighten,
                              label: l10n.statDistance,
                              value: formatDistance(
                                l10n,
                                units,
                                totals.distanceM!,
                              ),
                            ),
                          if (totals.movingTime != null)
                            RideStatItem(
                              icon: Icons.schedule,
                              label: l10n.statMovingTime,
                              value: formatClock(totals.movingTime!),
                            ),
                          if (totals.ascentM != null)
                            RideStatItem(
                              icon: Icons.trending_up,
                              label: l10n.statAscent,
                              value: formatHeight(l10n, units, totals.ascentM!),
                            ),
                          if (totals.calories != null)
                            RideStatItem(
                              icon: Icons.local_fire_department,
                              label: l10n.statCalories,
                              value: l10n.unitKcal('${totals.calories}'),
                            ),
                        ],
                      ),
                    ],
                    if (analysis != null) ...[
                      if (analysis.hasElevation) ...[
                        const SizedBox(height: 28),
                        RideElevationChart(
                          samples: analysis.samples,
                          highlight: range,
                          marks: <({double alongM, String label})>[
                            for (final mark in marks)
                              (alongM: mark.alongM, label: mark.poi.name),
                          ],
                          window: _window,
                          onWindow: _setWindow,
                        ),
                      ],
                      if (analysis.hasSpeed) ...[
                        const SizedBox(height: 28),
                        RideSpeedChart(
                          samples: analysis.samples,
                          highlight: range,
                          window: _window,
                          onWindow: _setWindow,
                        ),
                      ],
                      if (analysis.hasHeartRate) ...[
                        const SizedBox(height: 28),
                        RideHeartRateChart(
                          samples: analysis.samples,
                          highlight: range,
                          window: _window,
                          onWindow: _setWindow,
                        ),
                      ],
                      if (analysis.hasTemperature) ...[
                        const SizedBox(height: 28),
                        RideTemperatureChart(
                          samples: analysis.samples,
                          highlight: range,
                          window: _window,
                          onWindow: _setWindow,
                        ),
                      ],
                      if (maxHeartRateBpm != null &&
                          analysis.effort.heartRateTime > Duration.zero) ...[
                        const SizedBox(height: 28),
                        RideHeartRateZones(
                          effort: analysis.effort,
                          maxHeartRateBpm: maxHeartRateBpm,
                        ),
                      ],
                      if (thresholdPowerW != null &&
                          analysis.effort.powerTime > Duration.zero) ...[
                        const SizedBox(height: 28),
                        RidePowerZones(
                          effort: analysis.effort,
                          thresholdPowerW: thresholdPowerW,
                        ),
                      ],
                      if (analysis.splits.isNotEmpty) ...[
                        const SizedBox(height: 28),
                        RideSplitsTable(
                          splits: analysis.splits,
                          splitLengthM: analysis.splitLengthM,
                          laps: analysis.lapSplits,
                          selected: range?.selectedIn(RideRangeSource.split),
                          onSelect: (index) => _select(
                            index == null
                                ? null
                                : RideRange.ofSplit(
                                    analysis.splits[index],
                                    splitLengthM: analysis.splitLengthM,
                                  ),
                          ),
                        ),
                      ],
                      if (analysis.climbs.isNotEmpty) ...[
                        const SizedBox(height: 28),
                        RideClimbsTable(
                          climbs: analysis.climbs,
                          selected: range?.selectedIn(RideRangeSource.climb),
                          onSelect: (index) => _select(
                            index == null
                                ? null
                                : RideRange.ofClimb(
                                    analysis.climbs[index],
                                    index: index,
                                  ),
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 28),
                    RideSurfaceSection(rideId: saved.id),
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () =>
                              unawaited(_export(saved, TrackFormat.gpx)),
                          icon: const Icon(Icons.ios_share),
                          label: Text(l10n.rideDetailExportGpx),
                        ),
                        OutlinedButton.icon(
                          onPressed: () =>
                              unawaited(_export(saved, TrackFormat.fit)),
                          icon: const Icon(Icons.ios_share),
                          label: Text(l10n.rideDetailExportFit),
                        ),
                        ShareLinkButton(
                          name: saved.name,
                          points: saved.points,
                          kind: ShareKind.ride,
                          distanceM: stats.distanceM,
                          ascentM: stats.ascentM,
                          duration: stats.elapsedTime,
                        ),
                      ],
                    ),
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

enum _RideAction {
  continueRide,
  rename,
  delete,
  exportGpx,
  exportFit,
  exportTcx,
}

/// The chip over a ride's map that says what the thick line over the track
/// is: the split or the climb the rider picked, "Split 3 · 2–3 km", with a
/// dot in the line's colour before it and a cross after it. A tap anywhere
/// on it clears the pick, on the charts, in the tables and on the map.
class RideHighlightChip extends ConsumerWidget {
  /// Creates the chip for [range].
  const RideHighlightChip({
    required this.range,
    required this.onClear,
    super.key,
  });

  /// The stretch drawn on the map.
  final RideRange range;

  /// Called on a tap.
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final system = ref.watch(unitSystemProvider);
    final name = switch (range.source) {
      RideRangeSource.split => l10n.rideHighlightSplit(range.index + 1),
      RideRangeSource.climb => l10n.rideHighlightClimb(range.index + 1),
    };
    final label = l10n.rideHighlightChip(
      name,
      formatDistanceSpan(l10n, system, range.startM, range.endM),
    );
    return GlassPanel(
      radius: 22,
      child: InkWell(
        onTap: onClear,
        child: Semantics(
          button: true,
          label: label,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
            child: SizedBox(
              height: 44,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The colour the line has on the map.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.velorki.routeMain,
                      shape: BoxShape.circle,
                    ),
                    child: const SizedBox.square(dimension: 10),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.close,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the ride was ridden on, matched from the offline routing tiles: the
/// planner's surface bar once there is an answer, and until then the caption
/// with a thin progress line, so the rest of the page never waits for it.
class RideSurfaceSection extends ConsumerWidget {
  /// Creates the section for the ride [rideId].
  const RideSurfaceSection({required this.rideId, super.key});

  /// Id of the ride in the `rides` table.
  final String rideId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final quiet = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final surface = ref.watch(rideSurfaceProvider(rideId));

    Widget note(String text) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionCaption(l10n.surfaceTitle),
        const SizedBox(height: 10),
        Text(text, style: quiet),
      ],
    );

    return surface.when(
      // A write-back re-runs the provider; the answer it then reads off the
      // row is the one already on screen, so no flicker in between.
      skipLoadingOnReload: true,
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionCaption(l10n.surfaceTitle),
          const SizedBox(height: 10),
          const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 8),
          Text(l10n.rideSurfaceComputing, style: quiet),
        ],
      ),
      error: (_, _) => note(l10n.rideSurfaceUnavailable),
      data: (result) => switch (result.state) {
        RideSurfaceState.matched => SurfaceStatsBar(stats: result.stats),
        RideSurfaceState.noTiles => note(l10n.rideSurfaceNoTiles),
        RideSurfaceState.unmatched => note(l10n.rideSurfaceUnavailable),
        // A build without on-device routing has nothing to match against, and
        // a line saying the track "could not be matched" would blame the
        // track; the section simply is not there.
        RideSurfaceState.noRouting => const SizedBox.shrink(),
      },
    );
  }
}

/// What the calorie figure rests on, for the line under it.
String calorieSourceLabel(AppLocalizations l10n, CalorieSource source) =>
    switch (source) {
      CalorieSource.power => l10n.calorieSourcePower,
      CalorieSource.heartRate => l10n.calorieSourceHeartRate,
      CalorieSource.estimatedPower => l10n.calorieSourceEstimatedPower,
      CalorieSource.speed => l10n.calorieSourceSpeed,
    };

/// One figure of [RideStatsGrid].
class RideStatItem {
  /// Creates the item.
  const RideStatItem({
    required this.icon,
    required this.label,
    required this.value,
    this.detail,
  });

  /// The icon left of the label.
  final IconData icon;

  /// What the figure means.
  final String label;

  /// The figure, already formatted.
  final String value;

  /// A small line under the figure: where an estimate came from.
  final String? detail;
}

/// A wrapping grid of labelled figures, for the ride detail and the live
/// recording panel.
class RideStatsGrid extends StatelessWidget {
  /// Creates the grid.
  const RideStatsGrid({required this.items, super.key, this.columns = 3});

  /// The figures, in reading order.
  final List<RideStatItem> items;

  /// How many figures fit in a row.
  final int columns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 20,
          children: [
            for (final item in items)
              SizedBox(
                width: width,
                child: StatTile(
                  icon: item.icon,
                  label: item.label,
                  value: item.value,
                  detail: item.detail,
                  size: StatSize.medium,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Whether the device's totals say something the app's own figures do
/// not: a distance more than a percent (and a hundred metres) apart, a
/// moving time more than half a minute apart, an ascent more than five
/// percent (and ten metres) apart, or calories, which the app only
/// estimates.
bool deviceTotalsDiffer(DeviceTotals totals, RideStats stats) {
  bool apart(double? device, double own, double share, double least) =>
      device != null && (device - own).abs() > math.max(own * share, least);
  return apart(totals.distanceM, stats.distanceM, 0.01, 100) ||
      apart(
        totals.movingTime?.inSeconds.toDouble(),
        stats.movingTime.inSeconds.toDouble(),
        0,
        30,
      ) ||
      apart(totals.ascentM, stats.ascentM, 0.05, 10) ||
      totals.calories != null;
}

/// Where an imported ride came from, for the line under its date: the
/// file's format and who wrote it. Nothing for a ride recorded here.
String? rideSourceLine(AppLocalizations l10n, Ride ride) {
  final format = switch (ride.sourceFormat) {
    'gpx' => l10n.importFormatGpx,
    'fit' => l10n.importFormatFit,
    'tcx' => l10n.importFormatTcx,
    final other? => other.toUpperCase(),
    null => null,
  };
  if (format == null) return null;
  final creator = ride.creator?.trim();
  return creator == null || creator.isEmpty
      ? l10n.cardImportedFrom(format)
      : l10n.cardImportedFromBy(format, creator);
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:velorki_api/velorki_api.dart' show ShareKind;

import '../../../app/router.dart';
import '../../../core/files/track_exporter.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../integrations/presentation/ride_upload_menu.dart';
import '../../map/domain/map_controller.dart';
import '../../planner/presentation/planner_map_host.dart';
import '../../planner/presentation/route_format.dart';
import '../../shared/presentation/stat_tile.dart';
import '../../shared/presentation/placeholder_body.dart';
import '../../sharing/presentation/share_link_button.dart';
import '../data/ride_repository.dart';
import '../domain/ride.dart';
import 'recording_format.dart';
import 'rename_ride_dialog.dart';

/// The location of the detail screen for the ride [id].
String rideDetailLocation(String id) => '$recordingRoute/ride/$id';

/// One recorded ride: the track on the map, the numbers, and the way out to a
/// GPX or FIT file.
class RideDetailScreen extends ConsumerStatefulWidget {
  /// Creates the detail screen for the ride with [rideId].
  const RideDetailScreen({required this.rideId, super.key});

  /// Id of the ride in the `rides` table.
  final String rideId;

  @override
  ConsumerState<RideDetailScreen> createState() => _RideDetailScreenState();
}

class _RideDetailScreenState extends ConsumerState<RideDetailScreen> {
  MapController? _map;
  String? _shownRideId;

  // Called from the map widget's build, so it must not call setState.
  void _onMapReady(MapController controller) {
    _map = controller;
    _shownRideId = null;
    final ride = ref.read(rideProvider(widget.rideId)).value;
    if (ride != null) unawaited(_showOnMap(ride));
  }

  Future<void> _showOnMap(Ride ride) async {
    final map = _map;
    if (map == null || _shownRideId == ride.id) return;
    _shownRideId = ride.id;
    final positions = ride.positions;
    if (positions.isEmpty) return;
    await map.setTrackLine(positions);
    final bounds = ride.bounds;
    if (bounds != null) await map.fitBounds(bounds);
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
    router.go(recordingRoute);
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
          );
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.rideDetailExportFailed(error.toString()))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ride = ref.watch(rideProvider(widget.rideId));

    return Scaffold(
      appBar: AppBar(
        title: Text(ride.value?.name ?? l10n.tabRecord),
        leading: BackButton(onPressed: () => context.go(recordingRoute)),
        actions: [
          if (ride.value != null) RideUploadMenu(ride: ride.value!),
          if (ride.value != null)
            PopupMenuButton<_RideAction>(
              onSelected: (action) => unawaited(switch (action) {
                _RideAction.rename => _rename(ride.value!),
                _RideAction.delete => _delete(ride.value!),
                _RideAction.exportGpx => _export(ride.value!, TrackFormat.gpx),
                _RideAction.exportFit => _export(ride.value!, TrackFormat.fit),
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
                const PopupMenuDivider(),
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
      body: ride.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => PlaceholderBody(
          icon: Icons.error_outline,
          message: error.toString(),
        ),
        data: (saved) {
          if (saved == null) {
            return PlaceholderBody(
              icon: Icons.help_outline,
              message: l10n.rideDetailNotFound,
            );
          }
          unawaited(_showOnMap(saved));
          final theme = Theme.of(context);
          final stats = saved.stats;
          return ListView(
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom + 24,
            ),
            children: [
              // Full-bleed hero: the track is the headline of this screen.
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
                      formatDate(l10n, saved.startedAt),
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 20),
                    RideStatsGrid(
                      items: <RideStatItem>[
                        RideStatItem(
                          icon: Icons.straighten,
                          label: l10n.statDistance,
                          value: formatDistance(l10n, stats.distanceM),
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
                          value: formatSpeed(l10n, stats.avgSpeedMps),
                        ),
                        RideStatItem(
                          icon: Icons.bolt,
                          label: l10n.statMaxSpeed,
                          value: formatSpeed(l10n, stats.maxSpeedMps),
                        ),
                        RideStatItem(
                          icon: Icons.trending_up,
                          label: l10n.statAscent,
                          value: formatHeight(l10n, stats.ascentM),
                        ),
                        RideStatItem(
                          icon: Icons.trending_down,
                          label: l10n.statDescent,
                          value: formatHeight(l10n, stats.descentM),
                        ),
                      ],
                    ),
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
            ],
          );
        },
      ),
    );
  }
}

enum _RideAction { rename, delete, exportGpx, exportFit }

/// One figure of [RideStatsGrid].
class RideStatItem {
  /// Creates the item.
  const RideStatItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  /// The icon left of the label.
  final IconData icon;

  /// What the figure means.
  final String label;

  /// The figure, already formatted.
  final String value;
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
                  size: StatSize.medium,
                ),
              ),
          ],
        );
      },
    );
  }
}

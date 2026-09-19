import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../app/router.dart';
import '../../../core/geo/ride_stats.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../map/domain/map_controller.dart';
import '../../planner/application/planner_map_binding.dart';
import '../../planner/domain/elevation_profile.dart';
import '../../planner/domain/route_profile.dart';
import '../../planner/presentation/elevation_profile_chart.dart';
import '../../planner/presentation/planner_map_host.dart';
import '../../planner/presentation/route_stats_row.dart';
import '../../recording/presentation/ride_detail_screen.dart'
    show rideDetailLocation;
import '../../shared/presentation/placeholder_body.dart';
import '../../shared/presentation/stat_tile.dart';
import '../data/import_repository.dart';
import 'import_file_action.dart';
import '../data/track_decoder.dart';
import '../domain/imported_track.dart';

/// Previews an incoming GPX or FIT file and saves it as a route or a ride.
///
/// Reached from the `/import` route, either because a file arrived through the
/// share sheet or "open with", or because the user picked one in the library.
/// Nothing is written until Save is pressed, so a file opened by accident
/// costs one Back.
class ImportPreviewScreen extends ConsumerStatefulWidget {
  /// Creates the preview for [candidate], or an empty state when it is `null`:
  /// the reason in [rejection] when a file arrived and was refused, "nothing
  /// to import" without one.
  const ImportPreviewScreen({
    required this.candidate,
    this.rejection,
    super.key,
  });

  /// The file to preview. `null` when `/import` was opened without one, which
  /// is what a stale deep link does, or when the file was refused.
  final ImportCandidate? candidate;

  /// Why the file that arrived could not be imported, when that is the case.
  final ImportException? rejection;

  @override
  ConsumerState<ImportPreviewScreen> createState() =>
      _ImportPreviewScreenState();
}

class _ImportPreviewScreenState extends ConsumerState<ImportPreviewScreen> {
  late final TextEditingController _name = TextEditingController(
    text: widget.candidate?.suggestedName ?? '',
  );
  late ImportKind _kind = widget.candidate?.suggested ?? ImportKind.route;
  MapController? _map;
  bool _drawn = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  // Called from the map widget's build, so it must not call setState.
  void _onMapReady(MapController controller) {
    _map = controller;
    _drawn = false;
    unawaited(_showOnMap());
  }

  Future<void> _showOnMap() async {
    final map = _map;
    final track = widget.candidate?.track;
    if (map == null || track == null || _drawn) return;
    final positions = track.points.map((p) => p.pos).toList(growable: false);
    if (positions.isEmpty) return;
    _drawn = true;
    await map.setRouteLine(mainRouteLineId, positions);
    await map.fitBounds(BoundingBox.fromPoints(positions));
  }

  Future<void> _save() async {
    final candidate = widget.candidate;
    if (candidate == null || _saving) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final repository = ref.read(importRepositoryProvider);
    final name = _name.text.trim().isEmpty
        ? candidate.suggestedName
        : _name.text.trim();

    setState(() => _saving = true);
    try {
      switch (_kind) {
        case ImportKind.route:
          final saved = await repository.saveAsRoute(
            name: name,
            track: candidate.track,
          );
          messenger.showSnackBar(
            SnackBar(content: Text(l10n.importSavedRoute(saved.name))),
          );
          router.go(routeDetailLocation(saved.id));
        case ImportKind.ride:
          final saved = await repository.saveAsRide(
            name: name,
            track: candidate.track,
          );
          messenger.showSnackBar(
            SnackBar(content: Text(l10n.importSavedRide(saved.name))),
          );
          // Rides live under the Record tab, next to the recorded ones.
          router.go(rideDetailLocation(saved.id));
      }
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(l10n.importSaveFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final candidate = widget.candidate;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.importTitle),
        leading: BackButton(onPressed: () => context.go(libraryRoute)),
      ),
      body: candidate == null
          ? switch (widget.rejection) {
              final rejection? => PlaceholderBody(
                icon: Icons.error_outline,
                message: [
                  importFailureMessage(l10n, rejection.failure),
                  ?rejection.fileName,
                ].join('\n'),
              ),
              null => PlaceholderBody(
                icon: Icons.help_outline,
                message: l10n.importNothing,
              ),
            }
          : _body(context, l10n, candidate),
    );
  }

  Widget _body(
    BuildContext context,
    AppLocalizations l10n,
    ImportCandidate candidate,
  ) {
    final track = candidate.track;
    final stats = computeImportedStats(track.points);
    final duration = stats.hasTime
        ? stats.movingTime
        : RouteProfile.trekking.estimatedTime(stats.distanceM);

    return ListView(
      // The floating navigation bar sits over the list, so the Save button
      // needs room to clear it.
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + 24,
      ),
      children: [
        SizedBox(
          height: 220,
          child: PlannerMapHost(onMapReady: _onMapReady, embedded: true),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _name,
                decoration: InputDecoration(labelText: l10n.importNameLabel),
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 12),
              Text(
                l10n.importSummary(
                  formatLabel(l10n, track.format),
                  track.pointCount,
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(
                _timeLine(l10n, stats),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              RouteStatsRow(
                distanceM: stats.distanceM,
                ascentM: stats.ascentM,
                descentM: stats.descentM,
                duration: duration,
              ),
              const SizedBox(height: 24),
              ElevationProfileChart(samples: elevationProfile(track.points)),
              const SizedBox(height: 24),
              SectionCaption(l10n.importSaveAs),
              const SizedBox(height: 12),
              SegmentedButton<ImportKind>(
                segments: [
                  ButtonSegment(
                    value: ImportKind.route,
                    icon: const Icon(Icons.route_outlined),
                    label: Text(l10n.importKindRoute),
                  ),
                  ButtonSegment(
                    value: ImportKind.ride,
                    icon: const Icon(Icons.directions_bike_outlined),
                    label: Text(l10n.importKindRide),
                  ),
                ],
                selected: <ImportKind>{_kind},
                onSelectionChanged: (selection) =>
                    setState(() => _kind = selection.first),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : () => unawaited(_save()),
                icon: const Icon(Icons.save_outlined),
                label: Text(l10n.commonSave),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _timeLine(AppLocalizations l10n, RideStats stats) {
    final start = stats.startedAt;
    final end = stats.endedAt;
    if (start == null || end == null) return l10n.importNoTime;
    return l10n.importTimeSpan(
      formatDateTime(l10n, start),
      formatDateTime(l10n, end),
    );
  }
}

/// The name of an import format as it is shown to the user.
String formatLabel(AppLocalizations l10n, ImportFormat format) =>
    switch (format) {
      ImportFormat.gpx => l10n.importFormatGpx,
      ImportFormat.fit => l10n.importFormatFit,
    };

/// A timestamp in the locale's medium date plus short time format, in the
/// device's own time zone — the file stores UTC, the rider rode locally.
String formatDateTime(AppLocalizations l10n, DateTime time) =>
    DateFormat.yMMMd(l10n.localeName).add_Hm().format(time.toLocal());

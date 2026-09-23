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
import '../../navigation/application/route_cues.dart';
import '../../navigation/presentation/cue_sheet_list.dart';
import '../../navigation/presentation/cue_sheet_map.dart';
import '../../navigation/presentation/turn_phrases.dart';
import '../../planner/application/planner_map_binding.dart';
import '../../planner/domain/elevation_profile.dart';
import '../../planner/domain/route_profile.dart';
import '../../planner/presentation/elevation_profile_chart.dart';
import '../../planner/presentation/planner_map_host.dart';
import '../../planner/presentation/route_stats_row.dart';
import '../../shared/presentation/placeholder_body.dart';
import '../../shared/presentation/stat_tile.dart';
import '../../shared/presentation/swipe_pages.dart';
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

  /// Which of a file's several tracks to keep, all of them to begin with.
  late final Set<int> _chosen = {
    for (var i = 0; i < (widget.candidate?.tracks.length ?? 0); i++) i,
  };
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
    showCuesOnMap(
      map,
      _cues,
      pois: track.pois,
      onCueTapped: (index) => _selectCue(index),
    );
    await map.fitBounds(BoundingBox.fromPoints(positions));
  }

  /// The cue sheet of the file, worked out once.
  late final List<RouteCue> _cues = () {
    final track = widget.candidate?.track;
    if (track == null) return const <RouteCue>[];
    return routeCuesFor(
      track.points.map((p) => p.pos).toList(growable: false),
      turns: track.turns,
      pois: track.pois,
    );
  }();

  int? _selectedCue;

  /// Which page is under the map: the file, or its cue sheet.
  int _page = 0;

  /// Selects a cue, from the list or from the map, and takes the map there.
  /// A tap on the map brings the cue sheet page up, so the line is seen.
  void _selectCue(int index) {
    if (!mounted || index < 0 || index >= _cues.length) return;
    setState(() {
      _selectedCue = index;
      _page = 2;
    });
    final map = _map;
    if (map == null) return;
    final cue = _cues[index];
    final l10n = AppLocalizations.of(context);
    final label =
        cue.poi?.name ?? (cue.turn == null ? '' : turnLabel(cue.turn!, l10n));
    unawaited(goToCue(map, cue, label));
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
      if (candidate.hasSeveralTracks) {
        await _saveSeveral(candidate, name, repository, messenger, router);
        return;
      }
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
          router.go(rideDetailLocation(saved.id));
      }
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(l10n.importSaveFailed)));
    }
  }

  /// One route or ride per chosen track, each under the track's own name
  /// or, for a track without one, the file's name and its number.
  Future<void> _saveSeveral(
    ImportCandidate candidate,
    String name,
    ImportRepository repository,
    ScaffoldMessengerState messenger,
    GoRouter router,
  ) async {
    final l10n = AppLocalizations.of(context);
    final chosen = [
      for (final (i, track) in candidate.tracks.indexed)
        if (_chosen.contains(i)) (i, track),
    ];
    for (final (i, track) in chosen) {
      final trackName = track.name?.trim().isNotEmpty ?? false
          ? track.name!.trim()
          : '$name ${i + 1}';
      switch (_kind) {
        case ImportKind.route:
          await repository.saveAsRoute(name: trackName, track: track);
        case ImportKind.ride:
          await repository.saveAsRide(name: trackName, track: track);
      }
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(switch (_kind) {
          ImportKind.route => l10n.importSavedRoutes(chosen.length),
          ImportKind.ride => l10n.importSavedRides(chosen.length),
        }),
      ),
    );
    router.go(libraryRoute);
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

    // The map stays put while the pages under it scroll: a tap on a cue
    // moves a map the rider can see.
    final bottom = MediaQuery.paddingOf(context).bottom + 24;
    return Column(
      children: [
        SizedBox(
          height: 220,
          child: PlannerMapHost(onMapReady: _onMapReady, embedded: true),
        ),
        Expanded(
          child: SwipePages(
            fill: true,
            page: _page,
            onPage: (page) => setState(() => _page = page),
            children: [
              // Built whole rather than lazily: the Save button is below
              // the fold on a small phone, and it has to exist to be found.
              SingleChildScrollView(
                // The floating navigation bar sits over the page, so the
                // Save button needs room to clear it.
                padding: EdgeInsets.fromLTRB(20, 20, 20, bottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _name,
                      decoration: InputDecoration(
                        labelText: l10n.importNameLabel,
                      ),
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
                    // A file with several tracks: each one on or off, so a
                    // multi-day file becomes one ride a day, or only the
                    // days that matter.
                    if (candidate.hasSeveralTracks) ...[
                      const SizedBox(height: 24),
                      SectionCaption(l10n.importTracks),
                      const SizedBox(height: 4),
                      for (final (i, track) in candidate.tracks.indexed)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: _chosen.contains(i),
                          onChanged: (on) => setState(() {
                            if (on ?? false) {
                              _chosen.add(i);
                            } else {
                              _chosen.remove(i);
                            }
                          }),
                          title: Text(
                            track.name?.trim().isNotEmpty ?? false
                                ? track.name!.trim()
                                : l10n.importTrackNumber(i + 1),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            l10n.importSummary(
                              formatLabel(l10n, track.format),
                              track.pointCount,
                            ),
                          ),
                        ),
                    ],
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
                      onPressed:
                          _saving ||
                              (candidate.hasSeveralTracks && _chosen.isEmpty)
                          ? null
                          : () => unawaited(_save()),
                      icon: const Icon(Icons.save_outlined),
                      label: Text(l10n.commonSave),
                    ),
                  ],
                ),
              ),
              // The profile on a page of its own, as on the record sheet.
              SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, 20, 20, bottom),
                child: ElevationProfileChart(
                  samples: elevationProfile(track.points),
                  height: 220,
                ),
              ),
              if (_cues.length > 1)
                SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(20, 20, 20, bottom),
                  child: CueSheetList(
                    cues: _cues,
                    selected: _selectedCue,
                    onSelect: _selectCue,
                  ),
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

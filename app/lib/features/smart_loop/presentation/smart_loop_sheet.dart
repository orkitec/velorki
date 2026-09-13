import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../app/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../map/domain/map_controller.dart';
import '../../map/presentation/device_position_request.dart';
import '../../planner/application/planner_controller.dart';
import '../../planner/data/routing_backend_provider.dart';
import '../../planner/domain/route_profile.dart';
import '../../planner/presentation/route_format.dart';
import '../../planner/presentation/route_stats_row.dart';
import '../../search/domain/search_result.dart';
import '../../search/presentation/search_field.dart';
import '../../shared/presentation/stat_tile.dart';
import '../application/loop_map_preview.dart';
import '../application/smart_loop_controller.dart';
import '../domain/loops.dart';
import '../domain/smart_loop_state.dart';

/// Shortest loop the slider offers, in kilometres.
const double loopMinKm = 10;

/// Longest loop the slider offers, in kilometres.
const double loopMaxKm = 150;

/// Where the slider starts.
const double loopDefaultKm = 40;

/// Slider step in kilometres.
const double loopStepKm = 5;

/// How many via places one loop may have.
const int loopMaxVias = 2;

/// Opens the smart loop sheet over the planner.
///
/// [map] is the planner's own map controller: the sheet draws its candidates
/// on it through [LoopMapPreview] and takes them off again when it closes. A
/// `null` map is fine — the sheet then simply shows no preview.
Future<void> showSmartLoopSheet(
  BuildContext context, {
  MapController? map,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final preview = LoopMapPreview(map);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => SmartLoopSheet(preview: preview),
  );
  container.read(smartLoopControllerProvider.notifier).cancel();
  await preview.clear();
}

/// Where a loop starts.
enum LoopStartChoice {
  /// The device's own position.
  myPosition,

  /// The point the map is centred on.
  mapCentre,

  /// The first waypoint of the route in the planner.
  waypoint,
}

/// "A nice 60 km loop from here, past the lake", as a form.
class SmartLoopSheet extends ConsumerStatefulWidget {
  /// Creates the sheet.
  const SmartLoopSheet({required this.preview, super.key});

  /// Draws the candidates on the planner's map.
  final LoopMapPreview preview;

  @override
  ConsumerState<SmartLoopSheet> createState() => _SmartLoopSheetState();
}

class _SmartLoopSheetState extends ConsumerState<SmartLoopSheet> {
  final List<SearchResult> _vias = <SearchResult>[];
  late LoopStartChoice _start;
  late RouteProfile _profile;
  double _km = loopDefaultKm;
  Hills _hills = Hills.neutral;
  Surface _surface = Surface.mixed;
  bool _avoidBusy = true;
  String? _startProblem;

  @override
  void initState() {
    super.initState();
    final planner = ref.read(plannerControllerProvider);
    _profile = planner.options.profile;
    _start = planner.waypoints.isNotEmpty
        ? LoopStartChoice.waypoint
        : (widget.preview.map?.center != null
              ? LoopStartChoice.mapCentre
              : LoopStartChoice.myPosition);
    // Reopening the sheet redraws whatever the last search found.
    final state = ref.read(smartLoopControllerProvider);
    if (state.candidates.isNotEmpty) {
      unawaited(
        widget.preview.previewRoutes(state.previewLines, state.selected ?? 0),
      );
    }
  }

  List<LoopStartChoice> get _startChoices => <LoopStartChoice>[
    LoopStartChoice.myPosition,
    if (widget.preview.map?.center != null) LoopStartChoice.mapCentre,
    if (ref.read(plannerControllerProvider).waypoints.isNotEmpty)
      LoopStartChoice.waypoint,
  ];

  Future<LatLng?> _resolveStart() async {
    switch (_start) {
      case LoopStartChoice.waypoint:
        final waypoints = ref.read(plannerControllerProvider).waypoints;
        return waypoints.isEmpty ? null : waypoints.first.pos;
      case LoopStartChoice.mapCentre:
        return widget.preview.map?.center;
      case LoopStartChoice.myPosition:
        return requestDevicePosition(context, ref);
    }
  }

  Future<void> _generate({bool newSeed = false}) async {
    final l10n = AppLocalizations.of(context);
    final start = await _resolveStart();
    if (!mounted) return;
    if (start == null) {
      setState(
        () => _startProblem = _start == LoopStartChoice.myPosition
            ? l10n.loopPositionUnavailable
            : l10n.loopNoStart,
      );
      return;
    }
    setState(() => _startProblem = null);
    await ref
        .read(smartLoopControllerProvider.notifier)
        .start(
          LoopRequest(
            start: start,
            via: _vias.map((v) => v.position).toList(growable: false),
            targetM: _km * 1000,
            profile: _profile.brouterName,
            prefs: LoopPrefs(
              hills: _hills,
              surface: _surface,
              avoidTraffic: _avoidBusy,
            ),
          ),
          seed: newSeed
              ? DateTime.now().microsecondsSinceEpoch & 0x7fffffff
              : null,
        );
  }

  void _addVia(SearchResult place) {
    if (_vias.length >= loopMaxVias) return;
    setState(() => _vias.add(place));
  }

  void _removeVia(SearchResult place) => setState(() => _vias.remove(place));

  Future<void> _use() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    if (!ref.read(smartLoopControllerProvider.notifier).adopt()) return;
    await widget.preview.clear();
    navigator.pop();
    messenger?.showSnackBar(SnackBar(content: Text(l10n.loopAdopted)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(smartLoopControllerProvider);

    ref.listen(smartLoopControllerProvider, (previous, next) {
      if (previous != null &&
          previous.candidates == next.candidates &&
          previous.selected == next.selected) {
        return;
      }
      unawaited(
        widget.preview.previewRoutes(next.previewLines, next.selected ?? 0),
      );
    });

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.loopTitle, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text(
                    l10n.loopIntro,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (ref.watch(onDeviceRoutingActiveProvider))
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        l10n.loopOnDeviceNote,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                children: [
                  _Section(title: l10n.loopStart),
                  _StartChooser(
                    choices: _startChoices,
                    selected: _start,
                    onSelected: (choice) => setState(() {
                      _start = choice;
                      _startProblem = null;
                    }),
                  ),
                  if (_startProblem != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _startProblem!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  _Section(title: l10n.loopVia),
                  if (_vias.length < loopMaxVias)
                    SearchField(
                      onSelected: _addVia,
                      bias: () => widget.preview.map?.center,
                    ),
                  if (_vias.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          for (final via in _vias)
                            InputChip(
                              avatar: const Icon(
                                Icons.place_outlined,
                                size: 18,
                              ),
                              label: Text(via.name),
                              onDeleted: () => _removeVia(via),
                              deleteButtonTooltipMessage: l10n.loopViaRemove(
                                via.name,
                              ),
                            ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      l10n.loopViaHint,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  _Section(title: l10n.loopDistance),
                  Text(
                    formatDistance(l10n, _km * 1000),
                    style: theme.textTheme.statLarge.copyWith(
                      color: theme.velorki.accent,
                    ),
                  ),
                  Slider(
                    value: _km,
                    min: loopMinKm,
                    max: loopMaxKm,
                    divisions: ((loopMaxKm - loopMinKm) / loopStepKm).round(),
                    label: formatDistance(l10n, _km * 1000),
                    onChanged: (v) => setState(() => _km = v),
                  ),
                  _Section(title: l10n.plannerProfile),
                  _ProfileChips(
                    selected: _profile,
                    onSelected: (p) => setState(() => _profile = p),
                  ),
                  _Section(title: l10n.loopHills),
                  SegmentedButton<Hills>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: Hills.avoid,
                        label: Text(l10n.loopHillsAvoid),
                      ),
                      ButtonSegment(
                        value: Hills.neutral,
                        label: Text(l10n.loopHillsNeutral),
                      ),
                      ButtonSegment(
                        value: Hills.seek,
                        label: Text(l10n.loopHillsSeek),
                      ),
                    ],
                    selected: <Hills>{_hills},
                    onSelectionChanged: (s) => setState(() => _hills = s.first),
                  ),
                  _Section(title: l10n.surfaceTitle),
                  SegmentedButton<Surface>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: Surface.paved,
                        label: Text(l10n.surfacePaved),
                      ),
                      ButtonSegment(
                        value: Surface.mixed,
                        label: Text(l10n.loopSurfaceMixed),
                      ),
                      ButtonSegment(
                        value: Surface.gravel,
                        label: Text(l10n.loopSurfaceGravel),
                      ),
                    ],
                    selected: <Surface>{_surface},
                    onSelectionChanged: (s) =>
                        setState(() => _surface = s.first),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.loopAvoidBusy),
                    value: _avoidBusy,
                    onChanged: (v) => setState(() => _avoidBusy = v),
                  ),
                  _Results(state: state, profile: _profile),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                MediaQuery.viewPaddingOf(context).bottom + 16,
              ),
              child: _Actions(
                state: state,
                onGenerate: () => unawaited(_generate()),
                onRegenerate: () => unawaited(_generate(newSeed: true)),
                onStop: ref.read(smartLoopControllerProvider.notifier).cancel,
                onUse: () => unawaited(_use()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: SectionCaption(title),
  );
}

class _StartChooser extends StatelessWidget {
  const _StartChooser({
    required this.choices,
    required this.selected,
    required this.onSelected,
  });

  final List<LoopStartChoice> choices;
  final LoopStartChoice selected;
  final ValueChanged<LoopStartChoice> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 8,
      children: [
        for (final choice in choices)
          ChoiceChip(
            label: Text(switch (choice) {
              LoopStartChoice.myPosition => l10n.loopStartMyPosition,
              LoopStartChoice.mapCentre => l10n.loopStartMapCentre,
              LoopStartChoice.waypoint => l10n.loopStartWaypoint,
            }),
            selected: choice == selected,
            onSelected: (_) => onSelected(choice),
          ),
      ],
    );
  }
}

class _ProfileChips extends StatelessWidget {
  const _ProfileChips({required this.selected, required this.onSelected});

  final RouteProfile selected;
  final ValueChanged<RouteProfile> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final profile in RouteProfile.values)
          ChoiceChip(
            label: Text(profileLabel(l10n, profile)),
            selected: profile == selected,
            onSelected: (_) => onSelected(profile),
          ),
      ],
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.state, required this.profile});

  final SmartLoopState state;
  final RouteProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final error = state.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.running) ...[
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: state.progress, minHeight: 4),
          ),
          const SizedBox(height: 10),
          Text(l10n.loopSearching, style: theme.textTheme.bodySmall),
        ],
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: theme.colorScheme.error),
                const SizedBox(width: 12),
                Expanded(child: Text(l10n.loopFailed(error))),
              ],
            ),
          ),
        if (state.foundNothing)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(l10n.loopNoneFound, style: theme.textTheme.bodyMedium),
          ),
        for (var i = 0; i < state.candidates.length; i++)
          LoopCandidateCard(
            candidate: state.candidates[i],
            index: i,
            profile: profile,
            selected: i == state.selected,
            onTap: () =>
                ref.read(smartLoopControllerProvider.notifier).select(i),
          ),
      ],
    );
  }
}

/// One loop candidate: its statistics, what it is made of and its score.
class LoopCandidateCard extends StatelessWidget {
  /// Creates the card.
  const LoopCandidateCard({
    required this.candidate,
    required this.index,
    required this.profile,
    required this.selected,
    required this.onTap,
    super.key,
  });

  /// The loop being shown.
  final LoopCandidate candidate;

  /// Its rank, counted from zero.
  final int index;

  /// The profile the loop was routed with, for the time estimate.
  final RouteProfile profile;

  /// Whether this is the loop drawn as the main line.
  final bool selected;

  /// Picks this loop.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final result = candidate.result;
    final features = candidate.score.features;
    final stats = result.surfaceStats;

    final accent = theme.velorki.accent;

    return Card(
      margin: const EdgeInsets.only(top: 12),
      // The chosen loop is the one drawn on the map; a 2dp accent border says
      // so without recolouring the whole card.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: selected
            ? BorderSide(color: accent, width: 2)
            : BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.loopCandidateTitle(index + 1),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check_circle_rounded, size: 20, color: accent),
                ],
              ),
              const SizedBox(height: 12),
              RouteStatsRow(
                distanceM: result.lengthM,
                ascentM: result.ascentM,
                descentM: result.descentM,
                duration: profile.estimatedTime(result.lengthM),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _Metric(
                    label: l10n.labelWithPercent(
                      l10n.surfacePaved,
                      formatPercent(l10n, stats.pavedShare),
                    ),
                  ),
                  _Metric(
                    label: l10n.labelWithPercent(
                      l10n.surfaceCycleway,
                      formatPercent(l10n, features.cyclewayShare),
                    ),
                  ),
                  _Metric(
                    label: l10n.labelWithPercent(
                      l10n.surfaceBusy,
                      formatPercent(l10n, features.busyShare),
                    ),
                  ),
                  _Metric(
                    label: l10n.labelWithPercent(
                      l10n.loopRepeated,
                      formatPercent(l10n, features.repeatedSegmentRatio),
                    ),
                  ),
                  _Metric(
                    label: l10n.loopScore(
                      formatNumber(l10n, candidate.score.total, decimals: 2),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A Material chip inside a card the rider taps would look like a second
    // button; this is a label, so it is drawn as one.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.state,
    required this.onGenerate,
    required this.onRegenerate,
    required this.onStop,
    required this.onUse,
  });

  final SmartLoopState state;
  final VoidCallback onGenerate;
  final VoidCallback onRegenerate;
  final VoidCallback onStop;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (state.running) {
      return OutlinedButton.icon(
        onPressed: onStop,
        icon: const Icon(Icons.stop_rounded),
        label: Text(l10n.loopStop),
      );
    }
    if (state.candidates.isEmpty) {
      return FilledButton.icon(
        onPressed: onGenerate,
        icon: const Icon(Icons.loop_rounded),
        label: Text(l10n.loopGenerate),
      );
    }
    // "Use this loop" is what the rider came for, so it takes the width;
    // a new draw is one more tap away.
    return Row(
      children: [
        TextButton.icon(
          onPressed: onRegenerate,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(l10n.loopRegenerate),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: state.canAdopt ? onUse : null,
            icon: const Icon(Icons.check_rounded),
            label: Text(l10n.loopUseThis),
          ),
        ),
      ],
    );
  }
}

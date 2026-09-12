import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../assistant/domain/intent_resolver.dart';
import '../../assistant/presentation/assistant_sheet.dart';
import '../../map/domain/map_controller.dart';
import '../../search/domain/search_result.dart';
import '../../search/presentation/search_field.dart';
import '../../smart_loop/presentation/smart_loop_sheet.dart';
import '../application/planner_controller.dart';
import '../application/planner_map_binding.dart';
import '../data/route_repository.dart';
import '../data/routing_backend_provider.dart';
import '../domain/elevation_profile.dart';
import '../domain/planner_state.dart';
import '../domain/route_profile.dart';
import '../domain/routing_options.dart';
import 'elevation_profile_chart.dart';
import 'planner_map_host.dart';
import 'route_format.dart';
import 'route_stats_row.dart';
import 'save_route_dialog.dart';
import 'surface_stats_bar.dart';

/// The Plan tab: a full-screen map with the search and profile controls on
/// top and the route details in a draggable sheet at the bottom.
class PlannerScreen extends ConsumerStatefulWidget {
  /// Creates the planner.
  const PlannerScreen({super.key});

  @override
  ConsumerState<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends ConsumerState<PlannerScreen> {
  MapController? _map;
  PlannerMapBinding? _binding;
  SearchResult? _placeToStartFrom;

  @override
  void dispose() {
    _binding?.detach();
    super.dispose();
  }

  // Called from the map widget's build, so it must not call setState.
  void _onMapReady(MapController controller) {
    _map = controller;
    _binding?.detach();
    final binding = PlannerMapBinding(
      map: controller,
      planner: ref.read(plannerControllerProvider.notifier),
    )..attach();
    _binding = binding;
    unawaited(binding.sync(ref.read(plannerControllerProvider)));
  }

  void _onPlaceSelected(SearchResult result) {
    final planner = ref.read(plannerControllerProvider.notifier);
    if (ref.read(plannerControllerProvider).isEmpty) {
      unawaited(_map?.moveTo(result.position, zoom: 13));
      setState(() => _placeToStartFrom = result);
      return;
    }
    planner.addWaypoint(result.position, name: result.name);
    setState(() => _placeToStartFrom = null);
  }

  void _setSearchedPlaceAsStart() {
    final place = _placeToStartFrom;
    if (place == null) return;
    ref
        .read(plannerControllerProvider.notifier)
        .addWaypoint(place.position, name: place.name);
    setState(() => _placeToStartFrom = null);
  }

  Future<void> _loadAlternatives() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final ok = await ref
        .read(plannerControllerProvider.notifier)
        .loadAlternatives();
    if (!mounted || ok) return;
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.plannerAlternativesFailed)),
    );
  }

  /// Opens the smart loop sheet, handing it the planner's map so it can draw
  /// its candidates on it.
  Future<void> _smartLoop() => showSmartLoopSheet(context, map: _map);

  /// Opens the assistant, then shows whatever it produced.
  ///
  /// A loop request is already running as a loop search when the sheet
  /// closes, so the loop sheet opens on top of it and shows the candidates as
  /// they arrive; a point-to-point route is simply on the map.
  Future<void> _ask() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final intent = await showAssistantSheet(context, map: _map);
    if (!mounted || intent == null) return;
    if (intent is LoopIntent) {
      await _smartLoop();
      return;
    }
    if (intent is RouteIntent) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.assistantRouteHandedOver)),
      );
    }
  }

  Future<void> _save() async {
    final state = ref.read(plannerControllerProvider);
    final route = state.result;
    if (route == null) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final name = await showSaveRouteDialog(
      context,
      initialName:
          state.savedRouteName ??
          l10n.plannerDefaultRouteName(formatDate(l10n, DateTime.now())),
    );
    if (name == null || !mounted) return;
    final saved = await ref
        .read(routeRepositoryProvider)
        .savePlannedRoute(
          name: name,
          route: route,
          waypoints: state.waypoints,
          options: state.options,
          id: state.savedRouteId,
        );
    ref
        .read(plannerControllerProvider.notifier)
        .markSaved(saved.id, saved.name);
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(l10n.plannerRouteSaved)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(plannerControllerProvider);
    final hasBackend = ref.watch(routingBackendProvider) != null;

    ref.listen(plannerControllerProvider, (previous, next) {
      unawaited(_binding?.sync(next));
      final error = next.error;
      if (error == null || error == previous?.error || !mounted) return;
      if (error == noRoutingBackendError) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.plannerRoutingFailed(error))));
      ref.read(plannerControllerProvider.notifier).clearError();
    });

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: PlannerMapHost(onMapReady: _onMapReady)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SearchField(
                    onSelected: _onPlaceSelected,
                    bias: () => _map?.center,
                  ),
                  if (_placeToStartFrom != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: ActionChip(
                          avatar: const Icon(Icons.play_arrow, size: 18),
                          label: Text(l10n.plannerSetAsStart),
                          onPressed: _setSearchedPlaceAsStart,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  _ProfileChooser(
                    selected: state.options.profile,
                    onSelected: ref
                        .read(plannerControllerProvider.notifier)
                        .setProfile,
                  ),
                  if (!hasBackend)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: _NoRoutingServerBanner(),
                    ),
                ],
              ),
            ),
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.28,
            minChildSize: 0.12,
            maxChildSize: 0.85,
            builder: (context, scrollController) => Material(
              elevation: 8,
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  _SheetBody(state: state),
                  const SizedBox(height: 12),
                  _PlannerActions(
                    state: state,
                    onAlternatives: _loadAlternatives,
                    onSmartLoop: _smartLoop,
                    onAsk: _ask,
                    onSave: _save,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoRoutingServerBanner extends StatelessWidget {
  const _NoRoutingServerBanner();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.cloud_off, color: theme.colorScheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n.plannerNoRoutingServer,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileChooser extends StatelessWidget {
  const _ProfileChooser({required this.selected, required this.onSelected});

  final RouteProfile selected;
  final ValueChanged<RouteProfile> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final profile in RouteProfile.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(profileLabel(l10n, profile)),
                selected: profile == selected,
                onSelected: (_) => onSelected(profile),
              ),
            ),
        ],
      ),
    );
  }
}

class _SheetBody extends StatelessWidget {
  const _SheetBody({required this.state});

  final PlannerState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (state.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.plannerEmptyState, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(l10n.plannerEmptyStateDetail, style: theme.textTheme.bodySmall),
        ],
      );
    }
    if (!state.isRoutable) {
      return Text(l10n.plannerOnePointHint, style: theme.textTheme.bodyMedium);
    }

    final route = state.result;
    if (route == null) {
      final failure = state.route.error;
      if (failure != null) {
        return Row(
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.error),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n.plannerRoutingFailed(_failureMessage(failure)),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        );
      }
      return Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(l10n.plannerRouting, style: theme.textTheme.bodyMedium),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RouteStatsRow(
          distanceM: route.lengthM,
          ascentM: route.ascentM,
          descentM: route.descentM,
          duration: state.estimatedTime ?? Duration.zero,
        ),
        if (state.isRouting)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(),
          ),
        const SizedBox(height: 16),
        ElevationProfileChart(samples: elevationProfile(route.geometry)),
        const SizedBox(height: 16),
        SurfaceStatsBar(stats: state.surfaceStats),
        if (state.alternatives.length > 1) ...[
          const SizedBox(height: 12),
          _AlternativeChips(state: state),
        ],
      ],
    );
  }
}

String _failureMessage(Object error) =>
    error is RoutingException ? error.message : error.toString();

class _AlternativeChips extends ConsumerWidget {
  const _AlternativeChips({required this.state});

  final PlannerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 8,
      children: [
        for (var i = 0; i < state.alternatives.length; i++)
          ChoiceChip(
            label: Text(
              i == 0 ? l10n.plannerMainRoute : l10n.plannerAlternativeIndex(i),
            ),
            selected: i == state.options.alternativeIdx,
            onSelected: (_) =>
                ref.read(plannerControllerProvider.notifier).setAlternative(i),
          ),
      ],
    );
  }
}

class _PlannerActions extends ConsumerWidget {
  const _PlannerActions({
    required this.state,
    required this.onAlternatives,
    required this.onSmartLoop,
    required this.onAsk,
    required this.onSave,
  });

  final PlannerState state;
  final Future<void> Function() onAlternatives;
  final Future<void> Function() onSmartLoop;
  final Future<void> Function() onAsk;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final planner = ref.read(plannerControllerProvider.notifier);
    final canAlternatives =
        state.isRoutable &&
        !state.loadingAlternatives &&
        state.alternatives.length <= RoutingOptions.maxAlternativeIdx;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        TextButton.icon(
          onPressed: state.canUndo ? planner.undo : null,
          icon: const Icon(Icons.undo),
          label: Text(l10n.plannerUndo),
        ),
        TextButton.icon(
          onPressed: state.canReverse ? planner.reverse : null,
          icon: const Icon(Icons.swap_vert),
          label: Text(l10n.plannerReverse),
        ),
        TextButton.icon(
          onPressed: state.isEmpty ? null : planner.clear,
          icon: const Icon(Icons.delete_outline),
          label: Text(l10n.plannerClear),
        ),
        TextButton.icon(
          onPressed: canAlternatives ? () => unawaited(onAlternatives()) : null,
          icon: state.loadingAlternatives
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.alt_route),
          label: Text(l10n.plannerAlternatives),
        ),
        TextButton.icon(
          onPressed: () => unawaited(onSmartLoop()),
          icon: const Icon(Icons.loop),
          label: Text(l10n.loopAction),
        ),
        TextButton.icon(
          onPressed: () => unawaited(onAsk()),
          icon: const Icon(Icons.auto_awesome),
          label: Text(l10n.assistantAction),
        ),
        FilledButton.icon(
          onPressed: state.canSave ? () => unawaited(onSave()) : null,
          icon: const Icon(Icons.bookmark_add_outlined),
          label: Text(l10n.plannerSave),
        ),
      ],
    );
  }
}

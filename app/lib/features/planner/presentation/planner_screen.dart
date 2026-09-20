import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

import '../../../app/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../assistant/domain/intent_resolver.dart';
import '../../assistant/presentation/assistant_sheet.dart';
import '../../integrations/common/data/relay_client_provider.dart';
import '../../map/domain/map_controller.dart';
import '../../map/presentation/device_position_request.dart';
import '../../map/presentation/map_chrome.dart';
import '../../offline/presentation/offline_screen.dart';
import '../../routing_tiles/presentation/missing_tiles_banner.dart';
import '../../routing_tiles/presentation/routing_source_chip.dart';
import '../../search/domain/search_result.dart';
import '../../search/presentation/search_field.dart';
import '../../settings/data/units.dart';
import '../../shared/presentation/stat_tile.dart';
import '../../smart_loop/presentation/smart_loop_sheet.dart';
import '../application/planner_controller.dart';
import '../application/planner_map_binding.dart';
import '../data/route_repository.dart';
import '../data/routing_backend_provider.dart';
import '../domain/elevation_profile.dart';
import '../domain/planner_state.dart';
import '../domain/routing_options.dart';
import 'elevation_profile_chart.dart';
import 'planner_map_host.dart';
import 'profile_chip_row.dart';
import 'route_format.dart';
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

class _PlannerScreenState extends ConsumerState<PlannerScreen>
    with WidgetsBindingObserver {
  MapController? _map;
  PlannerMapBinding? _binding;
  SearchResult? _placeToStartFrom;

  /// The chrome over the map (search field, place actions, profile chips),
  /// measured after each layout so the map's control column starts below
  /// it whatever the rows above happen to need.
  final GlobalKey _chromeKey = GlobalKey();
  double _chromeHeight = 8 + 56 + 10 + 44;

  void _measureChrome() {
    final height = _chromeKey.currentContext?.size?.height;
    if (height == null || (height - _chromeHeight).abs() < 0.5) return;
    setState(() => _chromeHeight = height);
  }

  final DraggableScrollableController _sheet = DraggableScrollableController();
  // Where the sheet was before the search field took it out of the way, or
  // null while it is where the rider left it.
  double? _sheetSizeBeforeSearch;
  // The sheet's collapsed size, as computed by the last build.
  double _collapsedSheetSize = 0.1;

  @override
  void initState() {
    super.initState();
    // The keyboard's going is what brings the sheet back; the window does
    // not rebuild this screen by itself, so metrics changes are listened for.
    WidgetsBinding.instance.addObserver(this);
  }

  bool _searchFocused = false;
  bool _keyboardUp = false;

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    // Only the keyboard's coming and going matter, not every metrics change:
    // the first one arrives before the keyboard has any height, and would
    // otherwise undo the parking straight away.
    final up = View.of(context).viewInsets.bottom > 0;
    if (up == _keyboardUp) return;
    _keyboardUp = up;
    if (!up) {
      _restoreSheet();
    } else if (_searchFocused) {
      // The keyboard came back to a field that never lost focus (dismissed
      // with the back gesture, tapped again).
      _parkSheet();
    }
  }

  /// The search field is about to open the keyboard: the sheet drops to its
  /// handle first, so it sits under the keyboard instead of peeking over it.
  /// When the field gives focus up with no keyboard in the way, it comes
  /// back at once; otherwise the keyboard's going brings it back.
  void _onSearchFocus(bool focused) {
    _searchFocused = focused;
    if (focused) {
      _parkSheet();
    } else if (!_keyboardUp) {
      _restoreSheet();
    }
  }

  void _parkSheet() {
    if (!_sheet.isAttached || _sheetSizeBeforeSearch != null) return;
    _sheetSizeBeforeSearch = _sheet.size;
    unawaited(
      _sheet.animateTo(
        _collapsedSheetSize,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      ),
    );
  }

  void _restoreSheet() {
    final size = _sheetSizeBeforeSearch;
    if (size == null) return;
    _sheetSizeBeforeSearch = null;
    if (!_sheet.isAttached) return;
    unawaited(
      _sheet.animateTo(
        size,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _binding?.detach();
    _sheet.dispose();
    super.dispose();
  }

  /// What can be done with a tapped marker: today, removing it.
  Future<void> _showWaypointActions(int index) async {
    final state = ref.read(plannerControllerProvider);
    if (index < 0 || index >= state.waypoints.length) return;
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final name = state.waypoints[index].name;
    final count = state.waypoints.length;
    final action = await showModalBottomSheet<_PointAction>(
      context: context,
      useRootNavigator: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                name ?? l10n.plannerPointTitle(index + 1),
                style: theme.textTheme.headlineSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              // Reordering by one place at a time: swap with a neighbour.
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: index > 0
                          ? () =>
                                Navigator.of(context).pop(_PointAction.earlier)
                          : null,
                      icon: const Icon(Icons.arrow_upward_rounded),
                      label: Text(l10n.plannerVisitEarlier),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: index < count - 1
                          ? () => Navigator.of(context).pop(_PointAction.later)
                          : null,
                      icon: const Icon(Icons.arrow_downward_rounded),
                      label: Text(l10n.plannerVisitLater),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).pop(_PointAction.remove),
                icon: const Icon(Icons.delete_outline_rounded),
                label: Text(l10n.plannerRemovePoint),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.commonCancel),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    final planner = ref.read(plannerControllerProvider.notifier);
    switch (action) {
      case _PointAction.earlier:
        planner.swapWaypoint(index, -1);
      case _PointAction.later:
        planner.swapWaypoint(index, 1);
      case _PointAction.remove:
        planner.removeWaypoint(index);
    }
  }

  /// Grows the sheet by one row when the variant chips appear, so they are in
  /// view and tappable without a pull.
  void _showVariantsRow(double size) {
    if (!_sheet.isAttached || _sheet.size >= size - 0.001) return;
    unawaited(
      _sheet.animateTo(
        size,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      ),
    );
  }

  // Called from the map widget's build, so it must not call setState.
  void _onMapReady(MapController controller) {
    _map = controller;
    _binding?.detach();
    final binding = PlannerMapBinding(
      map: controller,
      planner: ref.read(plannerControllerProvider.notifier),
    );
    binding.onWaypointTap = (index) {
      unawaited(_showWaypointActions(index));
    };
    binding.attach();
    _binding = binding;
    unawaited(binding.sync(ref.read(plannerControllerProvider)));
  }

  void _onPlaceSelected(SearchResult result) {
    final planner = ref.read(plannerControllerProvider.notifier);
    if (ref.read(plannerControllerProvider).isEmpty) {
      unawaited(_map?.moveTo(result.position, zoom: 13));
      unawaited(_map?.setSearchPin(result.position, label: result.name));
      setState(() => _placeToStartFrom = result);
      return;
    }
    planner.addWaypoint(result.position, name: result.name);
    unawaited(_map?.setSearchPin(null));
    setState(() => _placeToStartFrom = null);
  }

  /// Forgets a searched place that was never used: the pin goes, and so do
  /// the two buttons offering it.
  /// Opens the offline data screen for the area on screen, which is what the
  /// map's download button opens: "Download for the visible area" is then one
  /// tap away from a search that had nothing to answer with.
  void _openOfflineData() {
    final map = _map;
    if (map == null) return;
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OfflineScreen(mapController: map),
        ),
      ),
    );
  }

  void _clearSearchedPlace() {
    if (_placeToStartFrom == null) return;
    unawaited(_map?.setSearchPin(null));
    setState(() => _placeToStartFrom = null);
  }

  void _setSearchedPlaceAsStart() {
    final place = _placeToStartFrom;
    if (place == null) return;
    ref
        .read(plannerControllerProvider.notifier)
        .addWaypoint(place.position, name: place.name);
    unawaited(_map?.setSearchPin(null));
    setState(() => _placeToStartFrom = null);
  }

  /// The searched place is the destination; the ride starts where the
  /// rider is right now.
  Future<void> _rideFromPosition() async {
    final place = _placeToStartFrom;
    if (place == null) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // Asks for the permission if it has never been asked, like the locate
    // button does. Not read from the auto-dispose position stream: a single
    // read would spin it up and tear it down before the first fix.
    final start = await requestDevicePosition(context, ref);
    if (!mounted) return;
    if (start == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.plannerPositionUnavailable)),
      );
      return;
    }
    final planner = ref.read(plannerControllerProvider.notifier);
    planner.addWaypoint(start);
    planner.addWaypoint(place.position, name: place.name);
    unawaited(_map?.setSearchPin(null));
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

  /// Opens the loop sheet, handing it the planner's map for the map-centre
  /// fallback start.
  Future<void> _smartLoop() => showSmartLoopSheet(context, map: _map);

  /// Opens the assistant, then shows whatever it produced.
  ///
  /// A loop with no place to ride past is already running as a loop search
  /// when the sheet closes, so the loop sheet opens on top of it and shows
  /// the result as it arrives. Everything else — a loop through places, a
  /// point-to-point route — is already on the map.
  Future<void> _ask() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final intent = await showAssistantSheet(context, map: _map);
    if (!mounted || intent == null) return;
    if (intent is LoopIntent) {
      if (intent.via.isEmpty) {
        await _smartLoop();
      } else {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.assistantRouteHandedOver)),
        );
      }
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
      // Missing tiles are shown as a banner with a download action in the
      // sheet; a snack bar the rider cannot act on would only be in the way.
      if (next.missingTiles.isNotEmpty) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.plannerRoutingFailed(error))));
      ref.read(plannerControllerProvider.notifier).clearError();
    });

    final theme = Theme.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final screenHeight = MediaQuery.sizeOf(context).height;
    // Collapsed, only the drag handle peeks out above the floating
    // navigation bar: the map is free, and one pull brings the plan back.
    final collapsedSheetSize = screenHeight <= 0
        ? 0.1
        : ((bottomInset + 30) / screenHeight).clamp(0.06, 0.25);
    _collapsedSheetSize = collapsedSheetSize;
    // One more row when the variant chips are shown between the figures and
    // the toolbar.
    const restingSheetSize = 0.42;
    final variantsSheetSize = screenHeight <= 0
        ? 0.48
        : (restingSheetSize + 56 / screenHeight).clamp(0.42, 0.6);
    final hasVariants = state.alternatives.length > 1;
    ref.listen(
      plannerControllerProvider.select((s) => s.alternatives.length > 1),
      (previous, next) {
        if (next && !(previous ?? false)) _showVariantsRow(variantsSheetSize);
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measureChrome();
    });

    return Scaffold(
      // The map fills the screen and stays put; the keyboard overlays its
      // lower edge and the search results float above from the field. A
      // resizing scaffold would shrink the platform view to a strip.
      resizeToAvoidBottomInset: false,
      body: SizedBox.expand(
        child: Stack(
          children: [
            Positioned.fill(
              // Search field, place actions, chips and their gaps: the control
              // column starts underneath them.
              child: MapChromeInsets(
                controlsTop: _chromeHeight + 12,
                child: PlannerMapHost(onMapReady: _onMapReady),
              ),
            ),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Column(
                  key: _chromeKey,
                  // Only as tall as its rows, so its height is the chrome's.
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SearchField(
                      onSelected: _onPlaceSelected,
                      onFocusChanged: _onSearchFocus,
                      onCleared: _clearSearchedPlace,
                      bias: () => _map?.center,
                      onDownloadArea: _openOfflineData,
                    ),
                    const SizedBox(height: 10),
                    ProfileChipRow(
                      glass: true,

                      selected: state.options.profile,
                      onSelected: ref
                          .read(plannerControllerProvider.notifier)
                          .setProfile,
                    ),
                    if (_placeToStartFrom != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        // One row, the two actions sharing the width. The X
                        // in the search field is what forgets the place.
                        child: Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => unawaited(_rideFromPosition()),
                                icon: const Icon(Icons.near_me_rounded),
                                label: Text(
                                  l10n.plannerRideFromPosition,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: _setSearchedPlaceAsStart,
                                icon: const Icon(Icons.play_arrow_rounded),
                                label: Text(
                                  l10n.plannerSetAsStart,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
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
              controller: _sheet,
              // Enough for the headline, the toolbar and Save above the
              // floating navigation bar on a 20:9 phone.
              initialChildSize: hasVariants
                  ? variantsSheetSize
                  : restingSheetSize,
              minChildSize: collapsedSheetSize,
              maxChildSize: 0.9,
              snap: true,
              // One resting height, not both: with the two in the list a pull
              // down from the top settled on the higher one and a pull up from
              // the handle on the lower one, a chip row apart.
              snapSizes: <double>[
                hasVariants ? variantsSheetSize : restingSheetSize,
              ],
              builder: (context, scrollController) => DecoratedBox(
                decoration: const BoxDecoration(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 24,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                child: Material(
                  color: theme.colorScheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                    side: BorderSide(color: theme.velorki.glassBorder),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ListView(
                    controller: scrollController,
                    padding: EdgeInsets.fromLTRB(20, 10, 20, bottomInset + 24),
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.outline,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      _SheetHeader(state: state),
                      const SizedBox(height: 14),
                      // The variants right under the figures, where the sheet
                      // grows to show them; then the actions, so Loop and Save
                      // are visible at the sheet's resting height.
                      if (hasVariants) ...[
                        _AlternativeChips(state: state),
                        const SizedBox(height: 12),
                      ],
                      _PlannerActions(
                        state: state,
                        onAlternatives: _loadAlternatives,
                        onSmartLoop: _smartLoop,
                        onAsk: _ask,
                        onSave: _save,
                      ),
                      const SizedBox(height: 16),
                      _SheetBody(state: state),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _PointAction { earlier, later, remove }

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

/// The first row of the sheet: the headline figures when there is a route,
/// the hint or the progress when there is not.
class _SheetHeader extends ConsumerWidget {
  const _SheetHeader({required this.state});

  final PlannerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final units = ref.watch(unitSystemProvider);

    if (state.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.plannerEmptyState, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(l10n.plannerEmptyStateDetail, style: theme.textTheme.bodySmall),
        ],
      );
    }
    if (!state.isRoutable) {
      return Text(l10n.plannerOnePointHint, style: theme.textTheme.titleMedium);
    }
    final route = state.result;
    if (route == null) {
      final missing = state.missingTiles;
      if (missing.isNotEmpty) return MissingTilesBanner(tiles: missing);
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
          Text(l10n.plannerRouting, style: theme.textTheme.titleMedium),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatRow(
          children: [
            StatTile(
              label: l10n.statDistance,
              value: formatDistance(l10n, units, route.lengthM),
              emphasize: true,
            ),
            StatTile(
              label: l10n.statAscent,
              value: formatHeight(l10n, units, route.ascentM),
            ),
            StatTile(
              label: l10n.statDescent,
              value: formatHeight(l10n, units, route.descentM),
            ),
            StatTile(
              label: l10n.statDuration,
              value: formatDuration(l10n, state.estimatedTime ?? Duration.zero),
            ),
          ],
        ),
        if (state.isRouting)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: LinearProgressIndicator(minHeight: 3),
          ),
      ],
    );
  }
}

/// Everything under the actions: chart, surfaces, alternatives.
class _SheetBody extends StatelessWidget {
  const _SheetBody({required this.state});

  final PlannerState state;

  @override
  Widget build(BuildContext context) {
    final route = state.result;
    if (route == null || !state.isRoutable) return const SizedBox.shrink();
    final source = state.routingSource;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (source != null)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: RoutingSourceChip(source: source),
            ),
          ),
        ElevationProfileChart(samples: elevationProfile(route.geometry)),
        const SizedBox(height: 20),
        SurfaceStatsBar(stats: state.surfaceStats),
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
    final colors = Theme.of(context).velorki;
    return Wrap(
      spacing: 8,
      children: [
        for (var i = 0; i < state.alternatives.length; i++)
          ChoiceChip(
            // The dot is the colour the line has on the map.
            avatar: CircleAvatar(
              radius: 6,
              // Same formula as the map: alternative i wears colour i.
              backgroundColor: i == 0
                  ? colors.routeMain
                  : colors.routeAlternatives[i %
                        colors.routeAlternatives.length],
            ),
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
    // One row of round buttons sharing the width, so every action stays
    // visible whatever the screen width; Save gets the full-width pill.
    final actions = <Widget>[
      LabeledIconButton(
        icon: Icons.undo_rounded,
        label: l10n.plannerUndo,
        onPressed: state.canUndo ? planner.undo : null,
      ),
      LabeledIconButton(
        icon: Icons.swap_vert_rounded,
        label: l10n.plannerReverse,
        onPressed: state.canReverse ? planner.reverse : null,
      ),
      LabeledIconButton(
        icon: Icons.delete_outline_rounded,
        label: l10n.plannerClear,
        onPressed: state.isEmpty ? null : planner.clear,
      ),
      LabeledIconButton(
        icon: Icons.alt_route_rounded,
        label: l10n.plannerVariants,
        busy: state.loadingAlternatives,
        onPressed: canAlternatives ? () => unawaited(onAlternatives()) : null,
      ),
      LabeledIconButton(
        icon: Icons.loop_rounded,
        label: l10n.loopAction,
        onPressed: () => unawaited(onSmartLoop()),
      ),
      // The assistant needs the relay; a build without one has no Ask.
      if (ref.watch(relayClientProvider) != null)
        LabeledIconButton(
          icon: Icons.auto_awesome_rounded,
          label: l10n.assistantAction,
          onPressed: () => unawaited(onAsk()),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [for (final action in actions) Expanded(child: action)]),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: state.canSave ? () => unawaited(onSave()) : null,
          icon: const Icon(Icons.bookmark_add_outlined),
          label: Text(l10n.plannerSave),
        ),
      ],
    );
  }
}

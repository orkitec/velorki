import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../assistant/domain/intent_resolver.dart';
import '../../assistant/presentation/assistant_sheet.dart';
import '../../integrations/common/data/relay_client_provider.dart';
import '../../map/domain/map_controller.dart';
import '../../map/presentation/device_position_request.dart';
import '../../map/presentation/map_chrome.dart';
import '../../map/presentation/shared_map_host.dart';
import '../../offline/presentation/offline_screen.dart';
import '../../routing_tiles/presentation/missing_tiles_banner.dart';
import '../../search/domain/search_result.dart';
import '../../search/presentation/search_field.dart';
import '../../settings/data/units.dart';
import '../../shared/application/active_tab.dart';
import '../../shared/application/nav_bar_docking.dart';
import '../../shared/presentation/docking_sheet.dart';
import '../../shared/presentation/stat_tile.dart';
import '../../shared/presentation/tab_chrome_slide.dart';
import '../../smart_loop/presentation/smart_loop_sheet.dart';
import '../application/planner_controller.dart';
import '../application/planner_map_binding.dart';
import '../data/route_repository.dart';
import '../data/routing_backend_provider.dart';
import '../domain/elevation_profile.dart';
import '../domain/planner_state.dart';
import '../domain/routing_options.dart';
import 'elevation_profile_chart.dart';
import 'profile_chip_row.dart';
import 'route_format.dart';
import 'save_route_dialog.dart';
import 'surface_stats_bar.dart';
import 'waypoint_edit_sheet.dart';

/// The Plan tab: the search and profile controls at the top and the route
/// details in a draggable sheet at the bottom, over the map the shell
/// paints under the Plan and Record tabs.
class PlannerScreen extends ConsumerStatefulWidget {
  /// Creates the planner.
  const PlannerScreen({super.key});

  @override
  ConsumerState<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends ConsumerState<PlannerScreen>
    with WidgetsBindingObserver {
  /// The shared map, while it can be driven.
  MapController? _map;

  /// The binding of the plan to [_map]; kept while the tab is away, so the
  /// plan's history is not lost between a leave and a return.
  PlannerMapBinding? _binding;

  /// Whether this tab's layers and handlers are on the shared map right now.
  bool _drawing = false;

  /// Whether a draw is on its way, from the microtask it waits for.
  bool _drawPending = false;

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
  // The sheet's collapsed and resting sizes, as computed by the last build.
  double _collapsedSheetSize = 0.1;
  double _restingSheetSize = 0.48;

  /// The sheet's snap points, kept as one instance for as long as the
  /// resting size holds. DraggableScrollableSheet compares the list by
  /// identity and snaps to the nearest point after every rebuild it sees a
  /// new one, which cancels a drag or a rise in flight; this screen rebuilds
  /// on every tab change and chrome measurement.
  List<double> _snapSizes = const [];

  List<double> _snapSizesFor(double resting) {
    if (_snapSizes.length != 1 || _snapSizes.first != resting) {
      _snapSizes = <double>[resting];
    }
    return _snapSizes;
  }

  /// Whether this is the tab on screen.
  bool _active = true;

  /// What the shell's control column was last told about this tab.
  MapChromeData? _chromeData;

  /// Tells the shell's column what this tab wants of it, after the frame.
  void _shareChrome(MapChromeData data) {
    if (data == _chromeData) return;
    _chromeData = data;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _active && _chromeData == data) {
        ref.read(activeMapChromeProvider.notifier).set(data);
      }
    });
  }

  /// The sheet's extent, while this is the tab on screen, for the tab that
  /// comes next.
  void _onSheetExtent(double extent) {
    if (_active) ref.read(tabHandoverProvider.notifier).setSheetExtent(extent);
  }

  /// Where the map's control column rests under this tab's chrome. The
  /// column itself is one shared, animated value ([mapControlsTopProvider]):
  /// this tab sends it there when it comes on screen and when its chrome
  /// changes while it is.
  double _ownControlsTop = defaultMapControlsTop;

  /// This tab is coming on screen: the column glides from wherever it is
  /// to its place under this tab's chrome.
  void _takeOverControls() =>
      ref.read(mapControlsTopProvider).glide(to: _ownControlsTop);

  /// This tab has just come on screen: the sheet starts where the last
  /// tab's was and settles where this one's is, so the two tabs read as
  /// one screen re-arranging; and a sheet below its resting height (docked
  /// in the bar, say) rises to it, undocking the bar as it goes. A sheet
  /// already at rest, or pulled higher by the rider, stays.
  void _takeOverSheet() {
    if (!_sheet.isAttached) return;
    final current = _sheet.size;
    final from = ref.read(tabHandoverProvider).sheetExtent ?? current;
    if ((from - current).abs() >= 0.005) _sheet.jumpTo(from);
    final target = math.max(current, _restingSheetSize);
    if ((target - from).abs() < 0.005) return;
    unawaited(
      _sheet.animateTo(
        target,
        duration: tabSheetSettleDuration,
        curve: tabChromeSlideCurve,
      ),
    );
  }

  /// Whether the sheet was last reported to the bar as docked in it.
  bool _docked = false;
  late final NavBarDocking _docking = ref.read(navBarDockingProvider.notifier);

  void _reportDocked(bool docked) {
    if (docked == _docked) return;
    _docked = docked;
    _docking.setDocked(plannerRoute, docked);
  }

  @override
  void initState() {
    super.initState();
    // The keyboard's going is what brings the sheet back; the window does
    // not rebuild this screen by itself, so metrics changes are listened for.
    WidgetsBinding.instance.addObserver(this);
    _active = ref.read(activeTabProvider) == plannerRoute;
    _map = ref.read(sharedMapControllerProvider);
    _updateMapUse();
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
    if (_docked) {
      // Deferred: the tree is locked while a widget goes, and the shell
      // would rebuild for this.
      final docking = _docking;
      scheduleMicrotask(() => docking.setDocked(plannerRoute, false));
    }
    super.dispose();
  }

  /// A tapped marker: one sheet for the point's name, kind and note, its
  /// place in the order, and Remove. Swaps are applied while the sheet is
  /// open; name, kind and note when it closes with Done, as one undo step,
  /// and only when something about them changed.
  Future<void> _editWaypoint(int index) async {
    final state = ref.read(plannerControllerProvider);
    if (index < 0 || index >= state.waypoints.length) return;
    final point = state.waypoints[index];
    final planner = ref.read(plannerControllerProvider.notifier);
    final initial = WaypointDetails(
      name: point.name,
      poiKind: point.poiKind,
      note: point.note,
    );
    final result = await showModalBottomSheet<WaypointEditResult>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => WaypointEditSheet(
        index: index,
        count: state.waypoints.length,
        initial: initial,
        onSwap: planner.swapWaypoint,
      ),
    );
    if (!mounted || result == null) return;
    switch (result) {
      case WaypointEditRemove(:final index):
        planner.removeWaypoint(index);
      case WaypointEditDone(:final index, :final details):
        if (details == initial) return;
        planner.setWaypointDetails(
          index,
          name: details.name,
          poiKind: details.poiKind,
          note: details.note,
        );
    }
  }

  /// The shared map came, went, or was replaced after a style reload: the
  /// binding to the old one is worthless, and a new map is bare.
  void _onMapChanged(MapController? map) {
    if (identical(map, _map)) return;
    _binding?.detach();
    _binding = null;
    _drawing = false;
    _map = map;
    _updateMapUse();
  }

  /// Puts this tab's layers and handlers on the shared map while it is the
  /// tab on screen, and takes them off when it is not: the other tabs draw
  /// their own on the same map, and only one tab's belong there at a time.
  ///
  /// The clear is immediate and the draw waits a microtask, so the tab that
  /// leaves has cleared before the tab that arrives draws, whichever of the
  /// two hears of the change first.
  void _updateMapUse() {
    final map = _map;
    final wanted = _active && map != null;
    if (!wanted) {
      if (!_drawing) return;
      _drawing = false;
      final binding = _binding;
      if (binding == null) return;
      binding.detach();
      unawaited(binding.clear());
      unawaited(binding.map.setSearchPin(null));
      return;
    }
    if (_drawing || _drawPending) return;
    _drawPending = true;
    scheduleMicrotask(_drawOnMap);
  }

  void _drawOnMap() {
    _drawPending = false;
    final map = _map;
    if (!mounted || !_active || map == null || _drawing) return;
    _drawing = true;
    var binding = _binding;
    if (binding == null || !identical(binding.map, map)) {
      binding = PlannerMapBinding(
        map: map,
        planner: ref.read(plannerControllerProvider.notifier),
      );
      binding.onWaypointTap = (index) {
        unawaited(_editWaypoint(index));
      };
      _binding = binding;
    }
    binding.attach();
    unawaited(binding.sync(ref.read(plannerControllerProvider)));
    // A searched place the rider has not decided about is still theirs.
    final place = _placeToStartFrom;
    if (place != null) {
      unawaited(map.setSearchPin(place.position, label: place.name));
    }
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

    ref.listen(sharedMapControllerProvider, (_, next) => _onMapChanged(next));
    ref.listen(plannerControllerProvider, (previous, next) {
      // Only while this tab's layers are on the map; a plan that changes
      // while the tab is away is drawn whole when it comes back.
      if (_drawing) unawaited(_binding?.sync(next));
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

    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final screenHeight = MediaQuery.sizeOf(context).height;
    // Collapsed, only the handle strip is left above the floating navigation
    // bar, which the bottom padding already covers under `extendBody`: the
    // sheet is docked in the bar, the map is free, and one pull brings the
    // plan back.
    final collapsedSheetSize = screenHeight <= 0
        ? 0.1
        : ((bottomInset + sheetHandleDp) / screenHeight).clamp(0.01, 0.25);
    _collapsedSheetSize = collapsedSheetSize;
    final dockedRange = screenHeight <= 0
        ? 0.15
        : sheetDockingRangeDp / screenHeight;
    // One resting height whatever the sheet holds, shared with the Record
    // tab: room for the variant chips is always there.
    final restingSheetSize = sheetRestingExtent(screenHeight);
    _restingSheetSize = restingSheetSize;
    final hasVariants = state.alternatives.length > 1;

    // The tab on screen: the chrome over the map slides in when it is this
    // one, the plan goes on the map, and the map's control column and the
    // sheet pick up where the last tab left them.
    final active = ref.watch(activeTabProvider) == plannerRoute;
    _active = active;
    ref.listen(activeTabProvider, (previous, next) {
      if (next == plannerRoute && previous != plannerRoute) {
        _active = true;
        _updateMapUse();
        _takeOverControls();
        _takeOverSheet();
      } else if (previous == plannerRoute && next != plannerRoute) {
        _active = false;
        _updateMapUse();
        // The next tab tells the column its own wants; this one tells it
        // again, from scratch, when it comes back.
        _chromeData = null;
        // The bar is square only while a docked strip is on top: the next
        // tab's sheet says so for itself from here on.
        _reportDocked(false);
      }
    });
    if (active) _shareChrome(const MapChromeData());
    _ownControlsTop = _chromeHeight + 12;
    final controlsTop = ref.read(mapControlsTopProvider);
    if (active && (controlsTop.target - _ownControlsTop).abs() >= 0.5) {
      // A change of this tab's own chrome, on screen: the column glides,
      // after the frame, since the shell listens to it and may not be told
      // during a build. The first tab of the launch takes its place without
      // a glide.
      final own = _ownControlsTop;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_active) return;
        if (controlsTop.everMoved) {
          controlsTop.glide(to: own);
        } else {
          controlsTop.jump(own);
        }
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measureChrome();
    });

    // Not a Scaffold: a Scaffold's material absorbs every touch, and a tap
    // that lands on nothing of this screen has to fall through to the
    // shell's map. A transparent material is what the buttons need and
    // lets the touch pass; the shell's scaffold shows the snack bars and
    // keeps the screen its full height under the keyboard.
    return Material(
      type: MaterialType.transparency,
      child: SizedBox.expand(
        child: Stack(
          children: [
            TabChromeSlide(
              active: active,
              child: SafeArea(
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
                                  onPressed: () =>
                                      unawaited(_rideFromPosition()),
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
            ),
            DraggableScrollableSheet(
              controller: _sheet,
              // Enough for the headline, the toolbar and Save above the
              // floating navigation bar on a 20:9 phone.
              initialChildSize: restingSheetSize,
              minChildSize: collapsedSheetSize,
              maxChildSize: 0.9,
              snap: true,
              // One resting height, not one per state: with two in the list
              // a pull down from the top settled on the higher one and a pull
              // up from the handle on the lower one, a chip row apart.
              snapSizes: _snapSizesFor(restingSheetSize),
              builder: (context, scrollController) => DockingSheet(
                controller: scrollController,
                gripDp: sheetGripWithTitleDp,
                initialExtent: restingSheetSize,
                collapsedExtent: collapsedSheetSize,
                dockedRange: dockedRange,
                docks: true,
                dockedBottomInset: bottomInset,
                onDocked: _reportDocked,
                onExtent: _onSheetExtent,
                handle: const SheetHandle(),
                // Its own scrolling, at any height of the sheet; the
                // sheet moves by its handle.
                child: Builder(
                  // Looked up from inside the shell, which hands the controller down.
                  builder: (context) => ListView(
                    controller: SheetContentScroll.maybeOf(context),
                    padding: EdgeInsets.fromLTRB(20, 0, 20, bottomInset + 24),
                    children: [
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
        SizedBox(
          height: primaryButtonHeight,
          child: FilledButton.icon(
            onPressed: state.canSave ? () => unawaited(onSave()) : null,
            icon: const Icon(Icons.bookmark_add_outlined),
            label: Text(l10n.plannerSave),
          ),
        ),
      ],
    );
  }
}

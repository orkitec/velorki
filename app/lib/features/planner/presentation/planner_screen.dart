import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../assistant/application/assistant_sheet_memory.dart';
import '../../assistant/application/route_advice_controller.dart';
import '../../assistant/domain/intent_resolver.dart';
import '../../assistant/presentation/assistant_sheet.dart';
import '../../integrations/common/data/relay_client_provider.dart';
import '../../map/application/cycle_map_binding.dart';
import '../../map/application/locate_on_open.dart';
import '../../map/application/map_stops_controller.dart';
import '../../map/domain/visible_map.dart';
import '../../map/presentation/stops_zoom_chip.dart';
import '../../map/data/map_preferences.dart';
import '../../map/domain/map_controller.dart';
import '../../map/presentation/device_position_request.dart';
import '../../map/presentation/map_chrome.dart';
import '../../map/presentation/map_controls.dart' show mapControlButtonSize;
import '../../map/presentation/visible_map_padding.dart';
import '../../map/presentation/shared_map_host.dart';
import '../../offline/presentation/offline_screen.dart';
import '../../routing_tiles/presentation/missing_tiles_banner.dart';
import '../../search/domain/search_result.dart';
import '../../search/presentation/place_card.dart';
import '../../search/presentation/search_field.dart';
import '../../settings/data/units.dart';
import '../../shared/application/active_tab.dart';
import '../../shared/application/covering_sheets.dart';
import '../../shared/application/nav_bar_docking.dart';
import '../../../app/shell_layout.dart';
import '../../shared/presentation/adaptive_docking_sheet.dart';
import '../../shared/presentation/docking_sheet.dart';
import '../../shared/presentation/stat_tile.dart';
import '../../shared/presentation/tab_chrome_slide.dart';
import '../../smart_loop/application/smart_loop_controller.dart';
import '../../smart_loop/presentation/smart_loop_sheet.dart';
import '../application/incoming_place.dart';
import '../application/planner_controller.dart';
import '../application/planner_map_binding.dart';
import '../data/route_repository.dart';
import '../data/routing_backend_provider.dart';
import '../domain/elevation_profile.dart';
import '../domain/planner_state.dart';
import '../domain/route_waypoints.dart' show projectOnTrack;
import '../domain/routing_options.dart';
import 'elevation_profile_chart.dart';
import 'avoided_stretches_chip.dart';
import 'original_route_chip.dart';
import 'profile_chip_row.dart';
import 'route_format.dart';
import 'save_route_dialog.dart';
import 'surface_section.dart';
import 'surface_stats_bar.dart';
import 'waypoint_edit_sheet.dart';
import '../../shared/presentation/error_text.dart';

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
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  /// The shared map, while it can be driven.
  MapController? _map;

  /// The binding of the plan to [_map]; kept while the tab is away, so the
  /// plan's history is not lost between a leave and a return.
  PlannerMapBinding? _binding;

  /// Whether this tab's layers and handlers are on the shared map right now.
  bool _drawing = false;

  /// Whether a draw is on its way, from the microtask it waits for.
  bool _drawPending = false;

  /// The place whose card is open: pinned on the map until the card closes.
  SearchResult? _shownPlace;

  /// The chrome over the map (search field, chips),
  /// measured after each layout so the map's control column starts below
  /// it whatever the rows above happen to need.
  final GlobalKey _chromeKey = GlobalKey();
  double _chromeHeight = 8 + 56 + 10 + 44;

  void _measureChrome() {
    final height = _chromeKey.currentContext?.size?.height;
    if (height == null || (height - _chromeHeight).abs() < 0.5) return;
    setState(() => _chromeHeight = height);
  }

  /// The air between the things in the row at the top sideways.
  static const double _rowGap = 8;

  /// The chrome on a phone turned sideways: one row at the top of the map,
  /// the shell's controls beside the docked sheet, then [search], with the
  /// profile menu at its end, running on to the far edge; under the row,
  /// beside the resting sheet, the rows [below] that come and go.
  ///
  /// At rest the sheet lies over the controls, which the rider reaches by
  /// docking it. The search is what stays in reach: as wide as the strip
  /// the resting sheet leaves, menu and all, and narrower only where the
  /// docked row would not have room for the controls beside it.
  Widget _sidewaysChrome(
    BuildContext context, {
    required Widget search,
    required List<Widget> below,
  }) {
    final layout = ShellLayout.of(context);
    final media = MediaQuery.of(context);
    final left = layout.side == RailSide.left;
    final width = media.size.width;
    // The row reaches past the far edge's safe area, which the rows under
    // it keep to.
    const far = sidewaysTopRowFarEdge;
    final farSafe =
        (left ? media.viewPadding.right : media.viewPadding.left) +
        sidewaysTopRowGap;
    final controls = ref.watch(mapControlsRowWidthProvider);
    // From the rail's edge: the docked sheet, the shell's controls, air.
    final near =
        sidewaysTopRowStart(media, layout) +
        (controls > 0 ? controls + _rowGap : 0);
    final besideRest =
        sidewaysSheetCover(media, layout, docked: false) + sidewaysTopRowGap;
    final searchWidth = math.min(width - besideRest, width - near) - far;
    return Padding(
      padding: EdgeInsets.only(
        top: media.padding.top + sidewaysTopRowTop,
        left: left ? near : far,
        right: left ? far : near,
      ),
      child: Column(
        key: _chromeKey,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Held at the far edge.
          Align(
            alignment: left ? Alignment.centerRight : Alignment.centerLeft,
            child: SizedBox(width: math.max(0, searchWidth), child: search),
          ),
          Padding(
            padding: EdgeInsets.only(
              left: math.max(0, left ? besideRest - near : farSafe - far),
              right: math.max(0, left ? farSafe - far : besideRest - near),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: below,
            ),
          ),
        ],
      ),
    );
  }

  final DraggableScrollableController _sheet = DraggableScrollableController();

  /// The search field's key: it keeps its text and focus across a turn of
  /// the phone, which moves it to another row.
  final GlobalKey _searchKey = GlobalKey();
  // Where the sheet was before the search field took it out of the way, or
  // null while the search has not: its size among the stops it had then. A
  // size is a share of the screen's length, which a turn of the phone
  // changes: a sheet that was at rest comes back to rest, one that was
  // docked comes back docked, wherever that is now.
  //
  // Kept for as long as the field has focus, not only while the keyboard
  // is up: the keyboard can go and come back without the field letting go
  // (iOS puts it away for a turn of the phone and brings it back after),
  // and the sheet then comes back, in the end, to where the rider left it,
  // not to wherever it was when the keyboard came back.
  (double, SheetStops)? _sheetBeforeSearch;
  // Whether the sheet is parked under the keyboard now.
  bool _sheetParked = false;
  // The sheet's collapsed and resting sizes, as computed by the last build.
  double _collapsedSheetSize = 0.1;
  double _restingSheetSize = 0.48;

  /// How far the sheet opens.
  static const double _maxSheetSize = sheetMaxExtent;

  SheetStops get _sheetStops => SheetStops(
    collapsed: _collapsedSheetSize,
    resting: _restingSheetSize,
    max: _maxSheetSize,
  );

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
    // The stops follow what the sheet leaves of the map.
    _stops.visibleAreaChanged();
  }

  /// What covers this tab's map: its chrome, the column, and the sheet at
  /// its resting height. A searched place and a route that arrives whole
  /// both bring the sheet to rest, so they aim for the map above that
  /// rather than above wherever the sheet was a moment before.
  ///
  /// Asked for by work that finishes after an await; a screen that has gone
  /// in the meantime has no context to measure, and nothing left to fit.
  EdgeInsets _visiblePadding() => mounted
      ? visibleMapPadding(context, chromeTop: _ownControlsTop)
      : EdgeInsets.zero;

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
    _stops = MapStopsController(
      find: ref.read(mapStopsFinderProvider),
      coverage: ref.read(mapStopsCoverageProvider),
      // What the sheet leaves of the map now, pulled up or down, not at
      // its resting height.
      visibleShare: () => mounted
          ? visibleShareOf(
              visibleMapPadding(
                context,
                chromeTop: _ownControlsTop,
                sheetExtent: _sheet.isAttached ? _sheet.size : null,
              ),
              MediaQuery.sizeOf(context),
            )
          : null,
    )..onStopTapped = _onStopTapped;
    _updateMapUse();
  }

  /// The stops in the area on screen, from the Layers sheet.
  late final MapStopsController _stops;

  /// A stop tapped on the map: its card, the map kept at its zoom, since
  /// the rider is looking at the stop already.
  void _onStopTapped(SearchResult stop) => unawaited(_openPlace(stop));

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
    if (!_sheet.isAttached) return;
    _sheetBeforeSearch ??= (_sheet.size, _sheetStops);
    _sheetParked = true;
    unawaited(
      _sheet.animateTo(
        _collapsedSheetSize,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      ),
    );
  }

  /// Brings the sheet back to where it was before the search, and forgets
  /// that place once the field has let go.
  void _restoreSheet() {
    final before = _sheetBeforeSearch;
    if (before == null) return;
    if (!_searchFocused) _sheetBeforeSearch = null;
    // Back already, the keyboard gone before the field let go: the rider
    // may have moved it since.
    if (!_sheetParked) return;
    _sheetParked = false;
    // After the frame: the keyboard may go with a turn of the phone, and
    // the stops are the new ones only once this screen has been built for
    // it.
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (!mounted || !_sheet.isAttached) return;
        // The keyboard came back in the meantime.
        if (_keyboardUp && _searchFocused) return;
        // A sheet opened over the tab meanwhile (the card of the place
        // picked) holds the sheet down, and brings it back here itself.
        if (ref.read(coveringSheetsProvider) > 0) return;
        final (extent, stops) = before;
        unawaited(
          _sheet.animateTo(
            mapSheetExtent(extent, from: stops, to: _sheetStops),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          ),
        );
      })
      ..ensureVisualUpdate();
  }

  /// Where the sheet comes back to after a sheet opened over the tab: where
  /// it is, or where the search took it from while it is parked for one.
  double _sheetReturnExtent() {
    final before = _sheetBeforeSearch;
    if (_sheetParked && before != null) {
      final (extent, stops) = before;
      return mapSheetExtent(extent, from: stops, to: _sheetStops);
    }
    return _sheet.size;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _binding?.detach();
    _stops.dispose();
    _sheet.dispose();
    _assistantSlide.dispose();
    if (_docked) {
      // Deferred: the tree is locked while a widget goes, and the shell
      // would rebuild for this.
      final docking = _docking;
      scheduleMicrotask(() => docking.setDocked(plannerRoute, false));
    }
    super.dispose();
  }

  /// A tapped marker on the route: one sheet for the point's name, kind and
  /// note, its place in the order, the switch to the side of the route, and
  /// Remove. Swaps are applied while the sheet is open; the rest when it
  /// closes with Done, and only what changed.
  Future<void> _editWaypoint(int index) async {
    final state = ref.read(plannerControllerProvider);
    if (index < 0 || index >= state.waypoints.length) return;
    final point = state.waypoints[index];
    final planner = ref.read(plannerControllerProvider.notifier);
    final initial = WaypointDetails(
      name: point.name,
      poiKind: point.poiKind,
      note: point.note,
      turn: point.turn,
    );
    final result = await _showPointSheet(
      index: index,
      count: state.waypoints.length,
      initial: initial,
      onSwap: planner.swapWaypoint,
    );
    if (!mounted || result == null) return;
    switch (result) {
      case WaypointEditRemove(:final index):
        planner.removeWaypoint(index);
      case WaypointEditDone(:final index, :final details):
        if (details == initial) return;
        if (!details.sameDetailsAs(initial)) {
          planner.setWaypointDetails(
            index,
            name: details.name,
            poiKind: details.poiKind,
            note: details.note,
            turn: details.turn,
          );
        }
        // The details are on the point before it moves, so the place that
        // stays beside the route carries what the rider just typed.
        if (details.beside) planner.movePointBeside(index);
    }
  }

  /// A tapped place beside the route: the same sheet, opened on its side of
  /// the switch. Flipping it back routes the ride through the place.
  Future<void> _editPoi(int index) async {
    final state = ref.read(plannerControllerProvider);
    if (index < 0 || index >= state.pois.length) return;
    final poi = state.pois[index];
    final planner = ref.read(plannerControllerProvider.notifier);
    final initial = WaypointDetails(
      name: poi.name.isEmpty ? null : poi.name,
      poiKind: poi.kind,
      note: poi.description,
      beside: true,
    );
    final result = await _showPointSheet(
      index: index,
      count: state.pois.length,
      initial: initial,
      onSwap: (_, _) {},
    );
    if (!mounted || result == null) return;
    switch (result) {
      case WaypointEditRemove(:final index):
        planner.removePoi(index);
      case WaypointEditDone(:final index, :final details):
        if (details == initial) return;
        if (!details.sameDetailsAs(initial)) {
          planner.setPoiDetails(
            index,
            name: details.name,
            poiKind: details.poiKind,
            note: details.note,
          );
        }
        if (!details.beside) planner.movePointOnRoute(index);
    }
  }

  /// The map held down: the sheet for a new place there, on the beside
  /// side of the switch. Flipped to the route before Done, the point is
  /// routed through instead.
  Future<void> _addPoiAt(LatLng pos) async {
    final planner = ref.read(plannerControllerProvider.notifier);
    final result = await _showPointSheet(
      index: 0,
      count: 0,
      initial: const WaypointDetails(beside: true),
      onSwap: (_, _) {},
    );
    if (!mounted || result is! WaypointEditDone) return;
    final details = result.details;
    planner.addPoi(
      pos,
      name: details.name,
      kind: details.poiKind,
      note: details.note,
    );
    if (details.beside) return;
    planner.movePointOnRoute(
      ref.read(plannerControllerProvider).pois.length - 1,
    );
  }

  Future<WaypointEditResult?> _showPointSheet({
    required int index,
    required int count,
    required WaypointDetails initial,
    required void Function(int index, int offset) onSwap,
  }) => coverTabSheet(
    context,
    () => showModalBottomSheet<WaypointEditResult>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => WaypointEditSheet(
        index: index,
        count: count,
        initial: initial,
        onSwap: onSwap,
      ),
    ),
  );

  /// The shared map came, went, or was replaced after a style reload: the
  /// binding to the old one is worthless, and a new map is bare.
  void _onMapChanged(MapController? map) {
    if (identical(map, _map)) return;
    _binding?.detach();
    _binding = null;
    _stops.detach(clear: false);
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
      _stops.detach();
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
        // A route that arrives whole (Open in planner) is fitted into the
        // map between this tab's chrome and its sheet.
        fitPadding: _visiblePadding,
      );
      binding.onWaypointTap = (index) {
        unawaited(_editWaypoint(index));
      };
      binding.onPoiTap = (index) {
        unawaited(_editPoi(index));
      };
      binding.onLongPress = (pos) {
        unawaited(_addPoiAt(pos));
      };
      // What the assistant was asked to show about the route.
      binding.shownPlace = () =>
          switch (ref.read(routeAdviceControllerProvider).shown) {
            null => null,
            final place => shownPoi(place),
          };
      _binding = binding;
    }
    binding.attach();
    unawaited(binding.sync(ref.read(plannerControllerProvider)));
    _stops.attach(map);
    // A place whose card is open is still pinned.
    final place = _shownPlace;
    if (place != null) {
      unawaited(map.setSearchPin(place.position, label: _placeLabel(place)));
    }
    // A place another app sent while the map was not up yet.
    _takeIncomingPlace();
  }

  /// Shows a place another app sent ([incomingPlaceProvider]) once this tab
  /// is on screen and can: one with coordinates goes the way a tapped
  /// search result goes, an address or a name into the search field as
  /// typed, and a link only a browser can open gets a short message.
  void _takeIncomingPlace() {
    final place = ref.read(incomingPlaceProvider);
    // One card at a time: the next place waits for this one to close.
    if (place == null || !mounted || !_active || _shownPlace != null) return;
    final search = _searchKey.currentState;
    if (search is! SearchFieldState) return;
    final link = place.link;
    final position = link.position;
    final query = link.query;
    if (position != null) {
      // The pin and the camera need the map; on a cold start it comes later,
      // and the draw that follows it brings the place back here.
      if (_map == null || !_drawing) return;
      ref.read(incomingPlaceProvider.notifier).taken(place);
      // The place is where the rider asked the map to go, as surely as a
      // hand on it: the move to the rider's position that an opening of the
      // app starts (a cold start through this very link) must not take the
      // map back once its fix comes in.
      ref.read(locateOnOpenProvider).touched();
      search.select(
        SearchResult(
          name:
              link.name ??
              '${position.lat.toStringAsFixed(5)}, '
                  '${position.lon.toStringAsFixed(5)}',
          position: position,
        ),
      );
    } else if (query != null) {
      ref.read(incomingPlaceProvider.notifier).taken(place);
      search.searchFor(query);
    } else {
      ref.read(incomingPlaceProvider.notifier).taken(place);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).placeLinkNeedsBrowser),
        ),
      );
    }
  }

  /// A place picked in the search (or sent by another app, which goes the
  /// same way): its card, the map zoomed in on it.
  void _onPlaceSelected(SearchResult result) =>
      unawaited(_openPlace(result, fromSearch: true, zoom: 13));

  /// What the pin on the map says: the place's name, or what it is.
  String _placeLabel(SearchResult place) => place.name.isNotEmpty
      ? place.name
      : searchResultTitle(AppLocalizations.of(context), place);

  /// What the plan can do with a picked place: start from it or ride to it
  /// while it is empty, end at it once it has a start, and with a route
  /// also take it in on the way.
  List<PlaceAction> _placeActions(PlannerState state) =>
      switch (state.waypoints.length) {
        0 => const [PlaceAction.routeHere, PlaceAction.startHere],
        1 => const [PlaceAction.destination],
        _ => const [PlaceAction.addStop, PlaceAction.destination],
      };

  /// The card of a picked [place]: pinned on the map and brought into view
  /// above the card (at [zoom], or the map's own) while it is open, and
  /// what the rider chose done once it closes. Closed without a choice, it
  /// leaves the plan as it was; one picked in the search also empties the
  /// field.
  Future<void> _openPlace(
    SearchResult place, {
    bool fromSearch = false,
    double? zoom,
  }) async {
    if (!mounted || _shownPlace != null) return;
    final state = ref.read(plannerControllerProvider);
    final route = state.result;
    final offRouteM = route != null && route.geometry.length >= 2
        ? projectOnTrack(route.positions, place.position).distanceM
        : null;
    _shownPlace = place;
    unawaited(_map?.setSearchPin(place.position, label: _placeLabel(place)));
    var moved = false;
    final action = await showPlaceCard(
      context,
      place: place,
      actions: _placeActions(state),
      offRouteM: offRouteM,
      onCover: (cover) {
        if (moved || !mounted) return;
        moved = true;
        unawaited(
          _map?.moveTo(
            place.position,
            zoom: zoom,
            padding: _paddingAbove(cover),
          ),
        );
      },
    );
    _shownPlace = null;
    if (!mounted) return;
    unawaited(_map?.setSearchPin(null));
    final planner = ref.read(plannerControllerProvider.notifier);
    switch (action) {
      case null:
        final search = _searchKey.currentState;
        if (fromSearch && search is SearchFieldState) search.clear();
      case PlaceAction.routeHere:
        await _rideFromPosition(place);
      case PlaceAction.startHere || PlaceAction.destination:
        planner.addWaypoint(place.position, name: place.name);
      case PlaceAction.addStop:
        planner.addWaypointAlongRoute(place.position, name: place.name);
    }
    // A place another app sent meanwhile is taken now.
    if (mounted) setState(() {});
  }

  /// The padding that keeps a place in the map between this tab's chrome
  /// and a card covering [cover] of the screen's bottom.
  EdgeInsets _paddingAbove(double cover) {
    final base = _visiblePadding();
    final height = MediaQuery.sizeOf(context).height;
    // Some map is left between the two, however tall the card.
    final bottom = math.max(0.0, math.min(cover + 24, height - base.top - 48));
    return base.copyWith(bottom: bottom);
  }

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

  /// [place] is the destination; the ride starts where the rider is right
  /// now.
  Future<void> _rideFromPosition(SearchResult place) async {
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
  /// fallback start. A loop the sheet made, closed or re-routed is fitted
  /// into the visible map once the sheet is gone: the start may have been
  /// off screen, and the sheet itself covered most of the map until now.
  ///
  /// With [returnWhenDone], for a search the assistant started, the sheet
  /// closes by itself once that search is done; answers whether it did.
  Future<bool> _smartLoop({bool returnWhenDone = false}) async {
    final before = ref.read(plannerControllerProvider).result;
    final done = await showSmartLoopSheet(
      context,
      map: _map,
      chromeTop: _ownControlsTop,
      returnWhenDone: returnWhenDone,
    );
    if (!mounted) return false;
    final result = ref.read(plannerControllerProvider).result;
    if (result != null && !identical(result, before)) _fitRoute(result);
    return done;
  }

  /// Fits [result] into the map between this tab's chrome and its sheet.
  void _fitRoute(RouteResult result) {
    final positions = result.positions;
    if (positions.isEmpty) return;
    unawaited(
      _map?.fitBounds(
        BoundingBox.fromPoints(positions),
        padding: _visiblePadding(),
      ),
    );
  }

  /// Whether the assistant's card is over the sheet: the plan's card stays
  /// where it was, as it was, under it, and is there again when the AI's
  /// card goes.
  bool _assistantOpen = false;

  /// The AI's card coming over the plan's: 0 out of view, 1 in. Opening, it
  /// slides in along the sheets' travel, in the time and curve a tab's
  /// sheet settles in; closing, back out from wherever it is. The plan's
  /// card does not move.
  late final AnimationController _assistantSlide =
      AnimationController(vsync: this, duration: tabSheetSettleDuration)
        ..addStatusListener((_) {
          if (mounted) setState(() {});
        });
  late final Animation<double> _assistantIn = CurvedAnimation(
    parent: _assistantSlide,
    curve: tabChromeSlideCurve,
    reverseCurve: tabChromeSlideCurve.flipped,
  );
  late final Animation<double> _assistantOut = ReverseAnimation(_assistantIn);

  /// Which opening of the AI's card this is: each one is a card of its own,
  /// set up from what the assistant remembers, even one that comes back
  /// while the last is still sliding out.
  int _assistantSession = 0;

  /// Whether the AI's card of this opening opens all the way.
  bool _assistantFull = false;

  /// How much of the screen's length the AI's card covers, as it reports.
  double _assistantExtent = 0.5;

  /// The screen's length along the sheets' travel, at the last build.
  double _sheetLength = 0;

  /// The entry that makes the system's back close the assistant's card,
  /// while it is open.
  LocalHistoryEntry? _assistantBack;

  /// Opens the assistant in the sheet's place.
  ///
  /// A rider known to be without Plus gets the card all the same, to look
  /// around in, with Subscribe where Ask would be.
  Future<void> _ask() async => _openAssistant();

  void _openAssistant() {
    if (_assistantOpen || !mounted) return;
    // Over a plan's card pulled up past its rest the AI's card opens all
    // the way, its next stop, so that none of the plan's card shows above
    // it; otherwise at the plan's card's resting height.
    final full = _sheet.isAttached && _sheet.size > _restingSheetSize + 0.005;
    setState(() {
      _assistantOpen = true;
      _assistantFull = full;
      _assistantSession++;
    });
    unawaited(_assistantSlide.forward());
    // Not docked: the AI's card is up.
    _reportDocked(false);
    final extent = full ? _maxSheetSize : _restingSheetSize;
    _assistantExtent = extent;
    _onSheetExtent(extent);
    late final LocalHistoryEntry entry;
    entry = LocalHistoryEntry(
      onRemove: () {
        // Back: the entry went by itself.
        if (!identical(_assistantBack, entry)) return;
        _assistantBack = null;
        _assistantClosed(null);
      },
    );
    _assistantBack = entry;
    ModalRoute.of(context)?.addLocalHistoryEntry(entry);
  }

  /// The assistant's card asked to go, with what it handed over.
  void _closeAssistant(ResolvedIntent? intent) {
    final entry = _assistantBack;
    _assistantBack = null;
    entry?.remove();
    _assistantClosed(intent);
  }

  /// The assistant's card has gone: the plan's card is back as it was, and
  /// whatever the assistant produced is shown.
  ///
  /// A loop with no place to ride past is running as a loop search, so the
  /// loop sheet opens on it and the card comes back once it is done. Anything
  /// else — a loop through places, a point-to-point route — is on the map.
  void _assistantClosed(ResolvedIntent? intent) {
    if (!_assistantOpen || !mounted) return;
    setState(() => _assistantOpen = false);
    unawaited(_assistantSlide.reverse());
    if (_sheet.isAttached) _onSheetExtent(_sheet.size);
    if (intent == null) return;
    if (intent is LoopIntent && intent.via.isEmpty) {
      unawaited(_loopForAssistant(intent));
      return;
    }
    if (intent is LoopIntent || intent is RouteIntent) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).assistantRouteHandedOver),
        ),
      );
    }
  }

  /// Shows the loop search the assistant started for [intent] and, once it
  /// is done, brings the assistant back: asking about the loop when one is
  /// on the map, saying so when none was found. A rider who closed the loop
  /// sheet or took the search over meanwhile is left where they are.
  Future<void> _loopForAssistant(LoopIntent intent) async {
    // The card goes as the intent is ready, a moment before the search it
    // starts is under way.
    await Future<void>.value();
    if (!mounted) return;
    final running = ref.read(smartLoopControllerProvider).running;
    // Done before the sheet could open: nothing to watch.
    final done = running ? await _smartLoop(returnWhenDone: true) : true;
    if (!mounted || !done || _assistantOpen) return;
    final planner = ref.read(plannerControllerProvider);
    final loop = ref.read(smartLoopControllerProvider);
    final found = loop.current != null && canAskAboutRoute(planner);
    if (!running && planner.result != null) _fitRoute(planner.result!);
    ref.read(assistantSheetMemoryProvider)
      ..loop = LoopHandover(
        intent: intent,
        found: found,
        ends: found ? planEnds(planner) : null,
      )
      ..mode = found ? AssistantMode.thisRoute : AssistantMode.newRoute;
    _openAssistant();
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
          pois: state.pois,
          options: state.options,
          id: state.savedRouteId,
          surfaceStats: state.surfaceStats,
          original: state.original,
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
    // A place another app sent: taken after this frame, when the search
    // field and the tab's state are settled.
    if (ref.watch(incomingPlaceProvider) != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _takeIncomingPlace());
    }
    ref.listen(routeAdviceControllerProvider.select((s) => s.shown), (_, _) {
      if (_drawing) {
        unawaited(_binding?.sync(ref.read(plannerControllerProvider)));
      }
    });
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.plannerRoutingFailed(errorText(l10n, error))),
        ),
      );
      ref.read(plannerControllerProvider.notifier).clearError();
    });

    // Upright the sheet rises over the screen's height and the bar covers
    // its end; sideways it is the same sheet turned, coming out from the
    // rail's side over the screen's width.
    final geometry = SheetGeometry.of(context);
    _sheetLength = geometry.length;
    final bottomInset = geometry.endInset;
    // Collapsed, only the handle strip is left beside the floating
    // navigation bar, which the padding already covers under `extendBody`:
    // the sheet is docked in the bar, the map is free, and one pull brings
    // the plan back.
    final collapsedSheetSize = geometry.collapsed;
    _collapsedSheetSize = collapsedSheetSize;
    final dockedRange = geometry.dockedRange;
    // One resting height whatever the sheet holds, shared with the Record
    // tab: room for the variant chips is always there.
    final restingSheetSize = geometry.resting;
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
    if (active) {
      _shareChrome(const MapChromeData(stopsOffer: MapStopsOffer.plan));
    }
    final stopsWanted = ref.watch(mapStopsPreferencesProvider);
    _stops.update(shown: stopsWanted.shown, kinds: stopsWanted.kinds);
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

    final sideways = ShellLayout.of(context).sideRail;
    final setProfile = ref.read(plannerControllerProvider.notifier).setProfile;
    // Keyed, so a search under way survives the phone turning, which moves
    // the field from its own row into the row with the controls. Sideways
    // the profile menu is at its end, where upright the chips are a row.
    final search = SearchField(
      key: _searchKey,
      onSelected: _onPlaceSelected,
      onFocusChanged: _onSearchFocus,
      bias: () => _map?.center,
      onDownloadArea: _openOfflineData,
      trailing: sideways
          ? ({required compact}) => ProfileDropdown(
              selected: state.options.profile,
              onSelected: setProfile,
              compact: compact,
            )
          : null,
    );

    final cycleMapNeedsDownload = ref.watch(
      sharedCycleMapNeedsDownloadProvider,
    );
    // What the chrome shows under its first rows, now and then.
    final below = <Widget>[
      // Stops on, but none to show: the area is not downloaded, or the map
      // is too far out. The download first, since zooming in would show
      // nothing either.
      // The cycle map on over an area with no tiles says so too, after
      // the stops: one chip, the same download.
      ListenableBuilder(
        listenable: _stops,
        builder: (context, _) =>
            _stops.needsDownload || cycleMapNeedsDownload || _stops.needsZoom
            ? Padding(
                // Clear of the map's control column at the side: a long
                // message wraps rather than run over its top button.
                padding: const EdgeInsetsDirectional.only(
                  top: 10,
                  end: mapControlButtonSize + 14,
                ),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: _stops.needsDownload
                      ? StopsDownloadChip(onDownload: _openOfflineData)
                      : cycleMapNeedsDownload
                      ? StopsDownloadChip(
                          onDownload: _openOfflineData,
                          message: AppLocalizations.of(context)
                              .mapCycleMapNotDownloaded,
                        )
                      : StopsZoomChip(
                          onZoomIn: () => unawaited(_stops.zoomIn()),
                        ),
                ),
              )
            : const SizedBox.shrink(),
      ),
      // Shown with the faint line of the file's route,
      // and gone with it.
      if (state.differsFromOriginal)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: OriginalRouteChip(
              onRestore: ref
                  .read(plannerControllerProvider.notifier)
                  .restoreOriginal,
            ),
          ),
        ),
      // Shown with the dashed lines of the stretches the router keeps off.
      if (state.avoid.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: AvoidedStretchesChip(
              count: state.avoid.length,
              onClear: ref
                  .read(plannerControllerProvider.notifier)
                  .clearAvoided,
            ),
          ),
        ),
      if (!hasBackend)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: _NoRoutingServerBanner(),
        ),
    ];

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
              child: sideways
                  ? _sidewaysChrome(context, search: search, below: below)
                  : SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        child: Column(
                          key: _chromeKey,
                          // Only as tall as its rows, so its height is the
                          // chrome's.
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            search,
                            const SizedBox(height: 10),
                            ProfileChipRow(
                              glass: true,
                              selected: state.options.profile,
                              onSelected: setProfile,
                            ),
                            ...below,
                          ],
                        ),
                      ),
                    ),
            ),
            // Where it is, as it is, while the AI's card is over it, but
            // neither touched nor read out meanwhile: nothing of it is moved
            // or pressed from under that card, and the map around them stays
            // the map.
            IgnorePointer(
              ignoring: _assistantOpen,
              child: ExcludeSemantics(
                excluding: _assistantOpen,
                child: AdaptiveDockingSheet(
                  controller: _sheet,
                  // Enough for the headline, the toolbar and Save above the
                  // floating navigation bar on a 20:9 phone.
                  initialExtent: restingSheetSize,
                  collapsedExtent: collapsedSheetSize,
                  maxExtent: _maxSheetSize,
                  // One resting height, not one per state: with two in the list
                  // a pull down from the top settled on the higher one and a pull
                  // up from the handle on the lower one, a chip row apart.
                  snapSizes: _snapSizesFor(restingSheetSize),
                  gripDp: sheetGripWithTitleDp,
                  dockedRange: dockedRange,
                  docks: true,
                  dockedBottomInset: bottomInset,
                  onDocked: _reportDocked,
                  // Down out from behind a sheet opened over the tab, and
                  // back where it was, or, parked under the keyboard for a
                  // search, where the search took it from.
                  collapseWhenCovered: active,
                  coveredReturnExtent: _sheetReturnExtent,
                  // Under the AI's card, the map is fitted to that card.
                  onExtent: (extent) {
                    if (!_assistantOpen) _onSheetExtent(extent);
                  },
                  // Its own scrolling, at any height of the sheet; the
                  // sheet moves by its handle.
                  child: Builder(
                    // Looked up from inside the shell, which hands the controller down.
                    builder: (context) => ListView(
                      controller: SheetContentScroll.maybeOf(context),
                      padding: EdgeInsets.fromLTRB(
                        20,
                        0,
                        20,
                        MediaQuery.paddingOf(context).bottom + 24,
                      ),
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
            ),
            // The AI's card, over the planner's: no barrier, so the map
            // above it is the planner's map as ever. Kept while it slides out.
            if (_assistantOpen || !_assistantSlide.isDismissed)
              Positioned.fill(
                child: SheetSlide(
                  hidden: _assistantOut,
                  distance: () => _assistantExtent * _sheetLength + 24,
                  child: IgnorePointer(
                    // On its way out it takes no more touches.
                    ignoring: !_assistantOpen,
                    child: AssistantSheet(
                      key: ValueKey<int>(_assistantSession),
                      map: _map,
                      chromeTop: _ownControlsTop,
                      onClose: _closeAssistant,
                      openFull: _assistantFull,
                      onExtent: (extent) {
                        _assistantExtent = extent;
                        _onSheetExtent(extent);
                      },
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
                l10n.plannerRoutingFailed(errorText(l10n, failure)),
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
          // The sheet's content is as narrow as 320 sideways.
          Flexible(
            child: Text(
              l10n.plannerRouting,
              style: theme.textTheme.titleMedium,
            ),
          ),
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
        // A route the router did not draw all of has its line matched
        // against the routing tiles; until that is done, the section says
        // what is in the way rather than showing part of the route.
        if (state.surfaceStats == null && state.matchedSurface != null)
          SurfaceSection(
            surface: state.matchedSurface!,
            hideWithoutRouting: false,
          )
        else
          SurfaceStatsBar(stats: state.surfaceStats),
      ],
    );
  }
}

class _AlternativeChips extends ConsumerWidget {
  const _AlternativeChips({required this.state});

  final PlannerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).velorki;
    // One row, whatever the language: the chips share the width, and a label
    // that does not fit is set a little smaller rather than pushing a chip onto
    // a second row under the others.
    final count = state.alternatives.length;
    return Row(
      children: [
        for (var i = 0; i < count; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsetsDirectional.only(end: i == count - 1 ? 0 : 8),
              child: ChoiceChip(
                // The dot is the colour the line has on the map.
                avatar: CircleAvatar(
                  radius: 6,
                  // Same formula as the map: alternative i wears colour i.
                  backgroundColor: i == 0
                      ? colors.routeMain
                      : colors.routeAlternatives[i %
                            colors.routeAlternatives.length],
                ),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    i == 0
                        ? l10n.plannerMainRoute
                        : l10n.plannerAlternativeIndex(i),
                    maxLines: 1,
                    softWrap: false,
                  ),
                ),
                selected: i == state.options.alternativeIdx,
                onSelected: (_) => ref
                    .read(plannerControllerProvider.notifier)
                    .setAlternative(i),
              ),
            ),
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
        onPressed: state.hasPoints ? planner.clear : null,
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
          ai: true,
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

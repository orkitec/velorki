import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../import_export/presentation/import_file_action.dart';
import '../../integrations/presentation/import_from_service_menu.dart';
import '../../map/presentation/map_chrome.dart';
import '../../planner/data/route_repository.dart';
import '../../planner/domain/saved_route.dart';
import '../../planner/presentation/route_format.dart';
import '../../recording/application/ride_highlight.dart';
import '../../recording/application/ride_route_provider.dart';
import '../../recording/data/ride_repository.dart';
import '../../recording/data/ride_view_settings.dart';
import '../../recording/presentation/ride_detail_screen.dart';
import '../../recording/presentation/rides_list.dart';
import '../../settings/data/units.dart';
import '../../shared/application/active_tab.dart';
import '../../shared/application/nav_bar_docking.dart';
import '../../shared/presentation/docking_sheet.dart';
import '../../shared/presentation/placeholder_body.dart';
import '../../shared/presentation/sheet_header.dart';
import '../../shared/presentation/stat_tile.dart';
import '../../shared/presentation/tab_chrome_slide.dart';
import '../application/library_card.dart';
import '../data/library_section.dart';
import 'rename_route_dialog.dart';
import 'route_detail_screen.dart';

/// The Library tab: a card over the map the tabs share, holding the saved
/// routes and the recorded rides, or the one route or ride the rider opened.
///
/// One card for the three locations of the branch. The list is its root;
/// a route or a ride swaps the card's content for the detail under a header
/// with a back arrow, and the detail draws itself on the shared map. The
/// card, its sheet and where the rider left it stay through the swap.
class LibraryScreen extends ConsumerStatefulWidget {
  /// Creates the library, showing the list, or the route or ride given.
  const LibraryScreen({super.key, this.routeId, this.rideId});

  /// The saved route the card shows, or `null`.
  final String? routeId;

  /// The recorded ride the card shows, or `null`.
  final String? rideId;

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final DraggableScrollableController _sheet = DraggableScrollableController();

  /// The sheet's resting size, as computed by the last build.
  double _restingSheetSize = 0.48;

  /// The sheet's greatest size, as computed by the last build.
  double _maxSheetSize = 0.9;

  /// Where the sheet started, decided once at the first build.
  double? _initialSheetSize;

  /// How many rows the list on screen has, `null` while it loads or while
  /// the card shows a detail.
  int? _rows;

  /// Whether the rows have had their say on the card's height since the
  /// tab came on screen: they say it once, on arrival, and switching the
  /// segment afterwards moves nothing.
  bool _rowsApplied = false;

  /// Whether an animation of this screen's own is moving the sheet, so the
  /// extents it reports are not taken for the rider's.
  bool _settling = false;

  /// Whether the sheet has settled since the tab came on screen, so an
  /// extent change from here on is the rider dragging.
  bool _armed = false;

  /// The height the list card should have when nothing else decides: what
  /// the rider left it at this session, else the top for a list longer
  /// than two rows, else the resting height. A detail rests.
  double get _preferredExtent {
    if (_detail) return _restingSheetSize;
    final left = ref.read(libraryCardExtentProvider);
    if (left != null) return left;
    final rows = _rows;
    return rows != null && rows > 2 ? _maxSheetSize : _restingSheetSize;
  }

  /// The sheet's snap points, kept as one instance for as long as the
  /// resting size holds: the sheet snaps anew on every new list it sees.
  List<double> _snapSizes = const [];

  List<double> _snapSizesFor(double resting) {
    if (_snapSizes.length != 1 || _snapSizes.first != resting) {
      _snapSizes = <double>[resting];
    }
    return _snapSizes;
  }

  /// Whether this is the tab on screen.
  bool _active = false;

  /// Where the sheet starts when this card is built in the middle of a
  /// change to its tab: where the other tab's sheet is, so the two match
  /// from the first frame; `null` once the sheet has taken over.
  double? _arrivingExtent;

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
    if (!_active) return;
    ref.read(tabHandoverProvider.notifier).setSheetExtent(extent);
    // The rider's own drag of the list card is remembered for the session.
    if (_armed && !_settling && !_detail) {
      ref.read(libraryCardExtentProvider.notifier).set(extent);
    }
  }

  /// Moves the sheet to [target] as this screen's own doing, and arms the
  /// drag memory once it is there.
  Future<void> _settleTo(double target) async {
    _settling = true;
    try {
      await _sheet.animateTo(
        target,
        duration: tabSheetSettleDuration,
        curve: tabChromeSlideCurve,
      );
    } finally {
      _settling = false;
      _arm();
    }
  }

  /// From the next frame on, an extent change is the rider's.
  void _arm() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _active) _armed = true;
    });
  }

  /// The rows are known and the card is on screen for the first time since
  /// arriving: a long list opens the card to the top, unless the rider has
  /// left it somewhere this session.
  void _applyRows() {
    if (_rowsApplied || !_active || _detail || _rows == null) return;
    _rowsApplied = true;
    if (!_sheet.isAttached) return;
    final target = _preferredExtent;
    if (target - _sheet.size > 0.005) {
      unawaited(_settleTo(target));
    } else {
      _arm();
    }
  }

  /// This tab is coming on screen: the column glides from wherever it is
  /// to its place, which on this tab is the top, there being no chrome.
  void _takeOverControls() =>
      ref.read(mapControlsTopProvider).glide(to: defaultMapControlsTop);

  /// This tab has just come on screen: the sheet starts where the last
  /// tab's was and settles where this one's is; a sheet below its resting
  /// height (docked in the bar, say) rises to it, undocking the bar as it
  /// goes. A sheet already at rest, or pulled higher by the rider, stays.
  void _takeOverSheet() {
    if (!_sheet.isAttached) return;
    _armed = false;
    final current = _sheet.size;
    final from = ref.read(tabHandoverProvider).sheetExtent ?? current;
    if ((from - current).abs() >= 0.005) _sheet.jumpTo(from);
    // The rows have their say now, if they are known; else when they are.
    _rowsApplied = _rows != null;
    final target = math.max(current, _preferredExtent);
    if ((target - from).abs() < 0.005) {
      _arm();
      return;
    }
    unawaited(_settleTo(target));
  }

  /// Whether the sheet was last reported to the bar as docked in it.
  bool _docked = false;
  late final NavBarDocking _docking = ref.read(navBarDockingProvider.notifier);

  void _reportDocked(bool docked) {
    if (docked == _docked) return;
    _docked = docked;
    _docking.setDocked(libraryRoute, docked);
    // A card put away in the bar is not a height the rider chose for it:
    // on the next arrival it rises to the height it would open at anyway.
    if (docked) ref.read(libraryCardExtentProvider.notifier).clear();
  }

  /// The route button of the column, on a ride that followed a route.
  void _toggleRoute() {
    final shown = ref.read(showRideRouteProvider);
    unawaited(ref.read(showRideRouteProvider.notifier).set(!shown));
  }

  @override
  void initState() {
    super.initState();
    _tellCard();
    _active = ref.read(activeTabProvider) == libraryRoute;
    // Built in the middle of a change to this tab (its first visit, from
    // another tab): the listener in build sees no change, so the sheet is
    // started from here.
    final tabs = ref.read(activeTabProvider.notifier);
    if (!_active || tabs.previous == null) return;
    _arrivingExtent = ref.read(tabHandoverProvider).sheetExtent;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _takeOverSheet();
      setState(() => _arrivingExtent = null);
    });
  }

  @override
  void didUpdateWidget(LibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.routeId != widget.routeId) _tellCard();
  }

  /// Which route the card shows, for the Record tab's proposal; after the
  /// frame, since a build may not write a provider.
  void _tellCard() {
    final routeId = widget.routeId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(libraryCardProvider.notifier).show(routeId);
    });
  }

  @override
  void dispose() {
    _sheet.dispose();
    if (_docked) {
      // Deferred: the tree is locked while a widget goes, and the shell
      // would rebuild for this.
      final docking = _docking;
      scheduleMicrotask(() => docking.setDocked(libraryRoute, false));
    }
    super.dispose();
  }

  /// Whether the card shows a route or a ride rather than the list.
  bool get _detail => widget.routeId != null || widget.rideId != null;

  @override
  Widget build(BuildContext context) {
    final rideId = widget.rideId;
    // The tab on screen: the detail goes on the map, and the map's control
    // column and the sheet pick up where the last tab left them.
    final active = ref.watch(activeTabProvider) == libraryRoute;
    _active = active;
    ref.listen(activeTabProvider, (previous, next) {
      if (next == libraryRoute && previous != libraryRoute) {
        _active = true;
        _takeOverControls();
        _takeOverSheet();
      } else if (previous == libraryRoute && next != libraryRoute) {
        _active = false;
        _armed = false;
        _rowsApplied = false;
        // The next tab tells the column its own wants; this one tells it
        // again, from scratch, when it comes back.
        _chromeData = null;
        // The bar is square only while a docked strip is on top: the next
        // tab's sheet says so for itself from here on.
        _reportDocked(false);
      }
    });
    // The column on this tab: locate and zoom, and on a ride that followed
    // a route the button that shows or hides that route.
    final followed = rideId == null
        ? null
        : ref.watch(rideRouteProvider(rideId)).value;
    final routeShown = ref.watch(showRideRouteProvider);
    if (active) {
      _shareChrome(
        MapChromeData(
          showRoutingTiles: false,
          routeShown: followed != null && routeShown,
          onToggleRoute: followed == null ? null : _toggleRoute,
        ),
      );
    }
    final controlsTop = ref.read(mapControlsTopProvider);
    if (active && (controlsTop.target - defaultMapControlsTop).abs() >= 0.5) {
      // After the frame, since the shell listens to it and may not be told
      // during a build. The first tab of the launch takes its place without
      // a glide.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_active) return;
        if (controlsTop.everMoved) {
          controlsTop.glide(to: defaultMapControlsTop);
        } else {
          controlsTop.jump(defaultMapControlsTop);
        }
      });
    }

    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final topInset = MediaQuery.paddingOf(context).top;
    final screenHeight = MediaQuery.sizeOf(context).height;
    // Collapsed, only the handle strip is left above the floating navigation
    // bar, which the bottom padding already covers under `extendBody`: the
    // sheet is docked in the bar and the map is free.
    final collapsedSheetSize = screenHeight <= 0
        ? 0.1
        : ((bottomInset + sheetHandleDp) / screenHeight).clamp(0.01, 0.25);
    final dockedRange = screenHeight <= 0
        ? 0.15
        : sheetDockingRangeDp / screenHeight;
    // One resting height, shared with the Plan and Record tabs.
    final restingSheetSize = sheetRestingExtent(screenHeight);
    _restingSheetSize = restingSheetSize;
    // Pulled up, the card may reach nearly the top: the charts, the splits
    // and the cue sheet want the room. The status bar and a little air
    // stay clear.
    final maxSheetSize = screenHeight <= 0
        ? 0.9
        : ((screenHeight - topInset - 24) / screenHeight).clamp(0.6, 0.95);
    _maxSheetSize = maxSheetSize;
    // The list on screen, for the card's height on arrival: routes or
    // rides, whichever segment is up. Watched only for the list card.
    _rows = _detail
        ? null
        : switch (ref.watch(librarySectionProvider)) {
            LibrarySection.routes =>
              ref.watch(savedRoutesProvider).value?.length,
            LibrarySection.rides => ref.watch(ridesProvider).value?.length,
          };
    if (!_rowsApplied && _rows != null && active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyRows();
      });
    } else if (!_armed && active && _rows == null && _detail) {
      _arm();
    }
    // Fixed at the first build: a sheet whose initial size keeps changing
    // is reset to each new one until something has moved it, so the rows
    // and the rider move it through the controller instead.
    final initialSheetSize = _initialSheetSize ??=
        _arrivingExtent ?? _preferredExtent;

    // The split or climb picked on a ride card is named over the map, out
    // of the column's way, and clears with a tap.
    final highlight = rideId == null ? null : ref.watch(rideHighlightProvider);

    // The system back on a detail returns to the list, as the arrow does.
    return PopScope<void>(
      canPop: !_detail,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go(libraryRoute);
      },
      // Not a Scaffold: a Scaffold's material absorbs every touch, and a tap
      // that lands on nothing of this card has to fall through to the
      // shell's map. A transparent material is what the buttons need.
      child: Material(
        type: MaterialType.transparency,
        child: SizedBox.expand(
          child: Stack(
            children: [
              if (highlight != null)
                Positioned(
                  top: topInset + defaultMapControlsTop,
                  left: 12,
                  child: RideHighlightChip(
                    range: highlight,
                    onClear: () =>
                        ref.read(rideHighlightProvider.notifier).set(null),
                  ),
                ),
              DraggableScrollableSheet(
                controller: _sheet,
                initialChildSize: initialSheetSize,
                minChildSize: collapsedSheetSize,
                maxChildSize: maxSheetSize,
                snap: true,
                snapSizes: _snapSizesFor(restingSheetSize),
                builder: (context, scrollController) => DockingSheet(
                  controller: scrollController,
                  initialExtent: initialSheetSize,
                  collapsedExtent: collapsedSheetSize,
                  dockedRange: dockedRange,
                  docks: true,
                  dockedBottomInset: bottomInset,
                  onDocked: _reportDocked,
                  onExtent: _onSheetExtent,
                  handle: const SheetHandle(),
                  // A fresh scroll view per content, so a detail opened from
                  // a scrolled list starts at its top.
                  child: KeyedSubtree(
                    key: ValueKey<String>(
                      rideId != null
                          ? 'ride:$rideId'
                          : widget.routeId != null
                          ? 'route:${widget.routeId}'
                          : 'list',
                    ),
                    child: rideId != null
                        ? RideDetailScreen(rideId: rideId)
                        : widget.routeId != null
                        ? RouteDetailScreen(routeId: widget.routeId!)
                        : const _LibraryList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The card's root: the saved routes or the recorded rides, newest first,
/// under the title and the import actions.
///
/// Which of the two shows is the rider's choice and survives a restart; see
/// [librarySectionProvider].
class _LibraryList extends ConsumerWidget {
  const _LibraryList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final section = ref.watch(librarySectionProvider);
    return CustomScrollView(
      controller: SheetContentScroll.maybeOf(context),
      slivers: [
        SliverSheetHeader(
          title: l10n.tabLibrary,
          actions: const [ImportFromServiceButton(), ImportFileButton()],
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<LibrarySection>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: LibrarySection.routes,
                    icon: const Icon(Icons.route_rounded, size: 18),
                    label: Text(l10n.libraryRoutes),
                  ),
                  ButtonSegment(
                    value: LibrarySection.rides,
                    icon: const Icon(Icons.directions_bike_rounded, size: 18),
                    label: Text(l10n.libraryRides),
                  ),
                ],
                selected: {section},
                onSelectionChanged: (selection) => unawaited(
                  ref
                      .read(librarySectionProvider.notifier)
                      .select(selection.first),
                ),
              ),
            ),
          ),
        ),
        switch (section) {
          LibrarySection.routes => const _RoutesSection(),
          LibrarySection.rides => const _RidesSection(),
        },
        // The floating navigation bar sits over the list, so the last row
        // needs room to clear it.
        SliverToBoxAdapter(
          child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 24),
        ),
      ],
    );
  }
}

/// Every saved route, newest first, as a sliver.
class _RoutesSection extends ConsumerWidget {
  const _RoutesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final routes = ref.watch(savedRoutesProvider);
    return routes.when(
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
      data: (items) => items.isEmpty
          ? SliverFillRemaining(
              hasScrollBody: false,
              child: PlaceholderBody(
                icon: Icons.folder_outlined,
                message: '${l10n.libraryEmpty}\n${l10n.libraryEmptyDetail}',
              ),
            )
          : SliverPadding(
              padding: const EdgeInsets.only(top: 6),
              sliver: SliverList.builder(
                itemCount: items.length,
                itemBuilder: (context, i) => _RouteTile(route: items[i]),
              ),
            ),
    );
  }
}

/// Every recorded ride, newest first, as a sliver.
///
/// The list itself is [RidesList], which owns the rows, the swipe-to-delete
/// and the tap into the ride card; only the count above it is the
/// library's own.
class _RidesSection extends ConsumerWidget {
  const _RidesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final count = ref.watch(ridesProvider).value?.length ?? 0;
    return SliverMainAxisGroup(
      slivers: [
        if (count > 0)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: SectionCaption(l10n.libraryRidesCount(count)),
            ),
          ),
        const RidesList(),
      ],
    );
  }
}

/// The rounded square holding a tile's icon.
class _TileIcon extends StatelessWidget {
  const _TileIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, size: 22, color: theme.velorki.accent),
    );
  }
}

/// A saved route as one row: the route icon, the name and under it the
/// date, the distance and the ascent. The Library's row, and the one the
/// Record tab's route picker lists.
class RouteRow extends ConsumerWidget {
  /// Creates the row for [route].
  const RouteRow({
    required this.route,
    super.key,
    this.trailing,
    this.onTap,
    this.selected = false,
  });

  /// The route shown.
  final SavedRoute route;

  /// What sits at the right: the Library's menu, the picker's tick.
  final Widget? trailing;

  /// Called on a tap.
  final VoidCallback? onTap;

  /// Whether the row is the current choice, drawn in the accent.
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final units = ref.watch(unitSystemProvider);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      leading: const _TileIcon(Icons.route_rounded),
      selected: selected,
      title: Text(
        route.name,
        style: theme.textTheme.titleMedium,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        l10n.libraryRouteSubtitle(
          formatDate(l10n, route.createdAt),
          formatDistance(l10n, units, route.distanceM),
          formatHeight(l10n, units, route.ascentM),
        ),
        style: theme.textTheme.bodySmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: trailing,
      onTap: onTap,
    );
  }
}

class _RouteTile extends ConsumerWidget {
  const _RouteTile({required this.route});

  final SavedRoute route;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final repository = ref.read(routeRepositoryProvider);
    await repository.delete(route.id);
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.libraryRouteDeleted(route.name)),
        action: SnackBarAction(
          label: l10n.commonUndo,
          onPressed: () => unawaited(repository.restore(route)),
        ),
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final name = await showRenameRouteDialog(context, initialName: route.name);
    if (name == null) return;
    await ref.read(routeRepositoryProvider).rename(route.id, name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey(route.id),
      direction: DismissDirection.endToStart,
      background: ColoredBox(
        color: scheme.errorContainer,
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 24),
            child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
          ),
        ),
      ),
      onDismissed: (_) => unawaited(_delete(context, ref)),
      child: RouteRow(
        route: route,
        trailing: PopupMenuButton<_RouteAction>(
          onSelected: (action) => unawaited(switch (action) {
            _RouteAction.rename => _rename(context, ref),
            _RouteAction.delete => _delete(context, ref),
          }),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: _RouteAction.rename,
              child: Text(l10n.commonRename),
            ),
            PopupMenuItem(
              value: _RouteAction.delete,
              child: Text(l10n.commonDelete),
            ),
          ],
        ),
        onTap: () => context.go(routeDetailLocation(route.id)),
      ),
    );
  }
}

enum _RouteAction { rename, delete }

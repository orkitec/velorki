import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../features/shared/presentation/adaptive_docking_sheet.dart';
import '../features/shared/presentation/floating_bar.dart';
import '../features/shared/presentation/gesture_zone_guard.dart';
import '../features/shared/presentation/wide_panel.dart';
import '../features/import_export/data/track_decoder.dart';
import '../features/import_export/domain/imported_track.dart';
import '../features/import_export/presentation/import_preview_screen.dart';
import '../features/integrations/application/connections_controller.dart';
import '../features/integrations/application/strava_route_checks.dart';
import '../features/integrations/presentation/strava_consent_sheet.dart';
import '../features/library/presentation/library_screen.dart';
import '../features/map/presentation/map_chrome.dart';
import '../features/map/presentation/map_controls.dart';
import '../features/map/presentation/visible_map_padding.dart';
import '../features/map/application/locate_on_open.dart';
import '../features/map/presentation/shared_map_host.dart';
import '../features/navigation/application/navigation_controller.dart';
import '../features/planner/presentation/planner_screen.dart';
import '../features/recording/application/recording_controller.dart';
import '../features/recording/application/ride_notification_updater.dart';
import '../features/recording/presentation/recording_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/shared/application/active_tab.dart';
import '../features/shared/application/nav_bar_docking.dart';
import '../features/shared/application/shown_bar_style.dart';
import '../features/subscription/presentation/paywall_screen.dart';
import '../features/sync/application/cloud_sync_controller.dart';
import '../l10n/generated/app_localizations.dart';
import 'map_tab_page.dart';
import 'platform_features.dart';
import 'shell_layout.dart';
import 'tab_fade.dart';

part 'router.g.dart';

const String plannerRoute = '/plan';
const String recordingRoute = '/record';
const String libraryRoute = '/library';
const String settingsRoute = '/settings';

/// The import preview, outside the tab shell so it covers whichever tab is
/// showing when a file arrives. The [ImportCandidate] travels in `extra`.
const String importRoute = '/import';

/// The paywall, also outside the shell: every gated feature pushes it from
/// whichever tab the rider is on, and it comes back with a Back button.
const String paywallRoute = '/plus';

/// The saved route [id] as a card on the Library tab.
const String routeDetailPath = '$libraryRoute/route/:id';

/// The recorded ride [id] as a card on the Library tab.
const String rideDetailPath = '$libraryRoute/ride/:id';

/// The four tabs' root routes, in the bar's order.
const List<String> tabRoutes = [
  plannerRoute,
  recordingRoute,
  libraryRoute,
  settingsRoute,
];

/// The tabs over the shell's one map, Plan, Record and Library, by index in
/// the bar.
const Set<int> mapTabs = {0, 1, 2};

/// The location of the card for the saved route [id].
String routeDetailLocation(String id) => '$libraryRoute/route/$id';

/// The location of the card for the recorded ride [id].
String rideDetailLocation(String id) => '$libraryRoute/ride/$id';

/// The one page of the Library branch, whatever the location: the card
/// keeps its element, and so its sheet, across the list and the details.
const ValueKey<String> _libraryCardKey = ValueKey<String>('library-card');

/// The Library branch's page for [child]: the same key at every location,
/// so the navigator updates the card in place rather than swapping it.
MapTabPage<void> _libraryPage(GoRouterState state, Widget child) =>
    MapTabPage<void>(
      key: _libraryCardKey,
      name: state.name ?? state.path,
      child: child,
    );

@Riverpod(keepAlive: true)
GoRouter router(Ref ref) =>
    createRouter(recording: ref.read(platformFeaturesProvider).recording);

/// Built by a function rather than a top-level final so widget tests can start
/// from any tab with a fresh navigator state.
///
/// Without [recording] the Record tab cannot be reached, not even by a link.
GoRouter createRouter({
  String initialLocation = plannerRoute,
  bool recording = true,
}) {
  // Which tab has a page pushed over it, for the map beside the column.
  final pages = TabPages();
  return GoRouter(
    navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'root'),
    initialLocation: initialLocation,
    // Links are read by app_links (OAuth returns, shared routes, files), and
    // the platforms are told not to hand them to the router. Should one get
    // here all the same, the rider stays where they were rather than on an
    // error page with no way back.
    onException: (context, state, router) {},
    redirect: recording
        ? null
        : (context, state) =>
              state.matchedLocation == recordingRoute ? plannerRoute : null,
    routes: [
      GoRoute(
        path: paywallRoute,
        pageBuilder: (context, state) => ColumnPage<void>(
          key: state.pageKey,
          name: state.name ?? state.path,
          child: const PaywallScreen(),
        ),
      ),
      GoRoute(
        path: importRoute,
        // A decoded file, a refused one with its reason, or nothing at all
        // (a stale deep link).
        pageBuilder: (context, state) => ColumnPage<void>(
          key: state.pageKey,
          name: state.name ?? state.path,
          child: switch (state.extra) {
            final ImportCandidate candidate => ImportPreviewScreen(
              candidate: candidate,
            ),
            final ImportException rejection => ImportPreviewScreen(
              candidate: null,
              rejection: rejection,
            ),
            _ => const ImportPreviewScreen(candidate: null),
          },
        ),
      ),
      StatefulShellRoute(
        builder: (context, state, shell) =>
            HomeShell(shell: shell, pages: pages),
        // Every tab stays alive; a change of tab is a short cross-fade.
        navigatorContainerBuilder: (context, shell, children) => TabFadeStack(
          index: shell.currentIndex,
          // Plan and Record are chrome over the shell's map: their sheets
          // cross-fade over it while Plan's search field and chips slide
          // and the control column glides across.
          chromeTabs: mapTabs,
          // In a wide window every tab is in a column on the left, laid
          // out as on a phone held upright, with the map beside it.
          children: [
            for (final child in children) WidePanelColumn(child: child),
          ],
        ),
        branches: [
          StatefulShellBranch(
            observers: [pages.observer()],
            routes: [
              GoRoute(
                path: plannerRoute,
                // The two map tabs are pages without a barrier, so the
                // map under the branch stack gets the touches they do not.
                pageBuilder: (context, state) => MapTabPage<void>(
                  key: state.pageKey,
                  name: state.name ?? state.path,
                  restorationId: state.pageKey.value,
                  child: const PlannerScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            observers: [pages.observer()],
            routes: [
              GoRoute(
                path: recordingRoute,
                pageBuilder: (context, state) => MapTabPage<void>(
                  key: state.pageKey,
                  name: state.name ?? state.path,
                  restorationId: state.pageKey.value,
                  child: const RecordingScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            observers: [pages.observer()],
            // Three locations, one card: the list, a route, a ride. They
            // are siblings rather than a stack, so only one card is ever
            // over the map, and the card's own back arrow goes to the list.
            routes: [
              GoRoute(
                path: libraryRoute,
                pageBuilder: (context, state) =>
                    _libraryPage(state, const LibraryScreen()),
              ),
              GoRoute(
                path: routeDetailPath,
                pageBuilder: (context, state) => _libraryPage(
                  state,
                  LibraryScreen(routeId: state.pathParameters['id'] ?? ''),
                ),
              ),
              GoRoute(
                path: rideDetailPath,
                pageBuilder: (context, state) => _libraryPage(
                  state,
                  LibraryScreen(rideId: state.pathParameters['id'] ?? ''),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            observers: [pages.observer()],
            routes: [
              GoRoute(
                path: settingsRoute,
                // In its column in a wide window, as every full page.
                pageBuilder: (context, state) => ColumnPage<void>(
                  key: state.pageKey,
                  name: state.name ?? state.path,
                  child: const SettingsScreen(),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

/// Scaffold around the four tabs; each branch keeps its own navigation stack.
class HomeShell extends ConsumerWidget {
  const HomeShell({required this.shell, required this.pages, super.key});

  final StatefulNavigationShell shell;

  /// Which tab has a page pushed over it, branch by branch.
  final TabPages pages;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // Turn-by-turn is kept alive for the whole session, and a keep-alive
    // provider only exists once something has read it. Listening rather than
    // watching: the shell has nothing to redraw when a turn comes closer.
    final features = ref.watch(platformFeaturesProvider);
    if (features.recording) {
      ref.listen(navigationControllerProvider, (previous, next) {});
    }
    // The same for what a recording ride puts on the lock screen: the Android
    // notification's turn line and the iOS live activity.
    if (features.recording) {
      ref.listen(rideNotificationUpdaterProvider, (previous, next) {});
    }
    // Strava refused Velorki's access and the Strava data went: the rider
    // is told in writing, wherever they are.
    // Routes from Strava the checks deleted: said once, in a snack bar.
    ref.listen(stravaRoutesRemovedNoticeProvider, (previous, next) {
      if (next == 0) return;
      ref.read(stravaRoutesRemovedNoticeProvider.notifier).dismiss();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.stravaRoutesRemoved(next))));
    });
    // A rider whose library was there before iCloud sync came is told
    // once that it syncs now, and where to switch it off.
    ref.listen(cloudSyncNoticeProvider, (previous, next) {
      if (!next) return;
      ref.read(cloudSyncNoticeProvider.notifier).dismiss();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.cloudSyncNotice),
          duration: const Duration(seconds: 10),
          action: SnackBarAction(
            label: l10n.cloudSyncNoticeAction,
            onPressed: () {
              ref.read(activeTabProvider.notifier).show(settingsRoute);
              context.go(settingsRoute);
            },
          ),
        ),
      );
    });
    ref.listen(stravaAccessLostNoticeProvider, (previous, next) {
      if (!next) return;
      ref.read(stravaAccessLostNoticeProvider.notifier).dismiss();
      unawaited(
        showStravaDataDeletedDialog(
          context,
          title: l10n.stravaAccessLostTitle,
          body: l10n.stravaAccessLostBody,
        ),
      );
    });
    // While a ride is being recorded on the Record tab the bar only takes
    // space from the figures; it comes back when the ride ends or the
    // rider leaves the tab through the system back gesture.
    final recording = ref.watch(
      recordingControllerProvider.select((s) => s.isRecording),
    );
    // Nor while the keyboard is up: a bar floating over the keyboard's edge
    // takes the room the search results need. This context sits above the
    // scaffold, so it still sees the inset the scaffold resizes for.
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;
    final hideRail = recording && shell.currentIndex == 1;
    final hideBar = hideRail || keyboardUp;
    // A sheet pulled all the way down docks in the bar: the bar then squares
    // its top corners so the handle strip above it and the tabs read as one
    // pill. Only the showing tab's sheet counts.
    final docked = ref.watch(
      navBarDockingProvider.select(
        (docking) => docking.contains(tabRoutes[shell.currentIndex]),
      ),
    );
    // The tab on screen, for the screens' own animations. The bar's tap
    // writes it before the branch changes; this is for the other ways a
    // branch changes (the system back gesture), after the frame, since a
    // build may not write a provider.
    final route = tabRoutes[shell.currentIndex];
    if (ref.read(activeTabProvider) != route) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) ref.read(activeTabProvider.notifier).show(route);
      });
    }
    // One control column over the tabs on the map: it glides between the
    // tabs' chrome and grows or shrinks for the buttons one tab has and
    // the other has not, instead of being swapped with the tab. Only while
    // the tab shows its map screen, not a page pushed over it; the
    // Library's card is its screen at every one of its locations.
    final matched = GoRouter.of(context).state.matchedLocation;
    final atTabRoot =
        matched == route ||
        (route == libraryRoute && matched.startsWith('$libraryRoute/'));
    final chrome = ref.watch(activeMapChromeProvider);
    // What the move to the rider on opening needs of the shell, read when
    // it happens: where the visible map is, and whether the Library shows
    // a card.
    final locate = ref.read(locateOnOpenProvider);
    // Read after a fix has been awaited: a shell that has gone since has no
    // context to measure.
    locate.visiblePadding = () => context.mounted
        ? visibleMapPadding(
            context,
            chromeTop: ref.read(mapControlsTopProvider).target,
            sheetExtent: ref.read(tabHandoverProvider).sheetExtent,
            // This context is above the layout the shell hands down.
            layout: ShellLayout.resolveAt(context, ref.read(railSideProvider)),
          )
        : EdgeInsets.zero;
    locate.cardOpen = () =>
        context.mounted &&
        GoRouter.of(context).state.matchedLocation.startsWith('$libraryRoute/');
    final showColumn =
        mapTabs.contains(shell.currentIndex) &&
        atTabRoot &&
        (chrome?.visible ?? true);
    final columnGlide = ref.watch(mapControlsTopProvider);
    // The tabs the bar offers, by branch: no Record where nothing records.
    final branches = <int>[0, if (features.recording) 1, 2, 3];
    // The layout the screen implies, handed down to the tabs: a bar at the
    // bottom upright, a rail at the side on a phone turned sideways.
    FloatingNavigationBar navigation(RailSide? railSide) =>
        FloatingNavigationBar(
          railSide: railSide,
          docked: docked,
          selectedIndex: math.max(0, branches.indexOf(shell.currentIndex)),
          onDestinationSelected: (position) {
            final index = branches[position];
            // Told first, so the screens arrange themselves before the
            // branch shows.
            ref.read(activeTabProvider.notifier).show(tabRoutes[index]);
            shell.goBranch(
              index,
              // Tapping the active tab pops back to that branch's root.
              initialLocation: index == shell.currentIndex,
            );
          },
          destinations: [
            for (final branch in branches)
              switch (branch) {
                0 => NavigationDestination(
                  icon: const Icon(Icons.route_outlined),
                  selectedIcon: const Icon(Icons.route),
                  label: l10n.tabPlan,
                ),
                1 => NavigationDestination(
                  icon: const Icon(Icons.radio_button_unchecked),
                  selectedIcon: const Icon(Icons.radio_button_checked),
                  label: l10n.tabRecord,
                ),
                2 => NavigationDestination(
                  icon: const Icon(Icons.bookmarks_outlined),
                  selectedIcon: const Icon(Icons.bookmarks),
                  label: l10n.tabLibrary,
                ),
                _ => NavigationDestination(
                  icon: const Icon(Icons.tune_outlined),
                  selectedIcon: const Icon(Icons.tune),
                  label: l10n.tabSettings,
                ),
              },
          ],
        );
    Widget controls(ShellLayout layout) => MapChromeInsets(
      showRoutingTiles: chrome?.showRoutingTiles ?? true,
      following: chrome?.following ?? false,
      headingUp: chrome?.headingUp ?? false,
      bearingDeg: chrome?.bearingDeg ?? 0,
      onLocate: chrome?.onLocate,
      onCompass: chrome?.onCompass,
      routeShown: chrome?.routeShown ?? false,
      onToggleRoute: chrome?.onToggleRoute,
      stopsOffer: chrome?.stopsOffer ?? MapStopsOffer.none,
      // Read at the tap: the sheet moves without a rebuild of the column.
      // Read after the fix is awaited, so the shell may be gone by then.
      visiblePadding: () => context.mounted
          ? visibleMapPadding(
              context,
              chromeTop: columnGlide.target,
              sheetExtent: ref.read(tabHandoverProvider).sheetExtent,
              layout: layout,
            )
          : EdgeInsets.zero,
      child: MapControls(
        controller: ref.watch(sharedMapControllerProvider),
        axis: layout.sideRail ? Axis.horizontal : Axis.vertical,
      ),
    );
    // How see-through the bar, the rail, the figures bar and a sheet
    // docked into them are, and the chrome over the map; solid while
    // power is being saved.
    final barStyle = ref.watch(shownBarStyleProvider);
    return FloatingBarStyle(
      style: barStyle,
      child: ShellLayoutHost(
        builder: (context, layout) {
          // A turn of the phone fades the map controls back in; the sheets do
          // the same with their content. The bar, the rail and the sheets
          // themselves stay in view, and the map is never faded: a native
          // view under a fade shows black.
          final fade = ShellLayoutHost.turnFadeOf(context);
          // Where the system's swipe up from the bottom edge starts, read
          // above the scaffold, which takes the bottom padding off its body.
          final gestureZone = systemGestureZoneHeight(
            MediaQuery.of(context),
            defaultTargetPlatform,
          );
          // In a wide window a snack bar shows over the column's bar, as
          // wide as the column. The same theme elsewhere, so a window
          // resized across the line keeps the shell's state.
          final theme = Theme.of(context);
          final column = wideColumnOf(context);
          // In a wide window the map's controls stand right beside the
          // column, at its outer edge, as a phone has them at its right
          // edge: on the column's left while it stands on the right.
          final controlsLeft =
              layout.widePanel &&
              wideColumnSideOf(context) == WideColumnSide.right;
          final media = MediaQuery.of(context);
          final controlsLeftEdge = !layout.widePanel
              ? 0.0
              : controlsLeft
              ? 0.0
              : column.right - media.padding.left;
          final controlsRightEdge = !layout.widePanel
              ? 0.0
              : controlsLeft
              ? media.size.width - column.left - media.padding.right
              : 0.0;
          final snackBars = layout.widePanel
              ? theme.copyWith(
                  snackBarTheme: theme.snackBarTheme.copyWith(
                    insetPadding: EdgeInsets.fromLTRB(
                      column.left + 15,
                      5,
                      MediaQuery.sizeOf(context).width - column.right + 15,
                      10,
                    ),
                  ),
                )
              : theme;
          return Theme(
            data: snackBars,
            child: Scaffold(
              // The bar floats over the content; screens read the bottom padding
              // from MediaQuery to keep their last rows above it.
              extendBody: true,
              // The keyboard inset is left to each tab's own scaffold: the map
              // screens keep their full height under the keyboard, the settings
              // screen resizes as usual.
              resizeToAvoidBottomInset: false,
              // A touch that starts in that zone moves neither the sheet nor the
              // map: iOS hands the start of its swipe to the app before taking
              // it over, and the sheet flung itself open. The bar upright is
              // outside the body and above the zone; the rail lets it through.
              body: GestureZoneGuard(
                zone: gestureZone,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // The one map under the Plan, Record and Library tabs, which draw
                    // on it and are transparent over it. Never hidden and never moved
                    // in the stack: the platform view would start over and show black.
                    // The settings tab is an opaque page over it.
                    //
                    // Its bottom inset is pinned to nothing: the scaffold takes the
                    // bottom view padding off its body only while it has a bar, so
                    // with the bar hidden for a ride the map's credit and (i) would
                    // climb by the home indicator's height into the figures bar.
                    MediaQuery.removeViewPadding(
                      context: context,
                      removeBottom: true,
                      // In a wide window the map stays in view beside a
                      // page in the column (the settings, a page pushed
                      // over a tab) but, as on a phone, under it: it takes
                      // no touch while such a page is up.
                      child: ValueListenableBuilder<int>(
                        valueListenable: pages,
                        child: const SharedMapHost(
                          key: ValueKey<String>('shared-map'),
                        ),
                        builder: (context, _, map) => IgnorePointer(
                          ignoring:
                              layout.widePanel &&
                              (!mapTabs.contains(shell.currentIndex) ||
                                  !atTabRoot ||
                                  pages.covers(shell.currentIndex)),
                          child: map,
                        ),
                      ),
                    ),
                    if (showColumn)
                      Positioned.fill(
                        child: FadeTransition(
                          opacity: fade,
                          child: layout.sideRail
                              ? _sidewaysControlsRow(
                                  context,
                                  layout,
                                  onWidth: ref
                                      .read(
                                        mapControlsRowWidthProvider.notifier,
                                      )
                                      .set,
                                  child: controls(layout),
                                )
                              : SafeArea(
                                  child: AnimatedBuilder(
                                    animation: columnGlide.animation,
                                    builder: (context, child) => Padding(
                                      padding: EdgeInsets.only(
                                        // In a wide window the tabs' chrome
                                        // is in their column, not over the
                                        // controls.
                                        top: layout.widePanel
                                            ? defaultMapControlsTop
                                            : columnGlide.animation.value,
                                        left: controlsLeftEdge + 12,
                                        right: controlsRightEdge + 12,
                                      ),
                                      child: Align(
                                        alignment:
                                            layout.widePanel != controlsLeft
                                            ? Alignment.topLeft
                                            : Alignment.topRight,
                                        child: child,
                                      ),
                                    ),
                                    child: controls(layout),
                                  ),
                                ),
                        ),
                      ),
                    // Over the column: a sheet or card pulled up covers it, and a
                    // touch beside a tab's chrome falls through to it and to the map,
                    // since the map tabs' routes put no barrier under their content.
                    _besideRail(
                      context,
                      layout,
                      railShown: !hideRail,
                      opaque:
                          !(mapTabs.contains(shell.currentIndex) && atTabRoot),
                      child: shell,
                    ),
                    if (layout.sideRail && !hideRail)
                      Positioned.fill(
                        child: GestureZonePassThrough(
                          child: navigation(layout.side),
                        ),
                      ),
                  ],
                ),
              ),
              // Upright the bar floats at the bottom, hidden under the keyboard;
              // turned sideways it is a rail at the side, which the keyboard
              // leaves alone.
              bottomNavigationBar: layout.sideRail || hideBar
                  ? null
                  : layout.widePanel
                  // In a wide window the bar is at the bottom of the tabs'
                  // column, as wide as it, as on a phone at the bottom of the
                  // screen.
                  ? Padding(
                      padding: EdgeInsets.only(left: column.left),
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        heightFactor: 1,
                        child: SizedBox(
                          width: column.width,
                          child: MediaQuery.removeViewPadding(
                            context: context,
                            removeLeft: true,
                            removeRight: true,
                            child: navigation(null),
                          ),
                        ),
                      ),
                    )
                  : navigation(null),
            ),
          );
        },
      ),
    );
  }
}

/// The map's controls on a phone turned sideways: a row at the top of the
/// map, beside the docked sheet (or the figures bar that takes the rail's
/// place during a ride), centred on the Plan tab's search, which runs on
/// from it to the far edge. At rest the sheet lies over the row, which the
/// rider pulls the sheet in to reach. [onWidth] hears the row's width after
/// each layout that changes it, for the search to leave it that room.
Widget _sidewaysControlsRow(
  BuildContext context,
  ShellLayout layout, {
  required ValueChanged<double> onWidth,
  required Widget child,
}) {
  final media = MediaQuery.of(context);
  final start = sidewaysTopRowStart(media, layout);
  final left = layout.side == RailSide.left;
  return Padding(
    padding: EdgeInsets.only(
      top: media.viewPadding.top + sidewaysTopRowTop,
      left: left ? start : 0,
      right: left ? 0 : start,
    ),
    child: Align(
      alignment: left ? Alignment.topLeft : Alignment.topRight,
      child: SizedBox(
        height: sidewaysTopRowHeight,
        child: Center(
          widthFactor: 1,
          child: _WidthReporter(onWidth: onWidth, child: child),
        ),
      ),
    ),
  );
}

/// Tells [onWidth] the width [child] was laid out at, after the frame,
/// whenever it changed.
class _WidthReporter extends SingleChildRenderObjectWidget {
  const _WidthReporter({required this.onWidth, required super.child});

  final ValueChanged<double> onWidth;

  @override
  _RenderWidthReporter createRenderObject(BuildContext context) =>
      _RenderWidthReporter(onWidth);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderWidthReporter renderObject,
  ) => renderObject.onWidth = onWidth;
}

class _RenderWidthReporter extends RenderProxyBox {
  _RenderWidthReporter(this.onWidth);

  ValueChanged<double> onWidth;
  double? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final width = size.width;
    if (width == _reported) return;
    _reported = width;
    // After the frame: a layout may not change what a build depends on.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached && _reported == width) onWidth(width);
    });
  }
}

/// The tabs' share of a sideways screen with the rail on it.
///
/// A map tab runs under the rail as it runs under the bar upright, its
/// sheet coming out from the screen's edge behind the rail: the rail is
/// padding to it, the way the scaffold makes the bar padding at the bottom.
/// A page that is not a map ([opaque]: the settings, a page pushed over a
/// tab) lies beside the rail instead, and keeps clear of the camera
/// island's side too, which an upright list never had to; the island's
/// strip takes the page's colour.
Widget _besideRail(
  BuildContext context,
  ShellLayout layout, {
  required bool railShown,
  required Widget child,
  bool opaque = false,
}) {
  if (!layout.sideRail) return child;
  final media = MediaQuery.of(context);
  final viewPadding = media.viewPadding;
  final left = layout.side == RailSide.left;
  final inset = railShown
      ? floatingRailInset(viewPadding, layout.side)
      : (left ? viewPadding.left : viewPadding.right);
  if (!opaque) {
    final padding = left
        ? media.padding.copyWith(left: inset)
        : media.padding.copyWith(right: inset);
    return MediaQuery(
      data: media.copyWith(padding: padding),
      child: child,
    );
  }
  final island = left
      ? EdgeInsets.only(right: viewPadding.right)
      : EdgeInsets.only(left: viewPadding.left);
  return Padding(
    padding: left
        ? EdgeInsets.only(left: inset)
        : EdgeInsets.only(right: inset),
    // A coloured box takes every touch, transparent or not: only here,
    // never over a map tab, whose touches beside its chrome are the map's.
    child: ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Padding(
        padding: island,
        child: MediaQuery.removePadding(
          context: context,
          removeLeft: true,
          removeRight: true,
          child: child,
        ),
      ),
    ),
  );
}

/// A [NavigationBar] in a floating glass pill, blurred over the map.
///
/// The Material bar underneath keeps the semantics, the ripples and the
/// label behaviour; only its chrome is replaced. [docked] is the look under
/// a sheet folded into the bar: square top corners, no top edge and no
/// shadow, so the sheet's handle strip and the tabs are one pill.
///
/// With a [railSide] it is a [NavigationRail] in the same glass, standing on
/// that side of a phone turned sideways, the icons and labels upright.
class FloatingNavigationBar extends StatelessWidget {
  const FloatingNavigationBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    this.docked = false,
    this.railSide,
    super.key,
  });

  /// The side the rail stands on; `null` for the bar at the bottom.
  final RailSide? railSide;

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestination> destinations;

  /// Whether a sheet rests on the bar's top edge.
  final bool docked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rail = railSide;
    if (rail != null) {
      // The bar itself, turned a quarter with its docked look and all, and
      // the destinations inside turned back upright, one over the next.
      final turns = shellQuarterTurns(ShellLayout(sideRail: true, side: rail));
      return QuarterTurnedFrame(
        quarterTurns: turns,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: FloatingBarShell(
            docked: docked,
            // The bar's own height, as the navigation bar upright has it:
            // turned back, the rail inside would take all the room it got.
            child: SizedBox(
              height: floatingBarHeight,
              child: QuarterTurnedFrame(
                quarterTurns: 4 - turns,
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  removeBottom: true,
                  removeLeft: true,
                  removeRight: true,
                  child: NavigationRail(
                    minWidth: floatingRailWidth,
                    backgroundColor: Colors.transparent,
                    indicatorColor: theme.colorScheme.primary,
                    indicatorShape: const StadiumBorder(),
                    labelType: NavigationRailLabelType.all,
                    groupAlignment: 0,
                    selectedIndex: selectedIndex,
                    onDestinationSelected: onDestinationSelected,
                    destinations: [
                      for (final d in destinations)
                        NavigationRailDestination(
                          icon: d.icon,
                          selectedIcon: IconTheme.merge(
                            data: IconThemeData(
                              color: theme.colorScheme.onPrimary,
                            ),
                            child: d.selectedIcon ?? d.icon,
                          ),
                          // One line, shrunk to the rail's width where a
                          // language's word is longer than it.
                          label: SizedBox(
                            width: floatingRailWidth - 12,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(d.label, maxLines: 1),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return FloatingBarShell(
      docked: docked,
      child: MediaQuery.removePadding(
        context: context,
        removeBottom: true,
        child: NavigationBar(
          height: floatingBarHeight,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          indicatorColor: theme.colorScheme.primary,
          indicatorShape: const StadiumBorder(),
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          destinations: [
            for (final d in destinations)
              NavigationDestination(
                icon: d.icon,
                selectedIcon: IconTheme.merge(
                  data: IconThemeData(color: theme.colorScheme.onPrimary),
                  child: d.selectedIcon ?? d.icon,
                ),
                label: d.label,
                tooltip: d.tooltip,
              ),
          ],
        ),
      ),
    );
  }
}

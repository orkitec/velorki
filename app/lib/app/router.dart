import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../features/shared/presentation/docking_sheet.dart';
import '../features/import_export/data/track_decoder.dart';
import '../features/import_export/domain/imported_track.dart';
import '../features/import_export/presentation/import_preview_screen.dart';
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
import '../features/subscription/presentation/paywall_screen.dart';
import '../l10n/generated/app_localizations.dart';
import 'map_tab_page.dart';
import 'tab_fade.dart';
import 'theme.dart';

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
GoRouter router(Ref ref) => createRouter();

/// Built by a function rather than a top-level final so widget tests can start
/// from any tab with a fresh navigator state.
GoRouter createRouter({String initialLocation = plannerRoute}) {
  return GoRouter(
    navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'root'),
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: paywallRoute,
        builder: (context, state) => const PaywallScreen(),
      ),
      GoRoute(
        path: importRoute,
        // A decoded file, a refused one with its reason, or nothing at all
        // (a stale deep link).
        builder: (context, state) => switch (state.extra) {
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
      StatefulShellRoute(
        builder: (context, state, shell) => HomeShell(shell: shell),
        // Every tab stays alive; a change of tab is a short cross-fade.
        navigatorContainerBuilder: (context, shell, children) => TabFadeStack(
          index: shell.currentIndex,
          // Plan and Record are chrome over the shell's map: their sheets
          // cross-fade over it while Plan's search field and chips slide
          // and the control column glides across.
          chromeTabs: mapTabs,
          children: children,
        ),
        branches: [
          StatefulShellBranch(
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
            routes: [
              GoRoute(
                path: settingsRoute,
                builder: (context, state) => const SettingsScreen(),
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
  const HomeShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // Turn-by-turn is kept alive for the whole session, and a keep-alive
    // provider only exists once something has read it. Listening rather than
    // watching: the shell has nothing to redraw when a turn comes closer.
    ref.listen(navigationControllerProvider, (previous, next) {});
    // The same for what a recording ride puts on the lock screen: the Android
    // notification's turn line and the iOS live activity.
    ref.listen(rideNotificationUpdaterProvider, (previous, next) {});
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
    final hideBar = (recording && shell.currentIndex == 1) || keyboardUp;
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
    locate.visiblePadding = () => visibleMapPadding(
      context,
      chromeTop: ref.read(mapControlsTopProvider).target,
      sheetExtent: ref.read(tabHandoverProvider).sheetExtent,
    );
    locate.cardOpen = () =>
        context.mounted &&
        GoRouter.of(context).state.matchedLocation.startsWith('$libraryRoute/');
    final showColumn =
        mapTabs.contains(shell.currentIndex) &&
        atTabRoot &&
        (chrome?.visible ?? true);
    final columnGlide = ref.watch(mapControlsTopProvider);
    return Scaffold(
      // The bar floats over the content; screens read the bottom padding
      // from MediaQuery to keep their last rows above it.
      extendBody: true,
      // The keyboard inset is left to each tab's own scaffold: the map
      // screens keep their full height under the keyboard, the settings
      // screen resizes as usual.
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // The one map under the Plan, Record and Library tabs, which draw
          // on it and are transparent over it. Never hidden and never moved
          // in the stack: the platform view would start over and show black.
          // The settings tab is an opaque page over it.
          const SharedMapHost(key: ValueKey<String>('shared-map')),
          if (showColumn)
            Positioned.fill(
              child: SafeArea(
                child: AnimatedBuilder(
                  animation: columnGlide.animation,
                  builder: (context, child) => Padding(
                    padding: EdgeInsets.only(
                      top: columnGlide.animation.value,
                      right: 12,
                    ),
                    child: child,
                  ),
                  child: Align(
                    alignment: Alignment.topRight,
                    child: MapChromeInsets(
                      showRoutingTiles: chrome?.showRoutingTiles ?? true,
                      following: chrome?.following ?? false,
                      headingUp: chrome?.headingUp ?? false,
                      bearingDeg: chrome?.bearingDeg ?? 0,
                      onLocate: chrome?.onLocate,
                      onCompass: chrome?.onCompass,
                      routeShown: chrome?.routeShown ?? false,
                      onToggleRoute: chrome?.onToggleRoute,
                      // Read at the tap: the sheet moves without a rebuild
                      // of the column.
                      visiblePadding: () => visibleMapPadding(
                        context,
                        chromeTop: columnGlide.target,
                        sheetExtent: ref.read(tabHandoverProvider).sheetExtent,
                      ),
                      child: MapControls(
                        controller: ref.watch(sharedMapControllerProvider),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          // Over the column: a sheet or card pulled up covers it, and a
          // touch beside a tab's chrome falls through to it and to the map,
          // since the map tabs' routes put no barrier under their content.
          shell,
        ],
      ),
      bottomNavigationBar: hideBar
          ? null
          : FloatingNavigationBar(
              docked: docked,
              selectedIndex: shell.currentIndex,
              onDestinationSelected: (index) {
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
                NavigationDestination(
                  icon: const Icon(Icons.route_outlined),
                  selectedIcon: const Icon(Icons.route),
                  label: l10n.tabPlan,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.radio_button_unchecked),
                  selectedIcon: const Icon(Icons.radio_button_checked),
                  label: l10n.tabRecord,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.bookmarks_outlined),
                  selectedIcon: const Icon(Icons.bookmarks),
                  label: l10n.tabLibrary,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.tune_outlined),
                  selectedIcon: const Icon(Icons.tune),
                  label: l10n.tabSettings,
                ),
              ],
            ),
    );
  }
}

/// A [NavigationBar] in a floating glass pill, blurred over the map.
///
/// The Material bar underneath keeps the semantics, the ripples and the
/// label behaviour; only its chrome is replaced. [docked] is the look under
/// a sheet folded into the bar: square top corners, no top edge and no
/// shadow, so the sheet's handle strip and the tabs are one pill.
class FloatingNavigationBar extends StatelessWidget {
  const FloatingNavigationBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    this.docked = false,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestination> destinations;

  /// Whether a sheet rests on the bar's top edge.
  final bool docked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.velorki;
    // Docked, the bar paints its own shape — square top, round bottom —
    // and clips nothing: over the map's native view a rounded clip with
    // straight top corners is not applied, and the glass came out square at
    // the bottom with its round border drawn inside. A rect clip and a
    // painted shape need no such favour from the compositor.
    final radius = docked ? BorderRadius.zero : BorderRadius.circular(30);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        MediaQuery.viewPaddingOf(context).bottom + 12,
      ),
      // Docked there is no shadow to keep off the sheet, but the clip stays
      // in the tree either way so the bar keeps its state.
      child: ClipRect(
        clipper: _BarShadowClipper(cutTop: docked),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            // No shadow at all while docked: beside the seam it would show
            // as dark wedges under the sheet's strip.
            boxShadow: docked
                ? const []
                : const [
                    BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 24,
                      offset: Offset(0, 8),
                    ),
                  ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: BackdropFilter(
              // Over the map's native view the blur is applied by the
              // engine to a rectangle, not to this rounded clip; at rest the
              // shadow hides its square corners, docked there is no shadow
              // and they showed as half circles beside the round ones. So
              // docked, the glass colour alone.
              enabled: !docked,
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                decoration: docked
                    ? _BarBorder(
                        color: colors.glassBorder,
                        docked: true,
                        fill: colors.glass,
                      )
                    : BoxDecoration(color: colors.glass),
                // Painted rather than a Border: a rounded border cannot
                // leave one side out, and docked the top edge is the seam.
                foregroundDecoration: docked
                    ? null
                    : _BarBorder(color: colors.glassBorder, docked: false),
                child: MediaQuery.removePadding(
                  context: context,
                  removeBottom: true,
                  child: NavigationBar(
                    height: 72,
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
                            data: IconThemeData(
                              color: theme.colorScheme.onPrimary,
                            ),
                            child: d.selectedIcon ?? d.icon,
                          ),
                          label: d.label,
                          tooltip: d.tooltip,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The hairline around the bar's pill; docked, it is open at the top, where
/// the sheet's strip continues it.
class _BarBorder extends Decoration {
  const _BarBorder({required this.color, required this.docked, this.fill});

  /// The glass to fill the docked shape with, under the hairline; `null`
  /// paints the hairline alone.
  final Color? fill;

  final Color color;
  final bool docked;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _BarBorderPainter(this);
}

class _BarBorderPainter extends BoxPainter {
  _BarBorderPainter(this.border);

  final _BarBorder border;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size!;
    final paint = Paint()
      ..color = border.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    // Half a pixel in, so the stroke lies inside the clip.
    final rect = (offset & size).deflate(0.5);
    if (!border.docked) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(29.5)),
        paint,
      );
      return;
    }
    final fill = border.fill;
    if (fill != null) {
      final box = offset & size;
      final shape = Path()
        ..moveTo(box.left, box.top)
        ..lineTo(box.right, box.top)
        ..lineTo(box.right, box.bottom - dockedPillRadius)
        // Round the right way: this path runs down the right side and back
        // along the bottom, so its convex corners are clockwise arcs on a
        // screen whose y points down (the border below runs the other way).
        ..arcToPoint(
          Offset(box.right - dockedPillRadius, box.bottom),
          radius: const Radius.circular(dockedPillRadius),
        )
        ..lineTo(box.left + dockedPillRadius, box.bottom)
        ..arcToPoint(
          Offset(box.left, box.bottom - dockedPillRadius),
          radius: const Radius.circular(dockedPillRadius),
        )
        ..close();
      canvas.drawPath(shape, Paint()..color = fill);
    }
    const r = Radius.circular(dockedPillRadius - 0.5);
    final path = Path()
      ..moveTo(rect.left, rect.top - 0.5)
      ..lineTo(rect.left, rect.bottom - (dockedPillRadius - 0.5))
      // Down the left side and along the bottom: both corners are convex,
      // which on a screen is an arc drawn against the clock.
      ..arcToPoint(
        Offset(rect.left + (dockedPillRadius - 0.5), rect.bottom),
        radius: r,
        clockwise: false,
      )
      ..lineTo(rect.right - (dockedPillRadius - 0.5), rect.bottom)
      ..arcToPoint(
        Offset(rect.right, rect.bottom - (dockedPillRadius - 0.5)),
        radius: r,
        clockwise: false,
      )
      ..lineTo(rect.right, rect.top - 0.5);
    canvas.drawPath(path, paint);
  }
}

/// Lets the bar's shadow out on every side but, while docked, the top.
class _BarShadowClipper extends CustomClipper<Rect> {
  const _BarShadowClipper({required this.cutTop});

  final bool cutTop;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
    -100,
    cutTop ? 0 : -100,
    size.width + 100,
    size.height + 100,
  );

  @override
  bool shouldReclip(_BarShadowClipper old) => old.cutTop != cutTop;
}

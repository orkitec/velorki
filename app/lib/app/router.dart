import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../features/import_export/data/track_decoder.dart';
import '../features/import_export/domain/imported_track.dart';
import '../features/import_export/presentation/import_preview_screen.dart';
import '../features/library/presentation/library_screen.dart';
import '../features/library/presentation/route_detail_screen.dart';
import '../features/navigation/application/navigation_controller.dart';
import '../features/planner/presentation/planner_screen.dart';
import '../features/recording/application/recording_controller.dart';
import '../features/recording/application/ride_notification_updater.dart';
import '../features/recording/presentation/recording_screen.dart';
import '../features/recording/presentation/ride_detail_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/subscription/presentation/paywall_screen.dart';
import '../l10n/generated/app_localizations.dart';
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

/// Route detail, relative to [libraryRoute].
const String routeDetailPath = 'route/:id';

/// The location of the detail screen for the saved route [id].
String routeDetailLocation(String id) => '$libraryRoute/route/$id';

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
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: plannerRoute,
                builder: (context, state) => const PlannerScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: recordingRoute,
                builder: (context, state) => const RecordingScreen(),
                routes: [
                  GoRoute(
                    path: 'ride/:id',
                    builder: (context, state) => RideDetailScreen(
                      rideId: state.pathParameters['id'] ?? '',
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: libraryRoute,
                builder: (context, state) => const LibraryScreen(),
                routes: [
                  GoRoute(
                    path: routeDetailPath,
                    builder: (context, state) => RouteDetailScreen(
                      routeId: state.pathParameters['id'] ?? '',
                    ),
                  ),
                ],
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
    return Scaffold(
      // The bar floats over the content; screens read the bottom padding
      // from MediaQuery to keep their last rows above it.
      extendBody: true,
      // The keyboard inset is left to each tab's own scaffold: the map
      // screens keep their full height under the keyboard, the settings
      // screen resizes as usual.
      resizeToAvoidBottomInset: false,
      body: shell,
      bottomNavigationBar: hideBar
          ? null
          : FloatingNavigationBar(
              selectedIndex: shell.currentIndex,
              onDestinationSelected: (index) => shell.goBranch(
                index,
                // Tapping the active tab pops back to that branch's root.
                initialLocation: index == shell.currentIndex,
              ),
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

/// How far a sheet's collapsed top must sit above the screen's bottom inset
/// to clear the floating navigation bar: the bar's 12 dp gap and 72 dp
/// height. A sheet pulled down to its handle rests on this, so the handle
/// strip sits on the bar instead of behind it, and the sheet's first line
/// starts under the bar's glass.
const double floatingNavBarClearance = 12 + 72;

/// The height of a sheet's handle strip: the drag handle with its margins.
const double sheetHandleDp = 28;

/// A [NavigationBar] in a floating glass pill, blurred over the map.
///
/// The Material bar underneath keeps the semantics, the ripples and the
/// label behaviour; only its chrome is replaced.
class FloatingNavigationBar extends StatelessWidget {
  const FloatingNavigationBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.velorki;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        MediaQuery.viewPaddingOf(context).bottom + 12,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          boxShadow: const [
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.glass,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: colors.glassBorder),
              ),
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
    );
  }
}

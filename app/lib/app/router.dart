import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../features/import_export/domain/imported_track.dart';
import '../features/import_export/presentation/import_preview_screen.dart';
import '../features/library/presentation/library_screen.dart';
import '../features/library/presentation/route_detail_screen.dart';
import '../features/planner/presentation/planner_screen.dart';
import '../features/recording/application/recording_controller.dart';
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
        builder: (context, state) =>
            ImportPreviewScreen(candidate: state.extra as ImportCandidate?),
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
    // While a ride is being recorded on the Record tab the bar only takes
    // space from the figures; it comes back when the ride ends or the
    // rider leaves the tab through the system back gesture.
    final recording = ref.watch(
      recordingControllerProvider.select((s) => s.isRecording),
    );
    final hideBar = recording && shell.currentIndex == 1;
    return Scaffold(
      // The bar floats over the content; screens read the bottom padding
      // from MediaQuery to keep their last rows above it.
      extendBody: true,
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

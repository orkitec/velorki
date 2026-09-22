import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'nav_bar_docking.g.dart';

/// Which tabs' bottom sheets are docked in the floating navigation bar right
/// now, by route path.
///
/// A sheet pulled all the way down folds into the bar; while it rests there
/// the bar squares its top corners so the two read as one pill. Each tab
/// keeps its own flag: the Plan sheet stays docked while the rider looks at
/// the library, and the bar there is round.
@Riverpod(keepAlive: true)
class NavBarDocking extends _$NavBarDocking {
  @override
  Set<String> build() => const <String>{};

  /// Records whether the sheet of the tab at [route] is docked.
  void setDocked(String route, bool docked) {
    // A screen may report from a deferred callback after the app has gone.
    if (!ref.mounted || state.contains(route) == docked) return;
    state = docked
        ? <String>{...state, route}
        : (<String>{...state}..remove(route));
  }
}

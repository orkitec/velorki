import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_config.dart';

const String _prefsShowRoute = 'rides.showRoute';

/// Whether a ride page draws the route the ride followed, with its points
/// of interest, under the track. On unless the rider switched it off; the
/// key is removed rather than written when it goes back to on, so the stored
/// preferences only hold the choices the rider actually made.
class ShowRideRouteController extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(sharedPreferencesProvider).getBool(_prefsShowRoute) ?? true;

  /// Shows or hides the route and remembers the choice.
  Future<void> set(bool value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (value) {
      await prefs.remove(_prefsShowRoute);
    } else {
      await prefs.setBool(_prefsShowRoute, false);
    }
    state = value;
  }
}

/// Whether ride pages show the followed route.
final showRideRouteProvider = NotifierProvider<ShowRideRouteController, bool>(
  ShowRideRouteController.new,
);

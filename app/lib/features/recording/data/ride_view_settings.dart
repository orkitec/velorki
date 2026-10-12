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

const String _prefsTrackColour = 'rides.trackColour';

/// What a ride's track on the map is coloured by.
enum RideTrackColour {
  /// How fast each stretch was ridden.
  speed,

  /// How steep each stretch was.
  gradient,
}

/// What ride pages colour the track by: the speed until the rider picks the
/// gradient; remembered across launches like [ShowRideRouteController]'s
/// choice, the key removed when it goes back to the speed.
class RideTrackColourController extends Notifier<RideTrackColour> {
  @override
  RideTrackColour build() =>
      ref.watch(sharedPreferencesProvider).getString(_prefsTrackColour) ==
          RideTrackColour.gradient.name
      ? RideTrackColour.gradient
      : RideTrackColour.speed;

  /// Colours the track by [colour] and remembers the choice.
  Future<void> set(RideTrackColour colour) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (colour == RideTrackColour.speed) {
      await prefs.remove(_prefsTrackColour);
    } else {
      await prefs.setString(_prefsTrackColour, colour.name);
    }
    state = colour;
  }
}

/// What ride pages colour the track by.
final rideTrackColourProvider =
    NotifierProvider<RideTrackColourController, RideTrackColour>(
      RideTrackColourController.new,
    );

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/app_config.dart';

part 'route_overlay.g.dart';

const String _prefsRouteOverlay = 'weather.route_overlay';

/// What the wind switch kept before the choice had three ways: `true` for
/// the wind on the route.
const String _prefsWindOnMap = 'weather.wind_on_map';

/// What the route on the map is coloured by.
enum RouteOverlay {
  /// Nothing: the route in its own colour.
  off,

  /// How the wind meets the rider.
  wind,

  /// The rain where the rider will be then.
  rain,
}

/// What the route on the map is coloured by, on the Plan tab and on a saved
/// route's card alike. Off until the rider picks one; remembered across
/// launches. A rider who had the wind switched on finds the wind chosen.
@Riverpod(keepAlive: true)
class RouteOverlayChoice extends _$RouteOverlayChoice {
  @override
  RouteOverlay build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final stored = prefs.getString(_prefsRouteOverlay);
    for (final overlay in RouteOverlay.values) {
      if (overlay.name == stored) return overlay;
    }
    return prefs.getBool(_prefsWindOnMap) ?? false
        ? RouteOverlay.wind
        : RouteOverlay.off;
  }

  /// Colours the route by [overlay].
  Future<void> set(RouteOverlay overlay) async {
    state = overlay;
    await ref
        .read(sharedPreferencesProvider)
        .setString(_prefsRouteOverlay, overlay.name);
  }
}

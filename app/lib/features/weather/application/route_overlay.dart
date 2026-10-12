import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/app_config.dart';
import '../../../core/plus/plus_gate.dart';
import '../../integrations/common/data/relay_client_provider.dart';
import '../../subscription/application/plus_access.dart';

part 'route_overlay.g.dart';

const String _prefsRouteOverlay = 'weather.route_overlay';

/// What the wind switch kept before the choice had three ways: `true` for
/// the wind on the route.
const String _prefsWindOnMap = 'weather.wind_on_map';

/// Whether the free forecast was accepted ([FreeRouteForecastAccepted]).
const String _prefsFreeForecast = 'weather.free_route_forecast';

/// What the route on the map and the elevation chart under it are coloured
/// by.
enum RouteOverlay {
  /// Nothing: the route in its own colour.
  off,

  /// How steep the road is: free, worked out from the route's own heights.
  gradient,

  /// How the wind meets the rider.
  wind,

  /// The rain where the rider will be then.
  rain,
}

/// Whether [overlay] is drawn from the route's weather: the relay's
/// forecast with Velorki Plus, the free one without
/// ([routeWeatherFromRelayProvider]).
bool isWeatherOverlay(RouteOverlay overlay) =>
    overlay == RouteOverlay.wind || overlay == RouteOverlay.rain;

/// What the route is coloured by as the rider chose it, on the Plan tab and
/// on a saved route's card alike: the gradient until the rider picks
/// another; remembered across launches. A rider who had the wind switched
/// on finds the wind chosen. What is drawn is [routeOverlayShownProvider].
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
        : RouteOverlay.gradient;
  }

  /// Colours the route by [overlay].
  Future<void> set(RouteOverlay overlay) async {
    state = overlay;
    await ref
        .read(sharedPreferencesProvider)
        .setString(_prefsRouteOverlay, overlay.name);
  }
}

/// Whether the route's wind and rain come from the relay's forecast: in a
/// build with the relay, for a rider the store says has Velorki Plus. Else
/// they come from the free forecast the phone loads itself, once the rider
/// has accepted it ([FreeRouteForecastAccepted]).
@riverpod
bool routeWeatherFromRelay(Ref ref) =>
    ref.watch(relayClientProvider) != null &&
    ref.watch(plusAccessProvider(PlusFeature.weather)) == PlusAccess.granted;

/// Whether the rider without Velorki Plus has accepted the free forecast
/// for the wind and the rain on the route, which is coarser than the
/// relay's: asked once, the first time they pick either; remembered across
/// launches.
@Riverpod(keepAlive: true)
class FreeRouteForecastAccepted extends _$FreeRouteForecastAccepted {
  @override
  bool build() =>
      ref.watch(sharedPreferencesProvider).getBool(_prefsFreeForecast) ?? false;

  /// Remembers that the rider accepted it.
  Future<void> accept() async {
    state = true;
    await ref.read(sharedPreferencesProvider).setBool(_prefsFreeForecast, true);
  }
}

/// What the route is coloured by: the rider's choice, but the gradient in
/// place of the wind or the rain while those cannot be had — Plus ran out
/// and the rider never accepted the free forecast — so the route is not
/// left bare for a reason the rider cannot see.
@riverpod
RouteOverlay routeOverlayShown(Ref ref) {
  final chosen = ref.watch(routeOverlayChoiceProvider);
  if (isWeatherOverlay(chosen) &&
      !ref.watch(routeWeatherFromRelayProvider) &&
      !ref.watch(freeRouteForecastAcceptedProvider)) {
    return RouteOverlay.gradient;
  }
  return chosen;
}

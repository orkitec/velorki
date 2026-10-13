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
/// another. Off and the gradient are remembered across launches, and so
/// are the wind and the rain picked by a rider who may have Plus; picked
/// from the free forecast (no relay in this build, or the store says the
/// rider has no Plus) they last until the app is closed, the choice kept
/// in the store being the one before. A rider who had the wind switched
/// on finds the wind chosen. What is drawn is [routeOverlayShownProvider].
@Riverpod(keepAlive: true)
class RouteOverlayChoice extends _$RouteOverlayChoice {
  /// Whether the choice is the one kept in the store, not one picked since
  /// the app started.
  bool _fromStore = true;

  @override
  RouteOverlay build() {
    _fromStore = true;
    final prefs = ref.watch(sharedPreferencesProvider);
    final stored = prefs.getString(_prefsRouteOverlay);
    for (final overlay in RouteOverlay.values) {
      if (overlay.name == stored) return overlay;
    }
    return prefs.getBool(_prefsWindOnMap) ?? false
        ? RouteOverlay.wind
        : RouteOverlay.gradient;
  }

  /// Colours the route by [overlay]: remembered across launches unless it
  /// is the wind or the rain from the free forecast.
  Future<void> set(RouteOverlay overlay) async {
    final wasStored = _fromStore;
    _fromStore = false;
    if (state == overlay) {
      // The same choice, now the rider's own: what is drawn may change.
      if (wasStored) ref.notifyListeners();
    } else {
      state = overlay;
    }
    if (isWeatherOverlay(overlay) && _free()) return;
    await ref
        .read(sharedPreferencesProvider)
        .setString(_prefsRouteOverlay, overlay.name);
  }

  /// Whether the wind and the rain come from the free forecast for sure: no
  /// relay in this build, or the store says the rider has no Plus.
  bool _free() =>
      ref.read(relayClientProvider) == null ||
      ref.read(plusAccessProvider(PlusFeature.weather)) == PlusAccess.missing;
}

/// Whether the route's wind and rain come from the relay's forecast: in a
/// build with the relay, for a rider the store says has Velorki Plus. Else
/// they come from the free forecast the phone loads itself.
@riverpod
bool routeWeatherFromRelay(Ref ref) =>
    ref.watch(relayClientProvider) != null &&
    ref.watch(plusAccessProvider(PlusFeature.weather)) == PlusAccess.granted;

/// What the route is coloured by: the rider's choice; but a wind or rain
/// kept in the store from a launch before is drawn as the gradient once it
/// is clear the rider has no Plus (no relay, or the store says so), as the
/// free forecast is only drawn when the rider picked it in this launch,
/// told what it is (`RouteColourChoice`). While the store has not answered
/// the kept choice stands.
@riverpod
RouteOverlay routeOverlayShown(Ref ref) {
  final chosen = ref.watch(routeOverlayChoiceProvider);
  if (!isWeatherOverlay(chosen) ||
      !ref.read(routeOverlayChoiceProvider.notifier)._fromStore ||
      ref.watch(routeWeatherFromRelayProvider)) {
    return chosen;
  }
  final relay = ref.watch(relayClientProvider) != null;
  final access = ref.watch(plusAccessProvider(PlusFeature.weather));
  if (relay && access == PlusAccess.unknown) return chosen;
  return RouteOverlay.gradient;
}

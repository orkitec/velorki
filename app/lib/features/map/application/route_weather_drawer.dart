import '../domain/map_controller.dart';

/// Draws the weather on a route ([RouteWeatherLines]) on a map, writing
/// only what changed: the wind or the rain, and taking off the other.
class RouteWeatherDrawer {
  /// What is on the map now.
  RouteWeatherLines _drawn = RouteWeatherLines.none;

  /// Draws [lines] on [map]; nothing when they are what is there already.
  Future<void> draw(MapController map, RouteWeatherLines lines) async {
    final before = _drawn;
    if (lines == before) return;
    _drawn = lines;
    await Future.wait(<Future<void>>[
      if (lines.wind.isNotEmpty)
        map.setRouteWind(lines.wind)
      else if (before.wind.isNotEmpty)
        map.clearRouteWind(),
      if (lines.rain.isNotEmpty)
        map.setRouteRain(lines.rain)
      else if (before.rain.isNotEmpty)
        map.clearRouteRain(),
    ]);
  }

  /// Takes what was drawn off [map].
  Future<void> clear(MapController map) => draw(map, RouteWeatherLines.none);
}

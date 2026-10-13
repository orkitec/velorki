import '../domain/map_controller.dart';

/// Draws what a route is coloured by ([RouteColourLines]) on a map, writing
/// only what changed: the wind or the coloured stretches, and taking off the
/// other.
class RouteColourDrawer {
  /// What is on the map now.
  RouteColourLines _drawn = RouteColourLines.none;

  /// Draws [lines] on [map]; nothing when they are what is there already.
  Future<void> draw(MapController map, RouteColourLines lines) async {
    final before = _drawn;
    if (lines == before) return;
    _drawn = lines;
    await Future.wait(<Future<void>>[
      if (lines.wind.isNotEmpty)
        map.setRouteWind(lines.wind)
      else if (before.wind.isNotEmpty)
        map.clearRouteWind(),
      if (lines.colours.isNotEmpty)
        map.setRouteColours(lines.colours)
      else if (before.colours.isNotEmpty)
        map.clearRouteColours(),
    ]);
  }

  /// Takes what was drawn off [map].
  Future<void> clear(MapController map) => draw(map, RouteColourLines.none);
}

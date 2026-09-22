import 'package:flutter/widgets.dart';

/// Tells the map how much of its top edge the owning screen covers with its
/// own chrome (search field, profile chips, a title), so the control column
/// starts below it instead of underneath it.
///
/// An inherited widget rather than a parameter: the map is built through the
/// `mapViewBuilder` provider, whose signature the screens and the tests
/// share, and this keeps that signature untouched.
class MapChromeInsets extends InheritedWidget {
  /// Creates the insets.
  const MapChromeInsets({
    required super.child,
    super.key,
    this.controlsTop,
    this.attributionBottom,
    this.showRoutingTiles = true,
    this.following = false,
    this.headingUp = false,
    this.bearingDeg = 0,
    this.onLocate,
    this.onCompass,
    this.routeShown = false,
    this.onToggleRoute,
  });

  /// Whether the followed route is drawn, for the route button's accent.
  final bool routeShown;

  /// Called by the route button at the top of the control column; `null`
  /// leaves the button out, which is every map but a ride's that followed
  /// a route.
  final VoidCallback? onToggleRoute;

  /// Whether the control column offers the routing-tile download. Only a
  /// map the rider plans on needs it; an embedded map does not.
  final bool showRoutingTiles;

  /// Distance from the safe-area top to the control column, in dp; `null`
  /// keeps the map's own default.
  final double? controlsTop;

  /// Distance from the map's bottom edge to the attribution chip, in dp,
  /// for a panel that overlaps the map; `null` keeps the default.
  final double? attributionBottom;

  /// Whether the owning screen currently keeps the camera on the rider. The
  /// locate button is drawn in the accent colour while it does.
  final bool following;

  /// Whether that following also turns the map with the direction of travel.
  /// The compass button is drawn in the accent colour while it does, so the
  /// rider can see which of the two follow styles is on.
  final bool headingUp;

  /// Where the map currently points, in degrees clockwise from north, so the
  /// compass needle can turn with it.
  final double bearingDeg;

  /// Called after the locate button moved the camera to the fix.
  ///
  /// The button lives inside the map, the follow mode belongs to the screen
  /// around it; this is the screen's way in without widening the
  /// `mapViewBuilder` signature every map in the app shares.
  final VoidCallback? onLocate;

  /// Called when the compass button was tapped; `null` leaves the button out
  /// altogether, which is what every map but a running ride wants.
  final VoidCallback? onCompass;

  /// The nearest insets, or `null` when the screen declared none.
  static MapChromeInsets? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MapChromeInsets>();

  @override
  bool updateShouldNotify(MapChromeInsets oldWidget) =>
      oldWidget.controlsTop != controlsTop ||
      oldWidget.attributionBottom != attributionBottom ||
      oldWidget.showRoutingTiles != showRoutingTiles ||
      oldWidget.following != following ||
      oldWidget.headingUp != headingUp ||
      oldWidget.bearingDeg != bearingDeg ||
      oldWidget.onLocate != onLocate ||
      oldWidget.onCompass != onCompass ||
      oldWidget.routeShown != routeShown ||
      oldWidget.onToggleRoute != onToggleRoute;
}

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
    this.onLocate,
  });

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

  /// Called after the locate button moved the camera to the fix.
  ///
  /// The button lives inside the map, the follow mode belongs to the screen
  /// around it; this is the screen's way in without widening the
  /// `mapViewBuilder` signature every map in the app shares.
  final VoidCallback? onLocate;

  /// The nearest insets, or `null` when the screen declared none.
  static MapChromeInsets? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MapChromeInsets>();

  @override
  bool updateShouldNotify(MapChromeInsets oldWidget) =>
      oldWidget.controlsTop != controlsTop ||
      oldWidget.attributionBottom != attributionBottom ||
      oldWidget.showRoutingTiles != showRoutingTiles ||
      oldWidget.following != following ||
      oldWidget.onLocate != onLocate;
}

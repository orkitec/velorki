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

  /// The nearest insets, or `null` when the screen declared none.
  static MapChromeInsets? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MapChromeInsets>();

  @override
  bool updateShouldNotify(MapChromeInsets oldWidget) =>
      oldWidget.controlsTop != controlsTop ||
      oldWidget.attributionBottom != attributionBottom ||
      oldWidget.showRoutingTiles != showRoutingTiles;
}

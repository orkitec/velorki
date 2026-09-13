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
    required this.controlsTop,
    required super.child,
    super.key,
  });

  /// Distance from the safe-area top to the control column, in dp.
  final double controlsTop;

  /// The nearest insets, or `null` when the screen declared none.
  static MapChromeInsets? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MapChromeInsets>();

  @override
  bool updateShouldNotify(MapChromeInsets oldWidget) =>
      oldWidget.controlsTop != controlsTop;
}

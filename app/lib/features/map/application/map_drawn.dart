import 'package:flutter/foundation.dart';

/// When the maps on screen have finished drawing.
///
/// [idles] counts MapLibre's "did become idle" from every map: the style,
/// its tiles, layers and images all drawn, no camera move or transition
/// running. Nothing in the app waits on it; the store pictures do, instead
/// of holding the screen still for a fixed time and hoping.
abstract final class MapDrawn {
  /// How often a map has become idle since the app started.
  static final ValueNotifier<int> idles = ValueNotifier<int>(0);
}

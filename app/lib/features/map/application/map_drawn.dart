import 'package:flutter/foundation.dart';

/// When the maps on screen have finished drawing.
///
/// [idles] counts MapLibre's "did become idle" from every map: the style,
/// its tiles, layers and images all drawn, no camera move or transition
/// running; [styles], [weatherFrames] and [cycleMaps] what comes in steps
/// before it.
/// Nothing in the app waits on them; the store pictures do, instead of
/// holding the screen still for a fixed time and hoping.
abstract final class MapDrawn {
  /// How often a map has become idle since the app started.
  static final ValueNotifier<int> idles = ValueNotifier<int>(0);

  /// How often a map style has loaded and been given the app's layers: a
  /// change of theme swaps the style, and an idle before this is the old
  /// one's.
  static final ValueNotifier<int> styles = ValueNotifier<int>(0);

  /// How many weather frames (rain, clouds) have been put on a map: they
  /// come after the radar is switched on, or a new style, once their
  /// images are in.
  static final ValueNotifier<int> weatherFrames = ValueNotifier<int>(0);

  /// How often the cycle map has been put on a map: it comes once its data
  /// is built, after the map has drawn everything else.
  static final ValueNotifier<int> cycleMaps = ValueNotifier<int>(0);
}

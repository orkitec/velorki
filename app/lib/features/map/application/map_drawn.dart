import 'package:flutter/foundation.dart';

/// When the maps on screen have finished drawing.
///
/// Every write the app makes to a map ([changed]: a source, a layer, an
/// image, their properties, the camera) and every "did become idle" from
/// MapLibre ([idle]: the style, its tiles, layers and images all drawn, no
/// camera move or transition running) gets the next number of one sequence,
/// so [drawnSince] can tell whether the map has drawn everything written to
/// it: its last idle came after the last write. [styles], [weatherFrames]
/// and [cycleMaps] count what comes in steps, after loading something.
///
/// Nothing in the app waits on them; the store pictures do, instead of
/// holding the screen still for a fixed time and hoping.
abstract final class MapDrawn {
  static int _sequence = 0;
  static int _lastIdle = 0;
  static int _lastChange = 0;

  /// The sequence so far: a mark for [drawnSince].
  static int get now => _sequence;

  /// Notes a write to a map.
  static void changed() => _lastChange = ++_sequence;

  /// Notes that a map has become idle.
  static void idle() {
    _lastIdle = ++_sequence;
    idles.value++;
  }

  /// Whether a map has become idle after [mark] and after the last write
  /// made to any map.
  static bool drawnSince(int mark) =>
      _lastIdle > mark && _lastIdle > _lastChange;

  static final Map<Object, int> _routeLines = <Object, int>{};

  /// How many route lines are on the maps: written to them, not just asked
  /// for (an owner draws its markers first and its route after them).
  static int get routeLines => _routeLines.values.fold(0, (a, b) => a + b);

  /// Notes that [map] now has [count] route lines on it.
  static void routeLinesOn(Object map, int count) {
    if (count == 0) {
      _routeLines.remove(map);
    } else {
      _routeLines[map] = count;
    }
  }

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

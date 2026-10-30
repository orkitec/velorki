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

  static int _writing = 0;
  static final Stopwatch _clock = Stopwatch()..start();
  static Duration _lastIdleAt = Duration.zero;
  static Duration _lastChangeAt = Duration.zero;
  static final List<Duration> _recentChanges = <Duration>[];

  /// Notes a write to a map setting out: until [changed] notes its end, the
  /// map is not drawn. An owner's writes follow one another without a
  /// break, so a run of them (the markers, then the route) holds this up
  /// from its first to its last.
  static void writing() => _writing++;

  /// Notes a write to a map done (or given up).
  static void changed() {
    if (_writing > 0) _writing--;
    _lastChange = ++_sequence;
    _lastChangeAt = _clock.elapsed;
    _recentChanges
      ..add(_lastChangeAt)
      ..removeWhere((at) => _lastChangeAt - at > const Duration(seconds: 5));
  }

  /// Notes that a map has become idle.
  static void idle() {
    _lastIdle = ++_sequence;
    _lastIdleAt = _clock.elapsed;
    idles.value++;
  }

  /// What holds the maps from counting as drawn, for a failure to say.
  static String describe() {
    final now = _clock.elapsed;
    final recent = _recentChanges
        .where((at) => now - at <= const Duration(seconds: 5))
        .length;
    return '$_writing write(s) under way; the last write '
        '${(now - _lastChangeAt).inMilliseconds} ms ago, the last idle '
        '${(now - _lastIdleAt).inMilliseconds} ms ago '
        '(${_lastIdle > _lastChange ? 'after' : 'before'} the last write); '
        '$recent write(s) in the last 5 s';
  }

  /// Whether the maps have drawn everything written to them since [mark]:
  /// no write under way and an idle after the last write. When nothing was
  /// written after [mark], an idle after the last write before it will do.
  static bool drawnSince(int mark) => _writing == 0 && _lastIdle > _lastChange;

  static final Map<Object, List<int>> _routeLines = <Object, List<int>>{};

  /// How many route lines are on the maps: written to them, not just asked
  /// for (an owner draws its markers first and its route after them).
  static int get routeLines =>
      _routeLines.values.fold(0, (sum, lines) => sum + lines.length);

  /// Whether a map has a route line of exactly [points] points on it: the
  /// route asked for, not one an earlier screen left that is still to go.
  static bool hasRouteLineOf(int points) =>
      _routeLines.values.any((lines) => lines.contains(points));

  /// Notes that [map] now has route lines of these point counts on it.
  static void routeLinesOn(Object map, List<int> points) {
    if (points.isEmpty) {
      _routeLines.remove(map);
    } else {
      _routeLines[map] = List<int>.unmodifiable(points);
    }
  }

  /// How often a map has become idle since the app started.
  static final ValueNotifier<int> idles = ValueNotifier<int>(0);

  /// How often a map style has loaded and been given the app's layers: a
  /// change of theme swaps the style, and an idle before this is the old
  /// one's.
  static final ValueNotifier<int> styles = ValueNotifier<int>(0);

  /// How often a weather frame (rain, clouds) has been shown on a map:
  /// drawn, or one kept unseen made visible. They come after the radar is
  /// switched on, or a new style, once their images are in; the frames
  /// preloaded unseen for other times do not count.
  static final ValueNotifier<int> weatherFrames = ValueNotifier<int>(0);

  /// How often the cycle map has been put on a map: it comes once its data
  /// is built, after the map has drawn everything else.
  static final ValueNotifier<int> cycleMaps = ValueNotifier<int>(0);
}

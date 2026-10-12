import 'dart:async';

import 'package:velorki_geo/velorki_geo.dart';

import '../../navigation/application/route_geometry.dart';
import '../domain/map_controller.dart';

/// How long the rider dot stays on the map after the finger leaves the
/// chart: a tap shows it for long enough to be seen, and the eye that goes
/// from the chart to the map on lifting still finds it there.
const Duration routeCursorLinger = Duration(milliseconds: 1500);

/// The rider dot a chart along a route or a ride puts on the map: a screen
/// hands it the line the chart is drawn along and the map, and the chart's
/// finger as a distance along the line; it draws the point there.
///
/// It never moves the camera. A sweep runs over the whole line in a second,
/// and a camera chasing it would fight the rider's own framing — and on a
/// ride, the follow mode; the screens fit the line into view when they
/// open, so the dot is mostly in sight anyway.
class RouteCursor {
  /// Creates the cursor; [linger] is how long the dot stays after the
  /// finger lifts.
  RouteCursor({this.linger = routeCursorLinger});

  /// See [routeCursorLinger].
  final Duration linger;

  MapController? _map;
  Object? _lineKey;
  List<LatLng> _line = const <LatLng>[];
  List<double> _along = const <double>[];
  LatLng? _shown;
  Timer? _clearing;

  /// The map to draw on; a new one takes the dot off the old one.
  set map(MapController? map) {
    if (identical(map, _map)) return;
    clear();
    _map = map;
  }

  /// The line the chart is drawn along, known by [key]: the same key again
  /// keeps the line worked out before. [along] is how far along the line
  /// each of its points lies, worked out from the line when left out. A new
  /// line takes the dot away.
  void setLine(
    Object? key,
    List<LatLng> Function() line, {
    List<double> Function()? along,
  }) {
    if (identical(key, _lineKey)) return;
    _lineKey = key;
    _line = key == null ? const <LatLng>[] : line();
    _along = key == null
        ? const <double>[]
        : along?.call() ?? cumulativeDistances(_line);
    if (_along.length != _line.length) _along = cumulativeDistances(_line);
    clear();
  }

  /// Puts the dot [alongM] metres along the line; `null`, the finger
  /// lifted, takes it away after [linger].
  void show(double? alongM) {
    if (alongM == null) {
      if (_shown != null) _clearing ??= Timer(linger, clear);
      return;
    }
    _clearing?.cancel();
    _clearing = null;
    if (_line.isEmpty) return;
    final at = pointAlong(_line, _along, alongM);
    if (at == _shown) return;
    _shown = at;
    unawaited(_map?.setRouteCursor(at));
  }

  /// Takes the dot away at once.
  void clear() {
    _clearing?.cancel();
    _clearing = null;
    if (_shown == null) return;
    _shown = null;
    unawaited(_map?.setRouteCursor(null));
  }

  /// Takes the dot away and lets go of the map.
  void dispose() {
    clear();
    _map = null;
  }
}

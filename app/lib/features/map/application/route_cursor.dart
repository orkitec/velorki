import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../navigation/application/route_geometry.dart';
import '../domain/map_controller.dart';

/// The cursor of the charts along a route or a ride, and the rider badge it
/// puts on the map: its [value] is how far along the line the cursor
/// stands, in metres, `null` while it is hidden.
///
/// A screen hands it the line its charts are drawn along and the map, and
/// hands it to every chart along that line: charts that share it share one
/// cursor, a move on one moves it on all, and the badge on the map follows.
/// It stays where it was put until the cursor is hidden, the line changes,
/// or the screen lets it go.
///
/// It never moves the camera. A sweep runs over the whole line in a second,
/// and a camera chasing it would fight the rider's own framing — and on a
/// ride, the follow mode; the screens fit the line into view when they
/// open, so the badge is mostly in sight anyway.
class RouteCursor extends ValueNotifier<double?> {
  /// Creates the cursor, hidden.
  RouteCursor() : super(null);

  MapController? _map;
  Object? _lineKey;
  List<LatLng> _line = const <LatLng>[];
  List<double> _along = const <double>[];

  // Where the badge is on [_map], as last written.
  LatLng? _shown;

  /// The map to draw on; a new one takes the badge off the old one and
  /// puts it on the new one, where the cursor stands.
  set map(MapController? map) {
    if (identical(map, _map)) return;
    if (_shown != null) unawaited(_map?.setRouteCursor(null));
    _shown = null;
    _map = map;
    _draw();
  }

  /// The line the charts are drawn along, known by [key]: the same key
  /// again keeps the line worked out before. [along] is how far along the
  /// line each of its points lies, worked out from the line when left out.
  /// A new line hides the cursor.
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
    value = null;
  }

  @override
  set value(double? alongM) {
    super.value = alongM;
    _draw();
  }

  /// Hides the cursor.
  void clear() => value = null;

  /// Puts the badge where the cursor stands, or takes it away.
  void _draw() {
    final map = _map;
    final alongM = value;
    final at = map == null || alongM == null || _line.isEmpty
        ? null
        : pointAlong(_line, _along, alongM);
    if (at == _shown) return;
    _shown = at;
    unawaited(map?.setRouteCursor(at));
  }

  /// Takes the badge away and lets go of the map.
  @override
  void dispose() {
    if (_shown != null) unawaited(_map?.setRouteCursor(null));
    _shown = null;
    _map = null;
    super.dispose();
  }
}

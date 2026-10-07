import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../navigation/application/route_geometry.dart';
import '../../search/data/gazetteer_store.dart';
import '../../search/domain/search_result.dart';
import '../../search/presentation/search_field.dart' show poiKindIcon;
import '../domain/map_controller.dart';
import '../domain/stops_along_route.dart';

part 'map_stops_controller.g.dart';

/// Below this zoom the stops in the area on screen are not drawn: the box
/// would hold a town's worth of them.
const double stopsMinZoom = 14;

/// The most stops drawn in the area on screen, the ones nearest its middle:
/// a busy old town has hundreds, and a pin over a pin helps nobody.
const int stopsAreaShown = 60;

/// The most stops one query for the area on screen asks for, per gazetteer.
const int stopsAreaLimit = 200;

/// The most stops one stretch of the route ahead asks for, per gazetteer.
const int stopsChunkLimit = 200;

/// How long the camera has to rest before the area on screen is asked for
/// its stops: a pan that stops and goes on is not asked about.
const Duration stopsDebounce = Duration(milliseconds: 250);

/// How long a stretch of the route ahead one query covers, in metres.
const double stopsChunkM = 5000;

/// How far the rider rides before the stops along the route are fetched
/// again, in metres: the far end of the search then moves on with them.
const double stopsRefetchM = 1000;

/// Finds the stops of [kinds] inside [box], at most [limit] per gazetteer.
typedef StopsFinder = Future<List<SearchResult>> Function(
  BoundingBox box,
  List<String> kinds,
  int limit,
);

/// The stops come from the gazetteers on the device, on the store's worker
/// isolate.
@Riverpod(keepAlive: true)
StopsFinder mapStopsFinder(Ref ref) => (box, kinds, limit) async {
  final store = await ref.read(gazetteerStoreProvider.future);
  return store.inBox(box, poiKinds: kinds, limit: limit);
};

/// How a stop is coloured on the map, by its gazetteer kind.
MapPoiKind mapPoiKindOfStop(String? kind) => switch (kind) {
  'drinking_water' => MapPoiKind.water,
  'cafe' ||
  'bakery' ||
  'restaurant' ||
  'fast_food' ||
  'ice_cream' ||
  'supermarket' => MapPoiKind.food,
  _ => MapPoiKind.generic,
};

/// The marker a stop is drawn with.
MapPoi stopMarker(SearchResult stop, {bool selected = false}) => MapPoi(
  position: stop.position,
  name: stop.name,
  kind: mapPoiKindOfStop(stop.detail),
  icon: poiKindIcon(stop.detail),
  selected: selected,
);

/// Where the stops come from right now.
enum MapStopsMode {
  /// None are shown.
  off,

  /// The ones in the part of the map on screen, from [stopsMinZoom] in.
  area,

  /// The ones beside the route still ahead, whatever the zoom.
  alongRoute,
}

/// The stops on one tab's map: which to fetch, when, and what to draw.
///
/// The tab says what it wants through [update] on every build (cheap when
/// nothing changed), lends its map through [attach] while it draws on the
/// shared map and takes it back through [detach], which takes the stops off
/// again so the other tab does not inherit them.
///
/// In the area on screen the stops are asked for once the camera has rested
/// for [debounce]; along a route whenever the route or the kinds change and
/// every [stopsRefetchM] the rider rides. An answer that comes back after a
/// newer question was asked is dropped.
class MapStopsController extends ChangeNotifier {
  /// Creates a controller that fetches through [find].
  MapStopsController({required this.find, this.debounce = stopsDebounce});

  /// Where the stops come from.
  final StopsFinder find;

  /// How long the camera rests before the area is asked about.
  final Duration debounce;

  /// A tap on one of the stops drawn.
  void Function(SearchResult stop)? onStopTapped;

  MapController? _map;
  bool _shown = false;
  Set<String> _kinds = const <String>{};
  String? _routeKey;
  List<LatLng> _line = const <LatLng>[];
  List<double> _cumulative = const <double>[];
  double _alongM = 0;

  Timer? _timer;
  int _generation = 0;

  /// What was last asked for along the route: the route, the kinds and
  /// where the rider stood. `null` until something was.
  String? _askedRoute;
  Set<String>? _askedKinds;
  double? _askedAtM;

  List<SearchResult> _area = const <SearchResult>[];
  List<StopAlongRoute<SearchResult>> _placed =
      const <StopAlongRoute<SearchResult>>[];

  List<SearchResult> _drawnStops = const <SearchResult>[];
  List<MapPoi> _drawn = const <MapPoi>[];
  SearchResult? _selected;

  /// Where the stops come from right now.
  MapStopsMode get mode {
    if (!_shown || _kinds.isEmpty) return MapStopsMode.off;
    return _routeKey != null && _line.length >= 2
        ? MapStopsMode.alongRoute
        : MapStopsMode.area;
  }

  /// The stops on the map, in the order [MapController.setStops] got them.
  List<SearchResult> get stops => _drawnStops;

  /// The stop the rider picked, if any.
  SearchResult? get selected => _selected;

  /// Whether stops are wanted in the area on screen but the map is zoomed
  /// out too far to show them: the rider is told to zoom in.
  bool get needsZoom => mode == MapStopsMode.area && _zoomedOut;
  bool _zoomedOut = false;

  /// Zooms the map in to where the stops show, on the same middle.
  Future<void> zoomIn() async {
    final map = _map;
    final center = map?.center;
    if (map == null || center == null) return;
    await map.moveTo(center, zoom: stopsMinZoom);
  }

  /// Notes whether [map] is zoomed out too far for the stops, telling the
  /// listeners when that changes.
  void _noteZoom(MapController map) {
    final zoom = map.zoom;
    final out = zoom != null && zoom < stopsMinZoom;
    if (out == _zoomedOut) return;
    _zoomedOut = out;
    _changed();
  }

  /// Along a route: every stop beside the route still ahead, nearest first.
  List<StopAlongRoute<SearchResult>> get ahead {
    if (mode != MapStopsMode.alongRoute) {
      return const <StopAlongRoute<SearchResult>>[];
    }
    return <StopAlongRoute<SearchResult>>[
      for (final placed in _placed)
        if (placed.atM >= _alongM && placed.atM - _alongM <= stopsAheadMaxM)
          placed.seenFrom(_alongM),
    ];
  }

  /// Along a route: the next stop of each kind ahead, nearest first, at
  /// most [max] of them.
  List<StopAlongRoute<SearchResult>> nextPerKind({int max = 3}) {
    final seen = <String?>{};
    final out = <StopAlongRoute<SearchResult>>[];
    for (final placed in ahead) {
      if (!seen.add(placed.stop.detail)) continue;
      out.add(placed);
      if (out.length >= max) break;
    }
    return out;
  }

  /// What the tab wants: whether stops are [shown], of which [kinds], and,
  /// with a [routeKey] and its [routeLine], the ones along that route ahead
  /// of a rider [alongM] metres along it rather than the ones on screen.
  void update({
    required bool shown,
    required Set<String> kinds,
    String? routeKey,
    List<LatLng> routeLine = const <LatLng>[],
    double alongM = 0,
  }) {
    final modeBefore = mode;
    final kindsChanged = !setEquals(kinds, _kinds);
    final shownChanged = shown != _shown;
    final routeChanged =
        routeKey != _routeKey ||
        (routeKey != null && !identical(routeLine, _line));
    _shown = shown;
    if (kindsChanged) _kinds = Set<String>.unmodifiable(kinds);
    if (routeChanged) {
      _routeKey = routeKey;
      _line = routeKey == null ? const <LatLng>[] : routeLine;
      _cumulative = _line.length < 2
          ? const <double>[]
          : cumulativeDistances(_line);
    }
    _alongM = alongM;
    if (_map == null) return;
    final now = mode;
    switch (now) {
      case MapStopsMode.off:
        if (modeBefore != MapStopsMode.off) _stop();
      case MapStopsMode.area:
        if (modeBefore != MapStopsMode.area || kindsChanged || shownChanged) {
          _placed = const <StopAlongRoute<SearchResult>>[];
          _askedRoute = null;
          _scheduleArea();
        }
      case MapStopsMode.alongRoute:
        // What was found along another route, or for other kinds, is not
        // what the rider asked for now.
        if (routeChanged || kindsChanged || modeBefore != now) {
          _placed = const <StopAlongRoute<SearchResult>>[];
        }
        if (_needsRouteFetch()) unawaited(_fetchAlongRoute());
        // The stops ridden past leave at once, not with the next answer.
        _drawAhead();
    }
  }

  /// Draws on [map] from now on, until [detach].
  void attach(MapController map) {
    if (identical(map, _map)) return;
    if (_map != null) detach();
    _map = map;
    _noteZoom(map);
    map.addCameraIdleListener(_handleCameraIdle);
    map.onStopTapped = _handleStopTapped;
    switch (mode) {
      case MapStopsMode.off:
        break;
      case MapStopsMode.area:
        _scheduleArea();
      case MapStopsMode.alongRoute:
        unawaited(_fetchAlongRoute());
    }
  }

  /// Takes the stops off the map and lets it go; whatever was on its way
  /// is dropped when it arrives. A map that is gone already (replaced after
  /// a style reload) is let go of without being drawn on: pass
  /// [clear] `false`.
  void detach({bool clear = true}) {
    final map = _map;
    if (map == null) return;
    map.removeCameraIdleListener(_handleCameraIdle);
    map.onStopTapped = null;
    if (clear && _drawn.isNotEmpty) {
      unawaited(map.setStops(const <MapPoi>[]));
    }
    _map = null;
    _zoomedOut = false;
    _forget();
    _changed();
  }

  /// Marks [stop] as the one the rider picked; `null` picks none.
  void select(SearchResult? stop) {
    if (stop == _selected) return;
    _selected = stop;
    _draw(_drawnStops);
  }

  @override
  void dispose() {
    _disposed = true;
    detach();
    _timer?.cancel();
    super.dispose();
  }

  bool _disposed = false;
  bool _changePending = false;

  /// Tells the listeners, from a microtask: [update] and [detach] are called
  /// from a tab's build and its tab changes, where a listener may not
  /// rebuild anything; and a screen reads [ahead] in its own build anyway.
  void _changed() {
    if (_changePending || _disposed) return;
    _changePending = true;
    scheduleMicrotask(() {
      _changePending = false;
      if (!_disposed) notifyListeners();
    });
  }

  // ------------------------------------------------------------- internals

  void _forget() {
    _timer?.cancel();
    _timer = null;
    _generation++;
    _askedRoute = null;
    _askedKinds = null;
    _askedAtM = null;
    _area = const <SearchResult>[];
    _placed = const <StopAlongRoute<SearchResult>>[];
    _drawnStops = const <SearchResult>[];
    _drawn = const <MapPoi>[];
  }

  /// Stops are off: everything on its way is dropped and the map cleared.
  void _stop() {
    _forget();
    unawaited(_map?.setStops(const <MapPoi>[]));
    _changed();
  }

  void _handleCameraIdle() {
    final map = _map;
    if (map != null) _noteZoom(map);
    if (mode == MapStopsMode.area) _scheduleArea();
  }

  void _handleStopTapped(int index) {
    if (index < 0 || index >= _drawnStops.length) return;
    onStopTapped?.call(_drawnStops[index]);
  }

  void _scheduleArea() {
    _timer?.cancel();
    _timer = Timer(debounce, () {
      _timer = null;
      unawaited(_fetchArea());
    });
  }

  Future<void> _fetchArea() async {
    final map = _map;
    if (map == null || mode != MapStopsMode.area) return;
    final generation = ++_generation;
    final zoom = map.zoom;
    if (zoom == null || zoom < stopsMinZoom) {
      _area = const <SearchResult>[];
      _draw(_area);
      return;
    }
    final bounds = map.visibleBounds;
    if (bounds == null) return;
    final List<SearchResult> found;
    try {
      found = await find(bounds, _kinds.toList()..sort(), stopsAreaLimit);
    } on Object catch (e) {
      debugPrint('velorki: stops in the area failed: $e');
      return;
    }
    if (generation != _generation || !identical(map, _map)) return;
    if (mode != MapStopsMode.area) return;
    final middle = map.center ?? bounds.center;
    final nearest = <SearchResult>[...found]
      ..sort(
        (a, b) => haversineMeters(
          a.position,
          middle,
        ).compareTo(haversineMeters(b.position, middle)),
      );
    _area = nearest.take(stopsAreaShown).toList();
    _draw(_area);
  }

  bool _needsRouteFetch() {
    final at = _askedAtM;
    return _askedRoute != _routeKey ||
        _askedKinds == null ||
        !setEquals(_askedKinds, _kinds) ||
        at == null ||
        (_alongM - at).abs() >= stopsRefetchM;
  }

  Future<void> _fetchAlongRoute() async {
    final map = _map;
    if (map == null || mode != MapStopsMode.alongRoute) return;
    _timer?.cancel();
    _timer = null;
    final generation = ++_generation;
    final key = _routeKey;
    final line = _line;
    final cumulative = _cumulative;
    final kinds = _kinds.toList()..sort();
    final from = _alongM;
    _askedRoute = key;
    _askedKinds = _kinds;
    _askedAtM = from;
    final boxes = routeChunkBoxes(
      line,
      cumulative,
      fromM: from,
      toM: from + stopsAheadMaxM,
      chunkM: stopsChunkM,
    );
    final List<List<SearchResult>> answers;
    try {
      answers = await Future.wait(<Future<List<SearchResult>>>[
        for (final box in boxes) find(box, kinds, stopsChunkLimit),
      ]);
    } on Object catch (e) {
      debugPrint('velorki: stops along the route failed: $e');
      // Asked again on the next update rather than a kilometre on.
      if (generation == _generation) _askedAtM = null;
      return;
    }
    if (generation != _generation || !identical(map, _map)) return;
    final candidates = <SearchResult>{for (final a in answers) ...a};
    _placed = stopsAlongRoute<SearchResult>(
      line: line,
      cumulative: cumulative,
      alongM: from,
      candidates: candidates,
      positionOf: (stop) => stop.position,
    );
    _drawAhead(force: true);
  }

  void _drawAhead({bool force = false}) {
    final stops = <SearchResult>[for (final placed in ahead) placed.stop];
    if (!force && listEquals(stops, _drawnStops)) {
      // Nothing new on the map, but the distances ahead moved on.
      _changed();
      return;
    }
    _draw(stops);
  }

  void _draw(List<SearchResult> stops) {
    final map = _map;
    if (map == null) return;
    _drawnStops = List<SearchResult>.unmodifiable(stops);
    final markers = <MapPoi>[
      for (final stop in stops) stopMarker(stop, selected: stop == _selected),
    ];
    if (!listEquals(markers, _drawn)) {
      _drawn = List<MapPoi>.unmodifiable(markers);
      unawaited(map.setStops(_drawn));
    }
    _changed();
  }
}

import 'package:flutter/foundation.dart';

import '../domain/map_controller.dart';
import 'map_stops_controller.dart' show StopsCoverage;

/// The zoom from which the map says an area is not downloaded: farther out
/// the view is a region, and its middle says little about where one rides.
const double areaHintMinZoom = 11;

/// Whether the middle of the map is in an area that is not downloaded, for
/// the hint that offers the download: kept up to date as the camera comes
/// to rest and as areas are downloaded.
///
/// It follows [coverage], which answers for the downloaded search index;
/// the index and the routing data come down together for an area.
class AreaDownloadHint extends ChangeNotifier {
  /// A hint judged by [coverage].
  AreaDownloadHint(this._coverage) {
    _coverage.addListener(_update);
  }

  final StopsCoverage _coverage;
  MapController? _map;
  bool _needed = false;

  /// Whether the hint shows.
  bool get needed => _needed;

  /// Judges [map] from now on.
  void attach(MapController map) {
    if (identical(map, _map)) return;
    detach();
    _map = map;
    map.addCameraIdleListener(_update);
    _update();
  }

  /// Lets the map go; the hint goes with it.
  void detach() {
    _map?.removeCameraIdleListener(_update);
    _map = null;
    _set(false);
  }

  void _update() {
    final map = _map;
    final zoom = map?.zoom;
    final bounds = map?.visibleBounds;
    if (map == null || zoom == null || bounds == null) return;
    _set(zoom >= areaHintMinZoom - 0.01 && !_coverage.covers(bounds.center));
  }

  void _set(bool value) {
    if (value == _needed) return;
    _needed = value;
    notifyListeners();
  }

  @override
  void dispose() {
    detach();
    _coverage.removeListener(_update);
    super.dispose();
  }
}

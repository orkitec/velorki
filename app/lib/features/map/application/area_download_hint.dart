import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:velorki_brouter/velorki_brouter.dart' show TileName;

import '../domain/map_controller.dart';
import 'map_stops_controller.dart' show StopsCoverage;

part 'area_download_hint.g.dart';

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
  TileName? _missingArea;

  /// Whether the hint shows, unless the rider closed it for [missingArea].
  bool get needed => _missingArea != null;

  /// The tile under the middle of the map while it is not downloaded, which
  /// is the area the hint speaks of; `null` while there is no hint.
  TileName? get missingArea => _missingArea;

  /// Whether the hint shows once the rider has closed it over [dismissed].
  bool shownDespite(Set<TileName> dismissed) =>
      _missingArea != null && !dismissed.contains(_missingArea);

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
    _set(null);
  }

  void _update() {
    final map = _map;
    final zoom = map?.zoom;
    final bounds = map?.visibleBounds;
    if (map == null || zoom == null || bounds == null) return;
    final center = bounds.center;
    if (zoom < areaHintMinZoom - 0.01 || _coverage.covers(center)) {
      _set(null);
      return;
    }
    try {
      _set(TileName.fromLatLng(center));
    } on ArgumentError {
      // A map that is not ready yet can answer with a non-finite centre.
      _set(null);
    }
  }

  void _set(TileName? area) {
    if (area == _missingArea) return;
    _missingArea = area;
    notifyListeners();
  }

  @override
  void dispose() {
    detach();
    _coverage.removeListener(_update);
    super.dispose();
  }
}

/// The areas whose not-downloaded hint the rider closed, for as long as the
/// app runs: the hint stays away over them and comes back over any other
/// area that is not downloaded, and over these after a restart.
@Riverpod(keepAlive: true)
class AreaHintDismissals extends _$AreaHintDismissals {
  @override
  Set<TileName> build() => const {};

  /// Closes the hint over [area].
  void dismiss(TileName area) {
    if (state.contains(area)) return;
    state = {...state, area};
  }
}

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../app/app_config.dart';

part 'map_preferences.g.dart';

/// Where the map looks: a centre, a zoom and a bearing.
@immutable
class MapCamera {
  const MapCamera({required this.center, required this.zoom, this.bearing = 0});

  final LatLng center;
  final double zoom;

  /// Degrees clockwise from north at the top of the map.
  final double bearing;

  @override
  bool operator ==(Object other) =>
      other is MapCamera &&
      other.center == center &&
      other.zoom == zoom &&
      other.bearing == bearing;

  @override
  int get hashCode => Object.hash(center, zoom, bearing);

  @override
  String toString() => 'MapCamera($center, zoom: $zoom, bearing: $bearing)';
}

/// Central Europe at a country-sized zoom: something recognisable before the
/// first fix, wherever the user is.
const MapCamera defaultMapCamera = MapCamera(
  center: LatLng(50.0, 10.0),
  zoom: 4.5,
);

const String _prefsCameraLat = 'map.camera.lat';
const String _prefsCameraLon = 'map.camera.lon';
const String _prefsCameraZoom = 'map.camera.zoom';
const String _prefsCyclosm = 'map.cyclosm_overlay';

/// The camera the map was left at: the one every map starts from. Centre
/// and zoom survive a restart; the bearing is for this launch only, so the
/// app never opens on a turned map.
@Riverpod(keepAlive: true)
class LastMapCamera extends _$LastMapCamera {
  @override
  MapCamera build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final lat = prefs.getDouble(_prefsCameraLat);
    final lon = prefs.getDouble(_prefsCameraLon);
    final zoom = prefs.getDouble(_prefsCameraZoom);
    if (lat == null || lon == null || zoom == null) return defaultMapCamera;
    return MapCamera(center: LatLng(lat, lon), zoom: zoom);
  }

  /// Remembers [camera]; called when the map camera comes to rest.
  Future<void> save(MapCamera camera) async {
    state = camera;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setDouble(_prefsCameraLat, camera.center.lat);
    await prefs.setDouble(_prefsCameraLon, camera.center.lon);
    await prefs.setDouble(_prefsCameraZoom, camera.zoom);
  }
}

/// Whether the CyclOSM raster overlay is switched on.
///
/// Offline downloads read this too: the OpenStreetMap Foundation tile policy
/// forbids bulk downloading CyclOSM tiles, so the download action is disabled
/// while the overlay is active.
@Riverpod(keepAlive: true)
class CyclosmOverlay extends _$CyclosmOverlay {
  @override
  bool build() =>
      ref.watch(sharedPreferencesProvider).getBool(_prefsCyclosm) ?? false;

  /// Switches the overlay on or off and remembers the choice.
  Future<void> set(bool value) async {
    await ref.read(sharedPreferencesProvider).setBool(_prefsCyclosm, value);
    state = value;
  }

  /// Flips the overlay.
  Future<void> toggle() => set(!state);
}

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

const String _prefsStopsShown = 'map.stops.shown';
const String _prefsStopsKinds = 'map.stops.kinds';
const String _prefsStopsAlongRoute = 'map.stops.alongRoute';

/// The kinds of stop shown until the rider picks their own: what a ride
/// most often stops for.
const Set<String> defaultStopKinds = <String>{
  'drinking_water',
  'cafe',
  'bakery',
  'toilets',
  'bicycle_repair_station',
};

/// What the map's Layers sheet says about stops: whether they are shown,
/// which kinds, and, on a guided ride, whether along the route ahead or in
/// the part of the map on screen.
@immutable
class MapStopsSettings {
  /// Creates the preferences.
  const MapStopsSettings({
    this.shown = false,
    this.kinds = defaultStopKinds,
    this.alongRoute = true,
  });

  /// Whether stops are drawn at all.
  final bool shown;

  /// The gazetteer POI kinds shown, `drinking_water`, `cafe` and so on.
  final Set<String> kinds;

  /// On a guided ride, whether the stops are the ones beside the route still
  /// ahead rather than the ones in the area on screen.
  final bool alongRoute;

  /// A copy with the named fields replaced.
  MapStopsSettings copyWith({
    bool? shown,
    Set<String>? kinds,
    bool? alongRoute,
  }) => MapStopsSettings(
    shown: shown ?? this.shown,
    kinds: kinds ?? this.kinds,
    alongRoute: alongRoute ?? this.alongRoute,
  );

  @override
  bool operator ==(Object other) =>
      other is MapStopsSettings &&
      other.shown == shown &&
      other.alongRoute == alongRoute &&
      setEquals(other.kinds, kinds);

  @override
  int get hashCode =>
      Object.hash(shown, alongRoute, Object.hashAllUnordered(kinds));

  @override
  String toString() =>
      'MapStopsSettings(shown: $shown, kinds: ${kinds.join(',')}, '
      'alongRoute: $alongRoute)';
}

/// The stops the map shows, remembered across launches.
@Riverpod(keepAlive: true)
class MapStopsPreferences extends _$MapStopsPreferences {
  @override
  MapStopsSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final kinds = prefs.getStringList(_prefsStopsKinds);
    return MapStopsSettings(
      shown: prefs.getBool(_prefsStopsShown) ?? false,
      kinds: kinds == null ? defaultStopKinds : Set<String>.unmodifiable(kinds),
      alongRoute: prefs.getBool(_prefsStopsAlongRoute) ?? true,
    );
  }

  /// Shows the stops or takes them away.
  Future<void> setShown(bool value) async {
    state = state.copyWith(shown: value);
    await ref.read(sharedPreferencesProvider).setBool(_prefsStopsShown, value);
  }

  /// Shows [kind] among the stops, or stops showing it.
  Future<void> setKind(String kind, {required bool shown}) async {
    final kinds = Set<String>.of(state.kinds);
    if (shown) {
      kinds.add(kind);
    } else {
      kinds.remove(kind);
    }
    state = state.copyWith(kinds: Set<String>.unmodifiable(kinds));
    await ref
        .read(sharedPreferencesProvider)
        .setStringList(_prefsStopsKinds, kinds.toList()..sort());
  }

  /// On a guided ride, along the route ahead or in the area on screen.
  Future<void> setAlongRoute(bool value) async {
    state = state.copyWith(alongRoute: value);
    await ref
        .read(sharedPreferencesProvider)
        .setBool(_prefsStopsAlongRoute, value);
  }
}

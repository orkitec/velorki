import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../app/app_config.dart';
import '../../settings/data/units.dart';
import '../domain/cycle_map.dart';
import 'country_map_views.dart';

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

/// Central Europe at a country-sized zoom: where the map opens when there is
/// no remembered view and the phone's country is unknown (see
/// [LastMapCamera]).
const MapCamera defaultMapCamera = MapCamera(
  center: LatLng(50.0, 10.0),
  zoom: 4.5,
);

const String _prefsCameraLat = 'map.camera.lat';
const String _prefsCameraLon = 'map.camera.lon';
const String _prefsCameraZoom = 'map.camera.zoom';
const String _prefsCyclosm = 'map.cyclosm_overlay';

/// Whether a map view was ever remembered: false on a fresh install, where
/// [LastMapCamera] opens over the phone's country instead.
bool hasStoredMapCamera(SharedPreferences prefs) =>
    prefs.getDouble(_prefsCameraLat) != null &&
    prefs.getDouble(_prefsCameraLon) != null &&
    prefs.getDouble(_prefsCameraZoom) != null;

/// The camera the map was left at: the one every map starts from. Centre
/// and zoom survive a restart; the bearing is for this launch only, so the
/// app never opens on a turned map. With nothing remembered it opens over
/// the phone's country, or at [defaultMapCamera] when that is unknown.
@Riverpod(keepAlive: true)
class LastMapCamera extends _$LastMapCamera {
  @override
  MapCamera build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final lat = prefs.getDouble(_prefsCameraLat);
    final lon = prefs.getDouble(_prefsCameraLon);
    final zoom = prefs.getDouble(_prefsCameraZoom);
    if (lat == null || lon == null || zoom == null) {
      final view = countryMapViews[ref.read(localeCountryProvider)];
      return view == null
          ? defaultMapCamera
          : MapCamera(center: LatLng(view.lat, view.lon), zoom: view.zoom);
    }
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
/// Offline downloads read this too: CyclOSM's tiles come from OpenStreetMap
/// France's servers, which are not for bulk downloading, so the download
/// action is disabled while the overlay is active.
///
/// It and the offline cycle map ([CycleMapPreferences]) draw the same ways,
/// so one switched on switches the other off.
@Riverpod(keepAlive: true)
class CyclosmOverlay extends _$CyclosmOverlay {
  @override
  bool build() =>
      ref.watch(sharedPreferencesProvider).getBool(_prefsCyclosm) ?? false;

  /// Switches the overlay on or off and remembers the choice.
  Future<void> set(bool value) async {
    await ref.read(sharedPreferencesProvider).setBool(_prefsCyclosm, value);
    state = value;
    if (value) {
      await ref.read(cycleMapPreferencesProvider.notifier).setShown(false);
    }
  }

  /// Flips the overlay.
  Future<void> toggle() => set(!state);
}

const String _prefsStopsShown = 'map.stops.shown';
const String _prefsStopsKinds = 'map.stops.kinds';
const String _prefsStopsAlongRoute = 'map.stops.alongRoute';
const String _prefsStopsAheadLine = 'map.stops.aheadLine';

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
/// which kinds, whether along a route or in the part of the map on screen,
/// and whether the ride screen lists the next of them.
@immutable
class MapStopsSettings {
  /// Creates the preferences.
  const MapStopsSettings({
    this.shown = true,
    this.kinds = defaultStopKinds,
    this.alongRoute = true,
    this.aheadLine = false,
  });

  /// Whether stops are drawn at all.
  final bool shown;

  /// The gazetteer POI kinds shown, `drinking_water`, `cafe` and so on.
  final Set<String> kinds;

  /// With a route to be along (a planned one, or one followed on a ride),
  /// whether the stops are the ones beside it rather than the ones in the
  /// area on screen.
  final bool alongRoute;

  /// Whether the ride screen lists the next stop of each kind over its map.
  final bool aheadLine;

  /// A copy with the named fields replaced.
  MapStopsSettings copyWith({
    bool? shown,
    Set<String>? kinds,
    bool? alongRoute,
    bool? aheadLine,
  }) => MapStopsSettings(
    shown: shown ?? this.shown,
    kinds: kinds ?? this.kinds,
    alongRoute: alongRoute ?? this.alongRoute,
    aheadLine: aheadLine ?? this.aheadLine,
  );

  @override
  bool operator ==(Object other) =>
      other is MapStopsSettings &&
      other.shown == shown &&
      other.alongRoute == alongRoute &&
      other.aheadLine == aheadLine &&
      setEquals(other.kinds, kinds);

  @override
  int get hashCode =>
      Object.hash(shown, alongRoute, aheadLine, Object.hashAllUnordered(kinds));

  @override
  String toString() =>
      'MapStopsSettings(shown: $shown, kinds: ${kinds.join(',')}, '
      'alongRoute: $alongRoute, aheadLine: $aheadLine)';
}

/// The stops the map shows, remembered across launches.
@Riverpod(keepAlive: true)
class MapStopsPreferences extends _$MapStopsPreferences {
  @override
  MapStopsSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final kinds = prefs.getStringList(_prefsStopsKinds);
    return MapStopsSettings(
      shown: prefs.getBool(_prefsStopsShown) ?? true,
      kinds: kinds == null ? defaultStopKinds : Set<String>.unmodifiable(kinds),
      alongRoute: prefs.getBool(_prefsStopsAlongRoute) ?? true,
      // Off until the rider asks for it: a line over the ride map is chrome
      // not every rider wants.
      aheadLine: prefs.getBool(_prefsStopsAheadLine) ?? false,
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

  /// With a route to be along, along it or in the area on screen.
  Future<void> setAlongRoute(bool value) async {
    state = state.copyWith(alongRoute: value);
    await ref
        .read(sharedPreferencesProvider)
        .setBool(_prefsStopsAlongRoute, value);
  }

  /// Lists the next stops on the ride screen, or stops listing them.
  Future<void> setAheadLine(bool value) async {
    state = state.copyWith(aheadLine: value);
    await ref
        .read(sharedPreferencesProvider)
        .setBool(_prefsStopsAheadLine, value);
  }
}

const String _prefsCycleMapShown = 'map.cycle_map.shown';
const String _prefsCycleMapParts = 'map.cycle_map.parts';
const String _prefsCycleMapKnown = 'map.cycle_map.known';

/// The offline cycle map's settings, remembered across launches.
@Riverpod(keepAlive: true)
class CycleMapPreferences extends _$CycleMapPreferences {
  @override
  CycleMapSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final names = prefs.getStringList(_prefsCycleMapParts);
    // A part added since the rider last chose starts as its default; one
    // they knew keeps their choice.
    final known = prefs.getStringList(_prefsCycleMapKnown) ?? names;
    return CycleMapSettings(
      // Shown until the rider says otherwise, unless they chose the CyclOSM
      // overlay, which draws the same ways.
      shown:
          prefs.getBool(_prefsCycleMapShown) ??
          !(prefs.getBool(_prefsCyclosm) ?? false),
      parts: names == null
          ? defaultCycleMapParts
          : Set<CycleMapPart>.unmodifiable(<CycleMapPart>{
              for (final part in CycleMapPart.values)
                if (names.contains(part.name) ||
                    !known!.contains(part.name) &&
                        defaultCycleMapParts.contains(part))
                  part,
            }),
    );
  }

  /// Draws the cycle map or takes it away; drawing it takes the CyclOSM
  /// overlay away, which shows the same ways.
  Future<void> setShown(bool value) async {
    if (value == state.shown) return;
    state = state.copyWith(shown: value);
    await ref
        .read(sharedPreferencesProvider)
        .setBool(_prefsCycleMapShown, value);
    if (value && ref.read(cyclosmOverlayProvider)) {
      await ref.read(cyclosmOverlayProvider.notifier).set(false);
    }
  }

  /// Draws [part] or stops drawing it.
  Future<void> setPart(CycleMapPart part, {required bool shown}) async {
    final parts = Set<CycleMapPart>.of(state.parts);
    if (shown) {
      parts.add(part);
    } else {
      parts.remove(part);
    }
    state = state.copyWith(parts: Set<CycleMapPart>.unmodifiable(parts));
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setStringList(
      _prefsCycleMapParts,
      <String>[for (final part in parts) part.name]..sort(),
    );
    await prefs.setStringList(_prefsCycleMapKnown, <String>[
      for (final part in CycleMapPart.values) part.name,
    ]);
  }
}

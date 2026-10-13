import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../map/data/weather_map_preferences.dart';

import '../../../core/geo/route_gradient.dart';
import '../../../core/geo/track_surface.dart';
import '../../map/domain/map_controller.dart';
import '../../planner/application/planner_controller.dart';
import '../../planner/application/track_surface_service.dart';
import '../../planner/data/route_repository.dart';
import '../../recording/domain/ride_range.dart';
import '../domain/route_weather_state.dart';
import '../data/dwd_route_forecast.dart';
import 'free_route_weather.dart';
import 'route_overlay.dart';
import 'route_weather_controller.dart';
import 'route_wind.dart';

part 'route_colouring.g.dart';

/// A stretch of a route, in metres from its start, and what colours it.
typedef RouteRun<K> = ({double startM, double endM, K key});

/// What a route is coloured by, along it: the stretches in metres, which the
/// elevation chart under the route shades, and the same stretches cut out
/// of the route's line, which the map draws over it.
///
/// The wind and the surface keep their classes, as the map and the chart
/// colour them from the theme; the gradient and the rain carry their
/// colours (0xRRGGBB). The surface's stretches on the line are
/// [surfaceLines], not in [lines], since their colours come from the theme
/// only where it is known (`routeColourLinesOf`).
@immutable
class RouteColouring {
  /// Creates the colouring.
  const RouteColouring({
    this.wind = const <RouteRun<WindClassOnMap>>[],
    this.colours = const <RouteRun<int>>[],
    this.surface = const <RouteRun<SurfaceKind>>[],
    this.lines = RouteColourLines.none,
    this.surfaceLines = const <SurfaceSegment>[],
  });

  /// Nothing coloured.
  static const RouteColouring none = RouteColouring();

  /// The wind's stretches.
  final List<RouteRun<WindClassOnMap>> wind;

  /// The stretches in colours of their own: the gradient's or the rain's.
  final List<RouteRun<int>> colours;

  /// The surface's stretches.
  final List<RouteRun<SurfaceKind>> surface;

  /// The wind's and the coloured stretches on the route's line, for the
  /// map.
  final RouteColourLines lines;

  /// The surface's stretches on the route's line, for the map.
  final List<SurfaceSegment> surfaceLines;

  /// Whether nothing is coloured.
  bool get isEmpty => wind.isEmpty && colours.isEmpty && surface.isEmpty;
}

/// One stretch of the route's line of one [SurfaceKind].
typedef SurfaceSegment = ({List<LatLng> points, SurfaceKind kind});

/// The gradient along [geometry] as colours, [gradientRunsOf] keyed by
/// [gradientClassColour].
List<RouteRun<int>> gradientColourRuns(List<TrackPoint> geometry) =>
    <RouteRun<int>>[
      for (final run in gradientRunsOf(geometry))
        (
          startM: run.startM,
          endM: run.endM,
          key: gradientClassColour(run.gradient),
        ),
    ];

/// What the route along [geometry] is coloured by when [overlay] is chosen:
/// nothing while colouring is off (`null`) or there is no route; its
/// gradient from its own heights; its [surface] stretches, nothing while
/// they are unknown; the wind or the rain from [weather], and nothing while
/// that is on its way, failed, or not this route's.
RouteColouring routeColouringFor(
  List<TrackPoint>? geometry,
  AsyncValue<RouteWeatherState?> weather,
  RouteOverlay? overlay, {
  List<SurfaceRun>? surface,
}) {
  if (overlay == null || geometry == null || geometry.length < 2) {
    return RouteColouring.none;
  }
  final positions = geometry.map((p) => p.pos).toList(growable: false);
  final along = cumulativeDistancesMeters(positions);
  // Each run cut out of the line, in one walk along it, with its key.
  List<(List<LatLng>, K)> cut<K>(List<RouteRun<K>> runs) {
    final slices = trackSlices(
      positions,
      along,
      runs.map((r) => (startM: r.startM, endM: r.endM)),
    );
    return [
      for (var i = 0; i < runs.length; i++)
        if (slices[i].length >= 2) (slices[i], runs[i].key),
    ];
  }

  RouteColouring coloured(List<RouteRun<int>> runs) => RouteColouring(
    colours: runs,
    lines: RouteColourLines(
      colours: [
        for (final (points, colour) in cut(runs))
          ColouredSegment(points: points, colour: colour),
      ],
    ),
  );

  if (overlay == RouteOverlay.gradient) {
    return coloured(gradientColourRuns(geometry));
  }
  if (overlay == RouteOverlay.surface) {
    if (surface == null || surface.isEmpty) return RouteColouring.none;
    final runs = <RouteRun<SurfaceKind>>[
      for (final run in surface)
        (startM: run.startM, endM: run.endM, key: run.kind),
    ];
    return RouteColouring(
      surface: runs,
      surfaceLines: [
        for (final (points, kind) in cut(runs)) (points: points, kind: kind),
      ],
    );
  }
  final value = weather.isLoading || weather.hasError ? null : weather.value;
  if (value == null) return RouteColouring.none;
  final total = along.last;
  if (overlay == RouteOverlay.rain) return coloured(rainRuns(total, value));
  final runs = windRuns(total, value);
  return RouteColouring(
    wind: runs,
    lines: RouteColourLines(
      wind: [
        for (final (points, windClass) in cut(runs))
          WindSegment(points: points, windClass: windClass),
      ],
    ),
  );
}

/// The line of [route] with its heights: the Plan tab's route, or a saved
/// one; `null` while there is none.
@riverpod
List<TrackPoint>? weatherRouteGeometry(Ref ref, WeatherRoute route) =>
    switch (route) {
      PlannerWeatherRoute() => ref.watch(
        plannerControllerProvider.select((s) => s.result?.geometry),
      ),
      SavedWeatherRoute(:final id) => ref.watch(
        savedRouteProvider(id).select((r) => r.value?.geometry),
      ),
    };

/// The weather [route] is coloured by, and the one its weather section
/// shows: the relay's forecast with Velorki Plus
/// ([routeWeatherFromRelayProvider]), the free one the phone loads itself
/// without ([freeRouteWeatherProvider]); for the moment the time
/// control stands on, and while it is dragged
/// ([weatherRadarPreviewProvider]) for the step under the finger, live.
///
/// Dragged, the relay's answer is evaluated for that step on the phone; the
/// free forecast is worked out from the grids already loaded, fetched ahead
/// for every step while this is watched ([FreeForecastPrefetch]). A step
/// they do not cover keeps the colours shown last, and the step let go is
/// asked for as ever. While the free forecast loads again for the same line
/// (a new step, another speed), the grids loaded colour it if they can, else
/// the colours shown last stand; for another line they are cleared.
@riverpod
class RouteColourWeather extends _$RouteColourWeather {
  @override
  AsyncValue<RouteWeatherState?> build(WeatherRoute route) {
    final last = stateOrNull?.value;
    final preview = ref.watch(weatherRadarPreviewProvider);
    if (ref.watch(routeWeatherFromRelayProvider)) {
      final plus = ref.watch(routeWeatherControllerProvider(route));
      final s = plus.value;
      if (preview == null || plus.isLoading || plus.hasError || s == null) {
        return plus;
      }
      final departure = s.earliestDeparture.add(Duration(minutes: preview));
      if (departure == s.departure) return plus;
      if (s.covers(departure)) {
        return AsyncData<RouteWeatherState?>(s.withDeparture(departure));
      }
      return AsyncData<RouteWeatherState?>(last ?? s);
    }
    ref.watch(freeForecastPrefetchProvider(route));
    final committed = ref.watch(freeRouteWeatherProvider(route));
    if (preview == null && !committed.isLoading) return committed;
    final geometry = ref.watch(weatherRouteGeometryProvider(route));
    final samples = ref.watch(freeRouteSamplesProvider(route));
    if (geometry == null || samples == null) return committed;
    final live = freeWeatherFromLoaded(
      ref.watch(dwdForecastClientProvider),
      samples,
      ref.read(weatherClockProvider)(),
      preview ?? ref.watch(weatherRadarOffsetProvider),
    );
    if (live != null) {
      freeForecastGeometry[live] = geometry;
      return AsyncData<RouteWeatherState?>(live);
    }
    for (final shown in [last, committed.value]) {
      if (shown != null && _sameLine(freeForecastGeometry[shown], geometry)) {
        return AsyncData<RouteWeatherState?>(shown);
      }
    }
    return committed;
  }
}

/// Whether [a] and [b] are the same line, point for point.
bool _sameLine(List<TrackPoint>? a, List<TrackPoint>? b) {
  if (identical(a, b)) return a != null;
  if (a == null || b == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].pos != b[i].pos) return false;
  }
  return true;
}

/// What [route] is coloured by, on the map and under its elevation chart:
/// [routeColouringFor] with what is shown ([routeOverlayShownProvider]),
/// nothing while colouring is off ([routeColouringOnProvider]). The weather
/// is only watched while the wind or the rain is shown, the surface while
/// it is.
@riverpod
RouteColouring routeColouring(Ref ref, WeatherRoute route) {
  if (!ref.watch(routeColouringOnProvider)) return RouteColouring.none;
  final overlay = ref.watch(routeOverlayShownProvider);
  final geometry = ref.watch(weatherRouteGeometryProvider(route));
  return routeColouringFor(
    geometry,
    isWeatherOverlay(overlay)
        ? ref.watch(routeColourWeatherProvider(route))
        : const AsyncData<RouteWeatherState?>(null),
    overlay,
    surface: overlay == RouteOverlay.surface
        ? ref.watch(routeSurfaceRunsProvider(route)).value
        : null,
  );
}

/// The stretches of [route] by what they are paved with ([SurfaceKind]),
/// in metres along its line; `null` where that cannot be known.
///
/// A route the router drew has its ways in its messages. One it did not —
/// a route read from a file, a saved route, whose messages are not stored —
/// is matched against the routing tiles on the phone ([matchedSurfaceRunsProvider]),
/// kept in memory only. Loading while that runs; `null` for a track that
/// could not be matched, without on-device routing, or whose tiles are not
/// on the phone.
@riverpod
AsyncValue<List<SurfaceRun>?> routeSurfaceRuns(Ref ref, WeatherRoute route) {
  switch (route) {
    case PlannerWeatherRoute():
      final (result, matched) = ref.watch(
        plannerControllerProvider.select(
          (s) => (s.result, s.matchedSurface?.value?.state),
        ),
      );
      if (result == null || result.geometry.length < 2) {
        return const AsyncData<List<SurfaceRun>?>(null);
      }
      if (result.messages.isNotEmpty) {
        return AsyncData<List<SurfaceRun>?>(
          surfaceRunsOf(
            result.messages,
            polylineLengthMeters([for (final p in result.geometry) p.pos]),
          ),
        );
      }
      if (matched == TrackSurfaceState.unmatched ||
          matched == TrackSurfaceState.noRouting) {
        return const AsyncData<List<SurfaceRun>?>(null);
      }
      return ref.watch(
        matchedSurfaceRunsProvider(
          SurfaceTrack(result.geometry, result.lengthM),
        ),
      );
    case SavedWeatherRoute(:final id):
      final saved = ref.watch(
        savedRouteProvider(id).select(
          (r) => switch (r.value) {
            null => r.isLoading ? null : (track: null, unavailable: true),
            final s => (
              track: SurfaceTrack(s.geometry, s.distanceM),
              unavailable: s.surfaceUnavailable,
            ),
          },
        ),
      );
      if (saved == null) return const AsyncLoading<List<SurfaceRun>?>();
      final track = saved.track;
      if (saved.unavailable || track == null || track.geometry.length < 2) {
        return const AsyncData<List<SurfaceRun>?>(null);
      }
      return ref.watch(matchedSurfaceRunsProvider(track));
  }
}

/// A track to match against the routing tiles, [distanceM] long, compared
/// by its points, so the same line read again is the same track.
@immutable
class SurfaceTrack {
  /// Creates the track of [geometry].
  SurfaceTrack(this.geometry, this.distanceM)
    : _hash = Object.hash(
        distanceM,
        Object.hashAll(geometry.map((p) => p.pos)),
      );

  /// Its points.
  final List<TrackPoint> geometry;

  /// Its length, in metres.
  final double distanceM;

  final int _hash;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SurfaceTrack ||
        other._hash != _hash ||
        other.distanceM != distanceM ||
        other.geometry.length != geometry.length) {
      return false;
    }
    for (var i = 0; i < geometry.length; i++) {
      if (other.geometry[i].pos != geometry[i].pos) return false;
    }
    return true;
  }

  @override
  int get hashCode => _hash;
}

/// The surface stretches of tracks matched since the tiles last changed,
/// the last few, so turning the surface colouring off and on again does
/// not route a long track once more.
@Riverpod(keepAlive: true)
Map<SurfaceTrack, List<SurfaceRun>?> matchedSurfaceCache(Ref ref) {
  ref.watch(trackSurfaceServiceProvider);
  return <SurfaceTrack, List<SurfaceRun>?>{};
}

/// How many matched tracks [matchedSurfaceCacheProvider] keeps.
const int _matchedSurfaceKept = 8;

/// The surface stretches of [track], matched against the routing tiles
/// (`TrackSurfaceService.matchWays`) and laid on its line; `null` when it
/// could not be. A track whose tiles are missing is not remembered, so it
/// is matched again once they are there.
@riverpod
Future<List<SurfaceRun>?> matchedSurfaceRuns(
  Ref ref,
  SurfaceTrack track,
) async {
  final cache = ref.watch(matchedSurfaceCacheProvider);
  if (cache.containsKey(track)) return cache[track];
  final ways = await ref
      .watch(trackSurfaceServiceProvider)
      .matchWays(points: track.geometry, distanceM: track.distanceM);
  final runs = ways.state == TrackSurfaceState.matched
      ? surfaceRunsOf(
          ways.messages,
          polylineLengthMeters([for (final p in track.geometry) p.pos]),
        )
      : null;
  if (ways.state != TrackSurfaceState.noTiles) {
    cache.remove(track);
    cache[track] = runs;
    while (cache.length > _matchedSurfaceKept) {
      cache.remove(cache.keys.first);
    }
  }
  return runs;
}

/// What the Plan tab's time control is (`weatherRadarOffsetProvider`).
enum PlannerTimeControl {
  /// No route: the moment the map's rain and wind show, while either is on.
  map,

  /// A route, whose weather the section under it shows for everyone: also
  /// its departure ("Leave now", "Leave +45 min"), which the route's
  /// forecast follows, shown whether the map's rain and wind are on or not.
  departureShown,
}

/// What the Plan tab's time control is: [PlannerTimeControl].
@riverpod
PlannerTimeControl plannerTimeControl(Ref ref) {
  final geometry = ref.watch(weatherRouteGeometryProvider(plannerWeatherRoute));
  if (geometry == null || geometry.length < 2) return PlannerTimeControl.map;
  return PlannerTimeControl.departureShown;
}

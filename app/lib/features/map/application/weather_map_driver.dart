import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../data/weather_fetcher.dart';
import '../data/weather_map_preferences.dart';
import '../data/weather_paint.dart';
import '../domain/map_controller.dart';
import '../domain/weather_map.dart';
import '../domain/wind_field.dart';

/// How often the radar looks for a newer frame while it is on.
const Duration radarRefreshInterval = Duration(minutes: 5);

/// How often the clouds do.
const Duration cloudsRefreshInterval = Duration(minutes: 10);

/// How long the camera rests before the clouds' detail image is asked
/// for: a pan of a few flicks asks once, at its end.
const Duration cloudDetailDebounce = Duration(milliseconds: 600);

/// How long the camera rests before the soft radar's image of the view is
/// asked for.
const Duration radarImageDebounce = Duration(milliseconds: 400);

/// How often the wind looks for a newer grid while it is on: the hour may
/// have turned, or the grid shown be older than [windCacheMaxAge].
const Duration windRefreshInterval = Duration(minutes: 15);

/// How long the camera rests before the wind of the view is asked for.
const Duration windDebounce = Duration(milliseconds: 400);

/// The zoom the radar's probe tile is asked at: low, so it is one cheap
/// tile around the middle of the view.
const int weatherProbeZoom = 5;

/// What the weather layers on a map say about themselves, for the time
/// control and its hints.
@immutable
class WeatherMapStatus {
  /// Creates the status.
  const WeatherMapStatus({
    this.centre,
    this.at,
    this.cloudsFrame,
    this.failed = const <WeatherKind>{},
    this.failedRain = const <RainRole>{},
  });

  /// The middle of the view, whose rain the time control's label describes
  /// (see `rainAtPoint`); `null` without a view.
  final LatLng? centre;

  /// When this was worked out: the clock the label's moments are read by.
  final DateTime? at;

  /// The moment the clouds in view show, UTC, where the service names it.
  final DateTime? cloudsFrame;

  /// The kinds of which a source over the view did not answer.
  final Set<WeatherKind> failed;

  /// Of the rain, which sources over the view did not answer: the radar,
  /// the satellite, the forecast.
  final Set<RainRole> failedRain;

  @override
  bool operator ==(Object other) =>
      other is WeatherMapStatus &&
      other.centre == centre &&
      other.at == at &&
      other.cloudsFrame == cloudsFrame &&
      setEquals(other.failed, failed) &&
      setEquals(other.failedRain, failedRain);

  @override
  int get hashCode => Object.hash(
    centre,
    at,
    cloudsFrame,
    Object.hashAllUnordered(failed),
    Object.hashAllUnordered(failedRain),
  );

  @override
  String toString() =>
      'WeatherMapStatus(centre: $centre, at: $at, clouds: $cloudsFrame, '
      'failed: $failed, failedRain: $failedRain)';
}

/// Keeps one map drawing the weather layers the settings ask for: the
/// sources whose coverage meets the view, at the frame the time control
/// and the clock say, refreshed every few minutes while the app is in the
/// foreground.
///
/// Radar is tiles the map loads itself; whether a radar service answers is
/// checked with one tile ([WeatherFetcher.probe]) when the layer comes on,
/// on each refresh and when the view first enters the source's coverage.
/// Clouds are one image per region, which this driver fetches; that fetch
/// is their check. Zoomed in to [cloudDetailMinZoom] and more, each cloud
/// source also gets a finer image of the view's surroundings once the
/// camera has rested ([cloudDetailDebounce]), drawn over the region's and
/// replaced when the view leaves it or the zoom moves on; one request per
/// source at a time, an answer for a view since left dropped.
///
/// The rain is the sources [rainPartsAt] picks for the time control's step:
/// the radars, the satellite around them at "Now", the DWD's nowcast and
/// the models ahead, each masked where one before it shows the same step:
/// drawn soft, by where the DWD's image of that step and view measures
/// ([RainCoverage]), so a source after it waits for that image and is cut
/// anew with each; nothing after it is asked for where it measures all over
/// the view.
/// Radar drawn soft ([RadarStyle.soft]), the satellite and the models are
/// one image of the view and its surroundings per source instead of tiles,
/// fetched and prepared by this driver once the camera has rested
/// ([radarImageDebounce]), at once when the time control or the style
/// changes, and with each refresh; the image shown stays until the next is
/// in, one request per source at a time, an answer for a view, moment or
/// mask since left dropped. That fetch is the source's check, in place of
/// the probe.
///
/// The wind is one grid of the view and its margin ([windRequestFor]) at
/// the time control's hour, fetched once the camera has rested
/// ([windDebounce]), at once when the step changes, and again when the
/// hour turns or the grid is older than [windCacheMaxAge]; from it the
/// arrows over the view are worked out on the phone ([windArrowsFor]) at
/// every rest of the camera. One request at a time, an answer for a view
/// or moment since left dropped; the grid shown stays until the next is
/// in. Not below [weatherImageMinZoom]. That fetch is the wind's check.
///
/// A source that does not answer is reported in [status], so the map can
/// say so instead of looking like a dry, clear day.
class WeatherMapDriver {
  /// A driver fetching through [fetcher], telling the time by [clock].
  WeatherMapDriver({required this._fetcher, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final WeatherFetcher _fetcher;
  final DateTime Function() _clock;
  MapController? _map;
  WeatherMapSettings _settings = const WeatherMapSettings();
  List<WeatherMapSource> _sources = const <WeatherMapSource>[];
  int _offset = 0;
  RadarStyle _radarStyle = RadarStyle.soft;
  bool _foreground = true;
  bool _disposed = false;
  Timer? _radarTimer;
  Timer? _cloudsTimer;
  Timer? _detailTimer;
  Timer? _radarImageTimer;
  Timer? _windTimer;
  Timer? _windRefreshTimer;

  /// The wind grid shown, the request in flight (its key) and the last
  /// one that failed, which is not asked again for until the next
  /// refresh, step or switch.
  _WindShown? _wind;
  String? _windInFlight;
  String? _windFailed;

  /// The arrows last handed to the map.
  WindArrows? _windDrawn;

  /// The probe URL each radar source was last checked with.
  final Map<String, String> _probed = <String, String>{};

  /// The sources that did not answer the last check.
  final Set<String> _failed = <String>{};

  /// The sources over the view at the last update.
  Set<String> _covering = <String>{};

  /// The last cloud image of each region (`source.region`), and the frame
  /// last asked for it: one that failed is asked again with the next
  /// refresh, not with every move of the map.
  final Map<String, WeatherLayer> _images = <String, WeatherLayer>{};
  final Map<String, String> _attempted = <String, String>{};

  /// Each cloud source's detail image, the request in flight for it (its
  /// key) and the last one that failed, which is not asked again for until
  /// the next refresh.
  final Map<String, _CloudDetail> _details = <String, _CloudDetail>{};
  final Map<String, String> _detailInFlight = <String, String>{};
  final Map<String, String> _detailFailed = <String, String>{};

  /// Each radar source's soft image, the request in flight for it (its
  /// key) and the last one that failed, which is not asked again for until
  /// the next refresh, step or look.
  final Map<String, _RadarImage> _radarImages = <String, _RadarImage>{};
  final Map<String, String> _radarInFlight = <String, String>{};
  final Map<String, String> _radarFailed = <String, String>{};

  /// The radar sources switched to soft while drawn as tiles: their tiles
  /// stay until the first soft image is in or fails, so the switch leaves
  /// no gap.
  final Set<String> _tilesUntilSoft = <String>{};

  List<WeatherLayer> _drawn = const <WeatherLayer>[];
  DateTime? _cloudsFrame;
  LatLng? _centre;
  DateTime? _clockAt;

  final ValueNotifier<WeatherMapStatus> _status =
      ValueNotifier<WeatherMapStatus>(const WeatherMapStatus());

  /// What the layers say about themselves.
  ValueListenable<WeatherMapStatus> get status => _status;

  /// Draws on [map] from now on: a new map, or a fresh one after a style
  /// reload.
  void attach(MapController map) {
    if (identical(map, _map)) return;
    detach(clear: false);
    _map = map;
    _drawn = const <WeatherLayer>[];
    _windDrawn = null;
    map.addCameraIdleListener(_onCameraIdle);
    _update();
    _resetTimers();
    _scheduleDetails();
    _planRadar();
    _planWind();
  }

  /// Lets the map go, taking the layers off it when [clear] is true.
  void detach({bool clear = true}) {
    final map = _map;
    if (map == null) return;
    map.removeCameraIdleListener(_onCameraIdle);
    if (clear && _drawn.isNotEmpty) {
      unawaited(map.setWeatherLayers(const <WeatherLayer>[]));
    }
    if (clear && _windDrawn != null) unawaited(map.setWindArrows(null));
    _drawn = const <WeatherLayer>[];
    _windDrawn = null;
    _map = null;
    _detailTimer?.cancel();
    _detailTimer = null;
    _radarImageTimer?.cancel();
    _radarImageTimer = null;
    _windTimer?.cancel();
    _windTimer = null;
    _resetTimers();
  }

  /// Follows new settings, sources, the time control's [offsetMinutes] and
  /// the [radarStyle].
  void configure({
    required WeatherMapSettings settings,
    required List<WeatherMapSource> sources,
    required int offsetMinutes,
    RadarStyle radarStyle = RadarStyle.soft,
  }) {
    if (settings == _settings &&
        listEquals(sources, _sources) &&
        offsetMinutes == _offset &&
        radarStyle == _radarStyle) {
      return;
    }
    if (radarStyle != _radarStyle) {
      // The other look is checked afresh; tiles drawn now stay until the
      // soft image replaces them.
      for (final source in _sources) {
        if (source.kind != WeatherKind.radar) continue;
        _probed.remove(source.id);
        _failed.remove(source.id);
      }
      _tilesUntilSoft
        ..clear()
        ..addAll(<String>{
          if (radarStyle == RadarStyle.soft)
            for (final layer in _drawn)
              if (layer.kind == WeatherKind.radar && layer.tiles != null)
                layer.id,
        });
      // The images shown stay until those in the new look replace them.
      _radarFailed.clear();
      _radarStyle = radarStyle;
    }
    final turnedOn = <WeatherKind>{
      for (final kind in WeatherKind.values)
        if (settings.shows(kind) && !_settings.shows(kind)) kind,
    };
    // Another step of the time control: what failed for the last one is
    // asked again.
    if (offsetMinutes != _offset) _radarFailed.clear();
    _settings = settings;
    _sources = sources;
    _offset = offsetMinutes;
    // A layer switched on is checked afresh.
    for (final source in sources) {
      if (turnedOn.contains(source.kind)) {
        _probed.remove(source.id);
        _failed.remove(source.id);
      }
    }
    if (turnedOn.contains(WeatherKind.clouds)) {
      _attempted.clear();
      _detailFailed.clear();
    }
    if (turnedOn.contains(WeatherKind.radar)) _radarFailed.clear();
    if (turnedOn.contains(WeatherKind.wind)) _windFailed = null;
    if (offsetMinutes != _offset) _windFailed = null;
    // Clouds switched off let their images go, and so does the radar.
    if (!settings.clouds) {
      _images.clear();
      _details.clear();
    }
    if (!settings.radar) {
      _radarImages.clear();
      _tilesUntilSoft.clear();
    }
    if (!settings.wind) {
      _wind = null;
      _windFailed = null;
    }
    _update();
    _resetTimers();
    _scheduleDetails();
    _planRadar();
    _planWind();
  }

  /// Whether the app is in the foreground: refreshes run only then, and
  /// coming back checks at once.
  void setForeground(bool foreground) {
    if (foreground == _foreground) return;
    _foreground = foreground;
    if (foreground) {
      _attempted.clear();
      _detailFailed.clear();
      _radarFailed.clear();
      _windFailed = null;
      _update(recheck: true);
    }
    _resetTimers();
    _scheduleDetails();
    _planRadar();
    _planWind();
  }

  /// Stops for good.
  void dispose() {
    _disposed = true;
    detach(clear: false);
    _radarTimer?.cancel();
    _cloudsTimer?.cancel();
    _detailTimer?.cancel();
    _radarImageTimer?.cancel();
    _windTimer?.cancel();
    _windRefreshTimer?.cancel();
    _status.dispose();
  }

  void _onCameraIdle() {
    _update();
    _scheduleDetails();
    _scheduleRadar();
    _scheduleWind();
  }

  /// Asks for the wind of the view once the camera has rested; only while
  /// the wind is on, on a map, in the foreground.
  void _scheduleWind() {
    _windTimer?.cancel();
    _windTimer = null;
    if (_disposed || _map == null || !_foreground || !_settings.wind) return;
    _windTimer = Timer(windDebounce, _planWind);
  }

  /// Asks for the rain's images once the camera has rested; only while
  /// the rain is on, on a map, in the foreground.
  void _scheduleRadar() {
    _radarImageTimer?.cancel();
    _radarImageTimer = null;
    if (_disposed || _map == null || !_foreground || !_settings.radar) return;
    _radarImageTimer = Timer(radarImageDebounce, _planRadar);
  }

  /// Asks for the detail images once the camera has rested; only while
  /// the clouds are on, on a map, in the foreground.
  void _scheduleDetails() {
    _detailTimer?.cancel();
    _detailTimer = null;
    if (_disposed || _map == null || !_foreground || !_settings.clouds) {
      return;
    }
    _detailTimer = Timer(cloudDetailDebounce, _planDetails);
  }

  void _resetTimers() {
    _radarTimer?.cancel();
    _cloudsTimer?.cancel();
    _windRefreshTimer?.cancel();
    _radarTimer = null;
    _cloudsTimer = null;
    _windRefreshTimer = null;
    if (_disposed || _map == null || !_foreground) return;
    if (_settings.wind) {
      _windRefreshTimer = Timer.periodic(windRefreshInterval, (_) {
        _windFailed = null;
        _update();
        _planWind();
      });
    }
    if (_settings.radar) {
      _radarTimer = Timer.periodic(radarRefreshInterval, (_) {
        _radarFailed.clear();
        _update(recheck: true);
        _planRadar();
      });
    }
    if (_settings.clouds) {
      _cloudsTimer = Timer.periodic(cloudsRefreshInterval, (_) {
        _attempted.clear();
        _detailFailed.clear();
        _update();
        _planDetails();
      });
    }
  }

  Iterable<WeatherMapSource> _enabled(WeatherKind kind) => _sources.where(
    (s) => s.enabled && s.kind == kind && _settings.shows(kind),
  );

  /// Works out what is drawn now and hands it to the map. [recheck] checks
  /// every radar over the view again, as a refresh does.
  void _update({bool recheck = false}) {
    if (_disposed) return;
    final map = _map;
    if (map == null) return;
    final view = map.visibleBounds;
    final now = _clock();
    final layers = <WeatherLayer>[];
    final covering = <String>{};

    // Clouds first, which is under the rain.
    _cloudsFrame = null;
    final zoom = map.zoom;
    final detailed = zoom != null && zoom >= cloudDetailMinZoom;
    final shownDetails = <String>{};
    for (final source in _enabled(WeatherKind.clouds)) {
      if (view == null || !source.covers(view)) continue;
      final frame = source.frameAt(now);
      if (frame == null) continue;
      covering.add(source.id);
      _cloudsFrame ??= frame.time;
      final stamp = cloudImageStamp(frame, now);
      for (var region = 0; region < source.coverage.length; region++) {
        if (!_regionMeets(source.coverage[region], view)) continue;
        // A box MapLibre cannot draw (a mirror's override) is not fetched.
        if (!safeImageBox(source.coverage[region])) continue;
        final key = '${source.id}.$region';
        final frameKey = '$key@$stamp';
        // The last image of the region stays until the next one is in.
        final shown = _images[key];
        if (shown != null) layers.add(shown);
        if (shown?.frameKey != frameKey && _attempted[key] != frameKey) {
          _attempted[key] = frameKey;
          unawaited(_loadCloud(source, region, frame, now, key, frameKey));
        }
      }
      // The detail over the region's image, the last one until the next
      // is in.
      final detail = _details[source.id];
      if (detailed && detail != null) {
        layers.add(detail.layer);
        shownDetails.add(source.id);
      }
    }
    // Zoomed out, off or out of view: the details go.
    _details.removeWhere((id, _) => !shownDetails.contains(id));

    // The rain: each source with a frame for the step over the view, each
    // leaving the reach of those before it to them.
    _centre = view?.center;
    _clockAt = now;
    final parts = view == null
        ? const <RainPart>[]
        : rainPartsAt(_enabled(WeatherKind.radar), now, _offset, view: view);
    final shownParts = <String>{for (final part in parts) part.source.id};
    for (final source in _enabled(WeatherKind.radar)) {
      // Out of the view or without the moment: checked again when back.
      if (!shownParts.contains(source.id)) _probed.remove(source.id);
    }
    final imageShown = <String>{};
    final imagesTooFar =
        view != null && _zoomOf(view, zoom) < weatherImageMinZoom;
    for (final part in parts) {
      final source = part.source;
      final frame = part.frame;
      if (imagesTooFar && _drawnAsImage(source)) {
        // Zoomed out too far for an image of the view: none, and no probe.
        _probed.remove(source.id);
        continue;
      }
      final mask = _maskOf(part, parts, view!, zoom, now);
      // Wholly left to those before it: nothing to draw, nothing to ask.
      if (mask != null && mask.hides) continue;
      covering.add(source.id);
      if (_imageBoxOf(source, view, zoom) != null) {
        // An image: the one shown stays until the next is in, unless the
        // next failed and it shows another moment. No probe: the fetch
        // checks. While the frames it is cut by are still out, the one
        // shown stays too.
        _probed.remove(source.id);
        imageShown.add(source.id);
        final shown = _radarImages[source.id];
        final stamp = mask == null ? null : _stampOf(part, now, mask.key);
        if (shown != null &&
            (shown.stamp == stamp || !_failed.contains(source.id))) {
          layers.add(shown.layer);
          continue;
        }
        if (!_tilesUntilSoft.contains(source.id)) continue;
        // Just switched to soft: the tiles until the image is in.
        layers.add(WeatherLayer.ofRadar(source, frame, now));
        continue;
      }
      layers.add(WeatherLayer.ofRadar(source, frame, now));
      final probe = source.probeUrl(frame, view.center, weatherProbeZoom);
      if (recheck || _probed[source.id] != probe) {
        _probed[source.id] = probe;
        unawaited(_probe(source.id, probe));
      }
    }
    // Out of view, off, without the moment or back on tiles: the images
    // go.
    _radarImages.removeWhere((id, _) => !imageShown.contains(id));
    _tilesUntilSoft.removeWhere((id) => !imageShown.contains(id));

    // The wind, over the rest: the arrows of the grid shown over the view.
    final wind = _windSource();
    WindArrows? arrows;
    if (wind != null && view != null) {
      final z = _zoomOf(view, zoom);
      if (windRequestFor(view, z) != null) {
        covering.add(wind.id);
        final shown = _wind;
        if (shown != null && shown.source == wind.id) {
          arrows = WindArrows(
            arrows: windArrowsFor(shown.grid, view, z),
            attribution: shown.attribution,
          );
        }
      }
    }
    _covering = covering;

    if (!listEquals(layers, _drawn)) {
      _drawn = List<WeatherLayer>.unmodifiable(layers);
      unawaited(map.setWeatherLayers(_drawn));
    }
    if (arrows != _windDrawn) {
      _windDrawn = arrows;
      unawaited(map.setWindArrows(arrows));
    }
    _publish();
  }

  /// The wind source in use: the first enabled one, while the wind is on.
  WeatherMapSource? _windSource() => _enabled(WeatherKind.wind).firstOrNull;

  /// Asks for the wind of the view where the grid shown is missing, of
  /// another hour, older than [windCacheMaxAge], or no longer serves the
  /// view ([WindRequest.fits]).
  void _planWind() {
    _windTimer?.cancel();
    _windTimer = null;
    if (_disposed || !_foreground || !_settings.wind) return;
    final map = _map;
    final view = map?.visibleBounds;
    final source = _windSource();
    if (map == null || view == null || source == null) return;
    final zoom = _zoomOf(view, map.zoom);
    final now = _clock();
    final request = windRequestFor(view, zoom);
    final frame = source.frameAt(now, offsetMinutes: _offset);
    final time = frame?.time;
    if (request == null || frame == null || time == null) return;
    final shown = _wind;
    if (shown != null &&
        shown.source == source.id &&
        shown.time == time &&
        now.difference(shown.fetchedAt) < windCacheMaxAge &&
        shown.request.fits(view, zoom)) {
      return;
    }
    // One request at a time: the next is planned when it is back.
    if (_windInFlight != null) return;
    final key = '${source.id}@${request.key}@${time.millisecondsSinceEpoch}';
    // Only a request that failed waits for the refresh.
    if (_windFailed == key) return;
    _windInFlight = key;
    unawaited(_loadWind(source, request, frame, key, now));
  }

  Future<void> _loadWind(
    WeatherMapSource source,
    WindRequest request,
    WeatherFrame frame,
    String key,
    DateTime now,
  ) async {
    final grid = await _fetcher.windGrid(source, request, frame, now);
    if (_disposed) return;
    _windInFlight = null;
    if (grid == null) {
      _windFailed = key;
      _failed.add(source.id);
      // A grid of another hour does not stand in for this one.
      if (_wind != null && _wind!.time != frame.time) _wind = null;
    } else {
      _windFailed = null;
      _failed.remove(source.id);
      if (_windStillWanted(source, request, frame)) {
        _wind = _WindShown(
          source: source.id,
          request: request,
          time: frame.time!,
          grid: grid,
          fetchedAt: now,
          attribution: source.attributionFor(frame, now),
        );
      }
    }
    _update();
    // An answer for a view or moment since left is dropped; what the view
    // wants now is asked for.
    _planWind();
  }

  /// Whether a grid of [request] at [frame] still serves the map: the wind
  /// on with [source] in use, the step's hour the same and the view inside
  /// the request's area at its thinning.
  bool _windStillWanted(
    WeatherMapSource source,
    WindRequest request,
    WeatherFrame frame,
  ) {
    if (!_settings.wind || _windSource()?.id != source.id) return false;
    final map = _map;
    final view = map?.visibleBounds;
    if (map == null || view == null) return false;
    if (source.frameAt(_clock(), offsetMinutes: _offset) != frame) {
      return false;
    }
    return request.fits(view, _zoomOf(view, map.zoom));
  }

  static bool _regionMeets(BoundingBox region, BoundingBox view) =>
      WeatherMapSource(
        id: '',
        kind: WeatherKind.clouds,
        urlTemplate: '',
        coverage: <BoundingBox>[region],
        attribution: '',
      ).covers(view);

  Future<void> _probe(String id, String url) async {
    final ok = await _fetcher.probe(url);
    if (_disposed || _probed[id] != url) return;
    if (ok) {
      _failed.remove(id);
    } else {
      _failed.add(id);
    }
    _publish();
  }

  Future<void> _loadCloud(
    WeatherMapSource source,
    int region,
    WeatherFrame frame,
    DateTime now,
    String key,
    String frameKey,
  ) async {
    final image = await _fetcher.cloudImage(source, region, frame, now);
    if (_disposed) return;
    if (image == null) {
      _failed.add(source.id);
      _publish();
      return;
    }
    _failed.remove(source.id);
    _images[key] = WeatherLayer.image(
      id: key,
      kind: WeatherKind.clouds,
      image: image,
      imageBox: source.coverage[region],
      frameKey: frameKey,
      attribution: source.attributionFor(frame, now),
      opacity: source.opacity,
    );
    _update();
  }

  /// Asks for each cloud source's detail image of the view where the one
  /// shown is missing, of another moment, or no longer fits: the view
  /// left its box or the zoom moved [cloudDetailRezoom] or more.
  void _planDetails() {
    _detailTimer?.cancel();
    _detailTimer = null;
    if (_disposed || !_foreground) return;
    final map = _map;
    final view = map?.visibleBounds;
    final zoom = map?.zoom;
    if (map == null || view == null || zoom == null) return;
    if (zoom < cloudDetailMinZoom) return;
    final now = _clock();
    for (final source in _enabled(WeatherKind.clouds)) {
      if (!source.covers(view)) continue;
      final frame = source.frameAt(now);
      if (frame == null) continue;
      final stamp = cloudImageStamp(frame, now);
      final shown = _details[source.id];
      if (shown != null && shown.stamp == stamp && shown.fits(view, zoom)) {
        continue;
      }
      // One request per source: the next is planned when it is back.
      if (_detailInFlight.containsKey(source.id)) continue;
      final area = cloudDetailArea(view, zoom);
      final box = area == null ? null : source.detailBox(area);
      if (area == null || box == null) continue;
      // Never an image MapLibre cannot draw.
      if (!safeImageBox(box)) continue;
      final key = '${source.id}.detail@${cloudDetailKey(box)}@$stamp';
      // Only a request that failed waits for the refresh.
      if (_detailFailed[source.id] == key) continue;
      final planned = _CloudDetail(
        layer: WeatherLayer.image(
          id: '${source.id}.detail',
          kind: WeatherKind.clouds,
          image: Uint8List(0),
          imageBox: box,
          frameKey: key,
          attribution: source.attributionFor(frame, now),
          opacity: source.opacity,
        ),
        area: area,
        zoom: zoom,
        stamp: stamp,
      );
      // One that would be dropped when it comes is not asked for.
      if (!planned.fits(view, zoom)) continue;
      _detailInFlight[source.id] = key;
      unawaited(_loadDetail(source, planned, frame, now));
    }
  }

  Future<void> _loadDetail(
    WeatherMapSource source,
    _CloudDetail planned,
    WeatherFrame frame,
    DateTime now,
  ) async {
    final box = planned.layer.imageBox!;
    final image = await _fetcher.cloudDetailImage(source, box, frame, now);
    if (_disposed) return;
    _detailInFlight.remove(source.id);
    if (image == null) {
      _detailFailed[source.id] = planned.layer.frameKey;
      _failed.add(source.id);
      _publish();
    } else {
      _detailFailed.remove(source.id);
      _failed.remove(source.id);
      // Kept only while it still fits what the map shows: zoomed out, the
      // clouds off or the view moved on, it is dropped.
      final map = _map;
      final view = map?.visibleBounds;
      final zoom = map?.zoom;
      if (_settings.clouds &&
          view != null &&
          zoom != null &&
          zoom >= cloudDetailMinZoom &&
          planned.fits(view, zoom) &&
          _enabled(WeatherKind.clouds).any((s) => s.id == source.id)) {
        _details[source.id] = planned.withImage(image);
        _update();
      } else {
        _publish();
      }
    }
    // What the view wants now, which may have moved on while this was out.
    _planDetails();
  }

  /// The box [source]'s image of [view] shows, `null` where the source is
  /// drawn as tiles: a radar as measured, or one without an image request,
  /// or a view across the antimeridian; also `null` zoomed out below
  /// [weatherImageMinZoom] or for a box MapLibre cannot draw
  /// ([safeImageBox]). The satellite and the models are
  /// always an image, as measured too, since their images are masked.
  BoundingBox? _imageBoxOf(
    WeatherMapSource source,
    BoundingBox view,
    double? zoom,
  ) {
    if (!_drawnAsImage(source)) return null;
    final z = _zoomOf(view, zoom);
    if (z < weatherImageMinZoom) return null;
    final area = _imageAreaOf(source, view, z);
    final box = area == null ? null : source.softBox(area);
    return box != null && safeImageBox(box) ? box : null;
  }

  /// Whether [source] is drawn as an image of the view rather than tiles:
  /// one with an image request, a radar only when drawn soft.
  bool _drawnAsImage(WeatherMapSource source) {
    if (source.imageUrlTemplate == null) return false;
    return source.role != RainRole.radar || _radarStyle == RadarStyle.soft;
  }

  /// The area [source]'s image of [view] at [zoom] is asked for, before
  /// its coverage clips it: the view and its margin ([cloudDetailArea]),
  /// for a model grown to [modelMinCells] of its cells ([modelImageArea]).
  static BoundingBox? _imageAreaOf(
    WeatherMapSource source,
    BoundingBox view,
    double zoom,
  ) {
    final area = cloudDetailArea(view, zoom);
    if (area == null || source.role != RainRole.model) return area;
    return modelImageArea(source, area);
  }

  /// What tells one image of [part] from the next, besides its box: its
  /// moment, the look and what it is masked by ([maskKey], see [_maskOf]).
  String _stampOf(RainPart part, DateTime now, String maskKey) =>
      '${radarImageStamp(part.source, part.frame, now)}'
      '${_radarStyle == RadarStyle.soft ? '' : 'm'}$maskKey';

  /// What [part] (one of [parts]) is masked by over [view]: the fixed rings
  /// of those before it, and of those in [RainPart.cutBy] their frame's
  /// coverage where it is drawn soft as an image. `null` while such a frame
  /// for the step and the view is still to come: the part waits for it.
  /// Where a frame cannot be had (it failed, it is drawn as tiles, or its
  /// image carries no coverage), its fixed reach stands in.
  _RainMask? _maskOf(
    RainPart part,
    List<RainPart> parts,
    BoundingBox view,
    double? zoom,
    DateTime now,
  ) {
    if (part.cutBy.isEmpty) {
      return _RainMask(rings: part.masks, key: part.maskKey);
    }
    final rings = <List<LatLng>>[];
    final coverages = <RainCoverage>[];
    final key = StringBuffer();
    var hides = false;
    var byReach = false;
    final z = _zoomOf(view, zoom);
    for (final beforePart in parts) {
      if (identical(beforePart, part)) break;
      final before = beforePart.source;
      if (!part.cutBy.contains(before)) {
        rings.addAll(before.reachRings);
        key.write('-${before.id}');
        continue;
      }
      final beforeArea = _imageAreaOf(before, view, z);
      // An image that would not serve the view is never asked for: no
      // frame to wait for.
      final asked =
          beforeArea != null &&
          view.west <= view.east &&
          view.west >= beforeArea.west &&
          view.east <= beforeArea.east &&
          view.south >= beforeArea.south &&
          view.north <= beforeArea.north;
      final beforeBox = asked ? _imageBoxOf(before, view, zoom) : null;
      final beforeMask = beforeBox == null
          ? null
          : _maskOf(beforePart, parts, view, zoom, now);
      if (beforeBox != null && beforeMask == null) return null;
      if (beforeBox != null && beforeMask != null && !beforeMask.hides) {
        final shown = _radarImages[before.id];
        final stamp = _stampOf(beforePart, now, beforeMask.key);
        final coverage = shown?.coverage;
        if (shown != null && shown.stamp == stamp && shown.fits(view, z)) {
          if (coverage != null) {
            coverages.add(coverage);
            key.write('-${before.id}~${_hashOf(shown.layer.frameKey)}');
            if (coverage.coversAll(view)) hides = true;
            continue;
          }
        } else if (_radarFailed[before.id] !=
            '${before.id}@${cloudDetailKey(beforeBox)}@$stamp') {
          // Its frame of this step and view is still to come.
          return null;
        }
      }
      // The frame cannot be had: its fixed reach instead.
      rings.addAll(before.reachRings);
      key.write('-${before.id}');
      byReach = true;
    }
    if (byReach && part.hiddenByReach(view)) hides = true;
    return _RainMask(
      rings: rings,
      coverages: coverages,
      key: key.toString(),
      hides: hides,
    );
  }

  /// A short name for [text] in a cache key: its 32-bit FNV-1a hash.
  static String _hashOf(String text) {
    var h = 0x811C9DC5;
    for (final unit in text.codeUnits) {
      h = ((h ^ unit) * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  /// [zoom], or where the map does not say, about the zoom that shows
  /// [view] on a phone.
  static double _zoomOf(BoundingBox view, double? zoom) {
    if (zoom != null) return zoom;
    final span = view.lonSpan <= 0 ? 360.0 : view.lonSpan;
    return (math.log(360 / span) / math.ln2 + 2).clamp(0.0, 22.0);
  }

  /// Asks for each rain source's image of the view where the one shown is
  /// missing, of another moment, or no longer fits.
  void _planRadar() {
    _radarImageTimer?.cancel();
    _radarImageTimer = null;
    if (_disposed || !_foreground || !_settings.radar) return;
    final map = _map;
    final view = map?.visibleBounds;
    if (map == null || view == null) return;
    final zoom = _zoomOf(view, map.zoom);
    final now = _clock();
    final parts = rainPartsAt(
      _enabled(WeatherKind.radar),
      now,
      _offset,
      view: view,
    );
    for (final part in parts) {
      final source = part.source;
      final frame = part.frame;
      final area = _imageAreaOf(source, view, zoom);
      final box = _imageBoxOf(source, view, zoom);
      if (area == null || box == null) continue;
      // Waiting for the frames it is cut by, or wholly left to them.
      final mask = _maskOf(part, parts, view, map.zoom, now);
      if (mask == null || mask.hides) continue;
      final stamp = _stampOf(part, now, mask.key);
      final shown = _radarImages[source.id];
      if (shown != null && shown.stamp == stamp && shown.fits(view, zoom)) {
        continue;
      }
      // One request per source: the next is planned when it is back.
      if (_radarInFlight.containsKey(source.id)) continue;
      final key = '${source.id}@${cloudDetailKey(box)}@$stamp';
      // Only a request that failed waits for the refresh; one that came
      // and was replaced (another step, another view) is asked again, and
      // comes from the cache.
      if (_radarFailed[source.id] == key) continue;
      final planned = _RadarImage(
        layer: WeatherLayer.image(
          id: source.id,
          kind: WeatherKind.radar,
          image: Uint8List(0),
          imageBox: box,
          frameKey: key,
          attribution: source.attributionFor(frame, now),
          // As measured, as see-through as the radar's tiles; soft, the
          // image's alpha says it all.
          opacity: _radarStyle == RadarStyle.soft
              ? null
              : source.opacity ?? radarTone.opacity,
        ),
        area: area,
        zoom: zoom,
        stamp: stamp,
        capped: radarSoftCapped(source, box),
      );
      // An image that would not serve the view even when it comes (a view
      // beyond the world's edges) is not asked for: its answer would be
      // dropped and asked for again, over and over.
      if (!planned.fits(view, zoom)) continue;
      _radarInFlight[source.id] = key;
      unawaited(_loadRadar(part, mask, planned, now));
    }
  }

  Future<void> _loadRadar(
    RainPart part,
    _RainMask mask,
    _RadarImage planned,
    DateTime now,
  ) async {
    final source = part.source;
    final box = planned.layer.imageBox!;
    final style = _radarStyle;
    final image = await _fetcher.radarImage(
      source,
      box,
      part.frame,
      now,
      style: style,
      masks: mask.rings,
      coverages: mask.coverages,
      maskKey: mask.key,
    );
    if (_disposed) return;
    _radarInFlight.remove(source.id);
    if (image == null) {
      _radarFailed[source.id] = planned.layer.frameKey;
    } else {
      _radarFailed.remove(source.id);
    }
    if (_stillWanted(source, planned)) {
      _tilesUntilSoft.remove(source.id);
      if (image == null) {
        _failed.add(source.id);
      } else {
        _failed.remove(source.id);
        // Where its frame measures, for the sources cut by it.
        final coverage = style == RadarStyle.soft && source.extent != null
            ? readRainCoverage(image, box)
            : null;
        _radarImages[source.id] = planned.withImage(image, coverage);
      }
      _update();
    }
    // An answer for a view, moment or look since left is dropped; what
    // the view wants now is asked for.
    _planRadar();
  }

  /// Whether [planned] still serves the map: the radar on, the source in
  /// use as an image, the view inside its area, the moment and the masks
  /// the same.
  bool _stillWanted(WeatherMapSource source, _RadarImage planned) {
    if (!_settings.radar) return false;
    final view = _map?.visibleBounds;
    if (view == null) return false;
    final now = _clock();
    final parts = rainPartsAt(
      _enabled(WeatherKind.radar),
      now,
      _offset,
      view: view,
    );
    final part = parts.where((p) => p.source.id == source.id).firstOrNull;
    if (part == null) return false;
    if (_imageBoxOf(part.source, view, _map?.zoom) == null) return false;
    final mask = _maskOf(part, parts, view, _map?.zoom, now);
    if (mask == null || mask.hides) return false;
    return _stampOf(part, now, mask.key) == planned.stamp &&
        planned.fits(view, _zoomOf(view, _map?.zoom));
  }

  void _publish() {
    if (_disposed) return;
    final failing = <WeatherMapSource>[
      for (final source in _sources)
        if (_covering.contains(source.id) && _failed.contains(source.id))
          source,
    ];
    _status.value = WeatherMapStatus(
      centre: _centre,
      at: _clockAt,
      cloudsFrame: _settings.clouds ? _cloudsFrame : null,
      failed: <WeatherKind>{for (final source in failing) source.kind},
      failedRain: <RainRole>{
        for (final source in failing)
          if (source.kind == WeatherKind.radar) source.role,
      },
    );
  }
}

/// The wind grid shown: the source and the request it came from, the hour
/// it shows, when it was fetched and its credit.
@immutable
class _WindShown {
  const _WindShown({
    required this.source,
    required this.request,
    required this.time,
    required this.grid,
    required this.fetchedAt,
    required this.attribution,
  });

  final String source;
  final WindRequest request;
  final DateTime time;
  final WindGrid grid;
  final DateTime fetchedAt;
  final String attribution;
}

/// A cloud source's detail image: the layer drawn, the [area] it was asked
/// for (the view and its margin, before the coverage clips it), the zoom
/// it was asked at and the moment it shows.
@immutable
class _CloudDetail {
  const _CloudDetail({
    required this.layer,
    required this.area,
    required this.zoom,
    required this.stamp,
  });

  final WeatherLayer layer;
  final BoundingBox area;
  final double zoom;
  final int stamp;

  /// Whether it still serves [view] at [zoom]: the view inside its area,
  /// the zoom less than [cloudDetailRezoom] away.
  bool fits(BoundingBox view, double zoom) =>
      (zoom - this.zoom).abs() < cloudDetailRezoom &&
      view.west <= view.east &&
      view.west >= area.west &&
      view.east <= area.east &&
      view.south >= area.south &&
      view.north <= area.north;

  _CloudDetail withImage(Uint8List image) => _CloudDetail(
    layer: WeatherLayer.image(
      id: layer.id,
      kind: layer.kind,
      image: image,
      imageBox: layer.imageBox!,
      frameKey: layer.frameKey,
      attribution: layer.attribution,
      opacity: layer.opacity,
    ),
    area: area,
    zoom: zoom,
    stamp: stamp,
  );
}

/// A radar source's soft image: the layer drawn, the [area] it was asked
/// for (the view and its margin, a model's grown to its cells, before the
/// coverage clips it), the zoom it was asked at, the moment it shows and
/// whether it is [capped] coarser than the radar's own resolution.
@immutable
class _RadarImage {
  const _RadarImage({
    required this.layer,
    required this.area,
    required this.zoom,
    required this.stamp,
    required this.capped,
    this.coverage,
  });

  final WeatherLayer layer;
  final BoundingBox area;
  final double zoom;
  final String stamp;
  final bool capped;

  /// Where the frame measures, for a source with an extent drawn soft.
  final RainCoverage? coverage;

  /// Whether it still serves [view] at [zoom]: the view inside its area,
  /// and, where the image is coarser than the radar's own cells, the zoom
  /// less than [cloudDetailRezoom] further in. At the radar's own
  /// resolution zooming in brings nothing finer.
  bool fits(BoundingBox view, double zoom) =>
      (!capped || zoom - this.zoom < cloudDetailRezoom) &&
      view.west <= view.east &&
      view.west >= area.west &&
      view.east <= area.east &&
      view.south >= area.south &&
      view.north <= area.north;

  _RadarImage withImage(Uint8List image, RainCoverage? coverage) => _RadarImage(
    layer: WeatherLayer.image(
      id: layer.id,
      kind: layer.kind,
      image: image,
      imageBox: layer.imageBox!,
      frameKey: layer.frameKey,
      attribution: layer.attribution,
      opacity: layer.opacity,
    ),
    area: area,
    zoom: zoom,
    stamp: stamp,
    capped: capped,
    coverage: coverage,
  );
}

/// What a rain part is masked by ([WeatherMapDriver._maskOf]): fixed
/// [rings], the [coverages] of the frames before it, the [key] naming them
/// in the cache, and whether they [hides] the whole view.
@immutable
class _RainMask {
  const _RainMask({
    required this.rings,
    required this.key,
    this.coverages = const <RainCoverage>[],
    this.hides = false,
  });

  final List<List<LatLng>> rings;
  final List<RainCoverage> coverages;
  final String key;
  final bool hides;
}

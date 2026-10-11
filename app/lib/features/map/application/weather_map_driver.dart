import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../data/weather_fetcher.dart';
import '../data/weather_map_preferences.dart';
import '../data/weather_paint.dart';
import '../domain/map_controller.dart';
import '../domain/weather_map.dart';

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
/// the models ahead, each masked where one before it shows the same step.
/// Radar drawn soft ([RadarStyle.soft]), the satellite and the models are
/// one image of the view and its surroundings per source instead of tiles,
/// fetched and prepared by this driver once the camera has rested
/// ([radarImageDebounce]), at once when the time control or the style
/// changes, and with each refresh; the image shown stays until the next is
/// in, one request per source at a time, an answer for a view, moment or
/// mask since left dropped. That fetch is the source's check, in place of
/// the probe.
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
  /// key) and the last one asked for, which a failure is not asked again
  /// for until the next refresh.
  final Map<String, _CloudDetail> _details = <String, _CloudDetail>{};
  final Map<String, String> _detailInFlight = <String, String>{};
  final Map<String, String> _detailAttempted = <String, String>{};

  /// Each radar source's soft image, the request in flight for it (its
  /// key) and the last one asked for, which a failure is not asked again
  /// for until the next refresh or a new view.
  final Map<String, _RadarImage> _radarImages = <String, _RadarImage>{};
  final Map<String, String> _radarInFlight = <String, String>{};
  final Map<String, String> _radarAttempted = <String, String>{};

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
    map.addCameraIdleListener(_onCameraIdle);
    _update();
    _resetTimers();
    _scheduleDetails();
    _planRadar();
  }

  /// Lets the map go, taking the layers off it when [clear] is true.
  void detach({bool clear = true}) {
    final map = _map;
    if (map == null) return;
    map.removeCameraIdleListener(_onCameraIdle);
    if (clear && _drawn.isNotEmpty) {
      unawaited(map.setWeatherLayers(const <WeatherLayer>[]));
    }
    _drawn = const <WeatherLayer>[];
    _map = null;
    _detailTimer?.cancel();
    _detailTimer = null;
    _radarImageTimer?.cancel();
    _radarImageTimer = null;
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
      _radarAttempted.clear();
      _radarStyle = radarStyle;
    }
    final turnedOn = <WeatherKind>{
      for (final kind in WeatherKind.values)
        if (settings.shows(kind) && !_settings.shows(kind)) kind,
    };
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
      _detailAttempted.clear();
    }
    if (turnedOn.contains(WeatherKind.radar)) _radarAttempted.clear();
    // Clouds switched off let their images go, and so does the radar.
    if (!settings.clouds) {
      _images.clear();
      _details.clear();
    }
    if (!settings.radar) {
      _radarImages.clear();
      _tilesUntilSoft.clear();
    }
    _update();
    _resetTimers();
    _scheduleDetails();
    _planRadar();
  }

  /// Whether the app is in the foreground: refreshes run only then, and
  /// coming back checks at once.
  void setForeground(bool foreground) {
    if (foreground == _foreground) return;
    _foreground = foreground;
    if (foreground) {
      _attempted.clear();
      _detailAttempted.clear();
      _radarAttempted.clear();
      _update(recheck: true);
    }
    _resetTimers();
    _scheduleDetails();
    _planRadar();
  }

  /// Stops for good.
  void dispose() {
    _disposed = true;
    detach(clear: false);
    _radarTimer?.cancel();
    _cloudsTimer?.cancel();
    _detailTimer?.cancel();
    _radarImageTimer?.cancel();
    _status.dispose();
  }

  void _onCameraIdle() {
    _update();
    _scheduleDetails();
    _scheduleRadar();
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
    _radarTimer = null;
    _cloudsTimer = null;
    if (_disposed || _map == null || !_foreground) return;
    if (_settings.radar) {
      _radarTimer = Timer.periodic(radarRefreshInterval, (_) {
        _radarAttempted.clear();
        _update(recheck: true);
        _planRadar();
      });
    }
    if (_settings.clouds) {
      _cloudsTimer = Timer.periodic(cloudsRefreshInterval, (_) {
        _attempted.clear();
        _detailAttempted.clear();
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
    for (final part in parts) {
      final source = part.source;
      final frame = part.frame;
      covering.add(source.id);
      if (_imageBoxOf(source, view!, zoom) != null) {
        // An image: the one shown stays until the next is in, unless the
        // next failed and it shows another moment. No probe: the fetch
        // checks.
        _probed.remove(source.id);
        imageShown.add(source.id);
        final shown = _radarImages[source.id];
        final stamp = _stampOf(part, now);
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
    _covering = covering;

    if (!listEquals(layers, _drawn)) {
      _drawn = List<WeatherLayer>.unmodifiable(layers);
      unawaited(map.setWeatherLayers(_drawn));
    }
    _publish();
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
      final key = '${source.id}.detail@${cloudDetailKey(box)}@$stamp';
      if (_detailAttempted[source.id] == key) continue;
      _detailAttempted[source.id] = key;
      _detailInFlight[source.id] = key;
      unawaited(
        _loadDetail(
          source,
          _CloudDetail(
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
          ),
          frame,
          now,
        ),
      );
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
      _failed.add(source.id);
      _publish();
    } else {
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
  /// or a view across the antimeridian. The satellite and the models are
  /// always an image, as measured too, since their images are masked.
  BoundingBox? _imageBoxOf(
    WeatherMapSource source,
    BoundingBox view,
    double? zoom,
  ) {
    if (source.imageUrlTemplate == null) return null;
    if (source.role == RainRole.radar && _radarStyle != RadarStyle.soft) {
      return null;
    }
    final area = _imageAreaOf(source, view, _zoomOf(view, zoom));
    return area == null ? null : source.softBox(area);
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
  /// moment, the look and the sources it is masked by.
  String _stampOf(RainPart part, DateTime now) =>
      '${radarImageStamp(part.source, part.frame, now)}'
      '${_radarStyle == RadarStyle.soft ? '' : 'm'}${part.maskKey}';

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
      final stamp = _stampOf(part, now);
      final shown = _radarImages[source.id];
      if (shown != null && shown.stamp == stamp && shown.fits(view, zoom)) {
        continue;
      }
      // One request per source: the next is planned when it is back.
      if (_radarInFlight.containsKey(source.id)) continue;
      final key = '${source.id}@${cloudDetailKey(box)}@$stamp';
      if (_radarAttempted[source.id] == key) continue;
      _radarAttempted[source.id] = key;
      _radarInFlight[source.id] = key;
      unawaited(
        _loadRadar(
          part,
          _RadarImage(
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
          ),
          now,
        ),
      );
    }
  }

  Future<void> _loadRadar(
    RainPart part,
    _RadarImage planned,
    DateTime now,
  ) async {
    final source = part.source;
    final box = planned.layer.imageBox!;
    final image = await _fetcher.radarImage(
      source,
      box,
      part.frame,
      now,
      style: _radarStyle,
      masks: part.masks,
      maskKey: part.maskKey,
    );
    if (_disposed) return;
    _radarInFlight.remove(source.id);
    if (_stillWanted(source, planned)) {
      _tilesUntilSoft.remove(source.id);
      if (image == null) {
        _failed.add(source.id);
      } else {
        _failed.remove(source.id);
        _radarImages[source.id] = planned.withImage(image);
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
    final part = rainPartsAt(
      _enabled(WeatherKind.radar),
      now,
      _offset,
      view: view,
    ).where((p) => p.source.id == source.id).firstOrNull;
    if (part == null) return false;
    if (_imageBoxOf(part.source, view, _map?.zoom) == null) return false;
    return _stampOf(part, now) == planned.stamp &&
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
  });

  final WeatherLayer layer;
  final BoundingBox area;
  final double zoom;
  final String stamp;
  final bool capped;

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

  _RadarImage withImage(Uint8List image) => _RadarImage(
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
  );
}

import 'dart:async';
import 'dart:collection';
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

/// How far behind the clock a satellite's newest frame may be before the
/// model stands in for it at "Now" (see [rainStandIn]).
const Duration satelliteStaleAfter = Duration(minutes: 90);

/// How often a source with a [WeatherMapSource.timesUrl] is asked for its
/// newest frame at most, unless it refuses a frame.
const Duration weatherTimesRefreshInterval = Duration(minutes: 5);

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

/// How many of the time control's other frames are asked for at once in
/// the background (see [WeatherMapDriver.prefetch]).
const int weatherPrefetchConcurrency = 2;

/// How many frames of one rain image (one source, one piece of the view)
/// the map keeps loaded at most: one a step of the time control.
const int weatherPreloadMaxFrames = 32;

/// How many pixels all the rain frames kept loaded hold together at most,
/// some 100 MB decoded: the background stops asking when they would hold
/// more, and the frames used longest ago go first.
const int weatherPreloadMaxPixels = 24 * 1024 * 1024;

/// How many wind grids are kept in memory: one an hour of the time control
/// and a few more.
const int windGridsKept = 32;

/// What the weather layers on a map say about themselves, for the time
/// control and its hints.
@immutable
class WeatherMapStatus {
  /// Creates the status.
  const WeatherMapStatus({
    this.centre,
    this.at,
    this.cloudsFrame,
    this.shownOffset,
    this.failed = const <WeatherKind>{},
    this.failedRain = const <RainRole>{},
    this.newest = const <String, DateTime>{},
    this.missing = const <String>{},
  });

  /// The middle of the view, whose rain the time control's label describes
  /// (see `rainAtPoint`); `null` without a view.
  final LatLng? centre;

  /// When this was worked out: the clock the label's moments are read by.
  final DateTime? at;

  /// The moment the clouds in view show, UTC, where the service names it.
  final DateTime? cloudsFrame;

  /// The step of the time control the rain and the wind on the map show,
  /// in minutes from now: while the slider is dragged the step under the
  /// finger, or the nearest one already loaded; `null` before the first.
  final int? shownOffset;

  /// The kinds of which a source over the view did not answer.
  final Set<WeatherKind> failed;

  /// Of the rain, which sources over the view did not answer: the radar,
  /// the satellite, the forecast.
  final Set<RainRole> failedRain;

  /// The newest frame each source with a [WeatherMapSource.timesUrl] said
  /// it has, by id, which the frames shown keep to (see
  /// [WeatherMapSource.frameAt]).
  final Map<String, DateTime> newest;

  /// The satellites without a frame of "Now", for which the model stands
  /// in (see [rainStandIn]).
  final Set<String> missing;

  @override
  bool operator ==(Object other) =>
      other is WeatherMapStatus &&
      other.centre == centre &&
      other.at == at &&
      other.cloudsFrame == cloudsFrame &&
      other.shownOffset == shownOffset &&
      setEquals(other.failed, failed) &&
      setEquals(other.failedRain, failedRain) &&
      mapEquals(other.newest, newest) &&
      setEquals(other.missing, missing);

  @override
  int get hashCode => Object.hash(
    centre,
    at,
    cloudsFrame,
    shownOffset,
    Object.hashAllUnordered(failed),
    Object.hashAllUnordered(failedRain),
    Object.hashAllUnordered(<Object>[
      for (final MapEntry(:key, :value) in newest.entries)
        Object.hash(key, value),
    ]),
    Object.hashAllUnordered(missing),
  );

  @override
  String toString() =>
      'WeatherMapStatus(centre: $centre, at: $at, clouds: $cloudsFrame, '
      'shown: $shownOffset, failed: $failed, failedRain: $failedRain, '
      'newest: $newest, missing: $missing)';
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
/// images of the view and its surroundings instead of tiles, at every zoom:
/// one, or zoomed far out or across the antimeridian two
/// ([weatherImageAreas]), fetched and prepared by this driver once the
/// camera has rested ([radarImageDebounce]), at once when the time control
/// or the style changes, and with each refresh; the image shown stays
/// until the next is in, one request per image at a time. That fetch is
/// the source's check, in place of the probe.
///
/// The wind is one grid of the view and its margin ([windRequestFor]) at
/// the time control's hour, fetched once the camera has rested
/// ([windDebounce]), at once when the step changes, and again when the
/// hour turns or the grid is older than [windCacheMaxAge]; from it the
/// arrows over the view are worked out on the phone ([windArrowsFor]) at
/// every rest of the camera. One request at a time; the grid shown stays
/// until the next is in. At every zoom, thinned zoomed out. That fetch is
/// the wind's check.
///
/// With the step's own frames in, the other steps' rain images and wind
/// grids for the view are asked for in the background ([prefetch]): from
/// the slider's position outwards, at most
/// [weatherPrefetchConcurrency] at a time, through the fetcher's cache.
/// They stay loaded on the map unseen ([WeatherLayer.preloaded]), at most
/// [weatherPreloadMaxFrames] an image and [weatherPreloadMaxPixels] in
/// all, until the view leaves them; so while the slider is dragged
/// ([preview]) the map shows the step under the finger at once where it is
/// loaded, or the nearest step that is, by switching which frame is seen.
///
/// A source that does not answer is reported in [status], so the map can
/// say so instead of looking like a dry, clear day.
class WeatherMapDriver {
  /// A driver fetching through [fetcher], telling the time by [clock];
  /// with [prefetch] off (for tests), only the time control's own step is
  /// asked for.
  WeatherMapDriver({
    required this._fetcher,
    DateTime Function()? clock,
    this.prefetch = true,
  }) : _clock = clock ?? DateTime.now;

  final WeatherFetcher _fetcher;
  final DateTime Function() _clock;

  /// Whether the other steps of the time control are asked for in the
  /// background.
  final bool prefetch;

  MapController? _map;
  WeatherMapSettings _settings = const WeatherMapSettings();
  List<WeatherMapSource> _sources = const <WeatherMapSource>[];
  int _offset = 0;
  int? _preview;
  RadarStyle _radarStyle = RadarStyle.soft;
  bool _foreground = true;
  bool _disposed = false;
  Timer? _radarTimer;
  Timer? _cloudsTimer;
  Timer? _detailTimer;
  Timer? _radarImageTimer;
  Timer? _windTimer;
  Timer? _windRefreshTimer;

  /// The wind grids in memory, the oldest used first; the one shown; the
  /// request in flight for the time control's own step (its key) and the
  /// requests that failed, which are not asked again for until the next
  /// refresh, step or switch.
  final LinkedHashMap<String, _WindShown> _windGrids =
      LinkedHashMap<String, _WindShown>();
  _WindShown? _wind;
  String? _windInFlight;
  final Set<String> _windFailed = <String>{};

  /// The arrows last handed to the map.
  WindArrows? _windDrawn;

  /// The newest frame of each source with a [WeatherMapSource.timesUrl]
  /// as its service last said, by id; when it was last asked, and the
  /// sources being asked now.
  final Map<String, DateTime> _newest = <String, DateTime>{};
  final Map<String, DateTime> _newestAskedAt = <String, DateTime>{};
  final Set<String> _newestInFlight = <String>{};

  /// The satellites that have no frame of "Now" to show: their image
  /// failed, or their newest frame is older than [satelliteStaleAfter]. The
  /// model stands in for them at "Now" while their image is asked for
  /// again in the background ([_retrySatellites]); one that comes, of a
  /// frame not too old, takes its place back.
  final Set<String> _satellitesDown = <String>{};

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

  /// The rain images loaded for the view, by key (the source, the box, the
  /// moment and what it is cut by), and when each was last used; those
  /// shown now, by slot (a source's piece of the view); the requests in
  /// flight for the time control's own step (by slot) and in the
  /// background (by key); and those that failed, by key, not asked again
  /// for until the next refresh, step or look.
  final Map<String, _RadarImage> _frames = <String, _RadarImage>{};
  final Map<String, int> _frameUse = <String, int>{};
  int _useCount = 0;
  final Map<String, _RadarImage> _shown = <String, _RadarImage>{};
  final Map<String, String> _radarInFlight = <String, String>{};
  final Set<String> _prefetchInFlight = <String>{};
  final Set<String> _rainFailed = <String>{};

  /// The radar sources switched to soft while drawn as tiles: their tiles
  /// stay until the first soft image is in or fails, so the switch leaves
  /// no gap.
  final Set<String> _tilesUntilSoft = <String>{};

  List<WeatherLayer> _drawn = const <WeatherLayer>[];
  DateTime? _cloudsFrame;
  LatLng? _centre;
  DateTime? _clockAt;
  int? _shownOffset;

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
      // The images shown stay until those in the new look replace them;
      // those kept for the time control go.
      _rainFailed.clear();
      _frames.clear();
      _radarStyle = radarStyle;
    }
    final turnedOn = <WeatherKind>{
      for (final kind in WeatherKind.values)
        if (settings.shows(kind) && !_settings.shows(kind)) kind,
    };
    // Another step of the time control: what failed for the last one is
    // asked again.
    if (offsetMinutes != _offset) {
      _rainFailed.clear();
      _windFailed.clear();
    }
    if (!listEquals(sources, _sources)) {
      _frames.clear();
      // A source asked elsewhere for its times, or not at all, starts over.
      for (final old in _sources) {
        final next = sources.where((s) => s.id == old.id).firstOrNull;
        if (next?.timesUrl != old.timesUrl) {
          _newest.remove(old.id);
          _newestAskedAt.remove(old.id);
        }
      }
    }
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
    if (turnedOn.contains(WeatherKind.radar)) {
      _rainFailed.clear();
      _satellitesDown.clear();
    }
    if (turnedOn.contains(WeatherKind.wind)) _windFailed.clear();
    // Clouds switched off let their images go, and so does the radar.
    if (!settings.clouds) {
      _images.clear();
      _details.clear();
    }
    if (!settings.radar) {
      _frames.clear();
      _shown.clear();
      _tilesUntilSoft.clear();
    }
    if (!settings.wind) {
      _wind = null;
      _windGrids.clear();
      _windFailed.clear();
    }
    _update();
    _resetTimers();
    _scheduleDetails();
    _planRadar();
    _planWind();
  }

  /// Shows the step [offsetMinutes] of the time control while its slider
  /// is dragged, without asking for anything: where its frames are loaded
  /// that step, else the nearest step whose are, else the step set; the
  /// step shown is in [status]. `null` when the slider is let go, back to
  /// the step set ([configure]).
  void preview(int? offsetMinutes) {
    final step = offsetMinutes == null
        ? null
        : snapWeatherOffset(offsetMinutes);
    if (step == _preview) return;
    _preview = step;
    _update();
  }

  /// Whether the app is in the foreground: refreshes run only then, and
  /// coming back checks at once.
  void setForeground(bool foreground) {
    if (foreground == _foreground) return;
    _foreground = foreground;
    if (foreground) {
      _attempted.clear();
      _detailFailed.clear();
      _rainFailed.clear();
      _windFailed.clear();
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
        _windFailed.clear();
        _update();
        _planWind();
      });
    }
    if (_settings.radar) {
      _radarTimer = Timer.periodic(radarRefreshInterval, (_) {
        _rainFailed.clear();
        _pruneFrames();
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

    // A satellite whose newest frame is too old stands aside.
    for (final source in _enabled(WeatherKind.radar)) {
      if (_stale(source, now)) _satellitesDown.add(source.id);
    }

    // The newest frames of the sources in use over the view that say them.
    if (view != null) {
      for (final source in _enabled(WeatherKind.clouds)) {
        if (source.covers(view)) _askNewest(source, now);
      }
      for (final part in rainPartsAt(
        _enabled(WeatherKind.radar),
        now,
        _offset,
        view: view,
      )) {
        _askNewest(part.source, now);
      }
      // A model named by its run has no frame before its run is known.
      for (final source in _enabled(WeatherKind.radar)) {
        if (source.timeFormat == WeatherTimeFormat.modelRun &&
            source.covers(view)) {
          _askNewest(source, now);
        }
      }
    }

    // Clouds first, which is under the rain.
    _cloudsFrame = null;
    final zoom = map.zoom;
    final detailed = zoom != null && zoom >= cloudDetailMinZoom;
    final shownDetails = <String>{};
    for (final source in _enabled(WeatherKind.clouds)) {
      if (view == null || !source.covers(view)) continue;
      final frame = source.frameAt(now, newest: _newest[source.id]);
      if (frame == null) continue;
      covering.add(source.id);
      _cloudsFrame ??= frame.time;
      final stamp = cloudImageStamp(frame, now);
      // Where it fades into its neighbours, which says what it is too.
      final fades = cloudFadesOf(source, _enabled(WeatherKind.clouds));
      final fadesKey = fades.map((f) => f.key).join('-');
      for (var region = 0; region < source.coverage.length; region++) {
        if (!_regionMeets(source.coverage[region], view)) continue;
        // A box MapLibre cannot draw (a mirror's override) is not fetched.
        if (!safeImageBox(source.coverage[region])) continue;
        final key = '${source.id}.$region';
        final frameKey = '$key@$stamp$fadesKey';
        // The last image of the region stays until the next one is in.
        final shown = _images[key];
        if (shown != null) layers.add(shown);
        if (shown?.frameKey != frameKey && _attempted[key] != frameKey) {
          _attempted[key] = frameKey;
          unawaited(
            _loadCloud(source, region, frame, now, key, frameKey, fades),
          );
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
    final z = view == null ? 0.0 : _zoomOf(view, zoom);
    // Frames that no longer serve the view go.
    if (view != null) {
      _frames.removeWhere((key, frame) {
        final gone = !frame.fits(view, z);
        if (gone) _frameUse.remove(key);
        return gone;
      });
    }
    final shownStep = view == null ? _offset : _shownStep(view, zoom, now);
    _shownOffset = shownStep;
    final plan = view == null
        ? const <_PartPlan>[]
        : _stepPlan(shownStep, view, zoom, now);
    final inPlan = <String>{for (final p in plan) p.part.source.id};
    for (final source in _enabled(WeatherKind.radar)) {
      // Out of the view or without the moment: checked again when back.
      if (!inPlan.contains(source.id)) _probed.remove(source.id);
    }
    final tiles = <String, WeatherLayer>{};
    final visible = <String, _RadarImage>{};
    final imageParts = <String>{};
    for (final p in plan) {
      final source = p.part.source;
      if (p.tiles) {
        covering.add(source.id);
        tiles[source.id] = WeatherLayer.ofRadar(source, p.part.frame, now);
        final probe = source.probeUrl(
          p.part.frame,
          view!.center,
          weatherProbeZoom,
        );
        if (recheck || _probed[source.id] != probe) {
          _probed[source.id] = probe;
          unawaited(_probe(source.id, probe));
        }
        continue;
      }
      // Wholly left to those before it: nothing to draw, nothing to ask.
      if (p.hidden) continue;
      // Images: no probe, the fetch checks. While the frames it is cut by
      // are still out, the one shown stays.
      covering.add(source.id);
      _probed.remove(source.id);
      imageParts.add(source.id);
      var any = false;
      for (final slot in p.slots) {
        final frame = p.waiting ? null : _frames[slot.key];
        if (frame != null) {
          _touch(slot.key);
          visible[slot.id] = frame;
          any = true;
          continue;
        }
        // The one shown stays until the next is in, unless the next failed
        // and it shows another moment.
        final old = _shown[slot.id];
        if (old != null &&
            (old.stamp == slot.stamp || !_rainFailed.contains(slot.key))) {
          visible[slot.id] = old;
          any = true;
        }
      }
      // Just switched to soft: the tiles until the image is in.
      if (!any && _tilesUntilSoft.contains(source.id)) {
        tiles[source.id] = WeatherLayer.ofRadar(source, p.part.frame, now);
      }
    }
    _shown
      ..clear()
      ..addAll(visible);
    _tilesUntilSoft.removeWhere((id) => !imageParts.contains(id));
    layers.addAll(_rainLayers(tiles, visible));

    // The wind, over the rest: the arrows of the grid shown over the view.
    final wind = _windSource();
    WindArrows? arrows;
    if (wind != null && view != null) {
      if (windRequestFor(view, z) != null) {
        covering.add(wind.id);
        final wanted = _windFor(wind, shownStep, view, z, now);
        if (wanted != null) _wind = wanted;
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

  /// The rain's layers, in the order of the sources: each source's tiles
  /// where it is drawn as tiles, and a layer for each piece of the view it
  /// has images of, the one shown ([visible]) and the others loaded for
  /// the time control kept unseen.
  List<WeatherLayer> _rainLayers(
    Map<String, WeatherLayer> tiles,
    Map<String, _RadarImage> visible,
  ) {
    final bySlot = <String, List<_RadarImage>>{};
    for (final frame in _frames.values) {
      (bySlot[frame.layer.id] ??= <_RadarImage>[]).add(frame);
    }
    final out = <WeatherLayer>[];
    for (final source in _enabled(WeatherKind.radar)) {
      final tile = tiles[source.id];
      if (tile != null) out.add(tile);
      final slots = <String>[
        for (final id in <String>{...visible.keys, ...bySlot.keys})
          if (_slotSource(id) == source.id) id,
      ]..sort((a, b) => _slotPiece(a).compareTo(_slotPiece(b)));
      for (final id in slots) {
        final shown = visible[id];
        final kept = <_RadarImage>[
          for (final frame in bySlot[id] ?? const <_RadarImage>[])
            if (frame.key != shown?.key) frame,
        ]..sort((a, b) => a.key.compareTo(b.key));
        final main = shown ?? kept.removeAt(0);
        final layer = main.layer;
        out.add(
          WeatherLayer.image(
            id: layer.id,
            kind: layer.kind,
            image: layer.image!,
            imageBox: layer.imageBox!,
            frameKey: layer.frameKey,
            attribution: layer.attribution,
            opacity: layer.opacity,
            visible: shown != null,
            preloaded: <WeatherImageFrame>[
              for (final frame in kept.take(weatherPreloadMaxFrames - 1))
                ?frame.layer.asFrame,
            ],
          ),
        );
      }
    }
    return out;
  }

  /// The id of the layer of [source]'s image of piece [piece] of the view.
  static String _slotId(WeatherMapSource source, int piece) =>
      piece == 0 ? source.id : '${source.id}#$piece';

  static String _slotSource(String slot) => slot.split('#').first;

  static int _slotPiece(String slot) {
    final at = slot.indexOf('#');
    return at < 0 ? 0 : int.tryParse(slot.substring(at + 1)) ?? 0;
  }

  /// The step the map shows: the one set, or while the slider is dragged
  /// the step under the finger where it is loaded ([_stepReady]), else the
  /// nearest one that is, on the side of the step set first.
  int _shownStep(BoundingBox view, double? zoom, DateTime now) {
    final preview = _preview;
    if (preview == null || preview == _offset) return _offset;
    final target = weatherSliderIndexOf(preview);
    final set = weatherSliderIndexOf(_offset);
    for (var d = 0; d < weatherRadarOffsets.length; d++) {
      final candidates = d == 0
          ? <int>[target]
          : set < target
          ? <int>[target - d, target + d]
          : <int>[target + d, target - d];
      for (final i in candidates) {
        if (i < 0 || i >= weatherRadarOffsets.length) continue;
        final step = weatherRadarOffsets[i];
        if (step == _offset || _stepReady(step, view, zoom, now)) return step;
      }
    }
    return _offset;
  }

  /// Whether everything [step] draws over [view] is loaded: with the rain
  /// on, each of its images (none of it tiles, which load only once
  /// shown); with the rain off, the wind's grid of its hour.
  bool _stepReady(int step, BoundingBox view, double? zoom, DateTime now) {
    if (_settings.radar) {
      for (final p in _stepPlan(step, view, zoom, now)) {
        if (p.tiles || p.waiting) return false;
        if (p.hidden) continue;
        for (final slot in p.slots) {
          if (!_frames.containsKey(slot.key)) return false;
        }
      }
      return true;
    }
    final wind = _windSource();
    if (wind == null) return false;
    return _windFor(wind, step, view, _zoomOf(view, zoom), now) != null;
  }

  /// What the rain draws over [view] at [step]: each part [rainPartsAt]
  /// picks, as tiles or as images of the pieces of the view, with what it
  /// is masked by and so the keys of its images.
  ///
  /// At "Now" the model stands in for the satellites that are down, unless
  /// [standIn] is false: the plan as it would be with them up.
  List<_PartPlan> _stepPlan(
    int step,
    BoundingBox view,
    double? zoom,
    DateTime now, {
    bool standIn = true,
  }) {
    final z = _zoomOf(view, zoom);
    final parts = rainPartsAt(
      _enabled(WeatherKind.radar),
      now,
      step,
      view: view,
      newest: _newest,
      missing: standIn ? _satellitesDown : const <String>{},
    );
    final areas = weatherImageAreas(view, z);
    final out = <_PartPlan>[];
    for (final part in parts) {
      final source = part.source;
      if (!_drawnAsImage(source)) {
        out.add(_PartPlan(part: part, tiles: true));
        continue;
      }
      final own = _imageAreasOf(source, areas);
      final mask = _maskOf(part, out, view);
      final stamp = mask == null ? '' : _stampOf(part, now, mask.key);
      out.add(
        _PartPlan(
          part: part,
          mask: mask,
          areas: own,
          zoom: z,
          slots: <_Slot>[
            for (final (piece, area) in own.indexed)
              if (source.softBox(area) case final box?)
                if (safeImageBox(box))
                  _Slot(
                    id: _slotId(source, piece),
                    box: box,
                    stamp: stamp,
                    key: '${source.id}@${cloudDetailKey(box)}@$stamp',
                  ),
          ],
        ),
      );
    }
    return out;
  }

  /// The areas [source]'s images over [areas] are asked for, before its
  /// coverage clips them: for a model each grown to [modelMinCells] of its
  /// cells ([modelImageArea]), kept to its piece's longitudes where the
  /// view is in two.
  static List<BoundingBox> _imageAreasOf(
    WeatherMapSource source,
    List<BoundingBox> areas,
  ) {
    if (source.role != RainRole.model) return areas;
    return <BoundingBox>[
      for (final area in areas)
        if (modelImageArea(source, area) case final grown)
          areas.length == 1
              ? grown
              : BoundingBox(
                  south: grown.south,
                  west: area.west,
                  north: grown.north,
                  east: area.east,
                ),
    ];
  }

  /// The wind source in use: the first enabled one, while the wind is on.
  WeatherMapSource? _windSource() => _enabled(WeatherKind.wind).firstOrNull;

  /// The grid in memory of [source]'s wind at [step]'s hour that serves
  /// [view] at [zoom] and is younger than [windCacheMaxAge]; `null` where
  /// there is none.
  _WindShown? _windFor(
    WeatherMapSource source,
    int step,
    BoundingBox view,
    double zoom,
    DateTime now,
  ) {
    final frame = _windFrame(source, now, step);
    final time = frame?.time;
    if (time == null) return null;
    for (final grid in _windGrids.values.toList().reversed) {
      if (grid.source == source.id &&
          grid.time == time &&
          grid.run == frame?.run &&
          now.difference(grid.fetchedAt) < windCacheMaxAge &&
          grid.request.fits(view, zoom)) {
        return grid;
      }
    }
    return null;
  }

  /// Asks for the wind of the view where the grid of the step's hour is
  /// not in memory, is older than [windCacheMaxAge], or no longer serves
  /// the view ([WindRequest.fits]).
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
    _askNewest(source, now);
    final request = windRequestFor(view, zoom);
    final frame = _windFrame(source, now, _offset);
    final time = frame?.time;
    if (request == null || frame == null || time == null) return;
    if (_windFor(source, _offset, view, zoom, now) != null) {
      // In memory: shown with the update, then the other steps.
      if (_wind?.time != time) _update();
      _prefetch();
      return;
    }
    // One that would be dropped when it comes is not asked for: its
    // answer would be asked for again, over and over.
    if (!request.fits(view, zoom)) return;
    // One request at a time: the next is planned when it is back.
    if (_windInFlight != null) return;
    final key = _windKey(source, request, frame);
    // Only a request that failed waits for the refresh.
    if (_windFailed.contains(key)) return;
    _windInFlight = key;
    unawaited(_loadWind(source, request, frame, key, now));
  }

  static String _windKey(
    WeatherMapSource source,
    WindRequest request,
    WeatherFrame frame,
  ) =>
      '${source.id}@${request.key}@${frame.time?.millisecondsSinceEpoch}'
      '@${frame.run?.millisecondsSinceEpoch}';

  /// [source]'s wind frame [step] minutes from [now], of the newest run its
  /// service named ([WeatherMapSource.frameAt]); `null` while a source
  /// that names its runs has not said its newest: asked without one, the
  /// DWD answers from its oldest.
  WeatherFrame? _windFrame(WeatherMapSource source, DateTime now, int step) {
    final frame = source.frameAt(
      now,
      offsetMinutes: step,
      newest: _newest[source.id],
    );
    if (source.timesUrl != null && frame?.run == null) return null;
    return frame;
  }

  Future<void> _loadWind(
    WeatherMapSource source,
    WindRequest request,
    WeatherFrame frame,
    String key,
    DateTime now, {
    bool background = false,
  }) async {
    final grid = await _fetcher.windGrid(source, request, frame, now);
    if (_disposed) return;
    if (background) {
      _prefetchInFlight.remove(key);
    } else {
      _windInFlight = null;
    }
    if (grid == null) {
      _windFailed.add(key);
      if (!background) {
        _failed.add(source.id);
        // A grid of another hour does not stand in for this one.
        if (_wind != null && _wind!.time != frame.time) _wind = null;
      }
    } else {
      _windFailed.remove(key);
      if (!background) _failed.remove(source.id);
      if (_windStillWanted(source, request)) {
        _windGrids
          ..remove(key)
          ..[key] = _WindShown(
            source: source.id,
            request: request,
            time: frame.time!,
            run: frame.run,
            grid: grid,
            fetchedAt: now,
            attribution: source.attributionFor(frame, now),
          );
        while (_windGrids.length > windGridsKept) {
          _windGrids.remove(_windGrids.keys.first);
        }
      }
    }
    _update();
    // What the view wants now is asked for, then the other steps.
    _planWind();
    _prefetch();
  }

  /// Whether a grid of [request] still serves the map: the wind on with
  /// [source] in use and the view inside the request's area at its
  /// thinning.
  bool _windStillWanted(WeatherMapSource source, WindRequest request) {
    if (!_settings.wind || _windSource()?.id != source.id) return false;
    final map = _map;
    final view = map?.visibleBounds;
    if (map == null || view == null) return false;
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

  /// Asks [source]'s service for its newest frame, where it says it
  /// ([WeatherMapSource.timesUrl]): not while asked already, and unless
  /// [force]d not within [weatherTimesRefreshInterval] of the last time.
  void _askNewest(WeatherMapSource source, DateTime now, {bool force = false}) {
    final url = source.timesUrl;
    if (url == null || _newestInFlight.contains(source.id)) return;
    final asked = _newestAskedAt[source.id];
    if (!force &&
        asked != null &&
        now.difference(asked) < weatherTimesRefreshInterval) {
      return;
    }
    _newestAskedAt[source.id] = now;
    _newestInFlight.add(source.id);
    unawaited(_loadNewest(source, url, force: force));
  }

  /// [source]'s newest frame, then the frames that keep to it. One that
  /// cannot be had leaves the last one known. An older one than known is
  /// taken only when asked after a refusal: a service behind several
  /// servers may answer with one a step behind, which would swap the
  /// frames back and forth.
  Future<void> _loadNewest(
    WeatherMapSource source,
    String url, {
    required bool force,
  }) async {
    final time = await _fetcher.newestFrame(source);
    _newestInFlight.remove(source.id);
    if (_disposed || time == null) return;
    // Switched to another source of times, or none, meanwhile.
    if (!_sources.any((s) => s.id == source.id && s.timesUrl == url)) return;
    final known = _newest[source.id];
    if (time == known || (known != null && !force && time.isBefore(known))) {
      return;
    }
    _newest[source.id] = time;
    _update();
    _planRadar();
    _planDetails();
    if (source.kind == WeatherKind.wind) _planWind();
  }

  /// After an image of [source] failed: where the service refused it (a
  /// moment past its newest frame), its newest frame is asked for again at
  /// once.
  void _onRefusal(WeatherMapSource source) {
    if (!_fetcher.takeRefusal(source.id)) return;
    _askNewest(source, _clock(), force: true);
  }

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
    List<CloudFade> fades,
  ) async {
    final image = await _fetcher.cloudImage(
      source,
      region,
      frame,
      now,
      fades: fades,
    );
    if (_disposed) return;
    if (image == null) {
      _failed.add(source.id);
      _onRefusal(source);
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
      final frame = source.frameAt(now, newest: _newest[source.id]);
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
    final image = await _fetcher.cloudDetailImage(
      source,
      box,
      frame,
      now,
      fades: cloudFadesOf(source, _enabled(WeatherKind.clouds)),
    );
    if (_disposed) return;
    _detailInFlight.remove(source.id);
    if (image == null) {
      _detailFailed[source.id] = planned.layer.frameKey;
      _failed.add(source.id);
      _onRefusal(source);
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

  /// Whether [source] is drawn as an image of the view rather than tiles:
  /// one with an image request, a radar only when drawn soft. The
  /// satellite and the models are always images, as measured too, since
  /// their images are masked.
  bool _drawnAsImage(WeatherMapSource source) {
    if (source.imageUrlTemplate == null) return false;
    return source.role != RainRole.radar || _radarStyle == RadarStyle.soft;
  }

  /// What tells one image of [part] from the next, besides its box: its
  /// moment, the look and what it is masked by ([maskKey], see [_maskOf]).
  String _stampOf(RainPart part, DateTime now, String maskKey) =>
      '${radarImageStamp(part.source, part.frame, now)}'
      '${_radarStyle == RadarStyle.soft ? '' : 'm'}$maskKey';

  /// What [part] is masked by over [view], [before] being the plans of the
  /// parts before it at the same step: the fixed rings of those, and of
  /// those in [RainPart.cutBy] their frame's coverage where it is drawn
  /// soft as images. `null` while such a frame for the step and the view
  /// is still to come: the part waits for it. Where a frame cannot be had
  /// (it failed, it is drawn as tiles, or its image carries no coverage),
  /// its fixed reach stands in.
  _RainMask? _maskOf(RainPart part, List<_PartPlan> before, BoundingBox view) {
    if (part.cutBy.isEmpty) {
      return _RainMask(rings: part.masks, key: part.maskKey);
    }
    final rings = <List<LatLng>>[];
    final coverages = <RainCoverage>[];
    final key = StringBuffer();
    var hides = false;
    var byReach = false;
    for (final prior in before) {
      final source = prior.part.source;
      if (!part.cutBy.contains(source)) {
        rings.addAll(source.reachRings);
        key.write('-${source.id}');
        continue;
      }
      final mask = prior.mask;
      if (!prior.tiles && prior.slots.isNotEmpty) {
        if (mask == null) return null;
        if (!mask.hides) {
          final frames = <_RadarImage?>[
            for (final slot in prior.slots) _frames[slot.key],
          ];
          if (frames.every((f) => f?.coverage != null)) {
            for (final frame in frames) {
              final coverage = frame!.coverage!;
              coverages.add(coverage);
              if (coverage.coversAll(view)) hides = true;
            }
            final keys = prior.slots.map((s) => s.key).join('|');
            key.write('-${source.id}~${_hashOf(keys)}');
            continue;
          }
          // Its frame of this step and view is still to come.
          if (prior.slots.any(
            (s) => !_frames.containsKey(s.key) && !_rainFailed.contains(s.key),
          )) {
            return null;
          }
          // A model whose frame failed leaves its place to those after it.
          if (source.role == RainRole.model &&
              prior.slots.every((s) => _rainFailed.contains(s.key))) {
            key.write('-${source.id}!');
            continue;
          }
        }
      }
      // The frame cannot be had: its fixed reach instead.
      rings.addAll(source.reachRings);
      key.write('-${source.id}');
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

  /// The image [p]'s [slot] would be, before it comes.
  _RadarImage _planned(_PartPlan p, _Slot slot, DateTime now) {
    final source = p.part.source;
    return _RadarImage(
      layer: WeatherLayer.image(
        id: slot.id,
        kind: WeatherKind.radar,
        image: Uint8List(0),
        imageBox: slot.box,
        frameKey: slot.key,
        attribution: source.attributionFor(p.part.frame, now),
        // As measured, as see-through as the radar's tiles; soft, the
        // image's alpha says it all.
        opacity: _radarStyle == RadarStyle.soft
            ? null
            : source.opacity ?? radarTone.opacity,
      ),
      areas: p.areas,
      zoom: p.zoom,
      stamp: slot.stamp,
      capped: radarSoftCapped(source, slot.box),
    );
  }

  /// Asks for each rain image of the time control's step over the view
  /// that is not loaded: one request per image at a time, a failed one not
  /// again before the refresh. Then the other steps ([_prefetch]).
  void _planRadar() {
    _radarImageTimer?.cancel();
    _radarImageTimer = null;
    if (_disposed || !_foreground || !_settings.radar) return;
    final map = _map;
    final view = map?.visibleBounds;
    if (map == null || view == null) return;
    final zoom = _zoomOf(view, map.zoom);
    final now = _clock();
    for (final p in _stepPlan(_offset, view, map.zoom, now)) {
      // Drawn as tiles, waiting for the frames it is cut by, or wholly
      // left to them.
      if (p.tiles || p.waiting || p.hidden) continue;
      for (final slot in p.slots) {
        if (_frames.containsKey(slot.key)) continue;
        // One request per image: the next is planned when it is back.
        if (_radarInFlight.containsKey(slot.id)) continue;
        // Only a request that failed waits for the refresh; one that came
        // and was replaced (another step, another view) is asked again,
        // and comes from the cache.
        if (_rainFailed.contains(slot.key)) continue;
        final planned = _planned(p, slot, now);
        // An image that would not serve the view even when it comes is not
        // asked for: its answer would be dropped and asked for again, over
        // and over.
        if (!planned.fits(view, zoom)) continue;
        _radarInFlight[slot.id] = slot.key;
        unawaited(_loadRadar(p, slot, planned, now));
      }
    }
    _retrySatellites(view, map.zoom, now);
    _prefetch();
  }

  /// Whether [source] is a satellite whose newest frame, as its service
  /// said, is older than [satelliteStaleAfter].
  bool _stale(WeatherMapSource source, DateTime now) {
    if (source.role != RainRole.satellite) return false;
    final newest = _newest[source.id];
    return newest != null && now.difference(newest) > satelliteStaleAfter;
  }

  /// At "Now", asks in the background for the images of the satellites
  /// down whose frames are not too old, as they would be drawn: once in,
  /// they take the model's place again. A failed one waits for the
  /// refresh, or for a newer frame.
  void _retrySatellites(BoundingBox view, double? mapZoom, DateTime now) {
    if (_offset != 0 || _satellitesDown.isEmpty) return;
    final zoom = _zoomOf(view, mapZoom);
    var back = false;
    for (final p in _stepPlan(0, view, mapZoom, now, standIn: false)) {
      final source = p.part.source;
      if (!_satellitesDown.contains(source.id) || _stale(source, now)) {
        continue;
      }
      if (p.tiles || p.waiting || p.hidden || p.slots.isEmpty) continue;
      if (p.slots.every((slot) => _frames.containsKey(slot.key))) {
        // Loaded already: back at once.
        _satellitesDown.remove(source.id);
        back = true;
        continue;
      }
      for (final slot in p.slots) {
        if (_frames.containsKey(slot.key) ||
            _rainFailed.contains(slot.key) ||
            _prefetchInFlight.contains(slot.key)) {
          continue;
        }
        final planned = _planned(p, slot, now);
        if (!planned.fits(view, zoom)) continue;
        _prefetchInFlight.add(slot.key);
        unawaited(_loadRadar(p, slot, planned, now, background: true));
      }
    }
    if (back) _update();
  }

  /// The order the other steps of the time control are asked for in: from
  /// the slider's position (the step under the finger while it is dragged,
  /// else the step set) outwards, alternately later and earlier, so what
  /// does not fit in memory is far from where the rider looks.
  List<int> _prefetchOrder() => <int>[
    for (final step in weatherStepsOutwards(_preview ?? _offset))
      if (step != _offset) step,
  ];

  /// Asks in the background for the other steps' rain images and wind
  /// grids of the view (see [_prefetchOrder]), once the step set has all
  /// of its own in; at most [weatherPrefetchConcurrency] at a time, the
  /// rain's within [weatherPreloadMaxPixels].
  void _prefetch() {
    if (!prefetch || _disposed || !_foreground) return;
    if (!_settings.radar && !_settings.wind) return;
    final map = _map;
    final view = map?.visibleBounds;
    if (map == null || view == null) return;
    // The step set first.
    if (_radarInFlight.isNotEmpty || _windInFlight != null) return;
    if (_prefetchInFlight.length >= weatherPrefetchConcurrency) return;
    final zoom = _zoomOf(view, map.zoom);
    final now = _clock();
    var pixels = 0;
    for (final frame in _frames.values) {
      pixels += frame.pixels;
    }
    final wind = _windSource();
    final windRequest = wind == null ? null : windRequestFor(view, zoom);
    for (final step in _prefetchOrder()) {
      if (_settings.radar) {
        for (final p in _stepPlan(step, view, map.zoom, now)) {
          if (p.tiles || p.waiting || p.hidden) continue;
          for (final slot in p.slots) {
            if (_frames.containsKey(slot.key) ||
                _rainFailed.contains(slot.key) ||
                _prefetchInFlight.contains(slot.key) ||
                _radarInFlight.containsValue(slot.key)) {
              continue;
            }
            final planned = _planned(p, slot, now);
            if (!planned.fits(view, zoom)) continue;
            final more = _pixelsOf(p.part.source, slot.box);
            // Full: no more in the background until the view changes.
            if (pixels + more > weatherPreloadMaxPixels) return;
            pixels += more;
            _prefetchInFlight.add(slot.key);
            unawaited(_loadRadar(p, slot, planned, now, background: true));
            if (_prefetchInFlight.length >= weatherPrefetchConcurrency) {
              return;
            }
          }
        }
      }
      if (wind != null && windRequest != null && windRequest.fits(view, zoom)) {
        final frame = _windFrame(wind, now, step);
        final time = frame?.time;
        if (frame == null || time == null) continue;
        if (_windFor(wind, step, view, zoom, now) != null) continue;
        final key = _windKey(wind, windRequest, frame);
        if (_windFailed.contains(key) || _prefetchInFlight.contains(key)) {
          continue;
        }
        _prefetchInFlight.add(key);
        unawaited(
          _loadWind(wind, windRequest, frame, key, now, background: true),
        );
        if (_prefetchInFlight.length >= weatherPrefetchConcurrency) return;
      }
    }
  }

  /// About how many pixels [source]'s image of [box] holds once prepared:
  /// drawn soft, scaled up ([rainUpsample]).
  int _pixelsOf(WeatherMapSource source, BoundingBox box) {
    final (w, h) = radarSoftImageSize(source, box);
    if (_radarStyle != RadarStyle.soft) return w * h;
    final long = math.max(w, h);
    final scale = math.max(
      1.0,
      math.min(rainUpsample, radarSoftMaxSide / long),
    );
    return (w * h * scale * scale).round();
  }

  Future<void> _loadRadar(
    _PartPlan p,
    _Slot slot,
    _RadarImage planned,
    DateTime now, {
    bool background = false,
  }) async {
    final source = p.part.source;
    final mask = p.mask!;
    final style = _radarStyle;
    final image = await _fetcher.radarImage(
      source,
      slot.box,
      p.part.frame,
      now,
      style: style,
      masks: mask.rings,
      coverages: mask.coverages,
      maskKey: mask.key,
    );
    if (_disposed) return;
    if (background) {
      _prefetchInFlight.remove(slot.key);
    } else {
      _radarInFlight.remove(slot.id);
    }
    if (image == null) {
      _rainFailed.add(slot.key);
      if (source.role == RainRole.satellite) _satellitesDown.add(source.id);
      _onRefusal(source);
    } else {
      _rainFailed.remove(slot.key);
      if (!_stale(source, _clock())) _satellitesDown.remove(source.id);
    }
    final map = _map;
    final view = map?.visibleBounds;
    // What the time control's own step draws says whether the source
    // answers; an image of another step does not.
    if (!background && view != null && _settings.radar) {
      final own = _stepPlan(
        _offset,
        view,
        map?.zoom,
        _clock(),
      ).any((q) => q.slots.any((s) => s.key == slot.key));
      if (own) {
        _tilesUntilSoft.remove(source.id);
        if (image == null) {
          _failed.add(source.id);
        } else {
          _failed.remove(source.id);
        }
      }
    }
    if (image != null &&
        style == _radarStyle &&
        _settings.radar &&
        view != null &&
        planned.fits(view, _zoomOf(view, map?.zoom))) {
      // Where its frame measures, for the sources cut by it.
      final coverage = style == RadarStyle.soft && source.extent != null
          ? readRainCoverage(image, slot.box)
          : null;
      _store(planned.withImage(image, coverage));
    }
    _update();
    // What the view wants now is asked for, then the other steps.
    _planRadar();
  }

  /// Keeps [frame] loaded, the frames used longest ago going where one
  /// image has more than [weatherPreloadMaxFrames] or all more than
  /// [weatherPreloadMaxPixels]; never one shown.
  void _store(_RadarImage frame) {
    _frames[frame.key] = frame;
    _touch(frame.key);
    final shown = <String>{for (final f in _shown.values) f.key, frame.key};
    List<String> byAge(bool Function(_RadarImage) which) => <String>[
      for (final MapEntry(:key, :value) in _frames.entries)
        if (!shown.contains(key) && which(value)) key,
    ]..sort((a, b) => (_frameUse[a] ?? 0).compareTo(_frameUse[b] ?? 0));
    final slot = frame.layer.id;
    var count = _frames.values.where((f) => f.layer.id == slot).length;
    for (final key in byAge((f) => f.layer.id == slot)) {
      if (count <= weatherPreloadMaxFrames) break;
      _drop(key);
      count--;
    }
    var pixels = 0;
    for (final f in _frames.values) {
      pixels += f.pixels;
    }
    for (final key in byAge((_) => true)) {
      if (pixels <= weatherPreloadMaxPixels) break;
      pixels -= _frames[key]?.pixels ?? 0;
      _drop(key);
    }
  }

  void _drop(String key) {
    _frames.remove(key);
    _frameUse.remove(key);
  }

  void _touch(String key) => _frameUse[key] = ++_useCount;

  /// Lets go of the loaded frames no step of the time control draws over
  /// the view any more (a newer measurement made them old).
  void _pruneFrames() {
    final map = _map;
    final view = map?.visibleBounds;
    if (map == null || view == null || _frames.isEmpty) return;
    final now = _clock();
    final wanted = <String>{
      for (final step in weatherRadarOffsets)
        for (final p in _stepPlan(step, view, map.zoom, now))
          for (final slot in p.slots) slot.key,
    };
    for (final key in _frames.keys.toList()) {
      if (!wanted.contains(key)) _drop(key);
    }
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
      shownOffset: _shownOffset,
      failed: <WeatherKind>{for (final source in failing) source.kind},
      failedRain: <RainRole>{
        for (final source in failing)
          if (source.kind == WeatherKind.radar) source.role,
      },
      newest: Map<String, DateTime>.unmodifiable(_newest),
      missing: Set<String>.unmodifiable(_satellitesDown),
    );
  }
}

/// A wind grid in memory: the source and the request it came from, the
/// hour it shows, when it was fetched and its credit.
@immutable
class _WindShown {
  const _WindShown({
    required this.source,
    required this.request,
    required this.time,
    required this.run,
    required this.grid,
    required this.fetchedAt,
    required this.attribution,
  });

  final String source;
  final WindRequest request;
  final DateTime time;
  final DateTime? run;
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

/// One image a rain part draws at a step: its layer's id (the source's,
/// with the piece of the view), its box, the moment and masks it shows
/// ([stamp]) and the [key] naming it.
@immutable
class _Slot {
  const _Slot({
    required this.id,
    required this.box,
    required this.stamp,
    required this.key,
  });

  final String id;
  final BoundingBox box;
  final String stamp;
  final String key;
}

/// What one rain part draws at a step: [tiles], or images ([slots]) asked
/// for over [areas] at [zoom], masked by [mask]; `null` there while it
/// waits for the frames it is cut by.
@immutable
class _PartPlan {
  const _PartPlan({
    required this.part,
    this.tiles = false,
    this.mask,
    this.areas = const <BoundingBox>[],
    this.zoom = 0,
    this.slots = const <_Slot>[],
  });

  final RainPart part;
  final bool tiles;
  final _RainMask? mask;
  final List<BoundingBox> areas;
  final double zoom;
  final List<_Slot> slots;

  /// Waiting for the frames it is cut by.
  bool get waiting => !tiles && mask == null;

  /// Wholly left to those before it.
  bool get hidden => mask?.hides ?? false;
}

/// A rain image loaded: the layer drawn, the [areas] it was asked for
/// (the pieces of the view and their margin, a model's grown to its cells,
/// before the coverage clips them), the zoom it was asked at, the moment
/// it shows and whether it is [capped] coarser than the source's own
/// resolution.
@immutable
class _RadarImage {
  const _RadarImage({
    required this.layer,
    required this.areas,
    required this.zoom,
    required this.stamp,
    required this.capped,
    this.coverage,
    this.pixels = 0,
  });

  final WeatherLayer layer;
  final List<BoundingBox> areas;
  final double zoom;
  final String stamp;
  final bool capped;

  /// Where the frame measures, for a source with an extent drawn soft.
  final RainCoverage? coverage;

  /// How many pixels the image holds.
  final int pixels;

  /// What names it: its layer's frame key.
  String get key => layer.frameKey;

  /// Whether it still serves [view] at [zoom]: the view inside its areas
  /// ([weatherAreasServe]), and, where the image is coarser than the
  /// source's own cells, the zoom less than [cloudDetailRezoom] further in.
  /// At the source's own resolution zooming in brings nothing finer.
  bool fits(BoundingBox view, double zoom) =>
      (!capped || zoom - this.zoom < cloudDetailRezoom) &&
      weatherAreasServe(areas, view);

  _RadarImage withImage(Uint8List image, RainCoverage? coverage) {
    final (w, h) = pngSize(image) ?? (1, 1);
    return _RadarImage(
      layer: WeatherLayer.image(
        id: layer.id,
        kind: layer.kind,
        image: image,
        imageBox: layer.imageBox!,
        frameKey: layer.frameKey,
        attribution: layer.attribution,
        opacity: layer.opacity,
      ),
      areas: areas,
      zoom: zoom,
      stamp: stamp,
      capped: capped,
      coverage: coverage,
      pixels: w * h,
    );
  }
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

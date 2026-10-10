import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../data/weather_fetcher.dart';
import '../data/weather_map_preferences.dart';
import '../domain/map_controller.dart';
import '../domain/weather_map.dart';

/// How often the radar looks for a newer frame while it is on.
const Duration radarRefreshInterval = Duration(minutes: 5);

/// How often the clouds do.
const Duration cloudsRefreshInterval = Duration(minutes: 10);

/// The zoom the radar's probe tile is asked at: low, so it is one cheap
/// tile around the middle of the view.
const int weatherProbeZoom = 5;

/// What the weather layers on a map say about themselves, for the time
/// control and its hints.
@immutable
class WeatherMapStatus {
  /// Creates the status.
  const WeatherMapStatus({
    this.radarFrame,
    this.cloudsFrame,
    this.failed = const <WeatherKind>{},
    this.forecastElsewhere = false,
  });

  /// The moment the radar shows, UTC; `null` while it is off.
  final DateTime? radarFrame;

  /// The moment the clouds in view show, UTC, where the service names it.
  final DateTime? cloudsFrame;

  /// The kinds of which a source over the view did not answer.
  final Set<WeatherKind> failed;

  /// Whether a moment ahead is chosen and no radar over the view
  /// forecasts it.
  final bool forecastElsewhere;

  @override
  bool operator ==(Object other) =>
      other is WeatherMapStatus &&
      other.radarFrame == radarFrame &&
      other.cloudsFrame == cloudsFrame &&
      setEquals(other.failed, failed) &&
      other.forecastElsewhere == forecastElsewhere;

  @override
  int get hashCode => Object.hash(
    radarFrame,
    cloudsFrame,
    Object.hashAllUnordered(failed),
    forecastElsewhere,
  );

  @override
  String toString() =>
      'WeatherMapStatus(radar: $radarFrame, clouds: $cloudsFrame, '
      'failed: $failed, forecastElsewhere: $forecastElsewhere)';
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
/// is their check. A source that does not answer is reported in [status],
/// so the map can say so instead of looking like a dry, clear day.
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
  bool _foreground = true;
  bool _disposed = false;
  Timer? _radarTimer;
  Timer? _cloudsTimer;

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

  List<WeatherLayer> _drawn = const <WeatherLayer>[];
  DateTime? _radarFrame;
  DateTime? _cloudsFrame;
  bool _forecastElsewhere = false;

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
    _resetTimers();
  }

  /// Follows new settings, sources and the time control's [offsetMinutes].
  void configure({
    required WeatherMapSettings settings,
    required List<WeatherMapSource> sources,
    required int offsetMinutes,
  }) {
    if (settings == _settings &&
        listEquals(sources, _sources) &&
        offsetMinutes == _offset) {
      return;
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
    if (turnedOn.contains(WeatherKind.clouds)) _attempted.clear();
    // Clouds switched off let their images go.
    if (!settings.clouds) _images.clear();
    _update();
    _resetTimers();
  }

  /// Whether the app is in the foreground: refreshes run only then, and
  /// coming back checks at once.
  void setForeground(bool foreground) {
    if (foreground == _foreground) return;
    _foreground = foreground;
    if (foreground) {
      _attempted.clear();
      _update(recheck: true);
    }
    _resetTimers();
  }

  /// Stops for good.
  void dispose() {
    _disposed = true;
    detach(clear: false);
    _radarTimer?.cancel();
    _cloudsTimer?.cancel();
    _status.dispose();
  }

  void _onCameraIdle() => _update();

  void _resetTimers() {
    _radarTimer?.cancel();
    _cloudsTimer?.cancel();
    _radarTimer = null;
    _cloudsTimer = null;
    if (_disposed || _map == null || !_foreground) return;
    if (_settings.radar) {
      _radarTimer = Timer.periodic(
        radarRefreshInterval,
        (_) => _update(recheck: true),
      );
    }
    if (_settings.clouds) {
      _cloudsTimer = Timer.periodic(cloudsRefreshInterval, (_) {
        _attempted.clear();
        _update();
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
    }

    _radarFrame = null;
    var forecastCovered = false;
    for (final source in _enabled(WeatherKind.radar)) {
      if (source.timeFormat != WeatherTimeFormat.none) {
        _radarFrame ??= latestFrameTime(
          now,
          stepMinutes: source.stepMinutes,
          delayMinutes: source.delayMinutes,
        ).add(Duration(minutes: _offset));
      }
      if (view == null || !source.covers(view)) {
        // Out of the view: checked again when the view comes back.
        _probed.remove(source.id);
        continue;
      }
      final frame = source.frameAt(now, offsetMinutes: _offset);
      if (frame == null) continue;
      covering.add(source.id);
      if (_offset > 0) forecastCovered = true;
      layers.add(WeatherLayer.ofRadar(source, frame, now));
      final probe = source.probeUrl(frame, view.center, weatherProbeZoom);
      if (recheck || _probed[source.id] != probe) {
        _probed[source.id] = probe;
        unawaited(_probe(source.id, probe));
      }
    }
    _forecastElsewhere =
        _settings.radar && _offset > 0 && view != null && !forecastCovered;
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

  void _publish() {
    if (_disposed) return;
    _status.value = WeatherMapStatus(
      radarFrame: _settings.radar ? _radarFrame : null,
      cloudsFrame: _settings.clouds ? _cloudsFrame : null,
      failed: <WeatherKind>{
        for (final source in _sources)
          if (_covering.contains(source.id) && _failed.contains(source.id))
            source.kind,
      },
      forecastElsewhere: _forecastElsewhere,
    );
  }
}

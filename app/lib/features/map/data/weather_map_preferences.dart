import 'dart:io' show Directory;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:velorki_api/velorki_api.dart';

import '../../../app/app_config.dart';
import '../../../core/http/user_agent.dart';
import '../../../core/plus/plus_gate.dart';
import '../../integrations/common/data/relay_client_provider.dart';
import '../../subscription/application/plus_access.dart';
import '../domain/weather_map.dart';
import 'weather_fetcher.dart';

part 'weather_map_preferences.g.dart';

const String _prefsRadar = 'map.weather.radar';
const String _prefsClouds = 'map.weather.clouds';
const String _prefsWind = 'map.weather.wind';
const String _prefsOverride = 'map.weather.override';
const String _prefsRadarOpacity = 'map.weather.radarOpacity';
const String _prefsCloudsOpacity = 'map.weather.cloudsOpacity';

/// How opaque the rain and the clouds are drawn until the rider says
/// otherwise, as a share of each layer's own opacity.
const double weatherOpacityDefault = 0.75;

/// The least share of its opacity a weather layer can be set to.
const double weatherOpacityMin = 0.2;

/// Which weather layers the rider switched on.
@immutable
class WeatherMapSettings {
  /// Creates the settings.
  const WeatherMapSettings({
    this.radar = false,
    this.clouds = false,
    this.wind = false,
  });

  /// The rain radar.
  final bool radar;

  /// The clouds.
  final bool clouds;

  /// The wind arrows.
  final bool wind;

  /// Whether [kind] is on.
  bool shows(WeatherKind kind) => switch (kind) {
    WeatherKind.radar => radar,
    WeatherKind.clouds => clouds,
    WeatherKind.wind => wind,
  };

  /// Whether any is on.
  bool get any => radar || clouds || wind;

  /// A copy with the layers named switched.
  WeatherMapSettings copyWith({bool? radar, bool? clouds, bool? wind}) =>
      WeatherMapSettings(
        radar: radar ?? this.radar,
        clouds: clouds ?? this.clouds,
        wind: wind ?? this.wind,
      );

  @override
  bool operator ==(Object other) =>
      other is WeatherMapSettings &&
      other.radar == radar &&
      other.clouds == clouds &&
      other.wind == wind;

  @override
  int get hashCode => Object.hash(radar, clouds, wind);

  @override
  String toString() =>
      'WeatherMapSettings(radar: $radar, clouds: $clouds, wind: $wind)';
}

/// The weather layers switched on, remembered across launches.
@Riverpod(keepAlive: true)
class WeatherMapPreferences extends _$WeatherMapPreferences {
  @override
  WeatherMapSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return WeatherMapSettings(
      radar: prefs.getBool(_prefsRadar) ?? false,
      clouds: prefs.getBool(_prefsClouds) ?? false,
      wind: prefs.getBool(_prefsWind) ?? false,
    );
  }

  /// Shows the rain radar or takes it away.
  Future<void> setRadar(bool value) async {
    state = state.copyWith(radar: value);
    await ref.read(sharedPreferencesProvider).setBool(_prefsRadar, value);
  }

  /// Shows the clouds or takes them away.
  Future<void> setClouds(bool value) async {
    state = state.copyWith(clouds: value);
    await ref.read(sharedPreferencesProvider).setBool(_prefsClouds, value);
  }

  /// Shows the wind arrows or takes them away.
  Future<void> setWind(bool value) async {
    state = state.copyWith(wind: value);
    await ref.read(sharedPreferencesProvider).setBool(_prefsWind, value);
  }
}

/// How opaque the rider wants the rain and the clouds: each a share, from
/// [weatherOpacityMin] to 1, of the layer's own opacity.
@immutable
class WeatherOpacity {
  /// Creates the shares.
  const WeatherOpacity({
    this.radar = weatherOpacityDefault,
    this.clouds = weatherOpacityDefault,
  });

  /// The rain's share.
  final double radar;

  /// The clouds' share.
  final double clouds;

  /// The share of [kind]; the wind's arrows keep theirs.
  double of(WeatherKind kind) => switch (kind) {
    WeatherKind.radar => radar,
    WeatherKind.clouds => clouds,
    WeatherKind.wind => 1,
  };

  @override
  bool operator ==(Object other) =>
      other is WeatherOpacity && other.radar == radar && other.clouds == clouds;

  @override
  int get hashCode => Object.hash(radar, clouds);

  @override
  String toString() => 'WeatherOpacity(radar: $radar, clouds: $clouds)';
}

/// How opaque the rain and the clouds are drawn, remembered across
/// launches.
@Riverpod(keepAlive: true)
class WeatherMapOpacity extends _$WeatherMapOpacity {
  @override
  WeatherOpacity build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    double read(String key) => (prefs.getDouble(key) ?? weatherOpacityDefault)
        .clamp(weatherOpacityMin, 1.0);
    return WeatherOpacity(
      radar: read(_prefsRadarOpacity),
      clouds: read(_prefsCloudsOpacity),
    );
  }

  /// Draws the rain at [value] of its opacity; remembered only with [save]
  /// (a slider saves when let go).
  Future<void> setRadar(double value, {bool save = true}) async {
    final share = value.clamp(weatherOpacityMin, 1.0);
    state = WeatherOpacity(radar: share, clouds: state.clouds);
    if (!save) return;
    await ref
        .read(sharedPreferencesProvider)
        .setDouble(_prefsRadarOpacity, share);
  }

  /// Draws the clouds at [value] of their opacity; remembered only with
  /// [save].
  Future<void> setClouds(double value, {bool save = true}) async {
    final share = value.clamp(weatherOpacityMin, 1.0);
    state = WeatherOpacity(radar: state.radar, clouds: share);
    if (!save) return;
    await ref
        .read(sharedPreferencesProvider)
        .setDouble(_prefsCloudsOpacity, share);
  }
}

/// How long the app may be away before the rain's time control is back on
/// "Now" when it returns: a step chosen for a ride later the same hour
/// stays, one from the morning does not.
const Duration weatherStepResetAfter = Duration(minutes: 30);

/// Where the rain's time control stands, in minutes from now: 0 is "Now",
/// else one of [weatherRadarOffsets]. One for the Plan, Record and Library
/// tabs, for this launch only, and back on "Now" when the app returns after
/// more than [weatherStepResetAfter] away.
@Riverpod(keepAlive: true)
class WeatherRadarOffset extends _$WeatherRadarOffset {
  DateTime? _hiddenAt;

  @override
  int build() => 0;

  /// Moves the control, to the nearest step.
  void set(int minutes) => state = snapWeatherOffset(minutes);

  /// The app went to the background at [at].
  void hidden(DateTime at) => _hiddenAt ??= at;

  /// The app came back at [at]: after long enough away, back to "Now".
  void shown(DateTime at) {
    final hidden = _hiddenAt;
    _hiddenAt = null;
    if (hidden != null && at.difference(hidden) > weatherStepResetAfter) {
      state = 0;
    }
  }
}

/// The step of the time control under the finger while its slider is
/// dragged, `null` while it is not: the map shows that step at once where
/// its frames are loaded (see `WeatherMapDriver.preview`), and the step is
/// set ([WeatherRadarOffset]) only when the slider is let go.
@Riverpod(keepAlive: true)
class WeatherRadarPreview extends _$WeatherRadarPreview {
  @override
  int? build() => null;

  /// The finger is on [minutes] (snapped to the nearest step), or with
  /// `null` let go.
  void set(int? minutes) =>
      state = minutes == null ? null : snapWeatherOffset(minutes);
}

/// The weather sources in force: the built-in ones, as the tile mirror's
/// `weatherLayers` last said (kept, so it holds offline); with Velorki Plus
/// granted, in a build with the relay, the relay's radars as well: the
/// DPC's over Italy and OPERA across Europe ([withDpcRadar],
/// [withOperaRadar]), which the mirror can switch off by their ids as any
/// other.
@Riverpod(keepAlive: true)
class WeatherMapSources extends _$WeatherMapSources {
  @override
  List<WeatherMapSource> build() {
    final stored = ref
        .watch(sharedPreferencesProvider)
        .getString(_prefsOverride);
    return _compose(
      stored,
      relay: ref.watch(relayClientProvider),
      access: ref.watch(plusAccessProvider(PlusFeature.weather)),
    );
  }

  static List<WeatherMapSource> _compose(
    String? stored, {
    required RelayClient? relay,
    required PlusAccess access,
  }) {
    if (relay == null || access != PlusAccess.granted) {
      return applyWeatherOverride(
        defaultWeatherMapSources,
        decodeWeatherOverride(stored),
      );
    }
    final base = relay.uriFor('/').toString();
    final defaults = withDpcRadar(
      withOperaRadar(defaultWeatherMapSources, base),
      base,
    );
    return applyWeatherOverride(defaults, decodeWeatherOverride(stored));
  }

  /// Takes the `weatherLayers` value of the mirror's pointer that was just
  /// read; `null` when it had none, which means the defaults.
  Future<void> applyPointer(Object? weatherLayers) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final encoded = encodeWeatherOverride(weatherLayers);
    if (encoded == prefs.getString(_prefsOverride)) return;
    if (encoded == null) {
      await prefs.remove(_prefsOverride);
    } else {
      await prefs.setString(_prefsOverride, encoded);
    }
    state = _compose(
      encoded,
      relay: ref.read(relayClientProvider),
      access: ref.read(plusAccessProvider(PlusFeature.weather)),
    );
  }
}

/// Whether any source of [kind] is in use: a fork or the mirror that turns
/// them all off takes the switch away.
bool weatherKindAvailable(List<WeatherMapSource> sources, WeatherKind kind) =>
    sources.any((s) => s.enabled && s.kind == kind);

/// The network the weather layers are fetched over. Only the requests to
/// the relay's radars carry the rider's credentials ([relayAuthFor]).
@Riverpod(keepAlive: true)
WeatherFetcher weatherFetcher(Ref ref) {
  final dio = velorkiDio();
  ref.onDispose(dio.close);
  return HttpWeatherFetcher(
    dio: dio,
    cacheDir: () async => Directory(
      p.join((await getApplicationCacheDirectory()).path, 'clouds'),
    ),
    headersFor: (url) => relayAuthFor(ref.read(relayClientProvider), url),
  );
}

import 'dart:io' show Directory;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/app_config.dart';
import '../../../core/http/user_agent.dart';
import '../domain/weather_map.dart';
import 'weather_fetcher.dart';

part 'weather_map_preferences.g.dart';

const String _prefsRadar = 'map.weather.radar';
const String _prefsClouds = 'map.weather.clouds';
const String _prefsOverride = 'map.weather.override';

/// Which weather layers the rider switched on.
@immutable
class WeatherMapSettings {
  /// Creates the settings.
  const WeatherMapSettings({this.radar = false, this.clouds = false});

  /// The rain radar.
  final bool radar;

  /// The clouds.
  final bool clouds;

  /// Whether [kind] is on.
  bool shows(WeatherKind kind) => switch (kind) {
    WeatherKind.radar => radar,
    WeatherKind.clouds => clouds,
  };

  /// Whether either is on.
  bool get any => radar || clouds;

  @override
  bool operator ==(Object other) =>
      other is WeatherMapSettings &&
      other.radar == radar &&
      other.clouds == clouds;

  @override
  int get hashCode => Object.hash(radar, clouds);

  @override
  String toString() => 'WeatherMapSettings(radar: $radar, clouds: $clouds)';
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
    );
  }

  /// Shows the rain radar or takes it away.
  Future<void> setRadar(bool value) async {
    state = WeatherMapSettings(radar: value, clouds: state.clouds);
    await ref.read(sharedPreferencesProvider).setBool(_prefsRadar, value);
  }

  /// Shows the clouds or takes them away.
  Future<void> setClouds(bool value) async {
    state = WeatherMapSettings(radar: state.radar, clouds: value);
    await ref.read(sharedPreferencesProvider).setBool(_prefsClouds, value);
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

/// The weather sources in force: the built-in ones, as the tile mirror's
/// `weatherLayers` last said (kept, so it holds offline).
@Riverpod(keepAlive: true)
class WeatherMapSources extends _$WeatherMapSources {
  @override
  List<WeatherMapSource> build() {
    final stored = ref
        .watch(sharedPreferencesProvider)
        .getString(_prefsOverride);
    return applyWeatherOverride(
      defaultWeatherMapSources,
      decodeWeatherOverride(stored),
    );
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
    state = applyWeatherOverride(
      defaultWeatherMapSources,
      decodeWeatherOverride(encoded),
    );
  }
}

/// Whether any source of [kind] is in use: a fork or the mirror that turns
/// them all off takes the switch away.
bool weatherKindAvailable(List<WeatherMapSource> sources, WeatherKind kind) =>
    sources.any((s) => s.enabled && s.kind == kind);

/// The network the weather layers are fetched over.
@Riverpod(keepAlive: true)
WeatherFetcher weatherFetcher(Ref ref) {
  final dio = velorkiDio();
  ref.onDispose(dio.close);
  return HttpWeatherFetcher(
    dio: dio,
    cacheDir: () async => Directory(
      p.join((await getApplicationCacheDirectory()).path, 'clouds'),
    ),
  );
}

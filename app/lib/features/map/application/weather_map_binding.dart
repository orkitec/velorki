import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../settings/data/appearance_controller.dart';
import '../data/weather_map_preferences.dart';
import '../domain/map_controller.dart';
import 'weather_map_driver.dart';

part 'weather_map_binding.g.dart';

/// What the weather layers on the shell's map say about themselves, for
/// the time control over it.
@Riverpod(keepAlive: true)
class SharedWeatherMapStatus extends _$SharedWeatherMapStatus {
  @override
  WeatherMapStatus build() => const WeatherMapStatus();

  /// Sets it; the shell's map host does.
  void set(WeatherMapStatus value) => state = value;
}

/// Puts the weather layers on a map host's map as the settings say: one
/// [WeatherMapDriver] per host, attached to whatever map the host has now,
/// fed the settings, the sources, the time control, the radar's look and
/// whether the app is in the foreground.
///
/// A host makes one in `initState`, calls [listen] from `build`, [attach]
/// with each map it is handed and [dispose] when it goes.
class WeatherMapBinding {
  /// A binding reading providers through [ref].
  WeatherMapBinding(this._ref)
    : driver = WeatherMapDriver(fetcher: _ref.read(weatherFetcherProvider)) {
    _configure();
    _lifecycle = AppLifecycleListener(
      onShow: () => driver.setForeground(true),
      onHide: () => driver.setForeground(false),
    );
  }

  final WidgetRef _ref;

  /// The driver, whose `status` a screen can show.
  final WeatherMapDriver driver;

  late final AppLifecycleListener _lifecycle;

  /// Draws on [map] from now on: a new map, or the same after a style
  /// reload.
  void attach(MapController map) => driver.attach(map);

  /// Follows the settings, the sources and the time control; call from the
  /// host's `build`.
  void listen() {
    _ref
      ..listen(weatherMapPreferencesProvider, (_, _) => _configure())
      ..listen(weatherMapSourcesProvider, (_, _) => _configure())
      ..listen(weatherRadarOffsetProvider, (_, _) => _configure())
      ..listen(
        appearanceSettingProvider.select((a) => a.radarStyle),
        (_, _) => _configure(),
      );
  }

  void _configure() => driver.configure(
    settings: _ref.read(weatherMapPreferencesProvider),
    sources: _ref.read(weatherMapSourcesProvider),
    offsetMinutes: _ref.read(weatherRadarOffsetProvider),
    radarStyle: _ref.read(appearanceSettingProvider).radarStyle,
  );

  /// Stops for good.
  void dispose() {
    _lifecycle.dispose();
    driver.dispose();
  }
}

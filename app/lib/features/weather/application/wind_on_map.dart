import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/app_config.dart';

part 'wind_on_map.g.dart';

const String _prefsWindOnMap = 'weather.wind_on_map';

/// Whether the planned route is drawn in the colours of the wind on it.
/// Off until the rider switches it on; remembered across launches.
@Riverpod(keepAlive: true)
class WindOnMap extends _$WindOnMap {
  @override
  bool build() =>
      ref.watch(sharedPreferencesProvider).getBool(_prefsWindOnMap) ?? false;

  /// Switches the wind on the map on or off.
  Future<void> set(bool on) async {
    state = on;
    await ref.read(sharedPreferencesProvider).setBool(_prefsWindOnMap, on);
  }
}

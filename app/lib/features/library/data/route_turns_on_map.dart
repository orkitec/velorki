import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_config.dart';

const String _prefsTurnsOnMap = 'routes.turnsOnMap';

/// Whether a route page marks every turn of its cue sheet on the map. Off
/// until the rider switches it on: a route with a hundred turns is a map
/// of dots. The key is removed rather than written when it goes back off,
/// so the stored preferences only hold the choice the rider made.
class RouteTurnsOnMapSetting extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(sharedPreferencesProvider).getBool(_prefsTurnsOnMap) ?? false;

  /// Shows or hides the turns and remembers the choice.
  Future<void> set(bool value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (value) {
      await prefs.setBool(_prefsTurnsOnMap, true);
    } else {
      await prefs.remove(_prefsTurnsOnMap);
    }
    state = value;
  }
}

/// Whether route pages mark the turns on the map.
final routeTurnsOnMapProvider = NotifierProvider<RouteTurnsOnMapSetting, bool>(
  RouteTurnsOnMapSetting.new,
);

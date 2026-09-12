import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/app_config.dart';
import '../domain/routing_preference.dart';

part 'routing_preference_controller.g.dart';

const String _prefsRoutingPreference = 'routing.preference';

/// Settings → Advanced → Routing, persisted in shared_preferences.
@Riverpod(keepAlive: true)
class RoutingPreferenceSetting extends _$RoutingPreferenceSetting {
  @override
  RoutingPreference build() => RoutingPreference.fromName(
    ref.watch(sharedPreferencesProvider).getString(_prefsRoutingPreference),
  );

  /// Stores [value] and re-builds the routing backend.
  Future<void> set(RoutingPreference value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (value == RoutingPreference.auto) {
      await prefs.remove(_prefsRoutingPreference);
    } else {
      await prefs.setString(_prefsRoutingPreference, value.name);
    }
    state = value;
  }
}

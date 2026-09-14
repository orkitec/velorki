import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_config.dart';

const String _prefsFollow = 'recording.follow';

/// How the camera is oriented while it follows the rider.
enum FollowMode {
  /// North stays up and the puck moves across the map.
  northUp,

  /// The map rotates so the direction of travel points up, the way a
  /// navigation app holds it.
  headingUp;

  /// The mode named [name], or [northUp] when the name is unknown.
  static FollowMode fromName(String? name) => FollowMode.values.firstWhere(
    (mode) => mode.name == name,
    orElse: () => northUp,
  );
}

/// The follow style of the Record tab, kept in shared_preferences so a rider
/// who prefers a rotating map gets it again on the next ride without asking.
class FollowModeSetting extends Notifier<FollowMode> {
  @override
  FollowMode build() => FollowMode.fromName(
    ref.watch(sharedPreferencesProvider).getString(_prefsFollow),
  );

  /// Follows in [mode] from now on and remembers the choice.
  Future<void> select(FollowMode mode) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (mode == FollowMode.northUp) {
      await prefs.remove(_prefsFollow);
    } else {
      await prefs.setString(_prefsFollow, mode.name);
    }
    state = mode;
  }
}

/// The follow style a ride starts in and the locate button re-arms.
final followModeProvider = NotifierProvider<FollowModeSetting, FollowMode>(
  FollowModeSetting.new,
);

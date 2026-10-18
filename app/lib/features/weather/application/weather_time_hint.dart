import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/app_config.dart';

part 'weather_time_hint.g.dart';

const String _prefsNever = 'weather.time_hint_never';

/// Whether the Plan tab may still explain its time control
/// (`showWeatherTimeHint`): each time it moves nothing in view, until the
/// rider says not to, remembered across launches.
@Riverpod(keepAlive: true)
class WeatherTimeHint extends _$WeatherTimeHint {
  @override
  bool build() =>
      !(ref.read(sharedPreferencesProvider).getBool(_prefsNever) ?? false);

  /// Not to be shown again ([never]), or, the rider changing their mind,
  /// shown again.
  Future<void> setNever({required bool never}) async {
    state = !never;
    await ref.read(sharedPreferencesProvider).setBool(_prefsNever, never);
  }
}

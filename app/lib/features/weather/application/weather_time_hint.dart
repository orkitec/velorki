import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/app_config.dart';

part 'weather_time_hint.g.dart';

const String _prefsNever = 'weather.time_hint_never';

/// Whether the Plan tab may still explain its time control
/// (`showWeatherTimeHint`): at most once a run of the app, and never again
/// once the rider said so, remembered across launches.
@Riverpod(keepAlive: true)
class WeatherTimeHint extends _$WeatherTimeHint {
  @override
  bool build() =>
      !(ref.read(sharedPreferencesProvider).getBool(_prefsNever) ?? false);

  /// Shown in this run: not again until the app starts anew.
  void shown() => state = false;

  /// Not to be shown again, in this run or any other ([never]), or, the
  /// rider changing their mind, again in a later run.
  Future<void> setNever({required bool never}) async {
    state = false;
    await ref.read(sharedPreferencesProvider).setBool(_prefsNever, never);
  }
}

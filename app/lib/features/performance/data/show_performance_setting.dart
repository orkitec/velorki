import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_config.dart';

const String _prefsShowPerformance = 'debug.showPerformance';

/// Settings → About → Show performance: whether the frame rate, frame times
/// and memory are shown over the app. Off unless the rider turns it on.
class ShowPerformanceController extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(sharedPreferencesProvider).getBool(_prefsShowPerformance) ??
      false;

  /// Turns the box on or off, and keeps the choice.
  Future<void> set(bool value) async {
    state = value;
    await ref
        .read(sharedPreferencesProvider)
        .setBool(_prefsShowPerformance, value);
  }
}

/// See [ShowPerformanceController].
final NotifierProvider<ShowPerformanceController, bool>
showPerformanceProvider = NotifierProvider<ShowPerformanceController, bool>(
  ShowPerformanceController.new,
);

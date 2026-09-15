import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/app_config.dart';

part 'loop_preferences.g.dart';

/// Shortest loop the slider offers, in kilometres.
const double loopMinKm = 5;

/// Longest loop the slider offers, in kilometres.
const double loopMaxKm = 200;

/// Slider step in kilometres.
const double loopStepKm = 5;

/// Shortest loop the imperial slider offers, in miles.
const double loopMinMi = 3;

/// Longest loop the imperial slider offers, in miles.
const double loopMaxMi = 125;

/// Slider step in miles.
const double loopStepMi = 1;

/// The range the stored distance is kept in, in kilometres.
///
/// Wider than either slider on its own: three miles is a shade under five
/// kilometres and a hundred and twenty-five a shade over two hundred, and a
/// distance picked on one slider has to survive being stored.
const double loopStoredMinKm = 4.8;

/// The far end of that range.
const double loopStoredMaxKm = 201.2;

/// The distance a rider who has never moved the slider gets.
const double loopDefaultKm = 30;

const String _prefsLoopKm = 'loop.distance_km';

/// The loop distance the rider last asked for.
///
/// Most riders have one ride length they keep coming back to, so the slider
/// opens where they left it rather than at the default every time.
@Riverpod(keepAlive: true)
class LastLoopDistanceKm extends _$LastLoopDistanceKm {
  @override
  double build() {
    final saved = ref.watch(sharedPreferencesProvider).getDouble(_prefsLoopKm);
    if (saved == null) return loopDefaultKm;
    return saved.clamp(loopStoredMinKm, loopStoredMaxKm);
  }

  /// Remembers [km] for the next time the sheet opens.
  Future<void> save(double km) async {
    final wanted = km.clamp(loopStoredMinKm, loopStoredMaxKm);
    if (wanted == state) return;
    await ref.read(sharedPreferencesProvider).setDouble(_prefsLoopKm, wanted);
    state = wanted;
  }
}

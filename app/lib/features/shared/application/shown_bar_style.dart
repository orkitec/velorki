import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/theme.dart' show BarStyle;
import '../../../core/power/system_power_save.dart';
import '../../recording/data/battery_saver.dart';
import '../../settings/data/appearance_controller.dart';

part 'shown_bar_style.g.dart';

/// The [BarStyle] the shell hands its `FloatingBarStyle`: the rider's
/// choice, or [BarStyle.solid] while power is being saved, the phone's own
/// power-saving mode or a ride recorded in Velorki's battery saver. A blur
/// redrawn over a moving map every frame is the costliest thing the chrome
/// does. A ride without the saver keeps the glass.
@Riverpod(keepAlive: true)
BarStyle shownBarStyle(Ref ref) {
  if (ref.watch(barStyleOverrideProvider) != null) return BarStyle.solid;
  return ref.watch(
    appearanceSettingProvider.select((appearance) => appearance.barStyle),
  );
}

/// Why the glass is solid whatever the rider picked.
enum BarStyleOverride {
  /// The phone's own power-saving mode is on.
  systemPowerSave,

  /// A ride is being recorded in Velorki's battery saver.
  batterySaverRide,
}

/// Why [shownBarStyle] is solid now, `null` while the rider's choice is
/// shown; Settings → Appearance says it, so a pick that changes nothing on
/// screen is explained.
@Riverpod(keepAlive: true)
BarStyleOverride? barStyleOverride(Ref ref) {
  if (ref.watch(systemPowerSaveProvider).value ?? false) {
    return BarStyleOverride.systemPowerSave;
  }
  if (ref.watch(batterySaverActiveProvider)) {
    return BarStyleOverride.batterySaverRide;
  }
  return null;
}

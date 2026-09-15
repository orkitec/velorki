import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_config.dart';
import '../../../core/units/units.dart';

export '../../../core/units/units.dart' show UnitSystem;

const String _prefsUnits = 'units.system';

/// The countries that measure a ride in miles and feet. Everywhere else is
/// metric, so almost nobody ever has to touch the setting.
const Set<String> imperialCountries = <String>{'US', 'LR', 'MM'};

/// The country the phone is set to, upper case, or null when it says nothing.
///
/// A provider of its own so a test can put the rider in a country without
/// reaching for the platform.
final localeCountryProvider = Provider<String?>(
  (ref) => PlatformDispatcher.instance.locale.countryCode?.toUpperCase(),
);

/// Settings → Units, persisted in shared_preferences.
///
/// Nothing is written until the rider picks a side: until then the phone's
/// country decides, so an American install opens in miles without anyone
/// having to say so, and a rider who does choose keeps that choice even when
/// it is the one the country would have given them anyway.
class UnitsSetting extends Notifier<UnitSystem> {
  @override
  UnitSystem build() {
    final stored = ref.watch(sharedPreferencesProvider).getString(_prefsUnits);
    if (stored == null) return _fromLocale();
    // An unreadable value is treated like no value at all.
    return UnitSystem.values.firstWhere(
      (system) => system.name == stored,
      orElse: _fromLocale,
    );
  }

  UnitSystem _fromLocale() =>
      imperialCountries.contains(ref.read(localeCountryProvider))
      ? UnitSystem.imperial
      : UnitSystem.metric;

  /// Shows everything in [system] from now on and remembers the choice.
  Future<void> select(UnitSystem system) async {
    await ref
        .read(sharedPreferencesProvider)
        .setString(_prefsUnits, system.name);
    state = system;
  }
}

/// The units distances, speeds and heights are shown and spoken in.
final unitSystemProvider = NotifierProvider<UnitsSetting, UnitSystem>(
  UnitsSetting.new,
);

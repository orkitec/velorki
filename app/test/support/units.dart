import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:velorki/features/settings/data/units.dart';

export 'package:velorki/features/settings/data/units.dart' show UnitSystem;

/// A units setting pinned to [system], so a widget test can pump a screen in
/// miles or in kilometres without a shared_preferences stand-in.
Override pinnedUnits(UnitSystem system) =>
    unitSystemProvider.overrideWith(() => _PinnedUnits(system));

/// Everything shown in kilometres, metres and km/h.
final Override metricUnits = pinnedUnits(UnitSystem.metric);

/// Everything shown in miles, feet and mph.
final Override imperialUnits = pinnedUnits(UnitSystem.imperial);

class _PinnedUnits extends UnitsSetting {
  _PinnedUnits(this._system);

  final UnitSystem _system;

  @override
  UnitSystem build() => _system;
}

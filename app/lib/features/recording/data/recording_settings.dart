import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_config.dart';
import '../domain/gps_precision.dart';
import '../domain/split_length.dart';

const String _prefsPrecision = 'recording.precision';
const String _prefsSaver = 'recording.saver';
const String _prefsSplitLength = 'recording.splitLength';
const String _prefsKeepScreenOn = 'recording.keepScreenOn';

/// What the rider chose under Settings → Recording.
class RecordingSettings {
  /// Creates the settings. A normal-precision ride with no saver, on a
  /// screen that stays on, is what a rider who never opened the section gets.
  const RecordingSettings({
    this.precision = GpsPrecision.normal,
    this.saver = false,
    this.splitLength = SplitLength.auto,
    this.keepScreenOn = true,
  });

  /// How precisely the ride is recorded.
  final GpsPrecision precision;

  /// Whether battery saver is on: a dark map, no animations and the glance
  /// view while riding, and the coarsest GPS profile whatever [precision]
  /// says.
  final bool saver;

  /// How long a split on the ride page is.
  final SplitLength splitLength;

  /// Whether the screen is held on while a ride is recorded. One value, set
  /// from the Record sheet or from Settings, and kept for the next ride.
  final bool keepScreenOn;

  /// The profile a ride actually runs at: the saver overrules the choice
  /// above it, which is the whole point of one switch.
  GpsPrecision get effectivePrecision => saver ? GpsPrecision.saver : precision;

  /// A copy with the named fields replaced.
  RecordingSettings copyWith({
    GpsPrecision? precision,
    bool? saver,
    SplitLength? splitLength,
    bool? keepScreenOn,
  }) => RecordingSettings(
    precision: precision ?? this.precision,
    saver: saver ?? this.saver,
    splitLength: splitLength ?? this.splitLength,
    keepScreenOn: keepScreenOn ?? this.keepScreenOn,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecordingSettings &&
          other.precision == precision &&
          other.saver == saver &&
          other.splitLength == splitLength &&
          other.keepScreenOn == keepScreenOn;

  @override
  int get hashCode => Object.hash(precision, saver, splitLength, keepScreenOn);

  @override
  String toString() =>
      'RecordingSettings(precision: ${precision.name}, saver: $saver, '
      'splitLength: ${splitLength.name}, keepScreenOn: $keepScreenOn)';
}

/// The recording settings, kept in shared_preferences.
///
/// A key is removed rather than written when it goes back to its default, so
/// the stored preferences only ever hold the choices the rider actually made.
class RecordingSettingsController extends Notifier<RecordingSettings> {
  @override
  RecordingSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return RecordingSettings(
      precision: GpsPrecision.fromName(prefs.getString(_prefsPrecision)),
      saver: prefs.getBool(_prefsSaver) ?? false,
      splitLength: SplitLength.fromName(prefs.getString(_prefsSplitLength)),
      keepScreenOn: prefs.getBool(_prefsKeepScreenOn) ?? true,
    );
  }

  /// Picks how precisely rides are recorded.
  Future<void> setPrecision(GpsPrecision precision) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (precision == GpsPrecision.normal) {
      await prefs.remove(_prefsPrecision);
    } else {
      await prefs.setString(_prefsPrecision, precision.name);
    }
    state = state.copyWith(precision: precision);
  }

  /// Picks how long a split on the ride page is.
  Future<void> setSplitLength(SplitLength length) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (length == SplitLength.auto) {
      await prefs.remove(_prefsSplitLength);
    } else {
      await prefs.setString(_prefsSplitLength, length.name);
    }
    state = state.copyWith(splitLength: length);
  }

  /// Switches battery saver on or off.
  Future<void> setSaver(bool value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (value) {
      await prefs.setBool(_prefsSaver, value);
    } else {
      await prefs.remove(_prefsSaver);
    }
    state = state.copyWith(saver: value);
  }

  /// Holds the screen on during rides, or lets it sleep as usual.
  Future<void> setKeepScreenOn(bool value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (value) {
      await prefs.remove(_prefsKeepScreenOn);
    } else {
      await prefs.setBool(_prefsKeepScreenOn, value);
    }
    state = state.copyWith(keepScreenOn: value);
  }
}

/// The recording settings.
final recordingSettingsProvider =
    NotifierProvider<RecordingSettingsController, RecordingSettings>(
      RecordingSettingsController.new,
    );

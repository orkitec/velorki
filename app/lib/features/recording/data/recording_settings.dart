import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_config.dart';
import '../domain/gps_precision.dart';

const String _prefsPrecision = 'recording.precision';
const String _prefsSaver = 'recording.saver';

/// What the rider chose under Settings → Recording.
class RecordingSettings {
  /// Creates the settings. A normal-precision ride with no saver is what a
  /// rider who never opened the section gets.
  const RecordingSettings({
    this.precision = GpsPrecision.normal,
    this.saver = false,
  });

  /// How precisely the ride is recorded.
  final GpsPrecision precision;

  /// Whether battery saver is on: a dark map, no animations and the glance
  /// view while riding, and the coarsest GPS profile whatever [precision]
  /// says.
  final bool saver;

  /// The profile a ride actually runs at: the saver overrules the choice
  /// above it, which is the whole point of one switch.
  GpsPrecision get effectivePrecision => saver ? GpsPrecision.saver : precision;

  /// A copy with the named fields replaced.
  RecordingSettings copyWith({GpsPrecision? precision, bool? saver}) =>
      RecordingSettings(
        precision: precision ?? this.precision,
        saver: saver ?? this.saver,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecordingSettings &&
          other.precision == precision &&
          other.saver == saver;

  @override
  int get hashCode => Object.hash(precision, saver);

  @override
  String toString() =>
      'RecordingSettings(precision: ${precision.name}, saver: $saver)';
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
}

/// The recording settings.
final recordingSettingsProvider =
    NotifierProvider<RecordingSettingsController, RecordingSettings>(
      RecordingSettingsController.new,
    );

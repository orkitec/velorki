import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/recording/data/recording_settings.dart';
import 'package:velorki/features/recording/domain/gps_precision.dart';

Future<ProviderContainer> _containerWith(Map<String, Object> stored) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('GpsPrecision', () {
    test('reads back the name it was stored under', () {
      expect(GpsPrecision.fromName('saver'), GpsPrecision.saver);
      expect(GpsPrecision.fromName('precise'), GpsPrecision.precise);
    });

    test('a name from another version is the normal profile', () {
      expect(GpsPrecision.fromName('turbo'), GpsPrecision.normal);
      expect(GpsPrecision.fromName(null), GpsPrecision.normal);
    });
  });

  group('RecordingSettings', () {
    test('the saver overrules the precision the rider picked', () {
      const precise = RecordingSettings(precision: GpsPrecision.precise);

      expect(precise.effectivePrecision, GpsPrecision.precise);
      expect(
        precise.copyWith(saver: true).effectivePrecision,
        GpsPrecision.saver,
      );
    });

    test('two settings with the same choices are the same', () {
      const one = RecordingSettings(precision: GpsPrecision.saver);
      const same = RecordingSettings(precision: GpsPrecision.saver);

      expect(one, same);
      expect(one.hashCode, same.hashCode);
      expect(one, isNot(const RecordingSettings()));
      expect(
        one.toString(),
        'RecordingSettings(precision: saver, saver: false)',
      );
    });
  });

  group('recordingSettingsProvider', () {
    test('a rider who never opened the section records normally', () async {
      final container = await _containerWith(<String, Object>{});

      final settings = container.read(recordingSettingsProvider);

      expect(settings.precision, GpsPrecision.normal);
      expect(settings.saver, isFalse);
      expect(settings.effectivePrecision, GpsPrecision.normal);
    });

    test('the stored choices come back', () async {
      final container = await _containerWith(<String, Object>{
        'recording.precision': 'precise',
        'recording.saver': true,
      });

      final settings = container.read(recordingSettingsProvider);

      expect(settings.precision, GpsPrecision.precise);
      expect(settings.saver, isTrue);
      // With the saver on, the profile is the saver one whatever was picked.
      expect(settings.effectivePrecision, GpsPrecision.saver);
    });

    test('picking a precision writes it and shows it at once', () async {
      final container = await _containerWith(<String, Object>{});
      final prefs = container.read(sharedPreferencesProvider);

      await container
          .read(recordingSettingsProvider.notifier)
          .setPrecision(GpsPrecision.precise);

      expect(
        container.read(recordingSettingsProvider).precision,
        GpsPrecision.precise,
      );
      expect(prefs.getString('recording.precision'), 'precise');
    });

    test(
      'going back to normal removes the key rather than writing it',
      () async {
        final container = await _containerWith(<String, Object>{
          'recording.precision': 'saver',
        });
        final prefs = container.read(sharedPreferencesProvider);

        await container
            .read(recordingSettingsProvider.notifier)
            .setPrecision(GpsPrecision.normal);

        expect(prefs.containsKey('recording.precision'), isFalse);
        expect(
          container.read(recordingSettingsProvider).precision,
          GpsPrecision.normal,
        );
      },
    );

    test('the saver switch is stored only while it is on', () async {
      final container = await _containerWith(<String, Object>{});
      final prefs = container.read(sharedPreferencesProvider);
      final notifier = container.read(recordingSettingsProvider.notifier);

      await notifier.setSaver(true);
      expect(prefs.getBool('recording.saver'), isTrue);
      expect(container.read(recordingSettingsProvider).saver, isTrue);

      await notifier.setSaver(false);
      expect(prefs.containsKey('recording.saver'), isFalse);
      expect(container.read(recordingSettingsProvider).saver, isFalse);
    });
  });
}

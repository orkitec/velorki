import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/recording/data/recording_settings.dart';
import 'package:velorki/features/recording/domain/gps_precision.dart';
import 'package:velorki/features/recording/domain/split_length.dart';

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
        'RecordingSettings(precision: saver, saver: false, splitLength: auto, '
        'keepScreenOn: true)',
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
      expect(settings.keepScreenOn, isTrue, reason: 'on from the start');
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

    test('the split length is stored only when it is not automatic', () async {
      final container = await _containerWith(<String, Object>{});
      final controller = container.read(recordingSettingsProvider.notifier);
      expect(
        container.read(recordingSettingsProvider).splitLength,
        SplitLength.auto,
      );

      await controller.setSplitLength(SplitLength.five);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('recording.splitLength'), 'five');
      expect(
        container.read(recordingSettingsProvider).splitLength,
        SplitLength.five,
      );

      await controller.setSplitLength(SplitLength.auto);
      expect(prefs.getString('recording.splitLength'), isNull);
    });

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

    test('keeping the screen on is stored only once it is off, and survives '
        'a restart', () async {
      final container = await _containerWith(<String, Object>{});
      final prefs = container.read(sharedPreferencesProvider);
      final notifier = container.read(recordingSettingsProvider.notifier);

      await notifier.setKeepScreenOn(false);
      expect(prefs.getBool('recording.keepScreenOn'), isFalse);
      expect(container.read(recordingSettingsProvider).keepScreenOn, isFalse);

      // A new container over the same preferences: the app started again.
      final restarted = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(restarted.dispose);
      expect(restarted.read(recordingSettingsProvider).keepScreenOn, isFalse);

      await notifier.setKeepScreenOn(true);
      expect(prefs.containsKey('recording.keepScreenOn'), isFalse);
      expect(container.read(recordingSettingsProvider).keepScreenOn, isTrue);
    });
  });
}

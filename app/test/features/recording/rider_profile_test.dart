import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/recording/data/rider_profile_settings.dart';
import 'package:velorki/features/recording/domain/rider_profile.dart';

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
  group('RiderSex', () {
    test('reads back the name it was stored under, unknown is unspecified', () {
      expect(RiderSex.fromName('female'), RiderSex.female);
      expect(RiderSex.fromName('male'), RiderSex.male);
      expect(RiderSex.fromName('other'), RiderSex.unspecified);
      expect(RiderSex.fromName(null), RiderSex.unspecified);
    });
  });

  group('RiderProfile', () {
    test('the age and the maximum heart rate follow the year of birth', () {
      const profile = RiderProfile(birthYear: 1986);

      expect(profile.ageIn(2026), 40);
      expect(profile.effectiveMaxHeartRate(2026), 180);
      expect(const RiderProfile().ageIn(2026), isNull);
      expect(const RiderProfile().effectiveMaxHeartRate(2026), isNull);
    });

    test('a maximum the rider entered wins over the estimate', () {
      const profile = RiderProfile(birthYear: 1986, maxHeartRateBpm: 192);

      expect(profile.effectiveMaxHeartRate(2026), 192);
    });

    test('copyWith clears a field only when told to', () {
      const profile = RiderProfile(weightKg: 75, birthYear: 1986);

      expect(profile.copyWith(zones: true).weightKg, 75);
      expect(profile.copyWith(clearWeight: true).weightKg, isNull);
      expect(profile.copyWith(clearBirthYear: true).birthYear, isNull);
      expect(profile, const RiderProfile(weightKg: 75, birthYear: 1986));
      expect(profile.hashCode, profile.copyWith().hashCode);
    });
  });

  group('riderProfileProvider', () {
    test(
      'a rider who never opened the section has both estimates off',
      () async {
        final container = await _containerWith(<String, Object>{});

        expect(container.read(riderProfileProvider), const RiderProfile());
      },
    );

    test('reads the stored profile', () async {
      final container = await _containerWith(<String, Object>{
        'rider.calories': true,
        'rider.zones': true,
        'rider.weightKg': 75.0,
        'rider.birthYear': 1986,
        'rider.sex': 'male',
        'rider.maxHeartRateBpm': 185,
      });

      expect(
        container.read(riderProfileProvider),
        const RiderProfile(
          calories: true,
          zones: true,
          weightKg: 75,
          birthYear: 1986,
          sex: RiderSex.male,
          maxHeartRateBpm: 185,
        ),
      );
    });

    test('the setters clamp, store and clear', () async {
      final container = await _containerWith(<String, Object>{});
      final controller = container.read(riderProfileProvider.notifier);
      final prefs = await SharedPreferences.getInstance();

      await controller.setWeightKg(500);
      await controller.setBirthYear(1800);
      await controller.setMaxHeartRate(50);
      await controller.setSex(RiderSex.female);
      await controller.setCalories(true);
      expect(container.read(riderProfileProvider).weightKg, 250);
      expect(container.read(riderProfileProvider).birthYear, 1900);
      expect(container.read(riderProfileProvider).maxHeartRateBpm, 100);
      expect(prefs.getDouble('rider.weightKg'), 250);
      expect(prefs.getString('rider.sex'), 'female');
      expect(prefs.getBool('rider.calories'), isTrue);

      await controller.setWeightKg(null);
      await controller.setBirthYear(null);
      await controller.setMaxHeartRate(null);
      await controller.setSex(RiderSex.unspecified);
      await controller.setCalories(false);
      expect(container.read(riderProfileProvider), const RiderProfile());
      expect(prefs.getKeys(), isEmpty);
    });
  });
}

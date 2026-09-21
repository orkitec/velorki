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

  group('RiderBike', () {
    test('reads back the name it was stored under, unknown is road', () {
      expect(RiderBike.fromName('touring'), RiderBike.touring);
      expect(RiderBike.fromName('mountain'), RiderBike.mountain);
      expect(RiderBike.fromName('unicycle'), RiderBike.road);
      expect(RiderBike.fromName(null), RiderBike.road);
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

    test('the bike defaults to a 9 kg road bike and copies over', () {
      const profile = RiderProfile();

      expect(profile.estimatePower, isFalse);
      expect(profile.bikeWeightKg, 9);
      expect(profile.bike, RiderBike.road);
      final copy = profile.copyWith(
        estimatePower: true,
        bikeWeightKg: 12,
        bike: RiderBike.mountain,
      );
      expect(copy.estimatePower, isTrue);
      expect(copy.bikeWeightKg, 12);
      expect(copy.bike, RiderBike.mountain);
      expect(copy, isNot(profile));
      expect(copy.toString(), contains('bike: mountain'));
    });

    test('the power zones are off and without a threshold to start', () {
      const profile = RiderProfile();

      expect(profile.powerZones, isFalse);
      expect(profile.thresholdPowerW, isNull);
      final copy = profile.copyWith(powerZones: true, thresholdPowerW: 250);
      expect(copy.powerZones, isTrue);
      expect(copy.thresholdPowerW, 250);
      expect(copy.copyWith(clearThresholdPower: true).thresholdPowerW, isNull);
      expect(copy.copyWith().thresholdPowerW, 250);
      expect(copy, isNot(profile));
      expect(copy.toString(), contains('thresholdPowerW: 250'));
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
        'rider.estimatePower': true,
        'rider.bikeWeightKg': 11.5,
        'rider.bike': 'touring',
        'rider.powerZones': true,
        'rider.thresholdPowerW': 250,
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
          estimatePower: true,
          bikeWeightKg: 11.5,
          bike: RiderBike.touring,
          powerZones: true,
          thresholdPowerW: 250,
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
      await controller.setEstimatePower(true);
      await controller.setBikeWeightKg(100);
      await controller.setBike(RiderBike.mountain);
      await controller.setPowerZones(true);
      await controller.setThresholdPower(1000);
      expect(container.read(riderProfileProvider).weightKg, 250);
      expect(container.read(riderProfileProvider).bikeWeightKg, 40);
      expect(container.read(riderProfileProvider).bike, RiderBike.mountain);
      expect(container.read(riderProfileProvider).powerZones, isTrue);
      expect(container.read(riderProfileProvider).thresholdPowerW, 600);
      expect(prefs.getBool('rider.powerZones'), isTrue);
      expect(prefs.getInt('rider.thresholdPowerW'), 600);
      await controller.setThresholdPower(10);
      expect(container.read(riderProfileProvider).thresholdPowerW, 50);
      expect(prefs.getBool('rider.estimatePower'), isTrue);
      expect(prefs.getDouble('rider.bikeWeightKg'), 40);
      expect(prefs.getString('rider.bike'), 'mountain');
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
      await controller.setEstimatePower(false);
      await controller.setBikeWeightKg(null);
      await controller.setBike(RiderBike.road);
      await controller.setPowerZones(false);
      await controller.setThresholdPower(null);
      expect(container.read(riderProfileProvider), const RiderProfile());
      expect(prefs.getKeys(), isEmpty);
    });

    test('the default bike weight is not stored', () async {
      final container = await _containerWith(<String, Object>{});
      final controller = container.read(riderProfileProvider.notifier);
      final prefs = await SharedPreferences.getInstance();

      await controller.setBikeWeightKg(9);

      expect(container.read(riderProfileProvider).bikeWeightKg, 9);
      expect(prefs.containsKey('rider.bikeWeightKg'), isFalse);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/recording/data/rider_profile_settings.dart';
import 'package:velorki/features/recording/domain/rider_profile.dart';
import 'package:velorki/features/settings/data/units.dart';
import 'package:velorki/features/settings/presentation/rider_section.dart';

import '../../support/app.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Map<String, Object> initial = const <String, Object>{},
  String? country,
}) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      // The weight is asked in the rider's units; pin them to metric rather
      // than to the machine's locale, unless the test puts the rider in a
      // country.
      localeCountryProvider.overrideWithValue(country),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: testApp(
        home: const Scaffold(
          body: SingleChildScrollView(child: RiderSection()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expectNoClippedText(tester);
  return container;
}

Finder get _caloriesSwitch =>
    find.widgetWithText(SwitchListTile, l10n.settingsRiderCalories);

Finder get _zonesSwitch =>
    find.widgetWithText(SwitchListTile, l10n.settingsRiderZones);

void main() {
  testWidgets('both switches are off by default and no fields are asked', (
    tester,
  ) async {
    await _pump(tester);

    expect(tester.widget<SwitchListTile>(_caloriesSwitch).value, isFalse);
    expect(tester.widget<SwitchListTile>(_zonesSwitch).value, isFalse);
    expect(find.text(l10n.settingsRiderCaloriesHint), findsOneWidget);
    expect(find.text(l10n.settingsRiderZonesHint), findsOneWidget);
    expect(find.text(l10n.settingsRiderPrivacy), findsOneWidget);
    expect(find.byKey(riderWeightFieldKey), findsNothing);
    expect(find.byKey(riderBirthYearFieldKey), findsNothing);
    expect(find.byKey(riderMaxHeartRateFieldKey), findsNothing);
    expect(find.byType(SegmentedButton<RiderSex>), findsNothing);
  });

  testWidgets('switching calories on shows the fields and is remembered', (
    tester,
  ) async {
    final container = await _pump(tester);

    await tester.tap(_caloriesSwitch);
    await tester.pumpAndSettle();
    expectNoClippedText(tester);

    expect(container.read(riderProfileProvider).calories, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('rider.calories'), isTrue);
    expect(find.byKey(riderWeightFieldKey), findsOneWidget);
    expect(find.byKey(riderBirthYearFieldKey), findsOneWidget);
    expect(find.byKey(riderMaxHeartRateFieldKey), findsOneWidget);
    expect(find.text(l10n.settingsRiderMaxHeartRateHint), findsOneWidget);
    expect(find.byType(SegmentedButton<RiderSex>), findsOneWidget);
    expect(find.text(l10n.settingsRiderWeightKg), findsOneWidget);
  });

  testWidgets('the zones switch alone shows the fields too', (tester) async {
    await _pump(tester, initial: const <String, Object>{'rider.zones': true});

    expect(tester.widget<SwitchListTile>(_zonesSwitch).value, isTrue);
    expect(find.byKey(riderMaxHeartRateFieldKey), findsOneWidget);
  });

  testWidgets('typing a weight stores it in kilograms', (tester) async {
    final container = await _pump(
      tester,
      initial: const <String, Object>{'rider.calories': true},
    );

    await tester.enterText(find.byKey(riderWeightFieldKey), '75');
    await tester.pumpAndSettle();

    expect(container.read(riderProfileProvider).weightKg, 75.0);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('rider.weightKg'), 75.0);

    // Clearing the field clears the weight.
    await tester.enterText(find.byKey(riderWeightFieldKey), '');
    await tester.pumpAndSettle();
    expect(container.read(riderProfileProvider).weightKg, isNull);
    expect(prefs.containsKey('rider.weightKg'), isFalse);
  });

  testWidgets('under imperial units the weight is typed in pounds and stored '
      'in kilograms', (tester) async {
    final container = await _pump(
      tester,
      initial: const <String, Object>{'rider.calories': true},
      country: 'US',
    );

    expect(find.text(l10n.settingsRiderWeightLb), findsOneWidget);
    await tester.enterText(find.byKey(riderWeightFieldKey), '165');
    await tester.pumpAndSettle();

    expect(
      container.read(riderProfileProvider).weightKg,
      closeTo(165 * kgPerPound, 1e-9),
    );
  });

  testWidgets('the stored weight is shown in the rider\'s units', (
    tester,
  ) async {
    await _pump(
      tester,
      initial: const <String, Object>{
        'rider.calories': true,
        'rider.weightKg': 74.84274105,
      },
      country: 'US',
    );

    expect(
      tester
          .widget<TextFormField>(find.byKey(riderWeightFieldKey))
          .controller!
          .text,
      '165',
    );
  });

  testWidgets('year of birth, sex and maximum heart rate are stored', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      initial: const <String, Object>{'rider.zones': true},
    );

    await tester.enterText(find.byKey(riderBirthYearFieldKey), '1986');
    await tester.enterText(find.byKey(riderMaxHeartRateFieldKey), '185');
    await tester.tap(find.text(l10n.riderSexFemale));
    await tester.pumpAndSettle();

    final profile = container.read(riderProfileProvider);
    expect(profile.birthYear, 1986);
    expect(profile.maxHeartRateBpm, 185);
    expect(profile.sex, RiderSex.female);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('rider.birthYear'), 1986);
    expect(prefs.getInt('rider.maxHeartRateBpm'), 185);
    expect(prefs.getString('rider.sex'), 'female');
  });

  testWidgets('a half-typed number is not stored', (tester) async {
    final container = await _pump(
      tester,
      initial: const <String, Object>{'rider.zones': true},
    );

    await tester.enterText(find.byKey(riderBirthYearFieldKey), '19');
    await tester.enterText(find.byKey(riderMaxHeartRateFieldKey), '18');
    await tester.enterText(find.byKey(riderWeightFieldKey), '7');
    await tester.pumpAndSettle();

    final profile = container.read(riderProfileProvider);
    expect(profile.birthYear, isNull);
    expect(profile.maxHeartRateBpm, isNull);
    expect(profile.weightKg, isNull);
  });

  testWidgets('the stored profile is the one shown', (tester) async {
    await _pump(
      tester,
      initial: const <String, Object>{
        'rider.calories': true,
        'rider.weightKg': 75.0,
        'rider.birthYear': 1986,
        'rider.sex': 'male',
        'rider.maxHeartRateBpm': 185,
      },
    );

    expect(
      tester
          .widget<TextFormField>(find.byKey(riderWeightFieldKey))
          .controller!
          .text,
      '75',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(riderBirthYearFieldKey))
          .controller!
          .text,
      '1986',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(riderMaxHeartRateFieldKey))
          .controller!
          .text,
      '185',
    );
    expect(
      tester
          .widget<SegmentedButton<RiderSex>>(
            find.byType(SegmentedButton<RiderSex>),
          )
          .selected,
      {RiderSex.male},
    );
  });
}

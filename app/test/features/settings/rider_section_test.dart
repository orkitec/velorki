import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/recording/application/threshold_power_suggestion.dart';
import 'package:velorki/features/recording/data/rider_profile_settings.dart';
import 'package:velorki/features/recording/domain/rider_profile.dart';
import 'package:velorki/features/settings/data/units.dart';
import 'package:velorki/features/settings/presentation/rider_section.dart';

import '../../support/app.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Map<String, Object> initial = const <String, Object>{},
  String? country,
  int? suggestedThreshold,
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
      // No ride database here: the suggestion is whatever the test says.
      thresholdPowerSuggestionProvider.overrideWith(
        (ref) async => suggestedThreshold,
      ),
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

Finder get _powerSwitch =>
    find.widgetWithText(SwitchListTile, l10n.settingsRiderEstimatePower);

Finder get _powerZonesSwitch =>
    find.widgetWithText(SwitchListTile, l10n.settingsRiderPowerZones);

void main() {
  testWidgets('all switches are off by default and no fields are asked', (
    tester,
  ) async {
    await _pump(tester);

    expect(tester.widget<SwitchListTile>(_caloriesSwitch).value, isFalse);
    expect(tester.widget<SwitchListTile>(_zonesSwitch).value, isFalse);
    expect(tester.widget<SwitchListTile>(_powerSwitch).value, isFalse);
    expect(tester.widget<SwitchListTile>(_powerZonesSwitch).value, isFalse);
    expect(find.text(l10n.settingsRiderCaloriesHint), findsOneWidget);
    expect(find.text(l10n.settingsRiderZonesHint), findsOneWidget);
    expect(find.text(l10n.settingsRiderEstimatePowerHint), findsOneWidget);
    expect(find.text(l10n.settingsRiderPowerZonesHint), findsOneWidget);
    expect(find.text(l10n.settingsRiderPrivacy), findsOneWidget);
    expect(find.byKey(riderWeightFieldKey), findsNothing);
    expect(find.byKey(riderBirthYearFieldKey), findsNothing);
    expect(find.byKey(riderMaxHeartRateFieldKey), findsNothing);
    expect(find.byKey(riderBikeWeightFieldKey), findsNothing);
    expect(find.byKey(riderThresholdPowerFieldKey), findsNothing);
    expect(find.byType(SegmentedButton<RiderSex>), findsNothing);
    expect(find.byType(SegmentedButton<RiderBike>), findsNothing);
  });

  testWidgets('the power zones switch asks for the threshold power alone', (
    tester,
  ) async {
    final container = await _pump(tester);

    await tester.tap(_powerZonesSwitch);
    await tester.pumpAndSettle();
    expectNoClippedText(tester);

    expect(container.read(riderProfileProvider).powerZones, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('rider.powerZones'), isTrue);
    expect(find.byKey(riderThresholdPowerFieldKey), findsOneWidget);
    expect(find.text(l10n.settingsRiderThresholdPowerHint), findsOneWidget);
    expect(find.text(l10n.settingsRiderThresholdPowerUnit), findsOneWidget);
    // Neither the rider's own figures nor the bike: the zones need none of
    // them.
    expect(find.byKey(riderWeightFieldKey), findsNothing);
    expect(find.byKey(riderBirthYearFieldKey), findsNothing);
    expect(find.byKey(riderMaxHeartRateFieldKey), findsNothing);
    expect(find.byKey(riderBikeWeightFieldKey), findsNothing);
    expect(find.byType(SegmentedButton<RiderSex>), findsNothing);
    expect(find.byType(SegmentedButton<RiderBike>), findsNothing);
  });

  testWidgets('typing a threshold power stores it, in range only', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      initial: const <String, Object>{'rider.powerZones': true},
    );

    await tester.enterText(find.byKey(riderThresholdPowerFieldKey), '25');
    await tester.pumpAndSettle();
    expect(container.read(riderProfileProvider).thresholdPowerW, isNull);

    await tester.enterText(find.byKey(riderThresholdPowerFieldKey), '250');
    await tester.pumpAndSettle();
    expect(container.read(riderProfileProvider).thresholdPowerW, 250);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('rider.thresholdPowerW'), 250);

    await tester.enterText(find.byKey(riderThresholdPowerFieldKey), '');
    await tester.pumpAndSettle();
    expect(container.read(riderProfileProvider).thresholdPowerW, isNull);
    expect(prefs.containsKey('rider.thresholdPowerW'), isFalse);
  });

  testWidgets('the best twenty minutes of the rides are offered as the '
      'threshold, and one tap stores them', (tester) async {
    final container = await _pump(
      tester,
      initial: const <String, Object>{'rider.powerZones': true},
      suggestedThreshold: 235,
    );

    expect(find.byKey(riderThresholdSuggestKey), findsOneWidget);
    expect(
      find.text(l10n.settingsRiderThresholdSuggest(l10n.unitWatts('235'))),
      findsOneWidget,
    );
    // The helper stays: the suggestion is added under it, not in its place.
    expect(find.text(l10n.settingsRiderThresholdPowerHint), findsOneWidget);

    await tester.tap(find.byKey(riderThresholdSuggestKey));
    await tester.pumpAndSettle();

    expect(container.read(riderProfileProvider).thresholdPowerW, 235);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('rider.thresholdPowerW'), 235);
    expect(
      tester
          .widget<TextFormField>(find.byKey(riderThresholdPowerFieldKey))
          .controller!
          .text,
      '235',
    );
    // Taken, the offer is gone.
    expect(find.byKey(riderThresholdSuggestKey), findsNothing);
  });

  testWidgets('a threshold that already is the suggestion is not offered', (
    tester,
  ) async {
    await _pump(
      tester,
      initial: const <String, Object>{
        'rider.powerZones': true,
        'rider.thresholdPowerW': 235,
      },
      suggestedThreshold: 235,
    );

    expect(find.byKey(riderThresholdSuggestKey), findsNothing);
  });

  testWidgets('without a ride to take it from nothing is offered', (
    tester,
  ) async {
    await _pump(
      tester,
      initial: const <String, Object>{'rider.powerZones': true},
    );

    expect(find.byKey(riderThresholdSuggestKey), findsNothing);
    expect(find.byKey(riderThresholdPowerFieldKey), findsOneWidget);
  });

  testWidgets('the stored threshold is the one shown, after the bike', (
    tester,
  ) async {
    await _pump(
      tester,
      initial: const <String, Object>{
        'rider.estimatePower': true,
        'rider.powerZones': true,
        'rider.thresholdPowerW': 265,
      },
    );

    expect(
      tester
          .widget<TextFormField>(find.byKey(riderThresholdPowerFieldKey))
          .controller!
          .text,
      '265',
    );
    expect(
      tester.getTopLeft(find.byKey(riderThresholdPowerFieldKey)).dy,
      greaterThan(
        tester.getBottomLeft(find.byType(SegmentedButton<RiderBike>)).dy,
      ),
    );
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
    expect(find.text(l10n.settingsRiderWeightHint), findsOneWidget);
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
    // But nothing about the bike: that is the power estimate's business.
    expect(find.byKey(riderBikeWeightFieldKey), findsNothing);
    expect(find.byType(SegmentedButton<RiderBike>), findsNothing);
  });

  testWidgets('switching the power estimate on shows the rider fields and '
      'the bike fields, with a 9 kg road bike to start', (tester) async {
    final container = await _pump(tester);

    await tester.tap(_powerSwitch);
    await tester.pumpAndSettle();
    expectNoClippedText(tester);

    expect(container.read(riderProfileProvider).estimatePower, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('rider.estimatePower'), isTrue);
    expect(find.byKey(riderWeightFieldKey), findsOneWidget);
    expect(find.byKey(riderBikeWeightFieldKey), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(riderBikeWeightFieldKey))
          .controller!
          .text,
      '9',
    );
    expect(find.text(l10n.settingsRiderBike), findsOneWidget);
    expect(
      tester
          .widget<SegmentedButton<RiderBike>>(
            find.byType(SegmentedButton<RiderBike>),
          )
          .selected,
      {RiderBike.road},
    );
  });

  testWidgets('picking a bike and typing its weight are stored', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      initial: const <String, Object>{'rider.estimatePower': true},
    );

    // The bike sits under three switches and four fields, below the fold.
    await tester.ensureVisible(find.text(l10n.riderBikeMountain));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.riderBikeMountain));
    await tester.enterText(find.byKey(riderBikeWeightFieldKey), '10');
    await tester.pumpAndSettle();

    final profile = container.read(riderProfileProvider);
    expect(profile.bike, RiderBike.mountain);
    expect(profile.bikeWeightKg, 10.0);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('rider.bike'), 'mountain');
    expect(prefs.getDouble('rider.bikeWeightKg'), 10.0);
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
    // The sex sits under four switches and two fields, below the fold.
    await tester.ensureVisible(find.text(l10n.riderSexFemale));
    await tester.pumpAndSettle();
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

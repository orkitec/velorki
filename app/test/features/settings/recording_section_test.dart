import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/recording/data/recording_settings.dart';
import 'package:velorki/features/recording/domain/gps_precision.dart';
import 'package:velorki/features/settings/data/units.dart';
import 'package:velorki/features/recording/domain/split_length.dart';
import 'package:velorki/features/settings/presentation/recording_section.dart';

import '../../support/app.dart';
import '../../support/format.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Map<String, Object> initial = const <String, Object>{},
}) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      // The split lengths are shown in the rider's units; pin them to metric
      // rather than to the machine's locale.
      localeCountryProvider.overrideWithValue(null),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: testApp(home: const Scaffold(body: RecordingSection())),
    ),
  );
  await tester.pumpAndSettle();
  expectNoClippedText(tester);
  return container;
}

void main() {
  testWidgets('offers the split length, automatic by default, and stores a '
      'pick', (tester) async {
    final container = await _pump(tester);
    expect(find.text(l10n.settingsSplitLength), findsOneWidget);
    expect(find.text(l10n.splitLengthAuto), findsOneWidget);
    expect(find.text(testSplitLength(5000)), findsOneWidget);
    expect(
      tester
          .widget<SegmentedButton<SplitLength>>(
            find.byType(SegmentedButton<SplitLength>),
          )
          .selected,
      {SplitLength.auto},
    );

    await tester.tap(find.text(testSplitLength(5000)));
    await tester.pumpAndSettle();

    expect(
      container.read(recordingSettingsProvider).splitLength,
      SplitLength.five,
    );
  });

  testWidgets('offers the three profiles and the saver switch', (tester) async {
    await _pump(tester);

    expect(find.text(l10n.settingsGpsPrecision), findsOneWidget);
    expect(
      find.text(l10n.gpsPrecisionSaver),
      findsNWidgets(2),
    ); // segment and switch
    expect(find.text(l10n.gpsPrecisionNormal), findsOneWidget);
    expect(find.text(l10n.gpsPrecisionPrecise), findsOneWidget);
    expect(find.text(l10n.settingsGpsPrecisionHint), findsOneWidget);
    expect(find.text(l10n.settingsBatterySaverHint), findsOneWidget);
    expect(
      tester
          .widget<SegmentedButton<GpsPrecision>>(
            find.byType(SegmentedButton<GpsPrecision>),
          )
          .selected,
      {GpsPrecision.normal},
    );
  });

  testWidgets('picking Precise is remembered', (tester) async {
    final container = await _pump(tester);

    await tester.tap(find.text(l10n.gpsPrecisionPrecise));
    await tester.pumpAndSettle();

    expect(
      container.read(recordingSettingsProvider).precision,
      GpsPrecision.precise,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('recording.precision'), 'precise');
  });

  testWidgets('the saver switch is remembered', (tester) async {
    final container = await _pump(tester);
    final tile = find.byType(SwitchListTile);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);

    await tester.tap(tile);
    await tester.pumpAndSettle();

    expect(container.read(recordingSettingsProvider).saver, isTrue);
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('recording.saver'), isTrue);
  });

  testWidgets('the stored choices are the ones shown', (tester) async {
    await _pump(
      tester,
      initial: const <String, Object>{
        'recording.precision': 'saver',
        'recording.saver': true,
      },
    );

    expect(
      tester
          .widget<SegmentedButton<GpsPrecision>>(
            find.byType(SegmentedButton<GpsPrecision>),
          )
          .selected,
      {GpsPrecision.saver},
    );
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
  });
}

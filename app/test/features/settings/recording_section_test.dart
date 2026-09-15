import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/features/recording/data/recording_settings.dart';
import 'package:velorki/features/recording/domain/gps_precision.dart';
import 'package:velorki/features/settings/presentation/recording_section.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Map<String, Object> initial = const <String, Object>{},
}) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildLightTheme(),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: RecordingSection()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('offers the three profiles and the saver switch', (tester) async {
    await _pump(tester);

    expect(find.text('GPS precision'), findsOneWidget);
    expect(find.text('Battery saver'), findsNWidgets(2)); // segment and switch
    expect(find.text('Normal'), findsOneWidget);
    expect(find.text('Precise'), findsOneWidget);
    expect(
      find.text('Precise is for trails; Normal is enough for roads'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Dark map, no animations, a plain page with the numbers after 30 s; '
        'the screen is what drains the battery',
      ),
      findsOneWidget,
    );
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

    await tester.tap(find.text('Precise'));
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

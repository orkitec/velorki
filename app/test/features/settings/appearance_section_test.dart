import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/features/settings/data/appearance_controller.dart';
import 'package:velorki/features/settings/presentation/appearance_section.dart';
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
        home: const Scaffold(body: AppearanceSection()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// The tappable swatch carrying [label].
Finder _swatch(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(InkWell));

void main() {
  testWidgets('the section offers the three modes and the four accents', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);

    expect(find.byType(SegmentedButton<ThemeMode>), findsOneWidget);
    for (final label in ['System', 'Light', 'Dark']) {
      // "Light" is also a map look chip, so look inside the segments.
      expect(
        find.descendant(
          of: find.byType(SegmentedButton<ThemeMode>),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
    }
    for (final label in ['Follows theme', 'Night', 'Black']) {
      expect(find.widgetWithText(ChoiceChip, label), findsOneWidget);
    }
    for (final label in ['Volt', 'Ember', 'Glacier', 'Berry']) {
      expect(_swatch(label), findsOneWidget);
      // A screen reader hears the accent's name on the swatch.
      expect(tester.getSemantics(_swatch(label)).label, contains(label));
    }

    final segmented = tester.widget<SegmentedButton<ThemeMode>>(
      find.byType(SegmentedButton<ThemeMode>),
    );
    expect(segmented.selected, {ThemeMode.system});
    semantics.dispose();
  });

  testWidgets('tapping Dark switches the mode and stores it', (tester) async {
    final container = await _pump(tester);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(container.read(appearanceSettingProvider).mode, ThemeMode.dark);
    final segmented = tester.widget<SegmentedButton<ThemeMode>>(
      find.byType(SegmentedButton<ThemeMode>),
    );
    expect(segmented.selected, {ThemeMode.dark});
  });

  testWidgets('tapping the Ember swatch switches the accent', (tester) async {
    final container = await _pump(tester);
    expect(container.read(appearanceSettingProvider).accent, AccentPreset.volt);

    await tester.tap(_swatch('Ember'));
    await tester.pumpAndSettle();

    expect(
      container.read(appearanceSettingProvider).accent,
      AccentPreset.ember,
    );
  });

  testWidgets('the stored choice is the one shown when the section opens', (
    tester,
  ) async {
    await _pump(
      tester,
      initial: <String, Object>{
        'appearance.mode': 'light',
        'appearance.accent': 'berry',
      },
    );

    final segmented = tester.widget<SegmentedButton<ThemeMode>>(
      find.byType(SegmentedButton<ThemeMode>),
    );
    expect(segmented.selected, {ThemeMode.light});
    // The selected swatch is the one wearing the check mark.
    expect(
      find.descendant(
        of: _swatch('Berry'),
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  testWidgets('tapping Night switches the map look', (tester) async {
    final container = await _pump(tester);
    expect(container.read(appearanceSettingProvider).mapLook, MapLook.auto);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Night'));
    await tester.pumpAndSettle();

    expect(container.read(appearanceSettingProvider).mapLook, MapLook.night);
  });
}

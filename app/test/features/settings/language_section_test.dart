import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/features/settings/data/language_controller.dart';
import 'package:velorki/features/settings/presentation/language_section.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';

/// The row under a small app that shows a tab title, so a test can see the
/// whole app change language and not just the picker.
class _Harness extends ConsumerWidget {
  const _Harness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      theme: buildLightTheme(),
      locale: ref.watch(appLocaleProvider),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Column(
          children: [
            Builder(
              builder: (context) => Text(AppLocalizations.of(context).tabPlan),
            ),
            const LanguageSection(),
          ],
        ),
      ),
    );
  }
}

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
    UncontrolledProviderScope(container: container, child: const _Harness()),
  );
  await tester.pumpAndSettle();
  return container;
}

/// The languages the app ships: one `lib/l10n/app_<lang>.arb` each.
List<String> _shippedLanguages() => [
  for (final f in Directory('lib/l10n').listSync().whereType<File>())
    if (RegExp(r'^app_(\w+)\.arb$').firstMatch(f.uri.pathSegments.last)
        case final m?)
      m.group(1)!,
];

void main() {
  testWidgets('the row follows the system until a language is picked', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Language'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);
  });

  testWidgets('the picker offers the system and every shipped language', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();

    final shipped = _shippedLanguages();
    expect(shipped, containsAll(['en', 'de']));
    expect(
      find.byType(RadioListTile<Locale?>, skipOffstage: false),
      findsNWidgets(shipped.length + 1),
    );
    expect(find.text('System'), findsWidgets);
    for (final lang in shipped) {
      final name = languageName(Locale(lang));
      expect(name, isNot(lang), reason: '$lang has a native name');
      expect(find.text(name, skipOffstage: false), findsOneWidget);
    }
  });

  testWidgets('picking Deutsch translates the app and is persisted', (
    tester,
  ) async {
    final container = await _pump(tester);
    expect(find.text('Plan'), findsOneWidget);

    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deutsch'));
    await tester.pumpAndSettle();

    expect(container.read(appLocaleProvider), const Locale('de'));
    // The tab title, the row and its subtitle are all German now.
    expect(find.text('Planen'), findsOneWidget);
    expect(find.text('Sprache'), findsOneWidget);
    expect(find.text('Deutsch'), findsOneWidget);
  });

  testWidgets('going back to System hands the app to the phone again', (
    tester,
  ) async {
    final container = await _pump(tester, initial: {'language.locale': 'de'});
    expect(find.text('Planen'), findsOneWidget);

    await tester.tap(find.text('Sprache'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('System').last);
    await tester.pumpAndSettle();

    expect(container.read(appLocaleProvider), isNull);
    expect(find.text('Plan'), findsOneWidget);
  });
}

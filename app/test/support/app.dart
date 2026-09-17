import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';

/// The language the widget suite runs in.
///
/// `flutter test --dart-define=VELORKI_TEST_LOCALE=de` runs every
/// harness-built screen in German, which is how a translation that no longer
/// fits its layout fails CI.
const String testLocaleName = String.fromEnvironment(
  'VELORKI_TEST_LOCALE',
  defaultValue: 'en',
);

/// [testLocaleName] as a [Locale], handed to every app this file builds.
const Locale testLocale = Locale(testLocaleName);

/// Whether the suite runs in English, the locale the string expectations are
/// written in.
bool get isEnglishTestLocale => testLocaleName == 'en';

/// The strings of the locale under test, for expectations that would
/// otherwise hard-code English.
final AppLocalizations l10n = lookupAppLocalizations(testLocale);

/// A `skip:` value that runs the test in English and skips it in every other
/// locale, naming [why].
///
/// Only for tests that really are about English — everything else should look
/// its strings up through [l10n].
Object? englishOnly(String why) => isEnglishTestLocale
    ? false
    : 'English-only ($why); VELORKI_TEST_LOCALE=$testLocaleName';

/// A localised [MaterialApp] showing [home], in the locale under test.
MaterialApp testApp({required Widget home, ThemeData? theme, Locale? locale}) =>
    MaterialApp(
      theme: theme ?? buildLightTheme(),
      locale: locale ?? testLocale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );

/// A localised [MaterialApp.router] driving [routerConfig], in the locale
/// under test.
MaterialApp testRouterApp({
  required RouterConfig<Object> routerConfig,
  ThemeData? theme,
  Locale? locale,
}) => MaterialApp.router(
  theme: theme ?? buildLightTheme(),
  locale: locale ?? testLocale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  routerConfig: routerConfig,
);

/// Fails when a laid-out string had to be cut to fit.
///
/// Flutter already turns a [RenderFlex] or [RenderBox] overflow into a test
/// failure through `FlutterError.onError`, but text that is merely ellipsised
/// or clipped overflows nothing — it just stops being readable. A German
/// string that no longer fits its button or its list tile shows up here.
void expectNoClippedText(WidgetTester tester) {
  final clipped = <String>[];
  for (final object in tester.allRenderObjects) {
    if (object is! RenderParagraph) continue;
    if (object.debugNeedsLayout || !object.didExceedMaxLines) continue;
    switch (object.overflow) {
      case TextOverflow.ellipsis:
      case TextOverflow.clip:
      case TextOverflow.fade:
        clipped.add(
          '"${object.text.toPlainText()}" '
          '(${object.overflow.name}, ${object.size.width.toStringAsFixed(1)}'
          'x${object.size.height.toStringAsFixed(1)})',
        );
      case TextOverflow.visible:
        break;
    }
  }
  if (clipped.isEmpty) return;
  fail(
    'Text does not fit in locale "$testLocaleName" and was cut off:\n'
    '  ${clipped.join('\n  ')}',
  );
}

/// Taps the app bar's back button.
///
/// Not [WidgetTester.pageBack]: that one looks for the tooltip "Back", which
/// only exists in English.
Future<void> tapBack(WidgetTester tester) async {
  await tester.tap(find.byType(BackButton).first);
  await tester.pumpAndSettle();
}

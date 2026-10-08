import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/features/shared/presentation/gesture_zone_guard.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';

/// The language the widget suite runs in.
///
/// `flutter test --dart-define=VELORKI_TEST_LOCALE=de`, or
/// `VELORKI_TEST_LOCALE=de flutter test`, runs every harness-built screen in
/// German, which is how a translation that no longer fits its layout fails
/// CI. The dart-define wins when both are given.
final String testLocaleName = _testLocaleName();

String _testLocaleName() {
  const defined = String.fromEnvironment('VELORKI_TEST_LOCALE');
  if (defined.isNotEmpty) return defined;
  final env = Platform.environment['VELORKI_TEST_LOCALE'] ?? '';
  return env.isNotEmpty ? env : 'en';
}

/// [testLocaleName] as a [Locale], handed to every app this file builds.
///
/// Named like the arb files: `de`, `pt_BR`, `zh_Hant`.
final Locale testLocale = _localeNamed(testLocaleName);

Locale _localeNamed(String name) {
  final parts = name.split(RegExp('[_-]'));
  if (parts.length == 1) return Locale(parts.first);
  final second = parts[1];
  // A four-letter subtag is a script (Hant), anything else a region (BR).
  return second.length == 4
      ? Locale.fromSubtags(languageCode: parts.first, scriptCode: second)
      : Locale(parts.first, second);
}

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
      builder: gestureZoneAppBuilder,
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
  builder: gestureZoneAppBuilder,
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

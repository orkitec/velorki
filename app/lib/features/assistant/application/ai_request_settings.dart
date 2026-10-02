import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velorki_api/velorki_api.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../settings/data/language_controller.dart';
import '../../settings/data/units.dart';

/// The phone's preferred locales, best first.
///
/// A provider of its own so a test can put the phone in another language
/// without reaching for the platform.
final systemLocalesProvider = Provider<List<Locale>>(
  (ref) => ui.PlatformDispatcher.instance.locales,
);

/// The language tag the assistant is asked to answer in: the language the
/// app is shown in, not the phone's.
///
/// A rider who set the app to English on a German phone reads English
/// everywhere else, so the model writes English too. While the app follows
/// the phone this is the language Flutter resolved the phone's list to,
/// which is English for a phone in a language Velorki is not translated
/// into. The phone's region is kept when it speaks that language, so a Swiss
/// phone still asks for `de-CH` spelling.
final aiLocaleTagProvider = Provider<String>(
  (ref) => aiLocaleTag(
    appLocale: ref.watch(appLocaleProvider),
    system: ref.watch(systemLocalesProvider),
  ),
);

/// See [aiLocaleTagProvider].
String aiLocaleTag({Locale? appLocale, required List<Locale> system}) {
  final shown =
      appLocale ??
      basicLocaleListResolution(system, AppLocalizations.supportedLocales);
  if (shown.countryCode != null) return shown.toLanguageTag();
  for (final locale in system) {
    if (locale.languageCode != shown.languageCode) continue;
    final region = locale.countryCode;
    if (region == null || region.isEmpty) break;
    return Locale(shown.languageCode, region).toLanguageTag();
  }
  return Locale(shown.languageCode).toLanguageTag();
}

/// The units the assistant is asked to speak in: Settings → Units.
final aiUnitsProvider = Provider<PlanUnits>(
  (ref) => switch (ref.watch(unitSystemProvider)) {
    UnitSystem.metric => PlanUnits.metric,
    UnitSystem.imperial => PlanUnits.imperial,
  },
);

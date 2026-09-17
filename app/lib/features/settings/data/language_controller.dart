import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/app_config.dart';
import '../../../l10n/generated/app_localizations.dart';

part 'language_controller.g.dart';

const String _prefsLocale = 'language.locale';

/// The language the app is shown in, persisted in shared_preferences.
///
/// `null` means "follow the system": nothing is stored, and Flutter resolves
/// the locale from the phone's preference order against
/// [AppLocalizations.supportedLocales]. A tag the app no longer ships a
/// translation for reads back as `null`, so an app that drops a language does
/// not leave a rider stranded in it.
@Riverpod(keepAlive: true)
class LanguageSetting extends _$LanguageSetting {
  @override
  Locale? build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return supportedLocaleFromTag(prefs.getString(_prefsLocale));
  }

  /// Shows the app in [locale], or follows the system when it is `null`.
  Future<void> select(Locale? locale) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (locale == null) {
      await prefs.remove(_prefsLocale);
    } else {
      await prefs.setString(_prefsLocale, locale.toLanguageTag());
    }
    state = locale;
  }
}

/// The locale the app runs in, or `null` while it follows the system.
///
/// What `MaterialApp.locale` is given, and what everything outside the
/// settings screen reads.
@Riverpod(keepAlive: true)
Locale? appLocale(Ref ref) => ref.watch(languageSettingProvider);

/// The supported locale [tag] names, or `null` when it names none.
///
/// Both `de` and `de-DE` find the shipped `de`.
Locale? supportedLocaleFromTag(String? tag) {
  if (tag == null || tag.isEmpty) return null;
  final parts = tag.split(RegExp('[-_]'));
  final language = parts.first.toLowerCase();
  for (final locale in AppLocalizations.supportedLocales) {
    if (locale.languageCode == language) return locale;
  }
  return null;
}

import 'dart:js_interop';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web/web.dart' as web;

import '../../features/map/application/web_storage_notice.dart';
import '../../features/settings/data/appearance_controller.dart';
import '../../features/settings/data/language_controller.dart';

/// The website's header above the planner (`web/site_header.mjs`) and the
/// app's own theme and language, kept the same both ways.
///
/// A pick in the header comes as a `velorki-header` event with the theme
/// (`system`, `light`, `dark`, [ThemeMode]'s names) or the language code, or
/// `storageNotice` to show the note on what the browser keeps; a
/// change of the app's settings, from its own Settings or from the header,
/// goes back as `velorki-app-settings`. The header keeps its pick where the
/// app keeps the setting (shared_preferences), and the app writes it again
/// through the same setting, so both read the same on the next visit.
abstract final class HeaderBridge {
  /// Starts listening both ways. Called once by the browser's bootstrap.
  static void install(ProviderContainer container) {
    void picked(web.Event event) {
      final detail = (event as web.CustomEvent).detail;
      if (detail == null || !detail.isA<JSObject>()) return;
      final settings = (detail as JSObject).dartify();
      if (settings is! Map) return;
      final theme = settings['theme'];
      if (theme is String) {
        final mode = ThemeMode.values.where((m) => m.name == theme).firstOrNull;
        if (mode != null) {
          container.read(appearanceSettingProvider.notifier).setMode(mode);
        }
      }
      // "Cookies" in the header's menu, which upright on a phone holds the
      // way back to the note the map's legal chip offers elsewhere.
      if (settings['storageNotice'] == true) {
        container.read(webStorageNoticeProvider.notifier).show();
      }
      final locale = settings['locale'];
      if (locale is String) {
        final chosen = supportedLocaleFromTag(locale);
        if (chosen != null) {
          container.read(languageSettingProvider.notifier).select(chosen);
        }
      }
    }

    web.window.addEventListener('velorki-header', picked.toJS);

    void tell() {
      final mode = container.read(appearanceSettingProvider).mode;
      final locale = container.read(languageSettingProvider);
      web.window.dispatchEvent(
        web.CustomEvent(
          'velorki-app-settings',
          web.CustomEventInit(
            detail: <String, Object?>{
              'theme': mode.name,
              'locale': locale?.languageCode,
            }.jsify(),
          ),
        ),
      );
    }

    container
      ..listen(
        appearanceSettingProvider.select((a) => a.mode),
        (_, _) => tell(),
      )
      ..listen<Locale?>(languageSettingProvider, (_, _) => tell());
    tell();
  }
}

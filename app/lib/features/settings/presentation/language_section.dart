import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../data/language_controller.dart';

/// What each shipped language calls itself. A language with no entry here is
/// named by its code, which is ugly but never wrong.
const Map<String, String> _nativeNames = <String, String>{
  'en': 'English',
  'de': 'Deutsch',
};

/// What to call [locale] in the picker: its own name for itself, so a rider
/// who ended up in a language they cannot read still finds their own.
String languageName(Locale locale) =>
    _nativeNames[locale.languageCode] ?? locale.languageCode;

/// Settings → Language: the row that says which language the app is in and
/// opens the picker.
class LanguageSection extends ConsumerWidget {
  /// Creates the row.
  const LanguageSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider);
    return ListTile(
      leading: const Icon(Icons.translate_outlined),
      title: Text(l10n.languageTitle),
      subtitle: Text(
        locale == null ? l10n.languageSystem : languageName(locale),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => unawaited(showLanguagePicker(context)),
    );
  }
}

/// Opens the language picker. A sheet rather than a segmented button: the
/// list grows with every translation the app ships.
Future<void> showLanguagePicker(BuildContext context) => showModalBottomSheet(
  context: context,
  useRootNavigator: true,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => const _LanguageSheet(),
);

class _LanguageSheet extends ConsumerWidget {
  const _LanguageSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final selected = ref.watch(appLocaleProvider);
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                l10n.languageTitle,
                style: theme.textTheme.titleMedium,
              ),
            ),
            RadioGroup<Locale?>(
              groupValue: selected,
              onChanged: (locale) {
                unawaited(
                  ref.read(languageSettingProvider.notifier).select(locale),
                );
                Navigator.of(context).pop();
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RadioListTile<Locale?>(
                    value: null,
                    title: Text(l10n.languageSystem),
                  ),
                  for (final locale in AppLocalizations.supportedLocales)
                    RadioListTile<Locale?>(
                      value: locale,
                      title: Text(languageName(locale)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

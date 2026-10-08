import 'package:flutter/widgets.dart';

import '../../l10n/generated/app_localizations.dart';

/// A sentence for the rider, put in words once the language is known.
///
/// Code without a `BuildContext` (a client, a repository) describes what went
/// wrong with one of these, and the screen that shows it passes its own
/// [AppLocalizations]; nothing below the presentation layer picks a language.
typedef LocalizedText = String Function(AppLocalizations l10n);

/// The English strings, for logs and `toString`, never for the screen.
final AppLocalizations englishLocalizations = lookupAppLocalizations(
  const Locale('en'),
);

/// An exception that can say what went wrong in the rider's language.
abstract interface class LocalizedException implements Exception {
  /// What went wrong, in [l10n]'s language.
  String describe(AppLocalizations l10n);
}

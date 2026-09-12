import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../domain/ai_consent.dart';

/// The one-time consent dialog, shown before the first assistant request.
///
/// It names exactly what leaves the phone (the typed text, and — only with
/// the first button — a position rounded to about a kilometre) and who gets
/// it (the Velorki server, which forwards it to our AI provider). Dismissing
/// it answers `null`, which is not the same as [AiConsent.denied]: nothing is
/// stored, so the dialog appears again next time.
Future<AiConsent?> showAiConsentDialog(BuildContext context) {
  return showDialog<AiConsent>(
    context: context,
    builder: (context) {
      final l10n = AppLocalizations.of(context);
      final theme = Theme.of(context);
      return AlertDialog(
        title: Text(l10n.aiConsentTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.aiConsentBody),
              const SizedBox(height: 12),
              Text(l10n.aiConsentLocationBody),
              const SizedBox(height: 12),
              Text(l10n.aiConsentRevokeHint, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(AiConsent.denied),
            child: Text(l10n.aiConsentDeny),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(AiConsent.textOnly),
            child: Text(l10n.aiConsentAllowTextOnly),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(AiConsent.withLocation),
            child: Text(l10n.aiConsentAllowWithLocation),
          ),
        ],
      );
    },
  );
}

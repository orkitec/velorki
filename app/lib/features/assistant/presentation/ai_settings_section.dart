import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/links/link_opener.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../data/ai_consent_controller.dart';
import 'ai_consent_dialog.dart';
import 'assistant_strings.dart';

/// Settings → AI assistant: what is sent, and how to report an answer.
///
/// The consent is revocable here, which is the half of Apple's 5.1.2(i) that
/// the one-time dialog does not cover; the report link is what the age-rating
/// questionnaire expects from an app that shows model output.
class AiSettingsSection extends ConsumerWidget {
  /// Creates the section.
  const AiSettingsSection({super.key});

  Future<void> _change(BuildContext context, WidgetRef ref) async {
    final choice = await showAiConsentDialog(context);
    if (choice == null) return;
    await ref.read(aiConsentControllerProvider.notifier).set(choice);
  }

  Future<void> _report(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final opened = await ref.read(linkOpenerProvider)(
      Uri.parse(aiReportMailto),
    );
    if (opened) return;
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.settingsAiReportFailed)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final consent = ref.watch(aiConsentControllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: Text(l10n.settingsAiConsent),
          subtitle: Text(aiConsentDescription(l10n, consent)),
          trailing: TextButton(
            onPressed: () => unawaited(_change(context, ref)),
            child: Text(l10n.settingsAiChange),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.flag_outlined),
          title: Text(l10n.settingsAiReport),
          subtitle: Text(l10n.settingsAiReportSubtitle),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => unawaited(_report(context, ref)),
        ),
      ],
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/links/link_opener.dart';
import '../../../core/links/velorki_urls.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../shared/presentation/docking_sheet.dart';

/// Shows what connecting Strava means before Strava's page opens, as
/// Strava's API policy asks: what is read, what is written, how, and how to
/// undo it. Answers whether the rider chose to continue.
Future<bool> showStravaConsentSheet(BuildContext context) async =>
    await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) =>
          ScrolledUnderLine(child: const StravaConsentSheet()),
    ) ??
    false;

/// The sheet [showStravaConsentSheet] opens.
class StravaConsentSheet extends ConsumerWidget {
  /// Creates the sheet.
  const StravaConsentSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    Widget section(IconData icon, String title, String body) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: theme.colorScheme.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(body, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        MediaQuery.paddingOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.stravaConsentTitle, style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          section(
            Icons.visibility_outlined,
            l10n.stravaConsentReadsTitle,
            l10n.stravaConsentReadsBody,
          ),
          section(
            Icons.upload_outlined,
            l10n.stravaConsentWritesTitle,
            l10n.stravaConsentWritesBody,
          ),
          section(
            Icons.lock_outline,
            l10n.stravaConsentHowTitle,
            l10n.stravaConsentHowBody,
          ),
          section(
            Icons.link_off,
            l10n.stravaConsentDisconnectTitle,
            l10n.stravaConsentDisconnectBody,
          ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => unawaited(
                  ref.read(linkOpenerProvider)(Uri.parse(velorkiPrivacyUrl)),
                ),
                child: Text(l10n.settingsPrivacyPolicy),
              ),
              // The address as text: a mail link does not open everywhere.
              SelectableText(
                l10n.stravaConsentSupport(velorkiSupportEmail),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l10n.commonContinue),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Confirms in writing that the Strava data on the phone is gone, under
/// [title]: after a disconnect, or after Strava refused the access.
Future<void> showStravaDataDeletedDialog(
  BuildContext context, {
  required String title,
  String? body,
}) {
  final l10n = AppLocalizations.of(context);
  return showDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body ?? l10n.stravaDataDeleted),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonOk),
        ),
      ],
    ),
  );
}

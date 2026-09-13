import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../shared/presentation/stat_tile.dart';

/// The card shown where a Velorki Plus feature would be.
///
/// It says what is gated in one sentence and offers the one way forward: the
/// paywall at [paywallRoute]. This replaces the M5 placeholder, which had no
/// button because there was nothing to buy yet.
class PlusUpsellCard extends StatelessWidget {
  /// Creates the card.
  const PlusUpsellCard({required this.body, super.key});

  /// What is gated, in one sentence.
  final String body;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Card(
        color: theme.colorScheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The product name, not a translatable label.
              const SectionCaption('Plus', accent: true),
              const SizedBox(height: 6),
              Text(l10n.plusTitle, style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(body, style: theme.textTheme.bodySmall),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  onPressed: () => context.push(paywallRoute),
                  child: Text(l10n.plusSeeDetails),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

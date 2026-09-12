import 'package:flutter/material.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

import '../../../l10n/generated/app_localizations.dart';

/// Says where the shown route was computed: on this device or on the routing
/// server.
///
/// Only the composite backend reports a source, so the chip is simply absent
/// when nothing said — it never guesses.
class RoutingSourceChip extends StatelessWidget {
  /// Creates the chip for [source].
  const RoutingSourceChip({required this.source, super.key});

  /// Which backend answered.
  final RoutingSource source;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final onDevice = source == RoutingSource.local;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            onDevice ? Icons.smartphone : Icons.cloud_outlined,
            size: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            onDevice ? l10n.plannerRoutedOnDevice : l10n.plannerRoutedOnServer,
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

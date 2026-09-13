import 'package:flutter/material.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

import '../../../app/theme.dart';
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
    final scheme = theme.colorScheme;
    final onDevice = source == RoutingSource.local;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // A dot rather than an icon: the state is binary, and green says
          // "no network needed" without a legend.
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: onDevice ? theme.velorki.success : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            (onDevice ? l10n.plannerRoutedOnDevice : l10n.plannerRoutedOnServer)
                .toUpperCase(),
            style: theme.textTheme.overline.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

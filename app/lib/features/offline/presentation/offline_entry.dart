import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../routing_tiles/data/routing_tiles_repository.dart';
import 'offline_screen.dart';

/// The Settings row into the offline data: maps and routing tiles together.
///
/// Pushed with the root [Navigator] rather than go_router. When the weekly
/// check has found rebuilt routing tiles, the row says how many and wears a
/// badge, so a rider who never opens the screen still learns that an update
/// is waiting.
class OfflineEntry extends ConsumerWidget {
  /// Creates the row.
  const OfflineEntry({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final tiles = ref.watch(routingTilesProvider).value ?? const [];
    final stale = tiles.where((tile) => tile.isStale).length;
    return ListTile(
      leading: const Icon(Icons.download_for_offline_outlined),
      title: Text(l10n.offlineEntryTitle),
      subtitle: stale == 0
          ? Text(l10n.offlineEntrySubtitle)
          : Text(
              l10n.routingTilesUpdatesHint(stale),
              style: TextStyle(color: theme.velorki.warning),
            ),
      trailing: stale == 0
          ? const Icon(Icons.chevron_right)
          : Badge(
              label: Text('$stale'),
              backgroundColor: theme.velorki.warning,
              child: const Icon(Icons.chevron_right),
            ),
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const OfflineScreen())),
    );
  }
}

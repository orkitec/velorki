import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../import_export/presentation/import_file_action.dart';
import '../../integrations/presentation/import_from_service_menu.dart';
import '../../planner/data/route_repository.dart';
import '../../planner/domain/saved_route.dart';
import '../../planner/presentation/route_format.dart';
import '../../shared/presentation/placeholder_body.dart';
import 'rename_route_dialog.dart';

/// The Library tab: every saved route, newest first.
class LibraryScreen extends ConsumerWidget {
  /// Creates the library.
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final routes = ref.watch(savedRoutesProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tabLibrary),
        actions: const [ImportFromServiceButton(), ImportFileButton()],
      ),
      body: routes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => PlaceholderBody(
          icon: Icons.error_outline,
          message: error.toString(),
        ),
        data: (items) => items.isEmpty
            ? PlaceholderBody(
                icon: Icons.folder_outlined,
                message: '${l10n.libraryEmpty}\n${l10n.libraryEmptyDetail}',
              )
            // The floating navigation bar sits over the list, so the last
            // route needs room to clear it.
            : ListView.builder(
                padding: EdgeInsets.only(
                  top: 6,
                  bottom: MediaQuery.paddingOf(context).bottom + 24,
                ),
                itemCount: items.length,
                itemBuilder: (context, i) => _RouteTile(route: items[i]),
              ),
      ),
    );
  }
}

/// The rounded square holding a tile's icon.
class _TileIcon extends StatelessWidget {
  const _TileIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, size: 22, color: theme.velorki.accent),
    );
  }
}

class _RouteTile extends ConsumerWidget {
  const _RouteTile({required this.route});

  final SavedRoute route;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final repository = ref.read(routeRepositoryProvider);
    await repository.delete(route.id);
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.libraryRouteDeleted(route.name)),
        action: SnackBarAction(
          label: l10n.commonUndo,
          onPressed: () => unawaited(repository.restore(route)),
        ),
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final name = await showRenameRouteDialog(context, initialName: route.name);
    if (name == null) return;
    await ref.read(routeRepositoryProvider).rename(route.id, name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Dismissible(
      key: ValueKey(route.id),
      direction: DismissDirection.endToStart,
      background: ColoredBox(
        color: scheme.errorContainer,
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 24),
            child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
          ),
        ),
      ),
      onDismissed: (_) => unawaited(_delete(context, ref)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        leading: const _TileIcon(Icons.route_rounded),
        title: Text(
          route.name,
          style: theme.textTheme.titleMedium,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          l10n.libraryRouteSubtitle(
            formatDate(l10n, route.createdAt),
            formatDistance(l10n, route.distanceM),
            formatHeight(l10n, route.ascentM),
          ),
          style: theme.textTheme.bodySmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: PopupMenuButton<_RouteAction>(
          onSelected: (action) => unawaited(switch (action) {
            _RouteAction.rename => _rename(context, ref),
            _RouteAction.delete => _delete(context, ref),
          }),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: _RouteAction.rename,
              child: Text(l10n.commonRename),
            ),
            PopupMenuItem(
              value: _RouteAction.delete,
              child: Text(l10n.commonDelete),
            ),
          ],
        ),
        onTap: () => context.go(routeDetailLocation(route.id)),
      ),
    );
  }
}

enum _RouteAction { rename, delete }

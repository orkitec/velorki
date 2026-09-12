import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/generated/app_localizations.dart';
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
      appBar: AppBar(title: Text(l10n.tabLibrary)),
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
            : ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) => _RouteTile(route: items[i]),
              ),
      ),
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
    return Dismissible(
      key: ValueKey(route.id),
      direction: DismissDirection.endToStart,
      background: ColoredBox(
        color: Theme.of(context).colorScheme.errorContainer,
        child: const Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: EdgeInsets.only(right: 24),
            child: Icon(Icons.delete_outline),
          ),
        ),
      ),
      onDismissed: (_) => unawaited(_delete(context, ref)),
      child: ListTile(
        leading: const Icon(Icons.route_outlined),
        title: Text(route.name),
        subtitle: Text(
          l10n.libraryRouteSubtitle(
            formatDate(l10n, route.createdAt),
            formatDistance(l10n, route.distanceM),
            formatHeight(l10n, route.ascentM),
          ),
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

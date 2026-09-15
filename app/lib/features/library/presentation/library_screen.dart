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
import '../../recording/data/ride_repository.dart';
import '../../recording/presentation/rides_list.dart';
import '../../settings/data/units.dart';
import '../../shared/presentation/placeholder_body.dart';
import '../../shared/presentation/stat_tile.dart';
import '../data/library_section.dart';
import 'rename_route_dialog.dart';

/// The Library tab: the saved routes and the recorded rides, newest first.
///
/// Which of the two shows is the rider's choice and survives a restart; see
/// [librarySectionProvider].
class LibraryScreen extends ConsumerWidget {
  /// Creates the library.
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final section = ref.watch(librarySectionProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tabLibrary),
        actions: const [ImportFromServiceButton(), ImportFileButton()],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<LibrarySection>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: LibrarySection.routes,
                    icon: const Icon(Icons.route_rounded, size: 18),
                    label: Text(l10n.libraryRoutes),
                  ),
                  ButtonSegment(
                    value: LibrarySection.rides,
                    icon: const Icon(Icons.directions_bike_rounded, size: 18),
                    label: Text(l10n.libraryRides),
                  ),
                ],
                selected: {section},
                onSelectionChanged: (selection) => unawaited(
                  ref
                      .read(librarySectionProvider.notifier)
                      .select(selection.first),
                ),
              ),
            ),
          ),
          Expanded(
            child: switch (section) {
              LibrarySection.routes => const _RoutesSection(),
              LibrarySection.rides => const _RidesSection(),
            },
          ),
        ],
      ),
    );
  }
}

/// Every saved route, newest first.
class _RoutesSection extends ConsumerWidget {
  const _RoutesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final routes = ref.watch(savedRoutesProvider);
    return routes.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) =>
          PlaceholderBody(icon: Icons.error_outline, message: error.toString()),
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
    );
  }
}

/// Every recorded ride, newest first.
///
/// The list itself is the record tab's [RidesList] without its limit, so the
/// rows, the swipe-to-delete and the tap into the ride detail behave exactly
/// as they do there; only the count above it is the library's own.
class _RidesSection extends ConsumerWidget {
  const _RidesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final count = ref.watch(ridesProvider).value?.length ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (count > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: SectionCaption(l10n.libraryRidesCount(count)),
          ),
        const Expanded(child: RidesList()),
      ],
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
    final units = ref.watch(unitSystemProvider);
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
            formatDistance(l10n, units, route.distanceM),
            formatHeight(l10n, units, route.ascentM),
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

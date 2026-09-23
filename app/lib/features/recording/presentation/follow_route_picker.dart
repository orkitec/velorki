import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../library/presentation/library_screen.dart';
import '../../planner/application/planner_controller.dart';
import '../../planner/data/route_repository.dart';
import '../../planner/presentation/route_format.dart';
import '../../settings/data/units.dart';
import '../application/recording_controller.dart';

/// The row on the Record tab's idle sheet that says which route the next
/// ride follows, and opens [FollowRoutePicker] on a tap.
///
/// A sheet rather than a menu: a menu opened downwards from here landed
/// behind the floating navigation bar, and a library of routes is longer
/// than the room under the row.
class FollowRouteField extends ConsumerWidget {
  /// Creates the row.
  const FollowRouteField({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final units = ref.watch(unitSystemProvider);
    final followed = ref.watch(
      recordingControllerProvider.select((s) => s.followedRouteId),
    );
    final route = followed == null
        ? null
        : ref.watch(savedRouteProvider(followed)).value;
    final hasPlan = ref.watch(
      plannerControllerProvider.select((p) => p.result != null),
    );
    final choice = route != null
        ? '${route.name} · ${formatDistance(l10n, units, route.distanceM)}'
        : hasPlan
        ? l10n.recordingFollowPlan
        : l10n.recordingFollowNone;
    // The height of the menu field it replaced: one row, label over value.
    return Material(
      type: MaterialType.transparency,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => unawaited(showFollowRoutePicker(context)),
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              const SizedBox(width: 12),
              Icon(
                Icons.route_outlined,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.recordingFollowRoute,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      choice,
                      style: theme.textTheme.bodyLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.unfold_more,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the route picker over everything, the navigation bar included.
Future<void> showFollowRoutePicker(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      // The shell's floating navigation bar belongs to the branch
      // navigator, so a sheet opened there would sit under it.
      useRootNavigator: true,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const FollowRoutePicker(),
    );

/// The routes the next ride can follow: none (or the route on the Plan tab,
/// when there is one) and every saved route, the current choice marked. A
/// tap chooses and closes.
class FollowRoutePicker extends ConsumerWidget {
  /// Creates the picker.
  const FollowRoutePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final routes = ref.watch(savedRoutesProvider).value ?? const [];
    final followed = ref.watch(
      recordingControllerProvider.select((s) => s.followedRouteId),
    );
    final hasPlan = ref.watch(
      plannerControllerProvider.select((p) => p.result != null),
    );
    void choose(String? id) {
      ref.read(recordingControllerProvider.notifier).selectRoute(id);
      Navigator.of(context).pop();
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              l10n.recordingFollowRoute,
              style: theme.textTheme.titleMedium,
            ),
          ),
          // Short lists take their own height; a long library scrolls.
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 6,
                  ),
                  leading: SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(
                      hasPlan ? Icons.route_outlined : Icons.block_outlined,
                    ),
                  ),
                  selected: followed == null,
                  title: Text(
                    hasPlan
                        ? l10n.recordingFollowPlan
                        : l10n.recordingFollowNone,
                    style: theme.textTheme.titleMedium,
                  ),
                  trailing: followed == null
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () => choose(null),
                ),
                for (final route in routes)
                  RouteRow(
                    route: route,
                    selected: route.id == followed,
                    trailing: route.id == followed
                        ? const Icon(Icons.check_rounded)
                        : null,
                    onTap: () => choose(route.id),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

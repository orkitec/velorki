import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../library/presentation/library_screen.dart';
import '../../planner/application/planner_controller.dart';
import '../../planner/data/route_repository.dart';
import '../../planner/presentation/route_format.dart';
import '../../settings/data/units.dart';
import '../application/recording_controller.dart';
import '../domain/follow_choice.dart';

part 'follow_route_picker.g.dart';

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
    final follow = ref.watch(effectiveFollowProvider);
    final route = follow is FollowSaved
        ? ref.watch(savedRouteProvider(follow.id)).value
        : null;
    final choice = switch (follow) {
      FollowSaved() when route != null =>
        '${route.name} · ${formatDistance(l10n, units, route.distanceM)}',
      FollowPlan() => l10n.recordingFollowPlan,
      _ => l10n.recordingFollowNone,
    };
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

/// The choice as the ride will see it: the plan only counts while there is
/// one, so a rider who has not planned anything is shown, and ticked, "No
/// route" rather than a plan that is nothing.
@riverpod
FollowChoice effectiveFollow(Ref ref) {
  final follow = ref.watch(recordingControllerProvider.select((s) => s.follow));
  final hasPlan = ref.watch(
    plannerControllerProvider.select((p) => p.result != null),
  );
  return follow is FollowPlan && !hasPlan ? FollowChoice.none : follow;
}

/// What the next ride can follow: no route, the route on the Plan tab when
/// there is one, and every saved route, the current choice marked. A tap
/// chooses and closes.
class FollowRoutePicker extends ConsumerWidget {
  /// Creates the picker.
  const FollowRoutePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final routes = ref.watch(savedRoutesProvider).value ?? const [];
    final follow = ref.watch(effectiveFollowProvider);
    final hasPlan = ref.watch(
      plannerControllerProvider.select((p) => p.result != null),
    );
    void choose(FollowChoice choice) {
      ref.read(recordingControllerProvider.notifier).choose(choice);
      Navigator.of(context).pop();
    }

    Widget row({
      required IconData icon,
      required String title,
      required FollowChoice choice,
    }) => ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      leading: SizedBox(width: 44, height: 44, child: Icon(icon)),
      selected: follow == choice,
      title: Text(title, style: theme.textTheme.titleMedium),
      trailing: follow == choice ? const Icon(Icons.check_rounded) : null,
      onTap: () => choose(choice),
    );

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
                row(
                  icon: Icons.block_outlined,
                  title: l10n.recordingFollowNone,
                  choice: FollowChoice.none,
                ),
                if (hasPlan)
                  row(
                    icon: Icons.route_outlined,
                    title: l10n.recordingFollowPlan,
                    choice: FollowChoice.plan,
                  ),
                for (final route in routes)
                  RouteRow(
                    route: route,
                    selected: follow == FollowSaved(route.id),
                    trailing: follow == FollowSaved(route.id)
                        ? const Icon(Icons.check_rounded)
                        : null,
                    onTap: () => choose(FollowSaved(route.id)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

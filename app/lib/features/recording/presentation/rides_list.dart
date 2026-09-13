import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../planner/presentation/route_format.dart';
import '../data/ride_repository.dart';
import '../domain/ride.dart';
import 'ride_detail_screen.dart';

/// The recorded rides, newest first.
///
/// Lives in its own widget because it is shown twice: under the start button
/// on the record tab, and — once the library grows a rides section — there.
class RidesList extends ConsumerWidget {
  /// Creates the list.
  const RidesList({super.key, this.limit, this.shrinkWrap = false});

  /// How many rides to show; `null` shows all of them.
  final int? limit;

  /// Whether the list sizes itself to its content, which it must when it is
  /// embedded in another scroll view.
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final rides = ref.watch(
      limit == null ? ridesProvider : recentRidesProvider,
    );
    return rides.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
        child: Text(error.toString(), style: theme.textTheme.bodyMedium),
      ),
      data: (items) {
        if (items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
            child: Text(
              l10n.recordingNoRides,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        return ListView.builder(
          shrinkWrap: shrinkWrap,
          physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
          // Embedded, the host scroll view already clears the floating
          // navigation bar; on its own the list has to do it itself.
          padding: shrinkWrap
              ? EdgeInsets.zero
              : EdgeInsets.only(
                  top: 6,
                  bottom: MediaQuery.paddingOf(context).bottom + 24,
                ),
          itemCount: items.length,
          // Embedded lists sit inside a padded host, so the tiles drop their
          // own horizontal inset.
          itemBuilder: (context, i) =>
              RideTile(ride: items[i], inset: !shrinkWrap),
        );
      },
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

/// One row of [RidesList]; swiping it away deletes the ride.
class RideTile extends ConsumerWidget {
  /// Creates the tile.
  const RideTile({required this.ride, super.key, this.inset = true});

  /// The ride shown.
  final Ride ride;

  /// Whether the tile carries the screen's own 20dp horizontal inset; `false`
  /// when it is embedded in a host that already pads its content.
  final bool inset;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final repository = ref.read(rideRepositoryProvider);
    await repository.delete(ride.id);
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.rideDeleted(ride.name)),
        action: SnackBarAction(
          label: l10n.commonUndo,
          onPressed: () => unawaited(repository.save(ride)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Dismissible(
      key: ValueKey('ride-${ride.id}'),
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
        contentPadding: EdgeInsets.symmetric(
          horizontal: inset ? 20 : 0,
          vertical: 6,
        ),
        leading: const _TileIcon(Icons.directions_bike_rounded),
        title: Text(
          ride.name,
          style: theme.textTheme.titleMedium,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          l10n.rideSubtitle(
            formatDate(l10n, ride.startedAt),
            formatDistance(l10n, ride.stats.distanceM),
            formatDuration(l10n, ride.stats.movingTime),
          ),
          style: theme.textTheme.bodySmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => context.go(rideDetailLocation(ride.id)),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../planner/presentation/route_format.dart';
import '../../settings/data/units.dart';
import '../data/ride_repository.dart';
import '../domain/ride.dart';
import 'ride_detail_screen.dart';

/// The recorded rides, newest first: the library's rides section.
class RidesList extends ConsumerWidget {
  /// Creates the list.
  const RidesList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final rides = ref.watch(ridesProvider);
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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Text(
              l10n.recordingNoRides,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        return ListView.builder(
          // The floating navigation bar overlays the content.
          padding: EdgeInsets.only(
            top: 6,
            bottom: MediaQuery.paddingOf(context).bottom + 24,
          ),
          itemCount: items.length,
          itemBuilder: (context, i) => RideTile(ride: items[i]),
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
  const RideTile({required this.ride, super.key});

  /// The ride shown.
  final Ride ride;

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
    final units = ref.watch(unitSystemProvider);
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
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
            formatDistance(l10n, units, ride.stats.distanceM),
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
    final rides = ref.watch(
      limit == null ? ridesProvider : recentRidesProvider,
    );
    return rides.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(error.toString()),
      ),
      data: (items) {
        if (items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              l10n.recordingNoRides,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          );
        }
        return ListView.separated(
          shrinkWrap: shrinkWrap,
          physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) => RideTile(ride: items[i]),
        );
      },
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
    return Dismissible(
      key: ValueKey('ride-${ride.id}'),
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
        leading: const Icon(Icons.directions_bike_outlined),
        title: Text(ride.name),
        subtitle: Text(
          l10n.rideSubtitle(
            formatDate(l10n, ride.startedAt),
            formatDistance(l10n, ride.stats.distanceM),
            formatDuration(l10n, ride.stats.movingTime),
          ),
        ),
        onTap: () => context.go(rideDetailLocation(ride.id)),
      ),
    );
  }
}

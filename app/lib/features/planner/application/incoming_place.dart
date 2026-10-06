import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../app/router.dart';
import '../../../core/links/location_link.dart';
import '../../import_export/data/incoming_file_service.dart';
import '../../recording/data/recording_recovery.dart';

final Logger _log = Logger('IncomingPlace');

/// A place another app sent, waiting for the planner to show it.
///
/// One object per arrival, compared by identity: the same place sent twice
/// is shown twice.
class IncomingPlace {
  /// Wraps [link].
  IncomingPlace(this.link);

  /// What arrived.
  final LocationLink link;
}

/// The place the planner has yet to show, or `null`.
///
/// Held here rather than handed straight to the screen, because on a cold
/// start the place arrives before the planner and its map are up.
final incomingPlaceProvider =
    NotifierProvider<IncomingPlaceRequest, IncomingPlace?>(
      IncomingPlaceRequest.new,
    );

/// See [incomingPlaceProvider].
class IncomingPlaceRequest extends Notifier<IncomingPlace?> {
  @override
  IncomingPlace? build() => null;

  /// Asks the planner to show [link].
  void send(LocationLink link) => state = IncomingPlace(link);

  /// The planner has shown [place].
  void taken(IncomingPlace place) {
    if (identical(state, place)) state = null;
  }
}

/// Watches the places other apps send and brings each to the planner.
///
/// Called once from `bootstrap()`, next to the import listener, so a place
/// the app was launched with is not lost. The service is started there.
void listenForIncomingLocations(ProviderContainer container) {
  container.listen<AsyncValue<LocationLink>>(
    incomingLocationsProvider,
    (previous, next) {
      final link = next.value;
      if (link == null || identical(link, previous?.value)) return;
      unawaited(_afterRecovery(container, link));
    },
    fireImmediately: true,
    onError: (error, _) => _log.warning('incoming place failed', error),
  );
}

/// Opens the planner with [link] once a ride left unfinished at launch has
/// been answered for: the place shows after the question, not under it.
Future<void> _afterRecovery(
  ProviderContainer container,
  LocationLink link,
) async {
  try {
    await waitForRecovery(container);
  } on Object catch (error) {
    _log.warning('recovery check failed; showing the place anyway', error);
  }
  _log.info('showing a place from ${link.source.name}');
  container.read(incomingPlaceProvider.notifier).send(link);
  // The first frame may not be up yet on a cold start.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    container.read(routerProvider).go(plannerRoute);
  });
}

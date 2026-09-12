import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../data/brouter_assets.dart';
import '../data/routing_tiles_repository.dart';

final Logger _log = Logger('velorki.routing_tiles');

/// Gets the on-device routing stack ready in the background.
///
/// Two things have to happen before the first route can run on the device:
/// the bundled `.brf` profiles have to be copied out of the app package (once
/// per app version), and the tile table has to be reconciled with the files on
/// disk. Neither blocks the first frame — until they are done the routing
/// backend simply has no local half and the server answers, which is what a
/// fresh install does anyway.
void prepareOnDeviceRouting(ProviderContainer container) {
  unawaited(
    Future<void>(() async {
      try {
        await container.read(brouterProfilesProvider.future);
        await container.read(routingTilesRepositoryProvider.future);
      } on Object catch (error, stackTrace) {
        // A device that cannot write to its own support directory still
        // routes against the server; it must not fail to start.
        _log.warning('on-device routing is unavailable', error, stackTrace);
      }
    }),
  );
}

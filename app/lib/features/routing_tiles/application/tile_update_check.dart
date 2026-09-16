import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

import '../../../app/app_config.dart';
import '../data/routing_tiles_repository.dart';
import '../data/segments_manifest_service.dart';
import '../domain/routing_tile.dart';

final Logger _log = Logger('velorki.routing_tiles');

/// How long a check of the mirror is good for.
const Duration tileUpdateCheckInterval = Duration(days: 7);

/// Where the time of the last successful check is kept.
const String tileUpdateCheckKey = 'routing_tiles.lastUpdateCheck';

/// Asks the mirror, at most once a week, whether any downloaded tile has been
/// rebuilt, and marks those tiles `stale` so the Settings entry and the tiles
/// screen can say so.
///
/// Quiet by design: nothing is shown while it runs, a mirror that cannot be
/// reached is logged and tried again on the next occasion, and a phone with
/// no tiles never asks at all. The occasions are app start and the start of
/// a route, so a phone that is never restarted still gets its weekly check.
class TileUpdateChecker {
  /// Creates a checker over the given collaborators. [clock] is for tests.
  TileUpdateChecker({
    required this.prefs,
    required this.tiles,
    required this.fetch,
    required this.apply,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Where the time of the last check is kept.
  final SharedPreferences prefs;

  /// The tiles on the phone.
  final Future<List<RoutingTile>> Function() tiles;

  /// The mirror's manifest.
  final Future<SegmentsManifest> Function() fetch;

  /// Marks the tiles the manifest has newer builds of.
  final Future<void> Function(SegmentsManifest manifest) apply;

  final DateTime Function() _clock;
  bool _running = false;

  /// Runs the check when a week has passed since the last one and there are
  /// tiles to check. Returns whether the mirror was asked.
  Future<bool> checkIfDue() async {
    if (_running) return false;
    _running = true;
    try {
      final now = _clock();
      final last = DateTime.tryParse(prefs.getString(tileUpdateCheckKey) ?? '');
      if (last != null && now.difference(last) < tileUpdateCheckInterval) {
        return false;
      }
      if (!(await tiles()).any((tile) => tile.isUsable)) return false;
      await apply(await fetch());
      await prefs.setString(tileUpdateCheckKey, now.toUtc().toIso8601String());
      return true;
    } on Object catch (error, stackTrace) {
      // Next launch or next route tries again; the timestamp is only written
      // after a check that went through.
      _log.info('tile update check skipped', error, stackTrace);
      return false;
    } finally {
      _running = false;
    }
  }
}

/// The app's [TileUpdateChecker], over the repository and the mirror.
final tileUpdateCheckerProvider = Provider<TileUpdateChecker>(
  (ref) => TileUpdateChecker(
    prefs: ref.watch(sharedPreferencesProvider),
    tiles: () async =>
        (await ref.read(routingTilesRepositoryProvider.future)).tiles(),
    fetch: () => ref.read(segmentsManifestServiceProvider).fetch(),
    apply: (manifest) async =>
        (await ref.read(routingTilesRepositoryProvider.future))
            .applyManifest(manifest),
  ),
);

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/app_config.dart';
import '../../../app/platform_features.dart';
import '../../../app/router.dart';
import '../../../core/db/database.dart';
import '../../settings/data/package_info_provider.dart';
import '../../shared/application/active_tab.dart';
import '../data/store_services.dart';
import 'calm_moment.dart';

final _log = Logger('velorki.store');

/// Recorded rides that earn the rating request.
const int reviewAfterRides = 3;

/// Routes kept in the library that earn it, whichever comes first.
const int reviewAfterRoutes = 5;

/// The least time between two requests, whatever the version.
const Duration reviewInterval = Duration(days: 90);

const _versionKey = 'store_prompts.review_version';
const _atKey = 'store_prompts.review_at';

/// Rides recorded on this phone, as the database has them.
final recordedRideCountProvider = StreamProvider<int>(
  (ref) => ref.watch(ridesDaoProvider).watchRecordedRideCount(),
);

/// Routes kept in the library, as the database has them.
final keptRouteCountProvider = StreamProvider<int>(
  (ref) => ref.watch(routesDaoProvider).watchKeptRouteCount(),
);

/// Whether the rider has done enough for the request, and it has not been
/// made for [version] or in the last [reviewInterval].
bool reviewDue(
  SharedPreferences prefs, {
  required int rides,
  required int routes,
  required String version,
  required DateTime now,
}) {
  if (rides < reviewAfterRides && routes < reviewAfterRoutes) return false;
  if (prefs.getString(_versionKey) == version) return false;
  final at = prefs.getInt(_atKey);
  return at == null ||
      now.difference(DateTime.fromMillisecondsSinceEpoch(at)) >= reviewInterval;
}

/// A moment the system's rating dialog may come up in: no ride running,
/// and the rider on the Plan or the Library tab.
final _reviewCalmProvider = Provider<bool>(
  (ref) =>
      ref.watch(rideCalmProvider) &&
      const {plannerRoute, libraryRoute}.contains(ref.watch(activeTabProvider)),
);

/// Asks for the store's rating after a ride is saved or a route is kept,
/// once the rider has [reviewAfterRides] rides or [reviewAfterRoutes]
/// routes: the platform's own dialog (StoreKit, Play In-App Review), never
/// a question of the app's own first.
///
/// The counts come from the database, so a rider who had them before this
/// version qualifies on the next save. A save only marks the request as
/// wanted; it is made at the next calm moment on the Plan or the Library
/// tab, never while a ride records or navigates, and at most once per app
/// version and per [reviewInterval]. The system may still show nothing.
///
/// Called once from `bootstrap()`; nothing happens in a browser.
void startReviewPrompts(ProviderContainer container) {
  if (!container.read(platformFeaturesProvider).storeListing) return;
  final counts = <String, int>{};
  var wanted = false;
  var asking = false;

  Future<void> ask() async {
    if (asking) return;
    asking = true;
    try {
      await untilCalm(container, _reviewCalmProvider);
      if (!wanted) return;
      wanted = false;
      final prefs = container.read(sharedPreferencesProvider);
      final version = (await container.read(packageInfoProvider.future))
          .version;
      final now = container.read(storePromptClockProvider)();
      if (!reviewDue(
        prefs,
        rides: counts['rides'] ?? 0,
        routes: counts['routes'] ?? 0,
        version: version,
        now: now,
      )) {
        return;
      }
      // Written first: whatever the system does, this version has asked.
      await prefs.setString(_versionKey, version);
      await prefs.setInt(_atKey, now.millisecondsSinceEpoch);
      await container.read(reviewRequestProvider)();
    } on Object catch (error) {
      _log.info('Rating request failed: $error');
    } finally {
      asking = false;
    }
  }

  void follow(String key, ProviderListenable<AsyncValue<int>> count) {
    container.listen<AsyncValue<int>>(count, (_, next) {
      final value = next.value;
      if (value == null) return;
      final before = counts[key];
      counts[key] = value;
      // The first answer is what was already there; only a save counts.
      if (before != null && value > before) {
        wanted = true;
        unawaited(ask());
      }
    }, fireImmediately: true);
  }

  follow('rides', recordedRideCountProvider);
  follow('routes', keptRouteCountProvider);
}

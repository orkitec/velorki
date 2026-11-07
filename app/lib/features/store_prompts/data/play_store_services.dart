import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:in_app_review/in_app_review.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'store_services.dart';

/// The two store SDKs behind the rating dialog and the update notice:
/// StoreKit and Play In-App Review through `in_app_review`, and Google
/// Play's in-app updates through `in_app_update`.
///
/// Reached from an entry point and nowhere else — `main.dart` installs
/// [storePromptOverrides], `main_fdroid.dart` does not — so a build without
/// Google Play compiles neither library in and simply never asks for a
/// rating and never offers an update.
final _log = Logger('velorki.store');

/// Velorki's page on Google Play.
const String playStorePageUrl =
    'https://play.google.com/store/apps/details?id=com.orkitec.velorki';

/// Where a build that carries Google Play's in-app update API looks for
/// updates: Play on Android, and the App Store's lookup on iOS as before.
///
/// [web] and [debug] are [kIsWeb] and [kDebugMode], named so tests can say
/// what a release build would do.
StoreUpdateSource? updateSourceWithPlay({
  required TargetPlatform platform,
  bool web = kIsWeb,
  bool debug = kDebugMode,
}) {
  if (web || debug) return null;
  return switch (platform) {
    TargetPlatform.iOS => AppStoreUpdateSource(),
    TargetPlatform.android => PlayUpdateSource(),
    _ => null,
  };
}

/// [reviewRequestProvider] and [storeUpdateSourceProvider] with the stores
/// behind them.
///
/// [debug] is [kDebugMode], named so a test can ask for what a release build
/// would install (a debug build has no store version to compare against, so
/// both this and the default answer null there).
List<Override> storePromptOverrides({bool debug = kDebugMode}) => [
  reviewRequestProvider.overrideWithValue(requestSystemReview),
  storeUpdateSourceProvider.overrideWith(
    (ref) =>
        updateSourceWithPlay(platform: defaultTargetPlatform, debug: debug),
  ),
];

/// Asks the platform for its rating dialog.
Future<void> requestSystemReview() async {
  final review = InAppReview.instance;
  if (await review.isAvailable()) await review.requestReview();
}

/// Google Play's in-app update API, through in_app_update. It answers only
/// for an install that came from Play; anything else is "nothing newer".
class PlayUpdateSource implements StoreUpdateSource {
  @override
  Future<StoreUpdate?> check(PackageInfo installed) async {
    final info = await InAppUpdate.checkForUpdate();
    if (info.installStatus == InstallStatus.downloaded) {
      return const UpdateDownloaded();
    }
    if (info.updateAvailability != UpdateAvailability.updateAvailable) {
      return null;
    }
    return UpdateAvailable(
      version: 'code ${info.availableVersionCode}',
      storeUrl: playStorePageUrl,
      inApp: info.flexibleUpdateAllowed,
    );
  }

  @override
  Future<bool> download() async {
    try {
      return await InAppUpdate.startFlexibleUpdate() == AppUpdateResult.success;
    } on PlatformException catch (error) {
      _log.info('Play update download failed: ${error.code}');
      return false;
    }
  }

  @override
  Future<void> install() => InAppUpdate.completeFlexibleUpdate();
}

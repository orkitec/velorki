import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/app_config.dart';
import '../../../app/platform_features.dart';
import '../../../core/links/link_opener.dart';
import '../../recording/data/recording_recovery.dart';
import '../../settings/data/package_info_provider.dart';
import '../data/store_services.dart';
import '../presentation/store_update_dialog.dart';
import 'calm_moment.dart';

final _log = Logger('velorki.store');

/// The least time between two update notices, whatever the version.
const Duration updateNoticeInterval = Duration(days: 3);

/// How long after launch the store is first asked: the first screen is up
/// and a recovered ride has had its say.
const Duration updateCheckDelay = Duration(seconds: 5);

/// How long an app brought back from the background goes before the store
/// is asked again.
const Duration updateRecheckAfter = Duration(hours: 24);

const _versionKey = 'store_prompts.update_version';
const _atKey = 'store_prompts.update_at';

/// Whether the notice for the store's [version] may come up: not shown for
/// that version yet, and none in the last [updateNoticeInterval].
bool updateNoticeDue(
  SharedPreferences prefs, {
  required String version,
  required DateTime now,
}) {
  if (prefs.getString(_versionKey) == version) return false;
  final at = prefs.getInt(_atKey);
  return at == null ||
      now.difference(DateTime.fromMillisecondsSinceEpoch(at)) >=
          updateNoticeInterval;
}

/// Tells the rider when the store has a newer Velorki.
///
/// On iOS the App Store's lookup says so, and the dialog's Update opens the
/// App Store page. On Android Google Play's in-app update API does: where
/// Play can update in place (a flexible update) its own sheet asks and
/// downloads in the background, and the app's dialog then offers the
/// restart that installs it; otherwise the dialog opens the Play page.
///
/// Asked a few seconds after launch and again when the app comes back after
/// a day; shown at most once per store version and once per
/// [updateNoticeInterval], never while a ride records or navigates (it
/// waits for the ride to end), and not at all in a browser, a debug build
/// or the `.dev` test build, which no store carries.
///
/// Called once from `bootstrap()`; the function it returns stops it.
void Function() startUpdateNotices(ProviderContainer container) {
  void none() {}
  if (!container.read(platformFeaturesProvider).storeListing) return none;
  final source = container.read(storeUpdateSourceProvider);
  if (source == null) return none;
  DateTime? checkedAt;
  var checking = false;
  var restartOffered = false;

  Future<void> offerRestart() async {
    if (restartOffered) return;
    restartOffered = true;
    await untilCalm(container, rideCalmProvider);
    if (await container.read(updatePromptProvider)(downloaded: true)) {
      await source.install();
    }
  }

  Future<void> check() async {
    if (checking) return;
    checking = true;
    final clock = container.read(storePromptClockProvider);
    checkedAt = clock();
    try {
      final installed = await container.read(packageInfoProvider.future);
      if (installed.packageName.endsWith('.dev')) return;
      // A ride left unfinished at launch is the rider's first question.
      final recovery = await container.read(recordingRecoveryProvider.future);
      if (recovery is! NoRecovery) return;
      final update = await source.check(installed);
      switch (update) {
        case null:
          return;
        case UpdateDownloaded():
          await offerRestart();
        case UpdateAvailable(:final version, :final storeUrl, :final inApp):
          final prefs = container.read(sharedPreferencesProvider);
          if (!updateNoticeDue(prefs, version: version, now: clock())) return;
          await untilCalm(container, rideCalmProvider);
          await prefs.setString(_versionKey, version);
          await prefs.setInt(_atKey, clock().millisecondsSinceEpoch);
          if (inApp) {
            if (await source.download()) await offerRestart();
          } else if (await container.read(updatePromptProvider)(
            downloaded: false,
          )) {
            await container.read(linkOpenerProvider)(Uri.parse(storeUrl));
          }
      }
    } on Object catch (error) {
      // Offline, or an install Play does not know: nothing to tell.
      _log.info('Update check failed: $error');
    } finally {
      checking = false;
    }
  }

  final first = Timer(updateCheckDelay, () => unawaited(check()));
  final lifecycle = AppLifecycleListener(
    onResume: () {
      final at = checkedAt;
      final now = container.read(storePromptClockProvider)();
      if (at != null && now.difference(at) >= updateRecheckAfter) {
        unawaited(check());
      }
    },
  );
  return () {
    first.cancel();
    lifecycle.dispose();
  };
}

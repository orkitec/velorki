import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:upgrader/upgrader.dart'
    show ITunesResults, ITunesSearchAPI, UpgraderOS;

final _log = Logger('velorki.store');

/// Velorki's page in the App Store.
const String appStorePageUrl = 'https://apps.apple.com/app/id6816790504';

/// Velorki's page on Google Play.
const String playStorePageUrl =
    'https://play.google.com/store/apps/details?id=com.orkitec.velorki';

/// Asks the platform for its rating dialog. The system decides whether it
/// shows: StoreKit at most three times a year, Play by its own quota.
typedef ReviewRequest = Future<void> Function();

Future<void> _requestSystemReview() async {
  final review = InAppReview.instance;
  if (await review.isAvailable()) await review.requestReview();
}

/// The rating request. Overridden in tests, where no store answers.
final reviewRequestProvider = Provider<ReviewRequest>(
  (ref) => _requestSystemReview,
);

/// What the store says about the installed version.
@immutable
sealed class StoreUpdate {
  const StoreUpdate();
}

/// The store has a newer version than the installed one.
final class UpdateAvailable extends StoreUpdate {
  /// Creates the offer.
  const UpdateAvailable({
    required this.version,
    required this.storeUrl,
    this.inApp = false,
  });

  /// The store's version, as the once-per-version rule keys it: the version
  /// name on the App Store, the version code on Google Play.
  final String version;

  /// The app's page in the store, which the dialog's Update button opens.
  final String storeUrl;

  /// Whether Google Play can download it inside the app (a flexible update)
  /// rather than on its own page.
  final bool inApp;
}

/// Google Play has downloaded an update; a restart installs it.
final class UpdateDownloaded extends StoreUpdate {
  /// Creates the state.
  const UpdateDownloaded();
}

/// Where the app learns about newer versions of itself.
abstract interface class StoreUpdateSource {
  /// What the store has for [installed], or `null` for nothing newer (or
  /// no answer: offline, a build the store does not know).
  Future<StoreUpdate?> check(PackageInfo installed);

  /// Starts Google Play's own download of an [UpdateAvailable.inApp]
  /// update; `true` once it is downloaded, `false` when the rider declined
  /// or it failed.
  Future<bool> download();

  /// Restarts the app into the downloaded update.
  Future<void> install();
}

/// The App Store's public lookup (`itunes.apple.com/lookup?bundleId=…`),
/// through upgrader's client for it.
class AppStoreUpdateSource implements StoreUpdateSource {
  /// Creates the source.
  AppStoreUpdateSource({ITunesSearchAPI? api, this._osVersion})
    : _api = api ?? ITunesSearchAPI();

  final ITunesSearchAPI _api;
  final String? _osVersion;

  @override
  Future<StoreUpdate?> check(PackageInfo installed) async {
    final locale = PlatformDispatcher.instance.locale;
    final response = await _api.lookupByBundleId(
      installed.packageName,
      country: locale.countryCode ?? 'US',
      language: locale.languageCode,
    );
    if (response == null) return null;
    final version = _api.version(response);
    if (version == null || !isNewerVersion(version, than: installed.version)) {
      return null;
    }
    // A version this phone's iOS cannot run is not an update for it.
    final minimumOs = _field(response, 'minimumOsVersion');
    final os = _osVersion ?? UpgraderOS().operatingSystemVersion;
    if (minimumOs != null && isNewerVersion(minimumOs, than: _dotted(os))) {
      return null;
    }
    return UpdateAvailable(
      version: version,
      storeUrl: _api.trackViewUrl(response) ?? appStorePageUrl,
    );
  }

  @override
  Future<bool> download() async => false;

  @override
  Future<void> install() async {}

  static String? _field(Map<dynamic, dynamic> response, String key) {
    final results = response['results'];
    if (results is! List || results.isEmpty) return null;
    final first = results.first;
    return first is Map ? first[key]?.toString() : null;
  }

  /// The first dotted number in [text]: `17.4` out of
  /// `Version 17.4 (Build 21E213)`, which is how iOS words it.
  static String _dotted(String text) =>
      RegExp(r'\d+(\.\d+)*').firstMatch(text)?.group(0) ?? '0';
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

/// Where this build looks for updates: the App Store on iOS, Google Play
/// on Android, nowhere in a debug build (whose version the store never
/// has) or anywhere else. Overridden in tests.
final storeUpdateSourceProvider = Provider<StoreUpdateSource?>((ref) {
  if (kIsWeb || kDebugMode) return null;
  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS => AppStoreUpdateSource(),
    TargetPlatform.android => PlayUpdateSource(),
    _ => null,
  };
});

/// Whether the dotted version [version] is later than [than]: `1.10.0`
/// after `1.9.2`. Anything after a `+` or `-` is ignored, and a part that
/// is not a number counts as nought.
bool isNewerVersion(String version, {required String than}) {
  List<int> parts(String v) => v
      .split(RegExp('[+-]'))
      .first
      .split('.')
      .map((p) => int.tryParse(p.trim()) ?? 0)
      .toList();
  final a = parts(version);
  final b = parts(than);
  for (var i = 0; i < a.length || i < b.length; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

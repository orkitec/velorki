// What each build is wired to, in one place.
//
// Seven providers used to pick a closed-source implementation themselves.
// Each now defaults to the free one, and `main.dart` installs the
// proprietary one over it (`proprietaryServiceOverrides`); `main_fdroid.dart`
// installs nothing, which is what lets the F-Droid build drop those plugins
// from pubspec.yaml altogether. Both halves are pinned here:
//
//  - the defaults, which are the whole of the F-Droid build, and
//  - the overrides, by the concrete type each installs, so a refactor that
//    silently drops one fails rather than quietly shipping the free service
//    to the stores.
//
// See docs/FDROID.md.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/proprietary_services.dart';
import 'package:velorki/features/recording/data/live_activity.dart';
import 'package:velorki/features/recording/data/plugin_live_activity.dart';
import 'package:velorki/features/sensors/data/plugin_watch_gateway.dart';
import 'package:velorki/features/sensors/data/watch_gateway.dart';
import 'package:velorki/features/store_prompts/data/play_store_services.dart';
import 'package:velorki/features/store_prompts/data/store_services.dart';
import 'package:velorki/features/subscription/data/revenuecat_subscription_service.dart';
import 'package:velorki/features/subscription/domain/plus_subscription.dart';
import 'package:velorki/features/subscription/data/subscription_service.dart';
import 'package:velorki/features/sync/data/drive_cloud_store.dart';
import 'package:velorki/features/sync/data/google_account.dart';
import 'package:velorki/features/sync/data/google_cloud.dart';
import 'package:velorki/features/sync/data/google_drive_sync.dart';

/// The config a build that carries every key would have.
const AppConfig _configured = AppConfig(
  revenueCatKeyAndroid: 'goog_test',
  revenueCatKeyIos: 'appl_test',
  googleWebClientId: 'web-client.apps.googleusercontent.com',
);

Future<ProviderContainer> _container({
  AppConfig config = _configured,
  List<Override> overrides = const [],
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appConfigProvider.overrideWithValue(config),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// A container wired as a real phone's release build is, running on
/// [platform]. The store platform and the debug flag are named because the
/// test VM is a desktop running a debug build, which has neither a store nor
/// a store version of itself to compare against.
Future<ProviderContainer> _storeBuild(TargetPlatform platform) {
  debugDefaultTargetPlatformOverride = platform;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  return _container(
    overrides: proprietaryServiceOverrides(
      storePlatform: switch (platform) {
        TargetPlatform.iOS => 'ios',
        TargetPlatform.android => 'android',
        _ => 'linux',
      },
      debug: false,
    ),
  );
}

void main() {
  group('the defaults, which are the whole of the F-Droid build', () {
    test('no store sells Plus, and the paywall can say so', () async {
      final container = await _container();
      final service = container.read(subscriptionServiceProvider);
      expect(service, isA<NoopSubscriptionService>());
      // What the paywall reads to show plusUnavailableBody instead of
      // packages, and what keeps Google Play's renewal terms off the screen.
      expect(service.isAvailable, isFalse);
      expect(service.latest, PlusCustomerInfo.none);
    });

    test('no Google sign-in, and so no Drive store and no Google in '
        'Settings → Sync with', () async {
      final container = await _container();
      expect(container.read(googleSignInServiceProvider), isNull);
      expect(container.read(googleDriveStoreProvider), isNull);
      expect(container.read(googleSyncBackendProvider), isNull);
    });

    test(
      'the rating dialog is never asked for, and asking costs nothing',
      () async {
        final container = await _container();
        // No plugin behind it: calling it in a test with no platform channel
        // registered would throw if it reached one.
        await expectLater(container.read(reviewRequestProvider)(), completes);
      },
    );

    test('no watch link', () async {
      for (final platform in TargetPlatform.values) {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final container = await _container();
        expect(
          container.read(watchGatewayProvider),
          isNull,
          reason: 'watch gateway on $platform',
        );
        expect(await container.read(watchPairedProvider.future), isFalse);
      }
    });

    test('no lock-screen card', () async {
      for (final platform in TargetPlatform.values) {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final container = await _container();
        expect(
          container.read(rideLiveActivityProvider),
          isA<NoRideLiveActivity>(),
          reason: 'live activity on $platform',
        );
      }
    });

    test(
      'no update source on Android — F-Droid updates the app itself',
      () async {
        expect(
          updateSourceWithoutStoreSdk(
            platform: TargetPlatform.android,
            debug: false,
          ),
          isNull,
        );
      },
    );

    test('the App Store lookup stays, because it is plain HTTP', () {
      expect(
        updateSourceWithoutStoreSdk(platform: TargetPlatform.iOS, debug: false),
        isA<AppStoreUpdateSource>(),
      );
    });
  });

  group('the proprietary services main.dart installs over them', () {
    test('RevenueCat sells Plus where this build carries a key', () async {
      final container = await _storeBuild(TargetPlatform.android);
      expect(
        container.read(subscriptionServiceProvider),
        isA<RevenueCatSubscriptionService>()
            .having((s) => s.apiKey, 'apiKey', 'goog_test')
            .having((s) => s.platform, 'platform', 'android'),
      );
    });

    test('...and still does not where it carries none, so a fork that set no '
        'key keeps the no-op service', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final container = await _container(
        config: const AppConfig(),
        overrides: proprietaryServiceOverrides(
          storePlatform: 'android',
          debug: false,
        ),
      );
      expect(
        container.read(subscriptionServiceProvider),
        isA<NoopSubscriptionService>(),
      );
    });

    test('Google sign-in on Android, with the web client id Credential '
        'Manager needs', () async {
      final container = await _storeBuild(TargetPlatform.android);
      expect(
        container.read(googleSignInServiceProvider),
        isA<PluginGoogleSignIn>().having(
          (s) => s.serverClientId,
          'serverClientId',
          _configured.googleWebClientId,
        ),
      );
    });

    test(
      'Google sign-in on iOS, which reads its client id from Info.plist',
      () async {
        final container = await _storeBuild(TargetPlatform.iOS);
        expect(
          container.read(googleSignInServiceProvider),
          isA<PluginGoogleSignIn>().having(
            (s) => s.serverClientId,
            'serverClientId',
            isNull,
          ),
        );
      },
    );

    test('no Google sign-in on Android without the web client id', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final container = await _container(
        config: const AppConfig(),
        overrides: proprietaryServiceOverrides(
          storePlatform: 'android',
          debug: false,
        ),
      );
      expect(container.read(googleSignInServiceProvider), isNull);
      expect(container.read(googleDriveStoreProvider), isNull);
    });

    test('the Drive store follows the sign-in', () async {
      final container = await _storeBuild(TargetPlatform.android);
      expect(container.read(googleDriveStoreProvider), isA<DriveCloudStore>());
      // ...and with it, Google appears in Settings → Sync with.
      expect(container.read(googleSyncBackendProvider), isNotNull);
    });

    test('the system rating dialog', () async {
      final container = await _storeBuild(TargetPlatform.android);
      expect(
        container.read(reviewRequestProvider),
        same(requestSystemReview),
        reason: 'the no-op default must have been replaced',
      );
    });

    test('Google Play in-app updates on Android', () async {
      final container = await _storeBuild(TargetPlatform.android);
      expect(
        container.read(storeUpdateSourceProvider),
        isA<PlayUpdateSource>(),
      );
    });

    test('and the App Store lookup on iOS, as before', () async {
      final container = await _storeBuild(TargetPlatform.iOS);
      expect(
        container.read(storeUpdateSourceProvider),
        isA<AppStoreUpdateSource>(),
      );
    });

    test('the WatchConnectivity gateway on iOS and on Android (Wear OS), '
        'nothing on a desktop', () async {
      final ios = await _storeBuild(TargetPlatform.iOS);
      expect(ios.read(watchGatewayProvider), isA<PluginWatchGateway>());
      debugDefaultTargetPlatformOverride = null;
      final android = await _storeBuild(TargetPlatform.android);
      expect(android.read(watchGatewayProvider), isA<PluginWatchGateway>());
      debugDefaultTargetPlatformOverride = null;
      final macos = await _storeBuild(TargetPlatform.macOS);
      expect(macos.read(watchGatewayProvider), isNull);
    });

    test('the ActivityKit card on iOS, nothing on Android', () async {
      final ios = await _storeBuild(TargetPlatform.iOS);
      expect(ios.read(rideLiveActivityProvider), isA<PluginRideLiveActivity>());
      debugDefaultTargetPlatformOverride = null;
      final android = await _storeBuild(TargetPlatform.android);
      expect(android.read(rideLiveActivityProvider), isA<NoRideLiveActivity>());
    });

    test('every one of the seven providers is actually overridden', () async {
      // The guard against the two builds drifting apart: an eighth
      // proprietary provider added without an override, or an override
      // dropped in a refactor, leaves one of these reading its free default
      // on a phone that paid for the store build.
      final container = await _storeBuild(TargetPlatform.iOS);
      expect(
        container.read(subscriptionServiceProvider),
        isNot(isA<NoopSubscriptionService>()),
      );
      expect(container.read(googleSignInServiceProvider), isNotNull);
      expect(container.read(reviewRequestProvider), isNot(isNull));
      expect(container.read(reviewRequestProvider), same(requestSystemReview));
      expect(container.read(storeUpdateSourceProvider), isNotNull);
      expect(container.read(watchGatewayProvider), isNotNull);
      expect(
        container.read(rideLiveActivityProvider),
        isNot(isA<NoRideLiveActivity>()),
      );
      // The Drive store needs a signed-in-capable service, which iOS has.
      expect(container.read(googleDriveStoreProvider), isNotNull);
    });
  });
}

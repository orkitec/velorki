import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/misc.dart' show Override;

import '../features/recording/data/plugin_live_activity.dart';
import '../features/sensors/data/plugin_watch_gateway.dart';
import '../features/store_prompts/data/play_store_services.dart';
import '../features/subscription/data/revenuecat_subscription_service.dart';
import '../features/subscription/data/subscription_service.dart';
import '../features/sync/data/google_cloud.dart';

/// The services Velorki reaches through a closed-source plugin, as overrides
/// on the free providers underneath them.
///
/// This file is the only place the six plugins are reached from, and it is
/// imported by `bootstrap.dart` alone — so the F-Droid entry point
/// (`main_fdroid.dart`, which calls `startVelorki()` with no overrides)
/// compiles none of them, and its build drops them from `pubspec.yaml`.
/// Every provider behind an override here has a free default that is what
/// the F-Droid build, the browser and the tests all run on:
///
/// - the store subscription: RevenueCat, else no store at all and a paywall
///   that says Plus cannot be bought in this build;
/// - Google sync: `google_sign_in` and the Drive store, else Settings →
///   Sync with offers iCloud only (or nothing);
/// - the store's rating dialog and the update notice: StoreKit and Google
///   Play, else neither is ever asked for;
/// - the Apple Watch link and the ride's lock-screen card: iOS only in any
///   case, and nothing at all without their plugins.
///
/// `docs/FDROID.md` is the whole picture; a seventh plugin added here has to
/// follow the same shape, or the Google-free build stops building.
///
/// [storePlatform] and [debug] are [currentStorePlatform] and [kDebugMode],
/// named so a test can ask for the list a real phone's release build gets:
/// the test VM is a desktop, which sells nothing, and a debug build has no
/// store version to compare its own against.
List<Override> proprietaryServiceOverrides({
  String? storePlatform,
  bool debug = kDebugMode,
}) => [
  storeSubscriptionOverride(storePlatform: storePlatform),
  ...googleCloudOverrides(),
  ...storePromptOverrides(debug: debug),
  watchGatewayOverride(),
  liveActivityOverride(),
];

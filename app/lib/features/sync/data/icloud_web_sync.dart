import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/app_config.dart';
import 'cloudkit_js_cloud_store.dart';
import 'cloudkit_web.dart';
import 'google_drive_sync.dart';
import 'store_sync_backend.dart';
import 'sync_backend.dart';

part 'icloud_web_sync.g.dart';

/// The CloudKit environment a page on [host] uses: Development on
/// localhost (`tool/web_serve.py --https`, which the Development token
/// allows), Production everywhere else (app.velorki.com).
String cloudKitEnvironmentFor(String host) =>
    host == 'localhost' || host == '127.0.0.1' ? 'development' : 'production';

/// CloudKit JS in the web planner, or null: off the web, or without the
/// environment's web token. Nothing of Apple's loads until iCloud is used.
@Riverpod(keepAlive: true)
CloudKitWeb? cloudKitWeb(Ref ref) {
  if (!kIsWeb) return null;
  final config = ref.watch(appConfigProvider);
  final environment = cloudKitEnvironmentFor(Uri.base.host);
  final token = environment == 'development'
      ? config.cloudKitTokenDevelopment
      : config.cloudKitTokenProduction;
  if (token.isEmpty) return null;
  return createCloudKitWeb(apiToken: token, environment: environment);
}

/// The `Library` zone over CloudKit JS, or null without [cloudKitWeb].
@Riverpod(keepAlive: true)
CloudKitJsCloudStore? iCloudWebStore(Ref ref) {
  final api = ref.watch(cloudKitWebProvider);
  if (api == null) return null;
  return CloudKitJsCloudStore(
    api: api,
    state: PrefsSyncEngineState(
      ref.watch(sharedPreferencesProvider),
      prefix: 'sync.icloud.web.store.',
    ),
  );
}

/// The browser's iCloud sync: the Dart engine over [iCloudWebStore], the
/// settings left out (the iOS app keeps them in the key-value store).
@Riverpod(keepAlive: true)
SyncBackend? iCloudWebSyncBackend(Ref ref) {
  final store = ref.watch(iCloudWebStoreProvider);
  if (store == null) return null;
  final backend = StoreSyncBackend(
    store: store,
    state: PrefsSyncEngineState(
      ref.watch(sharedPreferencesProvider),
      prefix: 'sync.icloud.web.',
    ),
    inbox: () => ref.read(cloudSyncInboxProvider.future),
    syncsSettings: false,
  );
  ref.onDispose(() => unawaited(backend.stop()));
  return backend;
}

/// Who is signed in to iCloud in this browser (the user record name), as
/// it changes; null while no one is. Asking loads CloudKit JS.
@Riverpod(keepAlive: true)
Stream<String?> iCloudWebUser(Ref ref) {
  final api = ref.watch(cloudKitWebProvider);
  if (api == null) return Stream<String?>.value(null);
  final out = StreamController<String?>();
  final changes = api.users.listen(out.add);
  unawaited(
    api.userRecordName().then(
      (user) => out.add(user),
      onError: (Object _) => out.add(null),
    ),
  );
  ref.onDispose(() {
    unawaited(changes.cancel());
    unawaited(out.close());
  });
  return out.stream.distinct();
}

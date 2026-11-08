import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:logging/logging.dart';

import '../../../app/app_config.dart';
import 'drive_cloud_store.dart';
import 'google_account.dart';
import 'google_drive_sync.dart';
import 'google_web_sign_in.dart';

/// Google sync as the Google Play builds have it: `google_sign_in` for the
/// account and `googleapis` for the Drive store.
///
/// Everything in this file is reached from an entry point and nowhere else —
/// `main.dart` and `bootstrap_web.dart` install [googleSignInOverride] and
/// [googleDriveStoreOverride]; `main_fdroid.dart` does not, and so compiles
/// neither library in. The defaults behind both overrides are null, which
/// leaves Google out of Settings → Sync with altogether.
final Logger _log = Logger('velorki.sync.google');

/// Google sync's two providers with Google behind them, for an entry point
/// to install together.
List<Override> googleCloudOverrides() => [
  googleSignInOverride(),
  googleDriveStoreOverride(),
];

/// [googleSignInServiceProvider] with Google's own sign-in behind it: iOS,
/// Android with the web client's id configured, and the browser with it;
/// null on anything else, as before.
Override googleSignInOverride() =>
    googleSignInServiceProvider.overrideWith((ref) {
      final webClientId = ref.watch(appConfigProvider).googleWebClientId;
      if (kIsWeb) {
        return webClientId.isEmpty ? null : createWebGoogleSignIn(webClientId);
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        return PluginGoogleSignIn();
      }
      if (defaultTargetPlatform == TargetPlatform.android &&
          webClientId.isNotEmpty) {
        return PluginGoogleSignIn(serverClientId: webClientId);
      }
      return null;
    });

/// [googleDriveStoreProvider] with the rider's hidden Drive folder behind
/// it. The store outlives the account: signed out, its account id is null
/// and the engine syncs nothing.
Override googleDriveStoreOverride() =>
    googleDriveStoreProvider.overrideWith((ref) {
      final service = ref.watch(googleSignInServiceProvider);
      if (service == null) return null;
      return DriveCloudStore(
        auth: GoogleDriveAuth(
          account: () => ref.read(googleAccountControllerProvider),
          service: service,
          onLost: () =>
              ref.read(googleAccountControllerProvider.notifier).lost(),
        ),
        state: PrefsSyncEngineState(
          ref.watch(sharedPreferencesProvider),
          prefix: 'sync.google.drive.',
        ),
      );
    });

/// [GoogleSignInService] over the `google_sign_in` plugin. iOS reads its
/// client id from Info.plist (`GIDClientID`); Android's client is matched
/// by package and signing key, and Credential Manager needs the web
/// client's id as [serverClientId] (no server auth code is asked for).
class PluginGoogleSignIn implements GoogleSignInService {
  /// Creates the service.
  PluginGoogleSignIn({this.serverClientId});

  /// The web client's id, for Android.
  final String? serverClientId;

  Future<void>? _ready;

  Future<void> _init() => _ready ??= GoogleSignIn.instance.initialize(
    serverClientId: serverClientId,
  );

  @override
  Future<GoogleAccount> signIn() async {
    try {
      await _init();
      final account = await GoogleSignIn.instance.authenticate(
        scopeHint: const [driveAppDataScope],
      );
      // Where the sign-in already granted the scope (iOS honours the hint),
      // asking again would show Google's screen a second time.
      final client = account.authorizationClient;
      if (await client.authorizationForScopes(const [driveAppDataScope]) ==
          null) {
        await client.authorizeScopes(const [driveAppDataScope]);
      }
      return GoogleAccount(id: account.id, email: account.email);
    } on GoogleSignInException catch (e) {
      _log.info('sign-in: ${e.code.name} ${e.description}');
      throw GoogleSignInFailure(
        canceled:
            e.code == GoogleSignInExceptionCode.canceled ||
            e.code == GoogleSignInExceptionCode.interrupted,
        message: e.description,
      );
    }
  }

  @override
  Future<void> signOut() async {
    await _init();
    await GoogleSignIn.instance.signOut();
  }

  @override
  Future<String?> accessToken(GoogleAccount account, {String? stale}) async {
    await _init();
    if (stale != null) {
      await GoogleSignIn.instance.authorizationClient.clearAuthorizationToken(
        accessToken: stale,
      );
    }
    // iOS restores its last sign-in when no user is named (it knows none
    // after a restart); Android finds the account by its email.
    final ios = Platform.isIOS;
    final tokens = await GoogleSignInPlatform.instance
        .clientAuthorizationTokensForScopes(
          ClientAuthorizationTokensForScopesParameters(
            request: AuthorizationRequestDetails(
              scopes: const [driveAppDataScope],
              userId: ios ? null : account.id,
              email: ios ? null : account.email,
              promptIfUnauthorized: false,
            ),
          ),
        );
    return tokens?.accessToken;
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Widget;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:googleapis/drive/v3.dart' show DriveApi;
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/app_config.dart';
import 'cloud_store.dart';
import 'drive_cloud_store.dart';
import 'google_web_sign_in.dart';

part 'google_account.g.dart';

final Logger _log = Logger('velorki.sync.google');

/// The one scope Google sync asks for: the app's hidden Drive folder,
/// nothing else in the rider's Drive.
const String driveAppDataScope = DriveApi.driveAppdataScope;

/// Where the signed-in account is kept.
const String _prefsAccount = 'sync.google.user';

/// The Google account this device syncs with.
@immutable
class GoogleAccount {
  /// Creates the account.
  const GoogleAccount({required this.id, required this.email});

  /// Google's stable id of the account.
  final String id;

  /// Its email address, shown in Settings.
  final String email;

  @override
  bool operator ==(Object other) =>
      other is GoogleAccount && other.id == id && other.email == email;

  @override
  int get hashCode => Object.hash(id, email);
}

/// Why a sign-in did not happen.
class GoogleSignInFailure implements Exception {
  /// Creates the failure; [canceled] when the rider stopped it.
  const GoogleSignInFailure({required this.canceled, this.message});

  /// Whether the rider closed the sign-in.
  final bool canceled;

  /// What the platform said, for the log.
  final String? message;

  @override
  String toString() => 'GoogleSignInFailure(canceled: $canceled, $message)';
}

/// Google's sign-in on this platform, as sync needs it.
abstract interface class GoogleSignInService {
  /// Signs in and asks for [driveAppDataScope], with the rider. Throws
  /// [GoogleSignInFailure].
  Future<GoogleAccount> signIn();

  /// Signs out on this device; nothing is revoked or deleted.
  Future<void> signOut();

  /// An access token for [account], without asking the rider; null when
  /// only they can grant one. [stale] is one Drive refused. Throws when it
  /// cannot be told now.
  Future<String?> accessToken(GoogleAccount account, {String? stale});
}

/// Google's sign-in in a browser (Google Identity Services), where only
/// Google's own button signs in and only a click of the rider's grants a
/// token: none outlives the page, and each lasts an hour. A token that
/// cannot be had silently is no lost account there, only a sign-in to do
/// again ([CloudStoreFailure.signInNeeded]).
abstract interface class ButtonGoogleSignIn implements GoogleSignInService {
  /// Google's sign-in button, [dark] or light.
  Widget button({required bool dark});

  /// The accounts signed in with [button], as they are.
  Stream<GoogleAccount> get signIns;

  /// Asks the rider for [driveAppDataScope] for [account] in Google's popup;
  /// call from a click of theirs. The access token. Throws
  /// [GoogleSignInFailure].
  Future<String> authorize(GoogleAccount account);
}

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
      await account.authorizationClient.authorizeScopes(const [
        driveAppDataScope,
      ]);
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

/// Google's sign-in where this build offers Google sync (iOS, Android and
/// the browser with the web client's id configured), else null.
@Riverpod(keepAlive: true)
GoogleSignInService? googleSignInService(Ref ref) {
  final webClientId = ref.watch(appConfigProvider).googleWebClientId;
  if (kIsWeb) {
    return webClientId.isEmpty ? null : createWebGoogleSignIn(webClientId);
  }
  if (Platform.isIOS) return PluginGoogleSignIn();
  if (Platform.isAndroid && webClientId.isNotEmpty) {
    return PluginGoogleSignIn(serverClientId: webClientId);
  }
  return null;
}

/// The Google account signed in for sync, kept in the preferences; null
/// while none is.
@Riverpod(keepAlive: true)
class GoogleAccountController extends _$GoogleAccountController {
  @override
  GoogleAccount? build() {
    if (ref.watch(googleSignInServiceProvider)
        case final ButtonGoogleSignIn web) {
      final signIns = web.signIns.listen(
        (account) => unawaited(_remember(account)),
        onError: (Object e) => _log.info('button sign-in: $e'),
      );
      ref.onDispose(signIns.cancel);
    }
    final json = ref.watch(sharedPreferencesProvider).getString(_prefsAccount);
    if (json == null) return null;
    try {
      final map = jsonDecode(json) as Map<String, Object?>;
      return GoogleAccount(
        id: map['id']! as String,
        email: map['email']! as String,
      );
    } on Object {
      return null;
    }
  }

  /// Signs in with the rider. Throws [GoogleSignInFailure].
  Future<GoogleAccount> signIn() async {
    final service = ref.read(googleSignInServiceProvider);
    if (service == null) {
      throw const GoogleSignInFailure(canceled: false);
    }
    final account = await service.signIn();
    await _remember(account);
    return account;
  }

  Future<void> _remember(GoogleAccount account) async {
    await ref
        .read(sharedPreferencesProvider)
        .setString(
          _prefsAccount,
          jsonEncode({'id': account.id, 'email': account.email}),
        );
    state = account;
  }

  /// Asks the rider for Drive access in a browser ([ButtonGoogleSignIn]),
  /// after a click of theirs; the access token. Throws
  /// [GoogleSignInFailure].
  Future<String> authorize() async {
    final service = ref.read(googleSignInServiceProvider);
    final account = state;
    if (service is! ButtonGoogleSignIn || account == null) {
      throw const GoogleSignInFailure(canceled: false);
    }
    return service.authorize(account);
  }

  /// Signs out on this device; what is in Drive stays there.
  Future<void> signOut() async {
    try {
      await ref.read(googleSignInServiceProvider)?.signOut();
    } on Object catch (e) {
      _log.info('sign-out: $e');
    }
    await _forget();
  }

  /// Google took the access back (or the rider did, elsewhere): signed
  /// out until they sign in again.
  Future<void> lost() async {
    _log.info('access to Drive lost');
    await _forget();
  }

  Future<void> _forget() async {
    await ref.read(sharedPreferencesProvider).remove(_prefsAccount);
    state = null;
  }
}

/// [DriveAuth] over the account signed in: its tokens kept for most of
/// their hour.
class GoogleDriveAuth implements DriveAuth {
  /// Creates the auth.
  GoogleDriveAuth({
    required this.account,
    required this.service,
    required this.onLost,
    this.clock = DateTime.now,
  });

  /// The account signed in now.
  final GoogleAccount? Function() account;

  /// Where the tokens come from.
  final GoogleSignInService service;

  /// Called when only the rider can grant access again.
  final Future<void> Function() onLost;

  /// The time.
  final DateTime Function() clock;

  String? _token;
  String? _tokenAccount;
  DateTime? _tokenAt;

  @override
  String? get accountId => account()?.id;

  @override
  Future<String?> accessToken({String? stale}) async {
    final current = account();
    if (current == null) return null;
    final at = _tokenAt;
    if (_token != null &&
        _token != stale &&
        _tokenAccount == current.id &&
        at != null &&
        clock().difference(at) < const Duration(minutes: 45)) {
      return _token;
    }
    _token = null;
    final String? token;
    try {
      token = await service.accessToken(current, stale: stale);
    } on Object catch (e) {
      _log.info('no token now: $e');
      throw CloudStoreException(CloudStoreFailure.transient, '$e');
    }
    if (token == null) {
      // In a browser only a click of the rider's gets a token: the account
      // stays theirs meanwhile.
      if (service is ButtonGoogleSignIn) {
        throw const CloudStoreException(
          CloudStoreFailure.signInNeeded,
          'Google needs the rider to sign in again',
        );
      }
      await onLost();
      return null;
    }
    _token = token;
    _tokenAccount = current.id;
    _tokenAt = clock();
    return token;
  }
}

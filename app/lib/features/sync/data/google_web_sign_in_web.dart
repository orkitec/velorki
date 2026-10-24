// The web side of a conditional export: what uses it is the same import on
// the phone side, which is the side dart_code_linter follows.
// ignore_for_file: unused-code

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/widgets.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:google_sign_in_web/web_only.dart' as gis;
import 'package:logging/logging.dart';

import 'google_account.dart';

final Logger _log = Logger('velorki.sync.google');

/// [ButtonGoogleSignIn] over google_sign_in's web implementation (Google
/// Identity Services) with the web client [clientId].
ButtonGoogleSignIn createWebGoogleSignIn(String clientId) =>
    _WebGoogleSignIn(clientId);

class _WebGoogleSignIn implements ButtonGoogleSignIn {
  _WebGoogleSignIn(this._clientId);

  final String _clientId;
  Future<void>? _ready;

  /// Lets Google's script onto the page (`device_gate.mjs` holds it back
  /// until the rider picks Google), then initialises the plugin with it.
  Future<void> _init() => _ready ??= () {
    if (globalContext.has('velorkiLoadGoogleSdk')) {
      globalContext.callMethod('velorkiLoadGoogleSdk'.toJS);
    }
    return GoogleSignIn.instance.initialize(clientId: _clientId);
  }();

  @override
  Widget button({required bool dark}) {
    unawaited(_init());
    return gis.renderButton(
      configuration: gis.GSIButtonConfiguration(
        theme: dark
            ? gis.GSIButtonTheme.filledBlack
            : gis.GSIButtonTheme.outline,
        size: gis.GSIButtonSize.large,
        text: gis.GSIButtonText.signinWith,
        shape: gis.GSIButtonShape.pill,
      ),
    );
  }

  @override
  Stream<GoogleAccount> get signIns => GoogleSignIn
      .instance
      .authenticationEvents
      .where((e) => e is GoogleSignInAuthenticationEventSignIn)
      .map((e) {
        final user = (e as GoogleSignInAuthenticationEventSignIn).user;
        return GoogleAccount(id: user.id, email: user.email);
      });

  /// A browser signs in with [button] only.
  @override
  Future<GoogleAccount> signIn() =>
      throw const GoogleSignInFailure(canceled: false);

  @override
  Future<String> authorize(GoogleAccount account) async {
    await _init();
    try {
      final token = await _tokens(account, prompt: true);
      if (token == null) throw const GoogleSignInFailure(canceled: true);
      return token;
    } on GoogleSignInException catch (e) {
      _log.info('authorize: ${e.code.name} ${e.description}');
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
    // The plugin keeps the token a click got for its hour; past that, or
    // after a reload, only another click gets one.
    return _tokens(account, prompt: false);
  }

  /// The plugin keeps tokens by the user id asked with: the silent ask
  /// and the click's name the same.
  Future<String?> _tokens(GoogleAccount account, {required bool prompt}) async {
    final tokens = await GoogleSignInPlatform.instance
        .clientAuthorizationTokensForScopes(
          ClientAuthorizationTokensForScopesParameters(
            request: AuthorizationRequestDetails(
              scopes: const [driveAppDataScope],
              userId: account.id,
              email: account.email,
              promptIfUnauthorized: prompt,
            ),
          ),
        );
    return tokens?.accessToken;
  }
}

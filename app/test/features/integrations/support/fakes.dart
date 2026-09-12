import 'dart:async';

import 'package:velorki/features/integrations/common/data/oauth_flow.dart';
import 'package:velorki/features/integrations/common/domain/integration_exception.dart';
import 'package:velorki_api/velorki_api.dart';

export 'package:velorki/features/integrations/common/data/secure_key_value_store.dart'
    show InMemorySecureKeyValueStore;

/// A [WebAuthenticator] that answers with a canned callback URL.
class FakeWebAuthenticator implements WebAuthenticator {
  /// Creates an authenticator that answers with [callback].
  FakeWebAuthenticator({this.callback, this.failure, this.delay});

  /// The redirect URL the "browser" came back with.
  Uri? callback;

  /// Thrown instead of answering, for the cancelled case.
  Object? failure;

  /// How long the "browser" stays open.
  Duration? delay;

  /// Every URL that was opened.
  final List<Uri> opened = <Uri>[];

  @override
  Future<Uri> authenticate({
    required Uri url,
    required String callbackUrlScheme,
  }) async {
    opened.add(url);
    if (delay != null) await Future<void>.delayed(delay!);
    final error = failure;
    if (error != null) throw error;
    final result = callback;
    if (result == null) {
      // Never answers: the deep link is expected to win this race.
      return Completer<Uri>().future;
    }
    return result;
  }
}

/// An [AppLauncher] that says whether an app-to-app URL can be opened.
class FakeAppLauncher implements AppLauncher {
  /// Creates a launcher.
  FakeAppLauncher({this.canOpen = false, this.opens = true});

  /// What [canLaunch] answers.
  bool canOpen;

  /// What [launch] answers.
  bool opens;

  /// Every URL that was handed over.
  final List<Uri> launched = <Uri>[];

  /// Every URL that was asked about.
  final List<Uri> asked = <Uri>[];

  @override
  Future<bool> canLaunch(Uri url) async {
    asked.add(url);
    return canOpen;
  }

  @override
  Future<bool> launch(Uri url) async {
    launched.add(url);
    return opens;
  }
}

/// A relay whose answers are set by the test.
///
/// `RelayClient` talks over `package:http`, not dio, so it is faked by
/// subclassing rather than by an adapter: that keeps the app's tests free of a
/// direct `http` dependency and still exercises the real call sites.
class FakeRelayClient extends RelayClient {
  /// Creates a fake relay.
  FakeRelayClient({
    this.stravaTokens,
    this.refreshedStravaTokens,
    this.rwgpsTokens,
    this.failure,
  }) : super('https://relay.test');

  /// What [exchangeStravaCode] answers.
  StravaTokens? stravaTokens;

  /// What [refreshStrava] answers.
  StravaTokens? refreshedStravaTokens;

  /// What [exchangeRwgpsCode] answers.
  RwgpsTokens? rwgpsTokens;

  /// Thrown by every method when set.
  RelayException? failure;

  /// The codes that were exchanged, in order.
  final List<String> exchangedCodes = <String>[];

  /// The redirect URIs that were sent, in order.
  final List<String> redirectUris = <String>[];

  /// The refresh tokens that were spent, in order.
  final List<String> refreshedWith = <String>[];

  @override
  Future<StravaTokens> exchangeStravaCode({
    required String code,
    required String redirectUri,
  }) async {
    if (failure != null) throw failure!;
    exchangedCodes.add(code);
    redirectUris.add(redirectUri);
    return stravaTokens!;
  }

  @override
  Future<StravaTokens> refreshStrava({required String refreshToken}) async {
    if (failure != null) throw failure!;
    refreshedWith.add(refreshToken);
    return refreshedStravaTokens!;
  }

  @override
  Future<RwgpsTokens> exchangeRwgpsCode({
    required String code,
    required String redirectUri,
  }) async {
    if (failure != null) throw failure!;
    exchangedCodes.add(code);
    redirectUris.add(redirectUri);
    return rwgpsTokens!;
  }
}

/// Runs [body] and returns the [IntegrationException] it threw.
Future<IntegrationException> integrationFailure(
  Future<void> Function() body,
) async {
  try {
    await body();
  } on IntegrationException catch (e) {
    return e;
  }
  throw StateError('expected an IntegrationException');
}

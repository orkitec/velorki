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
    this.planEvents = const <PlanEvent>[],
    this.planFailure,
    this.shareLink,
  }) : super('https://relay.test');

  /// What [exchangeStravaCode] answers.
  StravaTokens? stravaTokens;

  /// What [refreshStrava] answers.
  StravaTokens? refreshedStravaTokens;

  /// What [exchangeRwgpsCode] answers.
  RwgpsTokens? rwgpsTokens;

  /// Thrown by every method when set.
  RelayException? failure;

  /// The events `planStream` yields, in order.
  List<PlanEvent> planEvents = const <PlanEvent>[];

  /// Thrown by `planStream` before the stream opens, when set.
  RelayException? planFailure;

  /// Every `/ai/plan` request, in order.
  final List<PlanCall> planCalls = <PlanCall>[];

  /// What `createShare` answers.
  ShareLink? shareLink;

  /// Every `POST /share`, in order.
  final List<ShareCall> shareCalls = <ShareCall>[];

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
  Stream<PlanEvent> planStream({
    required String step,
    required String prompt,
    String locale = 'en',
    PlanUnits units = PlanUnits.metric,
    PlanContext? context,
    RouteSummary? routeSummary,
    String? appUserId,
  }) async* {
    planCalls.add(
      PlanCall(
        step: step,
        prompt: prompt,
        locale: locale,
        context: context,
        routeSummary: routeSummary,
      ),
    );
    final error = planFailure ?? failure;
    if (error != null) throw error;
    for (final event in planEvents) {
      yield event;
    }
  }

  @override
  Future<ShareLink> createShare({
    required String name,
    required String gpx,
    required ShareSummary summary,
    ShareKind kind = ShareKind.route,
  }) async {
    if (failure != null) throw failure!;
    shareCalls.add(
      ShareCall(name: name, gpx: gpx, summary: summary, kind: kind),
    );
    return shareLink ??
        const ShareLink(
          id: '7Kq2mZ0aTb',
          url: 'https://velorki.app/s/7Kq2mZ0aTb',
        );
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

/// One `POST /ai/plan` the fake relay saw.
class PlanCall {
  /// Records a request.
  const PlanCall({
    required this.step,
    required this.prompt,
    required this.locale,
    this.context,
    this.routeSummary,
  });

  /// `plan` or `describe`.
  final String step;

  /// The rider's text.
  final String prompt;

  /// The BCP47 tag the answer was asked for in.
  final String locale;

  /// The rough position, when consent allowed one.
  final PlanContext? context;

  /// The route summary of a `describe` request.
  final RouteSummary? routeSummary;
}

/// One `POST /share` the fake relay saw.
class ShareCall {
  /// Records a share.
  const ShareCall({
    required this.name,
    required this.gpx,
    required this.summary,
    required this.kind,
  });

  /// The title of the share page.
  final String name;

  /// The stored GPX document.
  final String gpx;

  /// The headline numbers.
  final ShareSummary summary;

  /// Route or ride.
  final ShareKind kind;
}

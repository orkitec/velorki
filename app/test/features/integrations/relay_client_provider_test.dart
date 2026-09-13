import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/integrations/common/data/relay_client_provider.dart';
import 'package:velorki/features/settings/data/package_info_provider.dart';
import 'package:velorki/features/integrations/common/domain/integration_exception.dart';
import 'package:velorki_api/velorki_api.dart';

import 'support/pump.dart';

/// [requireRelay] as the token sources use it: from a closure that runs long
/// after the provider was built, so the exception reaches the caller unwrapped.
final _requiredRelayProvider = Provider<RelayClient Function()>(
  (ref) =>
      () => requireRelay(ref),
);

PackageInfo _info({String version = '1.4.0', String buildNumber = '42'}) =>
    PackageInfo(
      appName: 'Velorki',
      packageName: 'app.velorki',
      version: version,
      buildNumber: buildNumber,
    );

void main() {
  test('the client id is the platform and the version', () {
    expect(
      velorkiClientId(version: '1.4.0+42'),
      '${Platform.operatingSystem}/1.4.0+42',
    );
  });

  group('building the client', () {
    test('a build with a relay URL gets a client pointed at it', () async {
      final container = await integrationsContainer(
        config: const AppConfig(apiUrl: 'https://relay.test/v1/'),
      );

      final client = container.read(relayClientProvider);

      expect(client, isNotNull);
      // The trailing slash is normalised away and the path prefix kept.
      expect(
        client!.uriFor('/share'),
        Uri.parse('https://relay.test/v1/share'),
      );
    });

    test('the app user id is what the relay authenticates', () async {
      final container = await integrationsContainer(
        initialPrefs: const <String, Object>{'plus.app_user_id': 'anon-42'},
      );

      expect(container.read(relayClientProvider)!.appUserId, 'anon-42');
    });

    test('a build without a relay URL has no client at all', () async {
      final container = await integrationsContainer(config: const AppConfig());

      expect(container.read(relayClientProvider), isNull);
    });

    test('a server override replaces the built-in relay URL', () async {
      final container = await integrationsContainer(
        config: const AppConfig(apiUrl: 'https://relay.test'),
        initialPrefs: const <String, Object>{
          'server_override.api_url': 'https://my-own-relay.test',
        },
      );

      expect(
        container.read(relayClientProvider)!.uriFor('/share'),
        Uri.parse('https://my-own-relay.test/share'),
      );
    });

    test('a server override can give a local build a relay', () async {
      final container = await integrationsContainer(
        config: const AppConfig(),
        initialPrefs: const <String, Object>{
          'server_override.api_url': 'https://my-own-relay.test',
        },
      );

      expect(container.read(relayClientProvider), isNotNull);
    });

    test('the client id carries the version and the build number', () async {
      final container = await integrationsContainer(
        packageInfo: _info(version: '1.4.0', buildNumber: '42'),
      );

      expect(
        container.read(relayClientProvider)!.clientId,
        '${Platform.operatingSystem}/1.4.0+42',
      );
    });

    test('the version is dev until the package info plugin answers', () async {
      final container = await integrationsContainer(
        extraOverrides: <Override>[
          packageInfoProvider.overrideWith(
            (ref) => Completer<PackageInfo>().future,
          ),
        ],
      );

      expect(
        container.read(relayClientProvider)!.clientId,
        '${Platform.operatingSystem}/dev',
      );
    });

    test('the client is closed when the container goes away', () async {
      final container = await integrationsContainer();
      final client = container.read(relayClientProvider)!;

      container.dispose();

      // A closed client refuses to send anything, which is how the relay
      // reports that its transport is gone.
      await expectLater(
        client.refreshStrava(refreshToken: 'whatever'),
        throwsA(
          isA<RelayException>().having(
            (e) => e.error.code,
            'code',
            RelayErrorCode.unavailable,
          ),
        ),
      );
    });
  });

  group('requireRelay', () {
    test('hands back the client of a configured build', () async {
      final container = await integrationsContainer();

      expect(
        container.read(_requiredRelayProvider)(),
        same(container.read(relayClientProvider)),
      );
    });

    test('explains that a local build has no relay', () async {
      final container = await integrationsContainer(config: const AppConfig());

      expect(
        container.read(_requiredRelayProvider),
        throwsA(
          isA<IntegrationException>()
              .having(
                (e) => e.failure,
                'failure',
                IntegrationFailure.relayUnavailable,
              )
              .having(
                (e) => e.message,
                'message',
                contains('no Velorki relay'),
              ),
        ),
      );
    });
  });

  group('mapping a relay failure', () {
    IntegrationException mapped(
      String code, {
      String message = 'nope',
      int? retryAfterS,
    }) => integrationExceptionFor(
      RelayException(
        RelayError(code: code, message: message, retryAfterS: retryAfterS),
      ),
    );

    test('a missing entitlement asks for Velorki Plus', () {
      final e = mapped(RelayErrorCode.notEntitled);
      expect(e.failure, IntegrationFailure.relayUnavailable);
      expect(e.message, contains('Velorki Plus'));
    });

    test('rate limiting keeps the relay\'s own retry hint', () {
      final e = mapped(
        RelayErrorCode.rateLimited,
        message: 'too many',
        retryAfterS: 90,
      );
      expect(e.failure, IntegrationFailure.rateLimited);
      expect(e.message, 'too many');
      expect(e.retryAfter, const Duration(seconds: 90));
    });

    test('rate limiting without a hint leaves the wait unknown', () {
      expect(mapped(RelayErrorCode.rateLimited).retryAfter, isNull);
    });

    test('an unavailable relay is unreachable, not a service error', () {
      expect(
        mapped(RelayErrorCode.unavailable).failure,
        IntegrationFailure.unreachable,
      );
    });

    test('anything else keeps its message and counts as relay trouble', () {
      final e = mapped(RelayErrorCode.upstreamError, message: 'Strava is down');
      expect(e.failure, IntegrationFailure.relayUnavailable);
      expect(e.message, 'Strava is down');
      expect(e.cause, isA<RelayException>());
    });
  });
}

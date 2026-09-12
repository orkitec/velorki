import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velorki_api/velorki_api.dart';

import '../../../../app/app_config.dart';
import '../../../../core/plus/app_user_id.dart';
import '../../../settings/data/package_info_provider.dart';
import '../domain/integration_exception.dart';

/// The `X-Velorki-Client` value, `<platform>/<version>`.
String velorkiClientId({required String version}) {
  final platform = kIsWeb
      ? 'web'
      : Platform.operatingSystem; // android, ios, linux, macos, windows
  return '$platform/$version';
}

/// The relay client, or `null` when this build has no relay.
///
/// An empty `VELORKI_API_URL` is the pure-local fork build: no AI, no Strava,
/// no Ride with GPS, no share links. Every caller treats `null` as "the
/// integrations do not exist in this build" rather than as an error.
final relayClientProvider = Provider<RelayClient?>((ref) {
  final config = ref.watch(effectiveConfigProvider);
  if (!config.hasApi) return null;
  final info = ref.watch(packageInfoProvider).value;
  final client = RelayClient(
    config.apiUrl,
    clientId: velorkiClientId(
      version: info == null ? 'dev' : '${info.version}+${info.buildNumber}',
    ),
    appUserId: ref.watch(appUserIdProvider),
  );
  ref.onDispose(client.close);
  return client;
});

/// The relay client, or an [IntegrationException] explaining its absence.
RelayClient requireRelay(Ref ref) {
  final relay = ref.read(relayClientProvider);
  if (relay == null) {
    throw const IntegrationException(
      IntegrationFailure.relayUnavailable,
      'This build has no Velorki relay configured, so Strava and '
      'Ride with GPS cannot be connected.',
    );
  }
  return relay;
}

/// Turns a [RelayException] into the app's own exception type.
IntegrationException integrationExceptionFor(RelayException e) =>
    switch (e.error.code) {
      RelayErrorCode.notEntitled => IntegrationException(
        IntegrationFailure.relayUnavailable,
        'Velorki Plus is needed to connect this service.',
        cause: e,
      ),
      RelayErrorCode.rateLimited => IntegrationException(
        IntegrationFailure.rateLimited,
        e.error.message,
        retryAfter: e.error.retryAfterS == null
            ? null
            : Duration(seconds: e.error.retryAfterS!),
        cause: e,
      ),
      RelayErrorCode.unavailable => IntegrationException(
        IntegrationFailure.unreachable,
        e.error.message,
        cause: e,
      ),
      _ => IntegrationException(
        IntegrationFailure.relayUnavailable,
        e.error.message,
        cause: e,
      ),
    };

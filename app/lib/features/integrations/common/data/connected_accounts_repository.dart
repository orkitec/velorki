import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../domain/connected_account.dart';
import 'secure_key_value_store.dart';

final Logger _log = Logger('ConnectedAccounts');

/// The one place OAuth tokens are read and written.
///
/// Everything lives in `flutter_secure_storage`, one entry per service, so a
/// device backup or an `adb backup` never carries a usable Strava token.
class ConnectedAccountsRepository {
  /// Creates a repository over [store].
  ConnectedAccountsRepository(this._store);

  final SecureKeyValueStore _store;

  /// The secure storage key [service] is kept under.
  static String keyFor(IntegrationService service) =>
      'integrations.${service.id}.account';

  /// The connected account for [service], or `null` when there is none.
  ///
  /// An entry that cannot be parsed — written by an older version, or
  /// truncated — is deleted and reported as "not connected" rather than
  /// thrown: the rider can simply connect again.
  Future<ConnectedAccount?> read(IntegrationService service) async {
    final raw = await _store.read(keyFor(service));
    if (raw == null || raw.isEmpty) return null;
    try {
      return ConnectedAccount.decode(raw);
    } on FormatException catch (e) {
      _log.warning('discarding unreadable ${service.id} account', e);
      await _store.delete(keyFor(service));
      return null;
    }
  }

  /// Writes [account], replacing whatever was stored for its service.
  Future<void> save(ConnectedAccount account) =>
      _store.write(keyFor(account.service), account.encode());

  /// Forgets the account for [service].
  Future<void> remove(IntegrationService service) =>
      _store.delete(keyFor(service));

  /// Every connected account, keyed by service.
  Future<Map<IntegrationService, ConnectedAccount>> readAll() async {
    final out = <IntegrationService, ConnectedAccount>{};
    for (final service in IntegrationService.values) {
      final account = await read(service);
      if (account != null) out[service] = account;
    }
    return out;
  }
}

/// The repository over the app's secure storage.
final connectedAccountsRepositoryProvider =
    Provider<ConnectedAccountsRepository>(
      (ref) =>
          ConnectedAccountsRepository(ref.watch(secureKeyValueStoreProvider)),
    );

/// The connected accounts, as the UI sees them.
///
/// Kept in one notifier rather than a provider per service so a connect or a
/// disconnect rebuilds both settings tiles from one source of truth, and so a
/// token refresh written by the dio interceptor can be published back here.
class ConnectedAccounts
    extends AsyncNotifier<Map<IntegrationService, ConnectedAccount>> {
  @override
  Future<Map<IntegrationService, ConnectedAccount>> build() =>
      ref.watch(connectedAccountsRepositoryProvider).readAll();

  /// Stores [account] and publishes it.
  Future<void> save(ConnectedAccount account) async {
    await ref.read(connectedAccountsRepositoryProvider).save(account);
    _publish((current) => {...current, account.service: account});
  }

  /// Forgets [service] and publishes the removal.
  Future<void> remove(IntegrationService service) async {
    await ref.read(connectedAccountsRepositoryProvider).remove(service);
    _publish((current) => {...current}..remove(service));
  }

  /// Publishes [account] without writing it again.
  ///
  /// The token source saves a refreshed account itself; this only brings the
  /// UI up to date with what is already in secure storage.
  void publish(ConnectedAccount account) =>
      _publish((current) => {...current, account.service: account});

  /// Re-reads secure storage, for instance after a refresh happened outside.
  Future<void> reload() async {
    state = await AsyncValue.guard(
      ref.read(connectedAccountsRepositoryProvider).readAll,
    );
  }

  void _publish(
    Map<IntegrationService, ConnectedAccount> Function(
      Map<IntegrationService, ConnectedAccount> current,
    )
    change,
  ) => state = AsyncData(
    change(state.value ?? const <IntegrationService, ConnectedAccount>{}),
  );
}

/// Every connected account, keyed by service.
final connectedAccountsProvider =
    AsyncNotifierProvider<
      ConnectedAccounts,
      Map<IntegrationService, ConnectedAccount>
    >(ConnectedAccounts.new);

/// The account for one service, `null` while loading or when not connected.
final connectedAccountProvider =
    Provider.family<ConnectedAccount?, IntegrationService>(
      (ref, service) => ref.watch(connectedAccountsProvider).value?[service],
    );

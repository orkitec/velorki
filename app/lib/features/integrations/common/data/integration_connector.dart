import '../domain/connected_account.dart';

/// Connecting and disconnecting one partner service.
///
/// The two implementations differ only in their authorise URL, their relay
/// endpoint and what they can revoke, so the controller and the settings tiles
/// work against this interface and know neither.
abstract class IntegrationConnector {
  /// Which service this connector speaks for.
  IntegrationService get service;

  /// Runs the whole authorisation and returns the account to store.
  ///
  /// Throws [IntegrationException] — including the cancelled case when the
  /// rider closed the page.
  Future<ConnectedAccount> connect();

  /// Tells the service to forget Velorki, where the service allows it.
  ///
  /// Must not throw when the service cannot be reached: the local token is
  /// deleted regardless, and a rider who is disconnecting wants it gone.
  Future<void> revoke(ConnectedAccount account);
}

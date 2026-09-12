import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The slice of `flutter_secure_storage` the integrations need.
///
/// An interface rather than the plugin itself so a `flutter test` run — which
/// has neither a Keystore nor a Keychain — can hand the repository a map.
abstract class SecureKeyValueStore {
  /// The value stored under [key], or `null`.
  Future<String?> read(String key);

  /// Stores [value] under [key].
  Future<void> write(String key, String value);

  /// Removes [key]; an unknown key is not an error.
  Future<void> delete(String key);
}

/// The production store: the platform Keystore or Keychain.
class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  /// Creates a store over [storage].
  FlutterSecureKeyValueStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // The plugin's Android default is already AES-GCM behind a
            // KeyStore-wrapped key; the iOS entry is pinned to
            // `first_unlock_this_device` so a token never travels in an
            // iCloud Keychain backup to another device.
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// An in-memory store, for tests and for the widget previews.
class InMemorySecureKeyValueStore implements SecureKeyValueStore {
  /// Creates a store seeded with [values].
  InMemorySecureKeyValueStore([Map<String, String>? values])
    : values = <String, String>{...?values};

  /// What is stored right now; tests read and seed it directly.
  final Map<String, String> values;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// The app's secure storage. Overridden in tests with an in-memory store.
final secureKeyValueStoreProvider = Provider<SecureKeyValueStore>(
  (ref) => FlutterSecureKeyValueStore(),
);

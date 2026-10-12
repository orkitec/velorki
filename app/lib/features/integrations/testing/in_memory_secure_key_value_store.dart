import '../common/data/secure_key_value_store.dart';

/// An in-memory [SecureKeyValueStore] for tests.
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

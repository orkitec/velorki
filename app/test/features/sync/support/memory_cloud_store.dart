import 'dart:async';

import 'package:velorki/features/sync/data/cloud_store.dart';

/// One account's records and change log.
class _Space {
  final Map<String, StoredRecord> records = <String, StoredRecord>{};

  /// Every change, in order: a record name.
  final List<String> log = <String>[];

  /// Bumped by [MemoryCloudStore.expireCursors]: older cursors are refused.
  int epoch = 0;
}

/// A [CloudStore] in memory, as Google Drive's app data folder will be:
/// whole-record writes over a version, a change log with cursors that can
/// expire, an account that can change, and failures on demand.
class MemoryCloudStore implements CloudStore {
  /// Creates the store, signed in to [account] (null: signed out).
  MemoryCloudStore({this._account = 'rider-a', this.pageSize = 100});

  String? _account;
  final Map<String, _Space> _spaces = <String, _Space>{};
  int _versions = 0;

  /// The most records a page of [pull] or [fullList] holds.
  int pageSize;

  _Space get _space => _spaces.putIfAbsent(_account ?? '', _Space.new);

  /// The account signed in now; null signs out.
  set account(String? account) => _account = account;

  /// Throws for [accountId] while set.
  CloudStoreException? accountFailure;

  /// The failures the next writes get, one each, in order.
  final List<CloudStoreFailure> failNext = <CloudStoreFailure>[];

  /// While set, a push waits for it before it writes anything.
  Completer<void>? gate;

  /// Completes when a push is waiting at [gate].
  Completer<void>? atGate;

  /// Whether a push writes and then fails as a whole, as when its answer
  /// is lost (the app killed, the network gone).
  bool loseReplies = false;

  /// How often [push], [pull] and [fullList] were called.
  int pushes = 0;
  int pulls = 0;
  int fullLists = 0;

  /// The names of the records of the account signed in.
  Set<String> get names => _space.records.keys.toSet();

  /// The names in [account]'s space.
  Set<String> namesOf(String account) =>
      _spaces[account]?.records.keys.toSet() ?? <String>{};

  /// The fields of the record [name], or null.
  Map<String, Object?>? fields(String name) => _space.records[name]?.fields;

  /// Deletes [name] as another device would.
  void deleteElsewhere(String name) {
    if (_space.records.remove(name) != null) _space.log.add(name);
  }

  /// Makes every cursor given out so far expire.
  void expireCursors() => _space.epoch++;

  @override
  Future<String?> accountId() async {
    if (accountFailure case final failure?) throw failure;
    return _account;
  }

  @override
  Future<StoredRecord?> get(String name) async => _space.records[name];

  @override
  Future<List<StoreResult>> push(List<StoreWrite> writes) async {
    pushes++;
    if (gate case final gate?) {
      atGate?.complete();
      await gate.future;
    }
    final results = [for (final write in writes) _apply(write)];
    if (loseReplies) {
      throw const CloudStoreException(CloudStoreFailure.transient, 'lost');
    }
    return results;
  }

  StoreResult _apply(StoreWrite write) {
    if (failNext.isNotEmpty) return StoreFailed(failNext.removeAt(0));
    final space = _space;
    final current = space.records[write.name];
    switch (write) {
      case StoreDelete():
        if (current != null) {
          space.records.remove(write.name);
          space.log.add(write.name);
        }
        return const StoreDone();
      case StoreSave(:final ifVersion):
        if (ifVersion == null && current != null) return StoreConflict(current);
        if (ifVersion != null && current == null) return const StoreMissing();
        if (ifVersion != null && current!.version != ifVersion) {
          return StoreConflict(current);
        }
        final version = 'v${++_versions}';
        space.records[write.name] = StoredRecord(
          name: write.name,
          type: write.type,
          fields: Map<String, Object?>.of(write.fields),
          body: write.body,
          version: version,
        );
        space.log.add(write.name);
        return StoreDone(version);
    }
  }

  String _cursor(int at) => '${_space.epoch}:$at';

  @override
  Future<StoreChanges> pull(String cursor) async {
    pulls++;
    final [epoch, at] = cursor.split(':');
    final space = _space;
    if (int.parse(epoch) != space.epoch) throw const StoreCursorExpired();
    final from = int.parse(at);
    final to = (from + pageSize).clamp(from, space.log.length);
    final touched = space.log.sublist(from, to).toSet();
    return StoreChanges(
      changed: [for (final name in touched) ?space.records[name]],
      deleted: [
        for (final name in touched)
          if (!space.records.containsKey(name)) name,
      ],
      cursor: _cursor(to),
      more: to < space.log.length,
    );
  }

  @override
  Future<StoreChanges> fullList([String? cursor]) async {
    fullLists++;
    final all = _space.records.values.toList();
    final from = cursor == null ? 0 : int.parse(cursor.substring(5));
    final to = (from + pageSize).clamp(from, all.length);
    final more = to < all.length;
    return StoreChanges(
      changed: all.sublist(from, to),
      deleted: const <String>[],
      cursor: more ? 'list:$to' : _cursor(_space.log.length),
      more: more,
    );
  }
}

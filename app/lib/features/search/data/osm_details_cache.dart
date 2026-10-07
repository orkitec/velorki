import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/app_config.dart';
import '../domain/osm_place_details.dart';

part 'osm_details_cache.g.dart';

const String _prefsKey = 'search.osm_details';

/// The tags of the places whose details were fetched lately, kept on the
/// device so a card opened again shows them without asking the network.
///
/// Raw tags, not what the card makes of them, so whether a place is open is
/// told when the card is shown. One JSON map in shared preferences: it is
/// read synchronously, so a card shows what is known on its first frame.
/// Only the tags the card reads are kept (a few hundred bytes a place), the
/// newest [capacity] places for [maxAge] each. "Not found" is kept as no
/// tags; failures are never kept.
class OsmDetailsCache {
  /// Creates the cache over [prefs]; [now] is the clock, injected in tests.
  OsmDetailsCache(this._prefs, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  /// How long fetched details are shown without fetching them again.
  static const Duration maxAge = Duration(days: 7);

  /// How many places are kept; the oldest go first.
  static const int capacity = 300;

  final SharedPreferences _prefs;
  final DateTime Function() _now;
  Map<String, _Entry>? _entries;

  static String _key(String type, int id) => '$type/$id';

  /// The tags kept for [type] [id], when they were fetched within [maxAge].
  Map<String, String>? lookup(String type, int id) {
    final entry = _load()[_key(type, id)];
    if (entry == null || !_fresh(entry)) return null;
    return entry.tags;
  }

  /// Keeps [tags] as the details of [type] [id], fetched now.
  Future<void> store(String type, int id, Map<String, String> tags) async {
    final entries = _load()
      ..removeWhere((_, entry) => !_fresh(entry))
      ..[_key(type, id)] = _Entry(
        _now().millisecondsSinceEpoch,
        <String, String>{
          for (final MapEntry(:key, :value) in tags.entries)
            if (OsmPlaceDetails.tagKeys.contains(key)) key: value,
        },
      );
    if (entries.length > capacity) {
      final oldest = entries.keys.toList()
        ..sort((a, b) => entries[a]!.at.compareTo(entries[b]!.at));
      oldest.take(entries.length - capacity).toList().forEach(entries.remove);
    }
    try {
      await _prefs.setString(
        _prefsKey,
        jsonEncode(<String, Object>{
          for (final MapEntry(:key, :value) in entries.entries)
            key: <String, Object>{'at': value.at, 'tags': value.tags},
        }),
      );
    } on Object {
      // Not kept on the device; the card still shows what was fetched.
    }
  }

  bool _fresh(_Entry entry) =>
      _now().millisecondsSinceEpoch - entry.at <= maxAge.inMilliseconds;

  Map<String, _Entry> _load() {
    final loaded = _entries;
    if (loaded != null) return loaded;
    final entries = <String, _Entry>{};
    try {
      final decoded = jsonDecode(_prefs.getString(_prefsKey) ?? '{}');
      if (decoded is Map) {
        for (final MapEntry(:key, :value) in decoded.entries) {
          if (value is! Map) continue;
          final at = value['at'];
          final tags = value['tags'];
          if (at is! int || tags is! Map) continue;
          entries['$key'] = _Entry(at, <String, String>{
            for (final tag in tags.entries) '${tag.key}': '${tag.value}',
          });
        }
      }
    } on FormatException {
      // A garbled store is as good as an empty one.
    }
    return _entries = entries;
  }
}

/// The tags of one place and when they were fetched (ms since the epoch).
class _Entry {
  const _Entry(this.at, this.tags);

  final int at;
  final Map<String, String> tags;
}

/// The place details kept on the device.
@Riverpod(keepAlive: true)
OsmDetailsCache osmDetailsCache(Ref ref) =>
    OsmDetailsCache(ref.watch(sharedPreferencesProvider));

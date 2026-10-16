import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/cloud_sync_bridge.dart';

/// The settings that follow the rider from device to device: how the app
/// looks, the units and how turns are announced. Their keys as the
/// controllers store them (`appearance_controller.dart`, `units.dart`,
/// `navigation_settings.dart`). Left out on purpose: whatever belongs to
/// one device — downloaded regions, permissions, paired sensors, the
/// voice installed on it, the camera, the language — and everything about
/// accounts.
const List<String> syncedSettingKeys = [
  'appearance.mode',
  'appearance.accent',
  'appearance.map',
  'appearance.overlay_dark',
  'appearance.bar',
  'appearance.column_side',
  'map.weather.radar_style',
  'units.system',
  'navigation.turns',
  'navigation.voice',
  'navigation.reroute',
  'navigation.rerouteMode',
  'navigation.leadSeconds',
];

/// The values last agreed with iCloud, as JSON; what tells a change here
/// from a change elsewhere.
const String _prefsBase = 'sync.settings.base';

/// Keeps [syncedSettingKeys] in step with the iCloud key-value store.
///
/// A setting at its default has no key, here and in iCloud alike. Per key,
/// a change in iCloud since the values last agreed wins over one here
/// (both changed: the one that reached iCloud first stays, as the store
/// itself decides); a change only here is written to iCloud.
class SettingsSync {
  /// Creates the sync over [prefs]. [onApplied] is called after values from
  /// iCloud were written, so the settings read them again.
  SettingsSync({
    required this._prefs,
    required this._bridge,
    required this._onApplied,
  });

  final SharedPreferences _prefs;
  final CloudSyncBridge _bridge;
  final void Function() _onApplied;

  /// Merges this device's settings with iCloud's.
  Future<void> start() async {
    final remote = await _bridge.readSettings(syncedSettingKeys);
    // An iCloud store with none of the values last agreed has not been
    // reached (no account, a store not loaded yet), or was emptied: never
    // taken as every setting put back to its default on another device,
    // which would reset this one's. Merged as a first start instead: what
    // is set here goes up.
    final agreed = _base();
    final base = remote.isEmpty && (agreed?.isNotEmpty ?? false)
        ? null
        : agreed;
    final push = <String, Object?>{};
    var applied = false;
    for (final key in syncedSettingKeys) {
      final r = remote[key];
      final l = _prefs.get(key);
      // Without a base this device has never synced: iCloud's value wins
      // where there is one, ours goes where there is none.
      final remoteChanged = base == null ? r != null : r != base[key];
      if (remoteChanged) {
        if (r != l) {
          await _write(key, r);
          applied = true;
        }
      } else if (l != r) {
        push[key] = l;
      }
    }
    if (push.isNotEmpty) await _bridge.writeSettings(push);
    await _saveBase();
    if (applied) _onApplied();
  }

  /// A setting may have changed here: sends whatever differs from the
  /// values last agreed.
  Future<void> localChanged() async {
    final base = _base() ?? const <String, Object?>{};
    final push = <String, Object?>{
      for (final key in syncedSettingKeys)
        if (_prefs.get(key) != base[key]) key: _prefs.get(key),
    };
    if (push.isEmpty) return;
    await _bridge.writeSettings(push);
    await _saveBase();
  }

  /// Another device changed [values].
  Future<void> remoteChanged(Map<String, Object?> values) async {
    var applied = false;
    for (final MapEntry(:key, :value) in values.entries) {
      if (!syncedSettingKeys.contains(key)) continue;
      if (_prefs.get(key) == value) continue;
      await _write(key, value);
      applied = true;
    }
    await _saveBase();
    if (applied) _onApplied();
  }

  /// Forgets the values last agreed, so the next [start] merges as a first
  /// one: what a different iCloud account needs.
  Future<void> forget() => _prefs.remove(_prefsBase);

  Map<String, Object?>? _base() {
    final json = _prefs.getString(_prefsBase);
    if (json == null) return null;
    try {
      final decoded = jsonDecode(json);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> _saveBase() => _prefs.setString(
    _prefsBase,
    jsonEncode(<String, Object?>{
      for (final key in syncedSettingKeys)
        if (_prefs.get(key) != null) key: _prefs.get(key),
    }),
  );

  Future<void> _write(String key, Object? value) async {
    switch (value) {
      case null:
        await _prefs.remove(key);
      case final bool v:
        await _prefs.setBool(key, v);
      case final int v:
        await _prefs.setInt(key, v);
      case final double v:
        await _prefs.setDouble(key, v);
      case final String v:
        await _prefs.setString(key, v);
      default:
        // A type no setting has: left alone.
        break;
    }
  }
}

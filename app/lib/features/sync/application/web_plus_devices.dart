import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable, kIsWeb, mapEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../app/app_config.dart';
import '../domain/cloud_record.dart';
import 'cloud_sync_controller.dart';
import 'plus_id_sync.dart';

final Logger _log = Logger('velorki.sync.plus');

/// Where the browser keeps the Plus records it fetched, by record name.
const String _prefsDevices = 'sync.plus.web_devices';

/// One device's Plus record ([PlusIdSync]), as the web planner read it.
@immutable
class PlusDeviceSeen {
  /// Creates the entry.
  const PlusDeviceSeen({
    required this.appUserId,
    required this.platform,
    required this.entitled,
    required this.lastSeen,
  });

  /// [record]'s entry, or null when it is no Plus record or lacks its id.
  static PlusDeviceSeen? fromRecord(CloudRecord record) {
    if (!PlusIdSync.isPlusRecord(record.name)) return null;
    return _fromFields(record.fields);
  }

  static PlusDeviceSeen? _fromFields(Map<String, Object?> fields) {
    final id = fields['appUserId'];
    final seen = fields['lastSeen'];
    if (id is! String || id.isEmpty || seen is! num) return null;
    final platform = fields['platform'];
    final entitled = fields['entitled'];
    return PlusDeviceSeen(
      appUserId: id,
      platform: platform is String ? platform : '',
      entitled: entitled == true || (entitled is num && entitled != 0),
      lastSeen: DateTime.fromMillisecondsSinceEpoch(seen.toInt()),
    );
  }

  /// The device's RevenueCat app user id.
  final String appUserId;

  /// `ios` or `android`.
  final String platform;

  /// Whether the device's store said Plus was active when it wrote.
  final bool entitled;

  /// When the device last wrote its record.
  final DateTime lastSeen;

  @override
  bool operator ==(Object other) =>
      other is PlusDeviceSeen &&
      other.appUserId == appUserId &&
      other.platform == platform &&
      other.entitled == entitled &&
      other.lastSeen == lastSeen;

  @override
  int get hashCode => Object.hash(appUserId, platform, entitled, lastSeen);

  Map<String, Object?> _toJson() => {
    'appUserId': appUserId,
    'platform': platform,
    'entitled': entitled ? 1 : 0,
    'lastSeen': lastSeen.millisecondsSinceEpoch,
  };
}

/// The device whose RevenueCat id the browser uses: of the records seen
/// within [plusRecordFreshFor] of [now], the freshest that says Plus is
/// active, else the freshest; null when none is fresh.
PlusDeviceSeen? pickPlusDevice(Iterable<PlusDeviceSeen> devices, DateTime now) {
  final fresh =
      devices
          .where((d) => now.difference(d.lastSeen) <= plusRecordFreshFor)
          .toList()
        ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
  return fresh.where((d) => d.entitled).firstOrNull ?? fresh.firstOrNull;
}

/// Whether this build keeps the other devices' Plus records: the browser,
/// which has no store of its own and uses the apps' ids. Tests override it.
final keepsPlusDevicesProvider = Provider<bool>((ref) => kIsWeb);

/// The Plus records the browser fetched from the cloud it syncs with, by
/// record name, kept in the browser so a reload needs no full fetch. The
/// browser never writes one ([plusDeviceIdentityProvider] is null there).
class WebPlusDevices extends Notifier<Map<String, PlusDeviceSeen>> {
  @override
  Map<String, PlusDeviceSeen> build() {
    final raw = ref.watch(sharedPreferencesProvider).getString(_prefsDevices);
    if (raw == null) return const {};
    Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException catch (e) {
      _log.warning('kept Plus records unreadable', e);
    }
    if (json is! Map<String, Object?>) return const {};
    return {
      for (final MapEntry(:key, :value) in json.entries)
        if (value is Map<String, Object?>)
          key: ?PlusDeviceSeen._fromFields(value),
    };
  }

  /// Takes in what a fetch brought: the Plus records among [modifications]
  /// and [deletions]; everything else passes by.
  Future<void> applyRemote(
    List<CloudRecord> modifications,
    List<String> deletions,
  ) async {
    final next = {...state};
    for (final record in modifications) {
      if (!PlusIdSync.isPlusRecord(record.name)) continue;
      final device = PlusDeviceSeen.fromRecord(record);
      if (device == null) {
        next.remove(record.name);
      } else {
        next[record.name] = device;
      }
    }
    deletions.where(PlusIdSync.isPlusRecord).forEach(next.remove);
    if (mapEquals(next, state)) return;
    await _save(next);
  }

  /// Forgets every record: signed out, another account or another service.
  Future<void> clear() async {
    if (state.isEmpty) return;
    await _save(const {});
  }

  Future<void> _save(Map<String, PlusDeviceSeen> devices) async {
    state = devices;
    final prefs = ref.read(sharedPreferencesProvider);
    if (devices.isEmpty) {
      await prefs.remove(_prefsDevices);
    } else {
      await prefs.setString(
        _prefsDevices,
        jsonEncode({
          for (final MapEntry(:key, :value) in devices.entries)
            key: value._toJson(),
        }),
      );
    }
  }
}

/// [WebPlusDevices].
final webPlusDevicesProvider =
    NotifierProvider<WebPlusDevices, Map<String, PlusDeviceSeen>>(
      WebPlusDevices.new,
    );

/// The device whose RevenueCat id this browser uses towards the relay
/// ([pickPlusDevice]), or null: none known, or not a browser.
final webPlusDeviceProvider = Provider<PlusDeviceSeen?>((ref) {
  if (!ref.watch(keepsPlusDevicesProvider)) return null;
  return pickPlusDevice(
    ref.watch(webPlusDevicesProvider).values,
    ref.watch(cloudSyncClockProvider)(),
  );
});

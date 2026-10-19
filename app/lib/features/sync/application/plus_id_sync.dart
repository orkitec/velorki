import 'dart:convert';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../data/sync_backend.dart';
import '../domain/cloud_record.dart';
import '../domain/sync_service.dart';

final Logger _log = Logger('velorki.sync.plus');

/// What starts the name of every device's Plus record: `plus_<device id>`.
/// `parseRecordName` does not know it, so the library never sees one.
const String plusRecordPrefix = 'plus_';

/// The record type of a device's Plus record (CloudKit's, and the Drive
/// file's `kind`).
const String plusRecordType = 'PlusDevice';

/// How often the record's `lastSeen` is written again while sync runs. The
/// relay ignores records older than 30 days.
const Duration plusRefreshEvery = Duration(hours: 6);

/// The store identity this device writes into its cloud, so the web
/// planner signed into the same cloud can use the Plus bought here.
class PlusDeviceIdentity {
  /// Creates the identity.
  const PlusDeviceIdentity({required this.appUserId, required this.platform});

  /// The RevenueCat app user id of this install.
  final String appUserId;

  /// `ios` or `android`.
  final String platform;
}

/// The preferences [PlusIdSync] keeps.
abstract final class _Keys {
  /// This install's device id, the record name's tail.
  static const String device = 'sync.plus.device';

  /// The service whose account this device may write its record into
  /// ([SyncService.name]), or [_held] once it may not; unset, the first
  /// account sync runs with.
  static const String target = 'sync.plus.target';

  /// The record's system fields (base64), from its last save.
  static const String systemFields = 'sync.plus.system_fields';

  /// When the record was last confirmed saved (ms); unset, it was never
  /// saved into the account it is bound to.
  static const String savedAt = 'sync.plus.saved_at';

  static const String _held = 'held';
}

/// Writes this device's own Plus record — its RevenueCat app user id, its
/// platform and when it was last seen — into the cloud it syncs with, as
/// one record of its own per device (`plus_<device id>`), so devices never
/// write over each other. Only the relay reads these records; this device
/// never reads, changes or deletes another device's.
///
/// It goes only into the account sync ran with when the record was first
/// written, or into one the rider picks in Settings → Sync with: an
/// account change, a sign-out or sync switched off forgets locally where
/// it went and stops writing, deleting nothing; the record left behind
/// ages out at the relay. Writing starts again only when the rider picks a
/// service ([chosen]).
class PlusIdSync {
  /// Creates the sync of [identity] over [backend], for [service].
  PlusIdSync({
    required this._prefs,
    required this._backend,
    required this._service,
    required this._identity,
    this._clock = DateTime.now,
  });

  final SharedPreferences _prefs;
  final SyncBackend _backend;
  final SyncService _service;
  final PlusDeviceIdentity _identity;
  final DateTime Function() _clock;

  /// The rider picked [service] in Settings: this device may write its
  /// record into that service's account from now on (off: into none).
  /// Picking the service already chosen counts too, so a rider held after
  /// an account change switches it off and on again to write there.
  static Future<void> chosen(
    SharedPreferences prefs,
    SyncService service,
  ) async {
    await _forget(prefs);
    await prefs.setString(
      _Keys.target,
      service == SyncService.off ? _Keys._held : service.name,
    );
  }

  /// This device's record name.
  String get recordName {
    var id = _prefs.getString(_Keys.device);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      // Read again before it lands: the same id, from the cache.
      _prefs.setString(_Keys.device, id).ignore();
    }
    return '$plusRecordPrefix$id';
  }

  /// Whether [name] is a Plus record (this device's or another's).
  static bool isPlusRecord(String name) => name.startsWith(plusRecordPrefix);

  /// Whether this device may write into the account sync runs with.
  bool get _allowed {
    final target = _prefs.getString(_Keys.target);
    return target == null || target == _service.name;
  }

  /// Starts: binds to this service's account when nothing was bound yet,
  /// and writes the record when it is due.
  Future<void> start() async {
    if (!_allowed) {
      _log.info('held: not written into this account');
      return;
    }
    if (_prefs.getString(_Keys.target) == null) {
      await _prefs.setString(_Keys.target, _service.name);
    }
    await refresh();
  }

  /// Writes the record again when it was not saved in the last
  /// [plusRefreshEvery].
  Future<void> refresh() async {
    if (!_allowed) return;
    final savedAt = _prefs.getInt(_Keys.savedAt);
    final now = _clock().millisecondsSinceEpoch;
    if (savedAt != null && now - savedAt < plusRefreshEvery.inMilliseconds) {
      return;
    }
    await _backend.enqueue(saves: [recordName]);
  }

  /// The record as it is to be saved, or null when it is not to be (held,
  /// or a name not this device's).
  CloudRecord? recordToSave(String name) {
    if (name != recordName || !_allowed) return null;
    final now = _clock().millisecondsSinceEpoch;
    final systemFields = _prefs.getString(_Keys.systemFields);
    return CloudRecord(
      name: name,
      type: plusRecordType,
      systemFields: systemFields == null ? null : base64Decode(systemFields),
      fields: <String, Object?>{
        'schemaVersion': 1,
        'modifiedAt': now,
        'appUserId': _identity.appUserId,
        'platform': _identity.platform,
        'lastSeen': now,
      },
    );
  }

  /// The record was saved, with [systemFields].
  Future<void> saved(String name, Uint8List systemFields) async {
    if (name != recordName) return;
    if (!_allowed) return;
    await _prefs.setString(_Keys.systemFields, base64Encode(systemFields));
    await _prefs.setInt(_Keys.savedAt, _clock().millisecondsSinceEpoch);
    _log.info('saved');
  }

  /// A save of the record was refused.
  Future<void> failed(FailedSave failure) async {
    if (failure.name != recordName) return;
    switch (failure.failure) {
      case SaveFailure.conflict:
        // Ours is the only device writing it: the server's tag is taken
        // and the record goes again over it.
        final server = failure.serverRecord?.systemFields;
        if (server == null) {
          await _prefs.remove(_Keys.systemFields);
        } else {
          await _prefs.setString(_Keys.systemFields, base64Encode(server));
        }
        if (_allowed) await _backend.enqueue(saves: [recordName]);
      case SaveFailure.unknownItem:
        await _prefs.remove(_Keys.systemFields);
        if (_allowed) await _backend.enqueue(saves: [recordName]);
      case SaveFailure.quotaExceeded:
      case SaveFailure.retrying:
      case SaveFailure.other:
        // Written again on the next start or refresh.
        break;
    }
  }

  /// The cloud account changed under the running sync. Once the record
  /// was saved into one account, it never follows into another by itself.
  Future<void> accountChanged(AccountChange change) async {
    if (_prefs.getInt(_Keys.savedAt) == null) {
      // Nothing written anywhere yet: the account there is now is the
      // first, whatever the engine calls the change.
      await _prefs.remove(_Keys.systemFields);
      if (change != AccountChange.signOut) await start();
      return;
    }
    _log.info('account ${change.name}: held');
    await _forget(_prefs);
    await _prefs.setString(_Keys.target, _Keys._held);
  }

  /// The zone was deleted; the record goes again where it may.
  Future<void> zoneDeleted() async {
    await _prefs.remove(_Keys.systemFields);
    await _prefs.remove(_Keys.savedAt);
  }

  static Future<void> _forget(SharedPreferences prefs) async {
    await prefs.remove(_Keys.systemFields);
    await prefs.remove(_Keys.savedAt);
  }
}

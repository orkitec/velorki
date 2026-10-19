import 'package:flutter/foundation.dart';

export 'cloudkit_web_none.dart'
    if (dart.library.js_interop) 'cloudkit_web_js.dart';

/// The CloudKit container the apps sync with.
const String cloudKitContainer = 'iCloud.com.orkitec.velorki';

/// The zone of the private database the library lives in, as CKSyncEngine
/// keeps it on iOS (`CloudSync.swift`).
const String cloudKitZone = 'Library';

/// The element Apple's sign-in button is drawn into.
const String cloudKitSignInButtonId = 'apple-sign-in-button';

/// A record as CloudKit Web Services hands it over.
@immutable
class CkRecord {
  /// Creates the record.
  const CkRecord({
    required this.name,
    this.type,
    this.changeTag,
    this.fields = const <String, Object?>{},
    this.bodyUrl,
    this.deleted = false,
  });

  /// The record name.
  final String name;

  /// The record type; null for a deletion.
  final String? type;

  /// The server's change tag, the version a write names.
  final String? changeTag;

  /// The fields but the body: strings and numbers.
  final Map<String, Object?> fields;

  /// Where the `body` asset is downloaded from, or null without one.
  final String? bodyUrl;

  /// Whether this is a deletion in a change feed.
  final bool deleted;
}

/// One write in a [CloudKitWeb.modify].
sealed class CkWrite {
  const CkWrite(this.name);

  /// The record name.
  final String name;
}

/// Writes a record whole: created when [changeTag] is null, else replaced
/// if the server still has it at that tag.
class CkSave extends CkWrite {
  /// Creates the save.
  const CkSave(
    super.name, {
    required this.type,
    required this.fields,
    required this.body,
    required this.changeTag,
  });

  /// The record type.
  final String type;

  /// The fields, each with its CloudKit type.
  final Map<String, CkValue> fields;

  /// The `body` asset's bytes, or null.
  final Uint8List? body;

  /// The tag the record must be at, or null for a new one.
  final String? changeTag;
}

/// Deletes a record, whatever its tag.
class CkDelete extends CkWrite {
  /// Creates the delete.
  const CkDelete(super.name);
}

/// A field value with the CloudKit type it is saved as.
@immutable
class CkValue {
  /// Creates the value.
  const CkValue(this.value, this.type);

  /// A string or a number.
  final Object value;

  /// `STRING`, `INT64` or `DOUBLE`.
  final String type;
}

/// What CloudKit said of a request or of one record in it.
@immutable
class CkError {
  /// Creates the error.
  const CkError(this.code, {this.recordName, this.reason});

  /// CloudKit's `serverErrorCode` (or CloudKit JS's own `ckErrorCode`):
  /// `CONFLICT`, `NOT_FOUND`, `AUTHENTICATION_REQUIRED`, ...
  final String code;

  /// The record it is about, for a record's error.
  final String? recordName;

  /// What CloudKit said, for the log.
  final String? reason;

  @override
  String toString() =>
      'CkError($code${recordName == null ? '' : ' $recordName'}'
      '${reason == null ? '' : ': $reason'})';
}

/// A request CloudKit refused as a whole.
class CloudKitException implements Exception {
  /// Creates the failure.
  const CloudKitException(this.error);

  /// Why.
  final CkError error;

  @override
  String toString() => 'CloudKitException($error)';
}

/// What became of one record of a [CloudKitWeb.modify] or a
/// [CloudKitWeb.lookup]: the record as the server has it now, or an error.
@immutable
class CkResult {
  /// Creates the result.
  const CkResult({this.record, this.error});

  /// The record, for a write or a lookup that went through.
  final CkRecord? record;

  /// The error, for one that did not.
  final CkError? error;
}

/// A page of a zone's changes.
@immutable
class CkZoneChanges {
  /// Creates the page.
  const CkZoneChanges({
    required this.records,
    required this.syncToken,
    required this.moreComing,
  });

  /// The records changed, deletions among them.
  final List<CkRecord> records;

  /// Where the next page starts.
  final String syncToken;

  /// Whether another page follows at once.
  final bool moreComing;
}

/// What the web planner needs of CloudKit JS: Apple's sign-in, and the
/// private database's [cloudKitZone]. `cloudkit_web_js.dart` binds it to
/// Apple's library in a browser; tests use a fake. Every data call throws
/// [CloudKitException].
abstract interface class CloudKitWeb {
  /// The signed-in rider's user record name (stable per Apple Account and
  /// container), or null while no one is signed in. Asks CloudKit the first
  /// time; Apple's library then knows.
  Future<String?> userRecordName();

  /// The user record name each time someone signs in, and null each time
  /// they sign out.
  Stream<String?> get users;

  /// Draws Apple's sign-in button into the element [cloudKitSignInButtonId]
  /// while no one is signed in; call once the element is on the page.
  Future<void> showSignIn();

  /// Signs out in this browser; nothing in iCloud changes.
  Future<void> signOut();

  /// The web auth token of the session, or null while signed out.
  String? get sessionToken;

  /// Swaps in the token CloudKit handed out for the session elsewhere (the
  /// relay used it and got a new one).
  set sessionToken(String? token);

  /// Applies [writes] in the zone, one result per write in their order.
  Future<List<CkResult>> modify(List<CkWrite> writes);

  /// The records [names] in the zone, one result per name in their order.
  Future<List<CkResult>> lookup(List<String> names);

  /// The zone's changes since [syncToken], everything there is from null.
  Future<CkZoneChanges> zoneChanges(String? syncToken);

  /// Makes the zone, for an account whose apps never synced yet.
  Future<void> createZone();

  /// The bytes of an asset at [url].
  Future<Uint8List> download(String url);
}

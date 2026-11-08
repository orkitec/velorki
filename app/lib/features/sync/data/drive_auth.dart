import 'cloud_store.dart';

/// Where a `DriveCloudStore` gets the signed-in account and its tokens.
///
/// In its own file, and free of `googleapis`, so the account side of Google
/// sync compiles in a build that has no Drive store at all (the F-Droid
/// flavour: no `google_sign_in`, no `googleapis`).
abstract interface class DriveAuth {
  /// The signed-in Google account's id, or null.
  String? get accountId;

  /// An access token for `drive.appdata`, without asking the rider.
  /// [stale] is one Drive refused: it is let go of and another fetched.
  /// Null when only the rider can grant one (signed out, access taken
  /// back): the account is then gone until they sign in again. Throws
  /// [CloudStoreException] when it cannot be told now (no network).
  Future<String?> accessToken({String? stale});
}

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'brouter_storage.g.dart';

/// Where the on-device routing engine finds its files.
///
/// Everything lives under `<appSupport>/brouter/`, which is the plan's
/// location: not the documents directory, so the tiles stay out of the file
/// pickers and out of iCloud Drive. Marking the segments directory
/// `NSURLIsExcludedFromBackupKey` on iOS still has to happen in `ios/Runner`
/// (see `docs/OPEN_ITEMS.md`); a 250 MB tile has no business in a backup.
@immutable
class BrouterStorage {
  /// Creates the layout under [root].
  const BrouterStorage(this.root);

  /// `<appSupport>/brouter`.
  final Directory root;

  /// The `.rd5` segment tiles.
  Directory get segments => Directory(p.join(root.path, 'segments'));

  /// The `.brf` profiles and `lookups.dat`, copied out of the app bundle.
  Directory get profiles => Directory(p.join(root.path, 'profiles'));

  /// Creates both directories if they are not there yet.
  Future<BrouterStorage> create() async {
    await segments.create(recursive: true);
    await profiles.create(recursive: true);
    return this;
  }

  @override
  bool operator ==(Object other) =>
      other is BrouterStorage && other.root.path == root.path;

  @override
  int get hashCode => root.path.hashCode;

  @override
  String toString() => 'BrouterStorage(${root.path})';
}

/// The app's [BrouterStorage], with both directories created.
///
/// Tests override this with a temporary directory; nothing else in the
/// feature calls `path_provider`.
@Riverpod(keepAlive: true)
Future<BrouterStorage> brouterStorage(Ref ref) async {
  final base = await getApplicationSupportDirectory();
  return BrouterStorage(Directory(p.join(base.path, 'brouter'))).create();
}

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/files/backup_exclusion.dart';

part 'brouter_storage.g.dart';

/// Where the on-device routing engine finds its files.
///
/// Everything lives under `<appSupport>/brouter/`, which is the plan's
/// location: not the documents directory, so the tiles stay out of the file
/// pickers and out of iCloud Drive. [create] additionally marks the whole
/// tree `NSURLIsExcludedFromBackupKey` on iOS through [BackupExclusion], so
/// none of it reaches an iCloud or iTunes backup; a 250 MB tile has no
/// business in one, and everything here can be downloaded again.
@immutable
class BrouterStorage {
  /// Creates the layout under [root]; [backup] is injected in tests.
  const BrouterStorage(this.root, {BackupExclusion? backup})
    : _backup = backup ?? const BackupExclusion();

  /// `<appSupport>/brouter`.
  final Directory root;

  final BackupExclusion _backup;

  /// The `.rd5` segment tiles.
  Directory get segments => Directory(p.join(root.path, 'segments'));

  /// The `.brf` profiles and `lookups.dat`, copied out of the app bundle.
  Directory get profiles => Directory(p.join(root.path, 'profiles'));

  /// The `<TILE>.gaz` offline gazetteers, one per downloaded tile.
  Directory get gazetteer => Directory(p.join(root.path, 'gazetteer'));

  /// Creates the three directories if they are not there yet and asks the
  /// platform to keep [root] out of the backup. A refused exclusion is logged
  /// and ignored: it must not stop the app from routing.
  Future<BrouterStorage> create() async {
    await segments.create(recursive: true);
    await profiles.create(recursive: true);
    await gazetteer.create(recursive: true);
    await _backup.exclude(root);
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

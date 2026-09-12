// Port of btools.router.RoutingHelper (BRouter v1.7.10).
//
// static helper class for handling datafiles
//
// `StorageConfigHelper` (the Android app's storageconfig.txt) is not ported,
// so there is no additional maptool directory and no secondary segment
// directory: the two getters return null and `hasDirectoryAnyDatafiles` only
// looks at the directory itself.

import 'dart:io';

final class RoutingHelper {
  RoutingHelper._();

  static Directory? getAdditionalMaptoolDir(Directory segmentDir) => null;

  static Directory? getSecondarySegmentDir(Directory segmentDir) => null;

  static bool hasDirectoryAnyDatafiles(Directory segmentDir) {
    if (_hasAnyDatafiles(segmentDir)) {
      return true;
    }
    // check secondary, too
    final secondary = getSecondarySegmentDir(segmentDir);
    if (secondary != null) {
      return _hasAnyDatafiles(secondary);
    }
    return false;
  }

  static bool _hasAnyDatafiles(Directory dir) {
    for (final f in dir.listSync()) {
      if (f.path.endsWith('.rd5')) return true;
    }
    return false;
  }
}

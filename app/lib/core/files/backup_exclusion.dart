import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The channel `ios/Runner/AppDelegate.swift` answers on.
const String backupChannelName = 'app.velorki/backup';

/// Method that sets `NSURLIsExcludedFromBackupKey` on a directory. Its
/// argument is the directory path, its result whether the flag is now set.
const String excludeFromBackupMethod = 'excludeFromBackup';

/// Keeps re-downloadable directories out of the iOS backup.
///
/// Apple's data storage guidelines say that files the app can fetch again —
/// the routing tiles, the gazetteers, the profiles — must not go into iCloud
/// or an iTunes backup, so the directory holding them is flagged
/// `NSURLIsExcludedFromBackupKey`. Everywhere else (Android, tests) this is a
/// no-op that reports success: nothing there backs the files up.
@immutable
class BackupExclusion {
  /// Creates the exclusion; [channel] is the platform channel by default and
  /// is injected in tests.
  const BackupExclusion({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(backupChannelName);

  final MethodChannel _channel;

  /// Marks [dir] as excluded from the iOS backup.
  ///
  /// Returns true when the flag is set (and on every non-iOS platform, where
  /// there is nothing to do), false when the platform refused. Failures are
  /// logged and never thrown: nothing the app does depends on the flag.
  Future<bool> exclude(Directory dir) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return true;
    try {
      final excluded = await _channel.invokeMethod<bool>(
        excludeFromBackupMethod,
        dir.path,
      );
      return excluded ?? false;
    } on MissingPluginException {
      // An app delegate without the channel (an older build), or a test.
      return true;
    } on PlatformException catch (e) {
      debugPrint('BackupExclusion: cannot exclude ${dir.path}: $e');
      return false;
    }
  }
}

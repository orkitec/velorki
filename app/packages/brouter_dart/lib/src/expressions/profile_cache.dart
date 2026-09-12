// Port of btools.router.ProfileCache (BRouter v1.7.10).
//
// Container for routig configs
//
// Upstream lives in brouter-core and takes a RoutingContext; the fields it
// touches are behind [ProfileCacheClient] here so that the expressions module
// carries the cache and RoutingContext (track R4) implements the interface.

import 'dart:io';

import 'b_expression_context_node.dart';
import 'b_expression_context_way.dart';
import 'b_expression_meta_data.dart';

/// The part of `RoutingContext` that `ProfileCache` reads and writes.
abstract class ProfileCacheClient {
  /// `rc.localFunction`: the profile path (`profileBaseDir` unset) or name.
  String get localFunction;

  /// `rc.profileTimestamp`.
  set profileTimestamp(int value);
  int get profileTimestamp;

  /// `rc.getKeyValueChecksum()`.
  int getKeyValueChecksum();

  /// `rc.keyValues` (injected `assign`s, may be null).
  Map<String, String>? get keyValues;

  /// `rc.memoryclass`.
  int get memoryclass;

  /// `rc.processUnusedTags`.
  bool get processUnusedTags;

  BExpressionContextWay? expctxWay;
  BExpressionContextNode? expctxNode;

  /// `rc.readGlobalConfig()`.
  void readGlobalConfig();
}

final class ProfileCache {
  static File? _lastLookupFile;
  static int _lastLookupTimestamp = 0;

  BExpressionContextWay? _expctxWay;
  BExpressionContextNode? _expctxNode;
  File? _lastProfileFile;
  int _lastProfileTimestamp = 0;
  bool _profilesBusy = false;
  int _lastUseTime = 0;

  static List<ProfileCache?> _apc = List<ProfileCache?>.filled(1, null);

  /// `Boolean.getBoolean("debugProfileCache")`.
  static bool debug = false;

  /// `System.getProperty("profileBaseDir")`.
  static String? profileBaseDir;

  /// The lines upstream prints (`******** invalidating ...`, `******* adding
  /// new profile ...`) since the last call, for diagnostics.
  static final List<String> log = <String>[];

  static void setSize(int size) {
    _apc = List<ProfileCache?>.filled(size, null);
  }

  static int _lastModified(File f) {
    try {
      return f.lastModifiedSync().millisecondsSinceEpoch;
    } on FileSystemException {
      return 0; // File.lastModified() of a missing file
    }
  }

  static bool parseProfile(ProfileCacheClient rc) {
    final baseDir = profileBaseDir;
    Directory profileDir;
    File profileFile;
    if (baseDir == null) {
      profileFile = File(rc.localFunction);
      profileDir = profileFile.parent;
    } else {
      profileDir = Directory(baseDir);
      profileFile = File('${profileDir.path}/${rc.localFunction}.brf');
    }

    // upstream: lastModified() + checksum << 24 parses as (lastModified() + checksum) << 24
    rc.profileTimestamp =
        (_lastModified(profileFile) + rc.getKeyValueChecksum()) << 24;
    final lookupFile = File('${profileDir.path}/lookups.dat');

    // invalidate cache at lookup-table update
    if (!(_lastLookupFile != null &&
        lookupFile.path == _lastLookupFile!.path &&
        _lastModified(lookupFile) == _lastLookupTimestamp)) {
      if (_lastLookupFile != null) {
        log.add(
          '******** invalidating profile-cache after lookup-file update ******** ',
        );
      }
      _apc = List<ProfileCache?>.filled(_apc.length, null);
      _lastLookupFile = lookupFile;
      _lastLookupTimestamp = _lastModified(lookupFile);
    }

    ProfileCache? lru;
    var unusedSlot = -1;

    // check for re-use
    for (var i = 0; i < _apc.length; i++) {
      final pc = _apc[i];

      if (pc != null) {
        if (!pc._profilesBusy &&
            pc._lastProfileFile != null &&
            profileFile.path == pc._lastProfileFile!.path) {
          if (rc.profileTimestamp == pc._lastProfileTimestamp) {
            rc.expctxWay = pc._expctxWay;
            rc.expctxNode = pc._expctxNode;
            rc.readGlobalConfig();
            pc._profilesBusy = true;
            return true;
          }
          lru = pc; // name-match but timestamp-mismatch -> we overide this one
          unusedSlot = -1;
          break;
        }
        if (lru == null || lru._lastUseTime > pc._lastUseTime) {
          lru = pc;
        }
      } else if (unusedSlot < 0) {
        unusedSlot = i;
      }
    }

    final meta = BExpressionMetaData();

    final expctxWay = BExpressionContextWay(meta, rc.memoryclass * 512);
    final expctxNode = BExpressionContextNode(meta, 0);
    rc.expctxWay = expctxWay;
    rc.expctxNode = expctxNode;
    expctxNode.setForeignContext(expctxWay);

    meta.readMetaData(File('${profileDir.path}/lookups.dat'));

    expctxWay.parseFile(profileFile, 'global', rc.keyValues);
    expctxNode.parseFile(profileFile, 'global', rc.keyValues);

    rc.readGlobalConfig();

    if (rc.processUnusedTags) {
      expctxWay.setAllTagsUsed();
    }

    if (lru == null || unusedSlot >= 0) {
      lru = ProfileCache();
      if (unusedSlot >= 0) {
        _apc[unusedSlot] = lru;
        if (debug) {
          log.add(
            '******* adding new profile at idx=$unusedSlot for ${profileFile.path}',
          );
        }
      }
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    if (lru._lastProfileFile != null) {
      if (debug) {
        log.add(
          '******* replacing profile of age ${(now - lru._lastUseTime) ~/ 1000} sec ${lru._lastProfileFile!.path}->${profileFile.path}',
        );
      }
    }

    lru._lastProfileTimestamp = rc.profileTimestamp;
    lru._lastProfileFile = profileFile;
    lru._expctxWay = expctxWay;
    lru._expctxNode = expctxNode;
    lru._profilesBusy = true;
    lru._lastUseTime = now;
    return false;
  }

  static void releaseProfile(ProfileCacheClient rc) {
    for (var i = 0; i < _apc.length; i++) {
      final pc = _apc[i];

      if (pc != null) {
        // only the thread that holds the cached instance can release it
        if (identical(rc.expctxWay, pc._expctxWay) &&
            identical(rc.expctxNode, pc._expctxNode)) {
          pc._profilesBusy = false;
          break;
        }
      }
    }
    rc.expctxWay = null;
    rc.expctxNode = null;
  }
}

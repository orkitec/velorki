import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'brouter_storage.dart';

part 'brouter_assets.g.dart';

/// Copies the bundled BRouter profiles out of the app package.
///
/// The on-device engine reads `.brf` profiles and `lookups.dat` as files, so
/// the assets pinned to the same upstream release as the server image have to
/// be written to disk once. The copy is repeated when the bundled
/// `UPSTREAM_VERSION` differs from the marker left behind by the last copy,
/// which is what makes an app update replace the profiles.
class BrouterAssets {
  /// Creates an installer writing into [profilesDir].
  BrouterAssets({required this.bundle, required this.profilesDir});

  /// The bundled version of the profiles, e.g. `v1.7.10`.
  static const String versionAsset = 'assets/brouter/UPSTREAM_VERSION';

  /// Every asset under this prefix is copied.
  static const String profilesPrefix = 'assets/brouter/profiles/';

  /// Records which version was copied; sits next to the profiles.
  static const String markerFile = '.upstream_version';

  /// Where the assets are read from; `rootBundle` in the app.
  final AssetBundle bundle;

  /// Where they are written to; `<appSupport>/brouter/profiles`.
  final Directory profilesDir;

  /// Copies the profiles when they are missing or out of date and returns the
  /// directory they are in.
  ///
  /// Cheap on every later launch: the version string, the marker, and the
  /// sizes of the bundled profiles against the copies.
  Future<Directory> install() async {
    final version = await bundledVersion();
    if (await _isInstalled(version)) return profilesDir;

    await profilesDir.create(recursive: true);
    final assets = await profileAssets();
    for (final asset in assets) {
      final data = await bundle.load(asset);
      final file = File(p.join(profilesDir.path, p.basename(asset)));
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    await _marker.writeAsString(version, flush: true);
    return profilesDir;
  }

  /// The version string shipped in the bundle.
  Future<String> bundledVersion() async =>
      (await bundle.loadString(versionAsset)).trim();

  /// The version string of the copy on disk, or `null` when there is none.
  Future<String?> installedVersion() async {
    if (!_marker.existsSync()) return null;
    return (await _marker.readAsString()).trim();
  }

  /// The asset keys of the bundled profiles, from the asset manifest, so a
  /// profile added to `assets/brouter/profiles/` needs no code change.
  Future<List<String>> profileAssets() async {
    final manifest = await AssetManifest.loadFromAssetBundle(bundle);
    final assets =
        manifest
            .listAssets()
            .where((key) => key.startsWith(profilesPrefix))
            .toList()
          ..sort();
    return assets;
  }

  File get _marker => File(p.join(profilesDir.path, markerFile));

  Future<bool> _isInstalled(String version) async {
    if (await installedVersion() != version) return false;
    // A half-written copy (killed mid-install, or a file removed by a
    // cleaner) must not pass as installed.
    // So must a profile the bundle has since changed without upstream
    // moving: Velorki's own variants sit beside upstream's and change on
    // their own schedule. The size is the check; reading the bundle's
    // copies costs a couple of hundred kilobytes, once per launch.
    for (final asset in await profileAssets()) {
      final file = File(p.join(profilesDir.path, p.basename(asset)));
      if (!file.existsSync()) return false;
      final bundled = await bundle.load(asset);
      if (file.lengthSync() != bundled.lengthInBytes) return false;
    }
    return true;
  }
}

/// The profiles directory, with the bundled profiles copied into it.
///
/// Started in `bootstrap()` so the copy is done before the first route; the
/// routing backend waits for it rather than routing without profiles.
@Riverpod(keepAlive: true)
Future<Directory> brouterProfiles(Ref ref) async {
  final storage = await ref.watch(brouterStorageProvider.future);
  return BrouterAssets(
    bundle: rootBundle,
    profilesDir: storage.profiles,
  ).install();
}

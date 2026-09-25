import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/routing_tiles/data/brouter_assets.dart';

import 'support/fake_segments.dart';

/// `rootBundle` with a counter, to show that a second install reads no
/// profile assets at all.
class CountingBundle extends AssetBundle {
  /// Keys that were loaded, in order.
  final List<String> loaded = <String>[];

  @override
  Future<ByteData> load(String key) {
    loaded.add(key);
    return rootBundle.load(key);
  }

  /// The profile assets among [loaded].
  List<String> get profileLoads => <String>[
    for (final key in loaded)
      if (key.startsWith(BrouterAssets.profilesPrefix)) key,
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory profilesDir;
  late CountingBundle bundle;
  late BrouterAssets assets;

  setUp(() {
    profilesDir = Directory('${tempDir('velorki-assets').path}/profiles');
    bundle = CountingBundle();
    assets = BrouterAssets(bundle: bundle, profilesDir: profilesDir);
  });

  test('copies every bundled profile and the lookup table', () async {
    await assets.install();

    final names =
        profilesDir
            .listSync()
            .map((e) => e.uri.pathSegments.last)
            .where((name) => !name.startsWith('.'))
            .toList()
          ..sort();
    expect(names, contains('trekking.brf'));
    expect(names, contains('gravel.brf'));
    expect(names, contains('lookups.dat'));
    expect(
      File('${profilesDir.path}/trekking.brf').lengthSync(),
      greaterThan(1000),
    );
    expect(await assets.installedVersion(), await assets.bundledVersion());
    expect(await assets.bundledVersion(), startsWith('v'));
  });

  test('copies nothing on the next launch', () async {
    await assets.install();
    final trekking = File('${profilesDir.path}/trekking.brf');
    final stamp = DateTime.utc(2020);
    trekking.setLastModifiedSync(stamp);

    await assets.install();

    expect(trekking.lastModifiedSync().toUtc(), stamp);
  });

  test(
    'copies again when a bundled profile changed, the version not',
    () async {
      await assets.install();
      File('${profilesDir.path}/trekking.brf').writeAsStringSync('stale');

      await assets.install();

      expect(
        File('${profilesDir.path}/trekking.brf').lengthSync(),
        greaterThan(1000),
      );
    },
  );

  test('copies again when the bundled version moved on', () async {
    await assets.install();
    File('${profilesDir.path}/${BrouterAssets.markerFile}')
        .writeAsStringSync('v1.0.0');
    File('${profilesDir.path}/trekking.brf').writeAsStringSync('stale');

    await assets.install();

    expect(
      File('${profilesDir.path}/trekking.brf').lengthSync(),
      greaterThan(1000),
    );
    expect(await assets.installedVersion(), await assets.bundledVersion());
  });

  test('repairs a copy a file went missing from', () async {
    await assets.install();
    File('${profilesDir.path}/lookups.dat').deleteSync();

    await assets.install();

    expect(File('${profilesDir.path}/lookups.dat').existsSync(), isTrue);
  });
}

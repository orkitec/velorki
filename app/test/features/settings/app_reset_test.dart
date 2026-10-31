import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:velorki/features/settings/application/app_reset.dart';

void main() {
  late Directory root;
  late List<String> calls;

  setUp(() {
    root = Directory.systemTemp.createTempSync('app_reset_test');
    calls = <String>[];
  });
  tearDown(() => root.deleteSync(recursive: true));

  AppReset reset({List<Directory>? dirs, bool failMaps = false}) => AppReset(
    clearPreferences: () async => calls.add('prefs'),
    deleteOfflineMaps: () async {
      calls.add('maps');
      if (failMaps) throw StateError('no maplibre');
    },
    closeDatabase: () async => calls.add('close'),
    clearSecureStorage: () async => calls.add('secure'),
    directories: () async => dirs ?? <Directory>[],
    endApp: () => calls.add('end'),
  );

  test('clears every store, then ends the app', () async {
    await reset().run();
    expect(calls, ['maps', 'close', 'prefs', 'secure', 'end']);
  });

  test('empties the directories but keeps them', () async {
    final docs = Directory(p.join(root.path, 'docs'))..createSync();
    File(p.join(docs.path, 'velorki.sqlite')).writeAsStringSync('db');
    final brouter = Directory(p.join(docs.path, 'brouter', 'segments'))
      ..createSync(recursive: true);
    File(p.join(brouter.path, 'E0_N0.rd5')).writeAsStringSync('tile');
    final cache = Directory(p.join(root.path, 'cache'))..createSync();
    File(p.join(cache.path, 'clouds')).writeAsStringSync('x');
    final missing = Directory(p.join(root.path, 'missing'));

    // The documents directory twice, as on Android where it is the support
    // directory too.
    await reset(dirs: [docs, cache, docs, missing]).run();

    expect(docs.existsSync(), isTrue);
    expect(docs.listSync(), isEmpty);
    expect(cache.listSync(), isEmpty);
    expect(missing.existsSync(), isFalse);
    expect(calls.last, 'end');
  });

  test('a failing step does not stop the others', () async {
    await reset(failMaps: true).run();
    expect(calls, ['maps', 'close', 'prefs', 'secure', 'end']);
  });
}

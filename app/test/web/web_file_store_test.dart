@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/web/web_file_store.dart';
import 'package:velorki/core/files/app_directories.dart';
import 'package:velorki_io/io.dart';
import 'package:velorki_io/memory_fs.dart';
import 'package:web/web.dart' as web;

/// The browser's half of the file story, in a real browser
/// (`flutter test --platform chrome test/web/`): `package:velorki_io` is the
/// in-memory file system there, and [WebFileStore] keeps the finished tiles
/// and indexes in Cache Storage across visits.
void main() {
  setUp(() async {
    MemoryFileSystem.reset();
    MemoryFileSystem.onChange = null;
    await web.window.caches.delete('velorki-files-v1').toDart;
  });

  test('io.dart is the in-memory file system in a browser', () async {
    final support = await appSupportDirectory();
    expect(support.path, '/support');
    File('${support.path}/x.txt').writeAsStringSync('hello');
    expect(MemoryFileSystem.filesUnder('/support'), ['/support/x.txt']);
  });

  test('finished tiles and indexes outlive the page, parts do not', () async {
    await WebFileStore.open();
    Directory('/support/brouter/segments').createSync(recursive: true);
    Directory('/support/brouter/gazetteer').createSync(recursive: true);
    final rd5 = Uint8List.fromList(List<int>.generate(1000, (i) => i % 251));
    File('/support/brouter/segments/W20_N30.rd5').writeAsBytesSync(rd5);
    File('/support/brouter/gazetteer/W20_N30.gaz').writeAsStringSync('gaz');
    File('/support/brouter/segments/E5_N45.rd5.part').writeAsStringSync('half');
    File('/support/brouter/profiles/trekking.brf')
      ..createSync(recursive: true)
      ..writeAsStringSync('profile');
    // The cache writes are fire-and-forget; give them their turn.
    await Future<void>.delayed(const Duration(milliseconds: 300));

    // A new visit: memory is empty, the store puts back what it kept.
    MemoryFileSystem.reset();
    MemoryFileSystem.onChange = null;
    await WebFileStore.open();

    expect(
      File('/support/brouter/segments/W20_N30.rd5').readAsBytesSync(),
      rd5,
    );
    expect(
      File('/support/brouter/gazetteer/W20_N30.gaz').readAsStringSync(),
      'gaz',
    );
    expect(
      File('/support/brouter/segments/E5_N45.rd5.part').existsSync(),
      isFalse,
    );
    expect(
      File('/support/brouter/profiles/trekking.brf').existsSync(),
      isFalse,
    );

    // A deleted tile is gone on the next visit too.
    File('/support/brouter/segments/W20_N30.rd5').deleteSync();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    MemoryFileSystem.reset();
    MemoryFileSystem.onChange = null;
    await WebFileStore.open();
    expect(File('/support/brouter/segments/W20_N30.rd5').existsSync(), isFalse);
  });
}

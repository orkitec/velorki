import 'dart:typed_data';

import 'package:test/test.dart';
// The browser's implementation, tested on the VM where io.dart is dart:io.
import 'package:velorki_io/src/memory_io.dart';

void main() {
  setUp(MemoryFileSystem.reset);

  test('files are written, read, renamed and deleted', () async {
    await Directory('/app/brouter/segments').create(recursive: true);
    final part = File('/app/brouter/segments/W20_N30.rd5.part');
    final sink = part.openWrite();
    sink.add(<int>[1, 2, 3]);
    sink.add(<int>[4]);
    await sink.flush();
    await sink.close();
    expect(await part.length(), 4);

    final rd5 = await part.rename('/app/brouter/segments/W20_N30.rd5');
    expect(part.existsSync(), isFalse);
    expect(rd5.readAsBytesSync(), <int>[1, 2, 3, 4]);

    final appended = rd5.openWrite(mode: FileMode.append)..add(<int>[5]);
    await appended.close();
    expect(rd5.lengthSync(), 5);

    await rd5.delete();
    expect(rd5.existsSync(), isFalse);
    expect(() => rd5.lengthSync(), throwsA(isA<FileSystemException>()));
  });

  test('a file needs its directory', () {
    expect(
      () => File('/nowhere/x').writeAsStringSync('x'),
      throwsA(isA<FileSystemException>()),
    );
    File('/nowhere/x').createSync(recursive: true);
    expect(Directory('/nowhere').existsSync(), isTrue);
  });

  test('random access reads at a position like dart:io', () {
    Directory('/d').createSync();
    final f = File('/d/f')..writeAsBytesSync(List<int>.generate(10, (i) => i));
    final raf = f.openSync();
    raf.setPositionSync(7);
    final buffer = Uint8List(5);
    expect(raf.readIntoSync(buffer, 0, 5), 3);
    expect(buffer.sublist(0, 3), <int>[7, 8, 9]);
    expect(raf.readIntoSync(buffer, 0, 5), 0);
    expect(raf.lengthSync(), 10);
    raf.closeSync();
  });

  test('listing returns direct children, or all with recursive', () {
    File('/r/a/x.gaz').createSync(recursive: true);
    File('/r/y.gaz').createSync(recursive: true);
    final names = Directory('/r').listSync().map((e) => e.path).toList();
    expect(names, <String>['/r/a', '/r/y.gaz']);
    expect(Directory('/r').listSync()[0], isA<Directory>());
    final all = Directory('/r')
        .listSync(recursive: true)
        .whereType<File>()
        .map((e) => e.path);
    expect(all, <String>['/r/a/x.gaz', '/r/y.gaz']);
    expect(
      () => Directory('/r').deleteSync(),
      throwsA(isA<FileSystemException>()),
    );
    Directory('/r').deleteSync(recursive: true);
    expect(Directory('/r').existsSync(), isFalse);
    expect(File('/r/y.gaz').existsSync(), isFalse);
  });

  test('changes reach onChange and seeds do not', () {
    final seen = <String, int?>{};
    MemoryFileSystem.onChange = (path, bytes) => seen[path] = bytes?.length;
    addTearDown(() => MemoryFileSystem.onChange = null);
    MemoryFileSystem.seed('/s/kept', Uint8List(3));
    expect(File('/s/kept').lengthSync(), 3);
    File('/s/new').writeAsStringSync('ab');
    File('/s/kept').deleteSync();
    expect(seen, <String, int?>{'/s/new': 2, '/s/kept': null});
    expect(MemoryFileSystem.filesUnder('/s').toList(), <String>['/s/new']);
  });
}

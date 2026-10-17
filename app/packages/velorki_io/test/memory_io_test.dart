import 'dart:async';
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

  test('files written in parts go into the buffers newBytes makes', () async {
    final made = <int>[];
    final changes = <String>[];
    MemoryFileSystem.newBytes = (length) {
      made.add(length);
      return Uint8List(length);
    };
    MemoryFileSystem.onChange = (path, _) => changes.add(path);
    addTearDown(() {
      MemoryFileSystem.newBytes = Uint8List.new;
      MemoryFileSystem.onChange = null;
    });
    await Directory('/t').create();
    final file = File('/t/a');
    final sink = file.openWrite()..add(Uint8List.fromList(<int>[1, 2]));
    await sink.flush();
    await sink.close();
    expect(file.readAsBytesSync(), <int>[1, 2]);
    // The empty file when opened, then the flush; the close finds it there.
    expect(made, <int>[0, 2]);
    expect(changes, <String>['/t/a', '/t/a']);

    made.clear();
    file.writeAsBytesSync(<int>[3], mode: FileMode.append);
    file.writeAsBytesSync(<int>[4]);
    expect(made, <int>[3]);
    expect(file.readAsBytesSync(), <int>[4]);
  });

  test(
    'openRead hands out copies, in chunks, and lets the loop turn',
    () async {
      final bytes = Uint8List(64 * 1024 * 40 + 7);
      for (var i = 0; i < bytes.length; i++) {
        bytes[i] = i & 0xff;
      }
      MemoryFileSystem.seed('/t/big', bytes);
      var timerRan = false;
      Timer.run(() => timerRan = true);
      var seen = 0;
      var turnedBeforeEnd = false;
      await for (final chunk in File('/t/big').openRead()) {
        expect(chunk[0], seen & 0xff);
        seen += chunk.length;
        if (timerRan && seen < bytes.length) turnedBeforeEnd = true;
      }
      expect(seen, bytes.length);
      expect(turnedBeforeEnd, isTrue);
    },
  );

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

  test('a file keeps when it was last read apart from when it was written', () {
    final f = File('/a/f')..createSync(recursive: true);
    final written = f.statSync().modified;
    final read = written.add(const Duration(minutes: 5));
    f.setLastAccessedSync(read);
    expect(f.statSync().accessed, read);
    expect(f.statSync().modified, written);
  });

  test('zlib round-trips, and its output is what zlib reads', () {
    final data = Uint8List.fromList(List<int>.generate(4096, (i) => i % 7));
    final packed = const ZLibCodec(level: 6).encode(data);
    expect(packed.length, lessThan(data.length));
    // A zlib stream: deflate, 32 KB window, header checksum a multiple of 31.
    expect(packed[0], 0x78);
    expect((packed[0] << 8 | packed[1]) % 31, 0);
    expect(zlib.decode(packed), data);
  });
}

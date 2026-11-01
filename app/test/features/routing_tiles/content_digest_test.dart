import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:velorki/features/routing_tiles/data/content_digest.dart';

import 'support/fake_segments.dart';

// The values `tools/gazetteer/digest.py` and the mirror's manifest give for
// the committed fixtures: the Dart digests must come out the same.
const String _tiles = '../tools/brouter-oracle/tiles';
const String _gazetteers = '../tools/gazetteer/fixtures';

const Map<String, String> _rd5 = <String, String>{
  'W20_N30': 'd278c33d1e67abeaf418e946b5d7bbb79fc6df711ead4d04e1c4e9b6d967c09c',
  'W25_N60': '818711b97bc59af7e39009e50084c66cd1c20a548d7e552553dd76894e7aaa0c',
};
const Map<String, String> _gaz = <String, String>{
  'E5_N45': '77d62adfdcf821cad6d3b3d34e868d36a4e24cd8c3786295ba108f0b967d67f3',
  'W20_N30': 'e17f98de90b4b3f47702ec9f8eccc0cde06ef90c18c2e473a4beeb5fd58961e0',
};

/// Where the rd5's creation time sits, read as the digest reads it.
int _creationTimeAt(Uint8List bytes) {
  var offset = 0;
  for (var i = 194; i < 200; i++) {
    offset = offset * 256 + bytes[i];
  }
  return offset;
}

void main() {
  late Directory dir;

  setUp(() => dir = tempDir('velorki-digest'));

  group('the rd5 digest', () {
    for (final entry in _rd5.entries) {
      test('${entry.key} matches the mirror\'s', () async {
        final path = '$_tiles/${entry.key}.rd5';

        expect(await rd5DigestOfFile(File(path)), entry.value);
        // Through the isolate the app uses.
        expect(await rd5ContentDigest(path), entry.value);
      });
    }

    test('ignores the creation time and nothing else', () async {
      final source = File('$_tiles/W20_N30.rd5').readAsBytesSync();
      final at = _creationTimeAt(source);
      expect(at, greaterThan(200), reason: 'a real slot, inside the file');

      final stamped = Uint8List.fromList(source);
      for (var i = 0; i < 8; i++) {
        stamped[at + i] = 0x5a;
      }
      final changed = Uint8List.fromList(source)..[source.length - 1] ^= 1;
      File('${dir.path}/stamped.rd5').writeAsBytesSync(stamped);
      File('${dir.path}/changed.rd5').writeAsBytesSync(changed);

      expect(
        await rd5DigestOfFile(File('${dir.path}/stamped.rd5')),
        _rd5['W20_N30'],
      );
      expect(
        await rd5DigestOfFile(File('${dir.path}/changed.rd5')),
        isNot(_rd5['W20_N30']),
      );
    });

    test('a file too short to have a header is hashed as it is', () async {
      File('${dir.path}/tiny.rd5').writeAsStringSync('abc');

      expect(
        await rd5DigestOfFile(File('${dir.path}/tiny.rd5')),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });
  });

  group('the gazetteer digest', () {
    for (final entry in _gaz.entries) {
      test('${entry.key} matches the mirror\'s', () async {
        final path = '$_gazetteers/${entry.key}.gaz';

        expect(gazetteerDigestSync(path), entry.value);
        expect(await gazetteerContentDigest(path), entry.value);
      });
    }

    String copy() {
      final path = '${dir.path}/E5_N45.gaz';
      File('$_gazetteers/E5_N45.gaz').copySync(path);
      return path;
    }

    test('does not see when the file was built', () {
      final path = copy();
      sqlite3.open(path)
        ..execute("UPDATE meta SET value = 'later' WHERE key = 'built_at'")
        ..close();

      expect(gazetteerDigestSync(path), _gaz['E5_N45']);
    });

    test('sees a changed row', () {
      final path = copy();
      sqlite3.open(path)
        ..execute("UPDATE places SET name = 'Elsewhere' WHERE id = 1")
        ..close();

      expect(gazetteerDigestSync(path), isNot(_gaz['E5_N45']));
    });
  });
}

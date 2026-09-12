import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/routing_tiles/domain/sha256.dart';

import 'support/fake_segments.dart';

void main() {
  test('matches the FIPS 180-4 vectors', () {
    expect(
      sha256OfString(''),
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    );
    expect(
      sha256OfString('abc'),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    expect(
      sha256OfString(
        'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq',
      ),
      '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
    );
  });

  test('is independent of how the data is chunked', () {
    final text = List<String>.generate(500, (i) => 'chunk $i;').join();
    final whole = Sha256()..add(utf8.encode(text));
    final pieces = Sha256();
    for (var i = 0; i < text.length; i += 7) {
      pieces.add(utf8.encode(text.substring(i, (i + 7).clamp(0, text.length))));
    }
    expect(pieces.hexDigest(), whole.hexDigest());
  });

  test('hexDigest can be read twice and refuses more data', () {
    final digest = Sha256()..add(<int>[1, 2, 3]);
    final first = digest.hexDigest();
    expect(digest.hexDigest(), first);
    expect(() => digest.add(<int>[4]), throwsStateError);
  });

  test('hashes a file in chunks', () async {
    final dir = tempDir('velorki-sha256');
    final file = File('${dir.path}/blob.bin')
      ..writeAsBytesSync(utf8.encode('abc'));
    expect(
      await sha256OfFile(file),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });
}

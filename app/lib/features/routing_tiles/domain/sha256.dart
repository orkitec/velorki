import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Streaming SHA-256, enough to verify a downloaded rd5 tile.
///
/// Hand-written because `crypto` is only a transitive dependency here and the
/// app deliberately adds no package for eighty lines of FIPS 180-4. The test
/// checks it against the standard vectors.
class Sha256 {
  /// Starts an empty digest.
  Sha256();

  final Uint32List _h = Uint32List.fromList(<int>[
    0x6a09e667,
    0xbb67ae85,
    0x3c6ef372,
    0xa54ff53a,
    0x510e527f,
    0x9b05688c,
    0x1f83d9ab,
    0x5be0cd19,
  ]);
  final Uint8List _block = Uint8List(64);
  final Uint32List _w = Uint32List(64);
  int _blockLength = 0;
  int _totalLength = 0;
  String? _digest;

  /// Feeds [data] into the digest.
  void add(List<int> data) {
    if (_digest != null) throw StateError('Sha256 is already closed');
    _totalLength += data.length;
    var offset = 0;
    while (offset < data.length) {
      final take = (64 - _blockLength) < (data.length - offset)
          ? 64 - _blockLength
          : data.length - offset;
      _block.setRange(_blockLength, _blockLength + take, data, offset);
      _blockLength += take;
      offset += take;
      if (_blockLength == 64) {
        _compress(_block);
        _blockLength = 0;
      }
    }
  }

  /// Finishes the digest and returns it as lower-case hexadecimal.
  ///
  /// Idempotent: the padded state is computed once and the same string comes
  /// back on every later call. [add] after this throws.
  String hexDigest() {
    final done = _digest;
    if (done != null) return done;

    final bitLength = _totalLength * 8;
    final padding = <int>[0x80];
    final remainder = (_blockLength + 1) % 64;
    padding.addAll(
      List<int>.filled(remainder <= 56 ? 56 - remainder : 120 - remainder, 0),
    );
    final lengthBytes = Uint8List(8);
    ByteData.view(lengthBytes.buffer).setUint64(0, bitLength);
    padding.addAll(lengthBytes);
    add(padding);

    final out = StringBuffer();
    for (final word in _h) {
      out.write(word.toRadixString(16).padLeft(8, '0'));
    }
    return _digest = out.toString();
  }

  void _compress(Uint8List block) {
    final w = _w;
    for (var i = 0; i < 16; i++) {
      final j = i * 4;
      w[i] =
          (block[j] << 24) |
          (block[j + 1] << 16) |
          (block[j + 2] << 8) |
          block[j + 3];
    }
    for (var i = 16; i < 64; i++) {
      final s0 = _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final s1 = _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
    }

    var a = _h[0];
    var b = _h[1];
    var c = _h[2];
    var d = _h[3];
    var e = _h[4];
    var f = _h[5];
    var g = _h[6];
    var h = _h[7];

    for (var i = 0; i < 64; i++) {
      final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final ch = (e & f) ^ (~e & 0xffffffff & g);
      final temp1 = (h + s1 + ch + _k[i] + w[i]) & 0xffffffff;
      final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final temp2 = (s0 + maj) & 0xffffffff;
      h = g;
      g = f;
      f = e;
      e = (d + temp1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) & 0xffffffff;
    }

    _h[0] = (_h[0] + a) & 0xffffffff;
    _h[1] = (_h[1] + b) & 0xffffffff;
    _h[2] = (_h[2] + c) & 0xffffffff;
    _h[3] = (_h[3] + d) & 0xffffffff;
    _h[4] = (_h[4] + e) & 0xffffffff;
    _h[5] = (_h[5] + f) & 0xffffffff;
    _h[6] = (_h[6] + g) & 0xffffffff;
    _h[7] = (_h[7] + h) & 0xffffffff;
  }

  static int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xffffffff;

  static const List<int> _k = <int>[
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
  ];
}

/// The SHA-256 of [text], as lower-case hexadecimal.
String sha256OfString(String text) =>
    (Sha256()..add(utf8.encode(text))).hexDigest();

/// The SHA-256 of [file], read in chunks so a 250 MB tile never sits in
/// memory as a whole.
Future<String> sha256OfFile(File file) async {
  final digest = Sha256();
  await for (final chunk in file.openRead()) {
    digest.add(chunk);
  }
  return digest.hexDigest();
}

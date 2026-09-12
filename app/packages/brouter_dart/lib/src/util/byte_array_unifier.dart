// Port of btools.util.ByteArrayUnifier (BRouter v1.7.10).

import 'dart:typed_data';

import '../jvm.dart';
import 'crc32.dart';
import 'i_byte_array_unifier.dart';

class ByteArrayUnifier implements IByteArrayUnifier {
  ByteArrayUnifier(this._size, bool validateImmutability)
    : _byteArrayCache = List<Uint8List?>.filled(_size, null),
      _crcCrosscheck = validateImmutability ? Int32List(_size) : null;

  final List<Uint8List?> _byteArrayCache;
  final Int32List? _crcCrosscheck;
  final int _size;

  /// Unify a byte array in order to reuse instances when possible.
  /// The byte arrays are assumed to be treated as immutable,
  /// allowing the reuse
  ///
  /// Returns the cached instance or the input instanced if not cached
  Uint8List unifyAll(Uint8List ab) {
    return unify(ab, 0, ab.length);
  }

  @override
  Uint8List unify(Uint8List ab, int offset, int len) {
    final crc = Crc32.crc(ab, offset, len);
    final idx = rem(crc & 0xfffffff, _size);
    final abc = _byteArrayCache[idx];
    if (abc != null && abc.length == len) {
      var i = 0;
      while (i < len) {
        if (ab[offset + i] != abc[i]) break;
        i++;
      }
      if (i == len) return abc;
    }
    final crosscheck = _crcCrosscheck;
    if (crosscheck != null) {
      final abold = _byteArrayCache[idx];
      if (abold != null) {
        final crcold = Crc32.crc(abold, 0, abold.length);
        if (crcold != crosscheck[idx]) {
          throw ArgumentError(
            'ByteArrayUnifier: immutablity validation failed!',
          );
        }
      }
      crosscheck[idx] = crc;
    }
    final nab = Uint8List(len);
    nab.setRange(0, len, ab, offset);
    _byteArrayCache[idx] = nab;
    return nab;
  }
}

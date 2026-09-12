// Port of btools.codec.StatCoderContext (BRouter v1.7.10).

import 'dart:typed_data';

import '../jvm.dart';
import '../util/bit_coder_context.dart';

class StatCoderContext extends BitCoderContext {
  StatCoderContext(super.ab);

  static Map<String, Int64List>? _statsPerName;
  int _lastbitpos = 0;

  static final Int32List _noisyBits = _buildNoisyBits();

  static Int32List _buildNoisyBits() {
    // noisybits lookup
    final t = Int32List(1024);
    for (var i = 0; i < 1024; i++) {
      var p = i;
      var noisybits = 0;
      while (p > 2) {
        noisybits++;
        p >>= 1;
      }
      t[i] = noisybits;
    }
    return t;
  }

  /// assign the de-/encoded bits since the last call assignBits to the given
  /// name. Used for encoding statistics
  void assignBits(String name) {
    final bitpos = getWritingBitPosition();
    final stats = (_statsPerName ??= <String, Int64List>{}).putIfAbsent(
      name,
      () => Int64List(2),
    );
    stats[0] += bitpos - _lastbitpos;
    stats[1] += 1;
    _lastbitpos = bitpos;
  }

  /// Get a textual report on the bit-statistics (sorted by name, like the
  /// `TreeMap` upstream)
  static String getBitReport() {
    final stats = _statsPerName;
    if (stats == null) {
      return '<empty bit report>';
    }
    final sb = StringBuffer();
    final names = stats.keys.toList()..sort();
    for (final name in names) {
      final s = stats[name]!;
      sb.write('$name count=${s[1]} bits=${s[0]}\n');
    }
    _statsPerName = null;
    return sb.toString();
  }

  /// encode an unsigned integer with some of of least significant bits
  /// considered noisy
  void encodeNoisyNumber(int value, int noisybits) {
    if (value < 0) {
      throw ArgumentError('encodeVarBits expects positive value');
    }
    if (noisybits > 0) {
      final mask = ushr32(-1, 32 - noisybits);
      encodeBounded(mask, value & mask);
      value = shr32(value, noisybits);
    }
    encodeVarBits(value);
  }

  /// decode an unsigned integer with some of of least significant bits
  /// considered noisy
  int decodeNoisyNumber(int noisybits) {
    final value = decodeBits(noisybits);
    return value | shl32(decodeVarBits(), noisybits);
  }

  /// encode a signed integer with some of of least significant bits considered
  /// noisy
  void encodeNoisyDiff(int value, int noisybits) {
    if (noisybits > 0) {
      value = i32(value + shl32(1, noisybits - 1));
      final mask = ushr32(-1, 32 - noisybits);
      encodeBounded(mask, value & mask);
      value = shr32(value, noisybits);
    }
    encodeVarBits(value < 0 ? i32(-value) : value);
    if (value != 0) {
      encodeBit(value < 0);
    }
  }

  /// decode a signed integer with some of of least significant bits considered
  /// noisy
  int decodeNoisyDiff(int noisybits) {
    var value = 0;
    if (noisybits > 0) {
      value = i32(decodeBits(noisybits) - shl32(1, noisybits - 1));
    }
    var val2 = shl32(decodeVarBits(), noisybits);
    if (val2 != 0) {
      if (decodeBit()) {
        val2 = i32(-val2);
      }
    }
    return i32(value + val2);
  }

  /// encode a signed integer with the typical range and median taken from the
  /// predicted value
  void encodePredictedValue(int value, int predictor) {
    var p = predictor < 0 ? i32(-predictor) : predictor;
    var noisybits = 0;

    while (p > 2) {
      noisybits++;
      p >>= 1;
    }
    encodeNoisyDiff(i32(value - predictor), noisybits);
  }

  /// decode a signed integer with the typical range and median taken from the
  /// predicted value
  int decodePredictedValue(int predictor) {
    var p = predictor < 0 ? i32(-predictor) : predictor;
    var noisybits = 0;
    while (p > 1023) {
      noisybits++;
      p >>= 1;
    }
    return i32(predictor + decodeNoisyDiff(noisybits + _noisyBits[p]));
  }

  /// encode an integer-array making use of the fact that it is sorted. This is
  /// done, starting with the most significant bit, by recursively encoding the
  /// number of values with the current bit being 0. This yields an number of
  /// bits per value that only depends on the typical distance between subsequent
  /// values and also benefits
  ///
  /// [nextbit] is a bitmask with the most significant bit set to 1, [mask]
  /// should be 0
  void encodeSortedArray(
    Int32List values,
    int offset,
    int subsize,
    int nextbit,
    int mask,
  ) {
    if (subsize == 1) {
      // last-choice shortcut
      while (nextbit != 0) {
        encodeBit((values[offset] & nextbit) != 0);
        nextbit = shr32(nextbit, 1);
      }
    }
    if (nextbit == 0) {
      return;
    }

    final data = mask & values[offset];
    mask |= nextbit;

    // count 0-bit-fraction
    var i = offset;
    final end = subsize + offset;
    for (; i < end; i++) {
      if ((values[i] & mask) != data) {
        break;
      }
    }
    final size1 = i - offset;
    final size2 = subsize - size1;

    encodeBounded(subsize, size1);
    if (size1 > 0) {
      encodeSortedArray(values, offset, size1, shr32(nextbit, 1), mask);
    }
    if (size2 > 0) {
      encodeSortedArray(values, i, size2, shr32(nextbit, 1), mask);
    }
  }

  /// [nextbitpos] is the bit position to decode next, [value] should be 0
  void decodeSortedArray(
    Int32List values,
    int offset,
    int subsize,
    int nextbitpos,
    int value,
  ) {
    if (subsize == 1) {
      // last-choice shortcut
      if (nextbitpos >= 0) {
        value |= decodeBitsReverse(nextbitpos + 1);
      }
      values[offset] = value;
      return;
    }
    if (nextbitpos < 0) {
      while (subsize-- > 0) {
        values[offset++] = value;
      }
      return;
    }

    final size1 = decodeBounded(subsize);
    final size2 = subsize - size1;

    if (size1 > 0) {
      decodeSortedArray(values, offset, size1, nextbitpos - 1, value);
    }
    if (size2 > 0) {
      decodeSortedArray(
        values,
        offset + size1,
        size2,
        nextbitpos - 1,
        value | shl32(1, nextbitpos),
      );
    }
  }
}

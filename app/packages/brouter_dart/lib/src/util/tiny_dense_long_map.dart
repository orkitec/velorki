// Port of btools.util.TinyDenseLongMap (BRouter v1.7.10).

import 'dart:typed_data';

import '../jvm.dart';
import 'dense_long_map.dart';

/// TinyDenseLongMap implements the DenseLongMap interface
/// but actually is made for a medium count of non-dense keys
///
/// It's used as a replacement for DenseLongMap where we
/// have limited memory and far less keys than maykey
class TinyDenseLongMap extends DenseLongMap {
  TinyDenseLongMap() : super() {
    // pointer array
    _pa = Int32List(maxLists);

    // allocate key lists
    _al = List<Int64List?>.filled(maxLists, null);
    _al[0] = Int64List(1); // make the first array (the transient buffer)

    // same for the values
    _vla = List<Int8List?>.filled(maxLists, null);
    _vla[0] = Int8List(1);
  }

  late List<Int64List?> _al;
  late Int32List _pa;
  int _size = 0;
  final int _maxKeepExponent =
      14; // the maximum exponent to keep the invalid arrays

  static const int maxLists = 31; // enough for size Integer.MAX_VALUE

  late List<Int8List?> _vla; // value list array

  void _fillReturnValue(Int8List rv, int idx, int p) {
    rv[0] = _vla[idx]![p];
    if (rv.length == 2) {
      _vla[idx]![p] = rv[1];
    }
  }

  @override
  void put(int key, int value) {
    final rv = Int8List(2);
    rv[1] = toByte(value);
    if (_contains(key, rv)) {
      return;
    }

    _vla[0]![0] = toByte(value);
    _add(key);
  }

  /// Get the byte for the given id (signed, as the JVM version returns the
  /// `byte` widened to `int`), or -1 if unknown.
  @override
  int getInt(int key) {
    final rv = Int8List(1);
    if (_contains(key, rv)) {
      return rv[0];
    }
    return -1;
  }

  bool _add(int id) {
    if (_size == intMaxValue) {
      throw ArgumentError('cannot grow beyond size Integer.MAX_VALUE');
    }

    // put the new entry in the first array
    _al[0]![0] = id;

    // determine the first empty array
    var bp = _size++; // treat size as bitpattern
    var idx = 1;
    var n = 1;

    _pa[0] = 1;
    _pa[1] = 1;

    while ((bp & 1) == 1) {
      bp >>= 1;
      _pa[idx++] = n;
      n <<= 1;
    }

    // create it if not existant
    if (_al[idx] == null) {
      _al[idx] = Int64List(n);
      _vla[idx] = Int8List(n);
    }
    final alIdx = _al[idx]!;
    final vlaIdx = _vla[idx]!;

    // now merge the contents of arrays 0...idx-1 into idx
    while (n > 0) {
      var maxId = 0;
      var maxIdx = -1;

      for (var i = 0; i < idx; i++) {
        final p = _pa[i];
        if (p > 0) {
          final currentId = _al[i]![p - 1];
          if (maxIdx < 0 || currentId > maxId) {
            maxIdx = i;
            maxId = currentId;
          }
        }
      }

      // current maximum found, copy to target array
      if (n < alIdx.length && maxId == alIdx[n]) {
        throw ArgumentError('duplicate key found in late check: $maxId');
      }
      --n;
      alIdx[n] = maxId;
      vlaIdx[n] = _vla[maxIdx]![_pa[maxIdx] - 1];

      --_pa[maxIdx];
    }

    // de-allocate empty arrays of a certain size (fix at 64kByte)
    while (idx-- > _maxKeepExponent) {
      _al[idx] = null;
      _vla[idx] = null;
    }

    return false;
  }

  bool _contains(int id, Int8List? rv) {
    // determine the first empty array
    var bp = _size; // treat size as bitpattern
    var idx = 1;

    while (bp != 0) {
      if ((bp & 1) == 1) {
        // array at idx is valid, check
        if (_containsIn(idx, id, rv)) {
          return true;
        }
      }
      idx++;
      bp >>= 1;
    }
    return false;
  }

  // does sorted array "a" contain "id" ?
  bool _containsIn(int idx, int id, Int8List? rv) {
    final a = _al[idx]!;
    var offset = a.length;
    var n = 0;

    while ((offset >>= 1) > 0) {
      final nn = n + offset;
      if (a[nn] <= id) {
        n = nn;
      }
    }
    if (a[n] == id) {
      if (rv != null) {
        _fillReturnValue(rv, idx, n);
      }
      return true;
    }
    return false;
  }
}

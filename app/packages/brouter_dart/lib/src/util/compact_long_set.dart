// Port of btools.util.CompactLongSet (BRouter v1.7.10).

import 'dart:typed_data';

import '../jvm.dart';

/// Memory efficient Set for long-keys
class CompactLongSet {
  CompactLongSet() {
    // pointer array
    _pa = Int32List(maxLists);

    // allocate key lists
    _al = List<Int64List?>.filled(maxLists, null);
    _al[0] = Int64List(1); // make the first array (the transient buffer)
  }

  late List<Int64List?> _al;
  late Int32List _pa;
  int _size = 0;
  final int _maxKeepExponent =
      14; // the maximum exponent to keep the invalid arrays

  static const int maxLists = 31; // enough for size Integer.MAX_VALUE

  /// Returns the number of entries in this set
  int size() {
    return _size;
  }

  /// add a long value to this set if not yet in.
  ///
  /// Returns true if "id" already contained in this set.
  bool add(int id) {
    if (contains(id)) {
      return true;
    }
    _add(id);
    return false;
  }

  void fastAdd(int id) {
    _add(id);
  }

  void _add(int id) {
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
    }
    final alIdx = _al[idx]!;

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

      --_pa[maxIdx];
    }

    // de-allocate empty arrays of a certain size (fix at 64kByte)
    while (idx-- > _maxKeepExponent) {
      _al[idx] = null;
    }
  }

  /// Returns true if "id" is contained in this set.
  bool contains(int id) {
    // determine the first empty array
    var bp = _size; // treat size as bitpattern
    var idx = 1;

    while (bp != 0) {
      if ((bp & 1) == 1) {
        // array at idx is valid, check
        if (_containsIn(idx, id)) {
          return true;
        }
      }
      idx++;
      bp >>= 1;
    }
    return false;
  }

  // does sorted array "a" contain "id" ?
  bool _containsIn(int idx, int id) {
    final a = _al[idx]!;
    var offset = a.length;
    var n = 0;

    while ((offset >>= 1) > 0) {
      final nn = n + offset;
      if (a[nn] <= id) {
        n = nn;
      }
    }
    return a[n] == id;
  }

  /// `protected void moveToFrozenArray(long[] faid)`.
  void moveToFrozenArray(Int64List faid) {
    for (var i = 1; i < maxLists; i++) {
      _pa[i] = 0;
    }

    for (var ti = 0; ti < _size; ti++) {
      // target-index
      var bp = _size; // treat size as bitpattern
      var minIdx = -1;
      var minId = 0;
      var idx = 1;
      while (bp != 0) {
        if ((bp & 1) == 1) {
          final p = _pa[idx];
          if (p < _al[idx]!.length) {
            final currentId = _al[idx]![p];
            if (minIdx < 0 || currentId < minId) {
              minIdx = idx;
              minId = currentId;
            }
          }
        }
        idx++;
        bp >>= 1;
      }
      faid[ti] = minId;
      _pa[minIdx]++;

      if (ti > 0 && faid[ti - 1] == minId) {
        throw ArgumentError('duplicate key found in late check: $minId');
      }
    }

    // free the non-frozen array
    _al = List<Int64List?>.filled(0, null);
  }
}

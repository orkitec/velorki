// Port of btools.util.CompactLongMap (BRouter v1.7.10).

import 'dart:typed_data';

import '../jvm.dart';

/// Memory efficient Map to map a long-key to an object-value
///
/// Implementation is such that basically the 12 bytes
/// per entry is allocated that's needed to store
/// a long- and an object-value.
/// This class does not implement the Map interface
/// because it's not complete (remove() is not implemented,
/// CompactLongMap can only grow.)
///
/// Note that this map does not behave exactly like java.util.Map
/// - put(..) with already existing key throws exception
/// - get(..) with non-existing key thros exception
class CompactLongMap<V> {
  CompactLongMap() {
    // pointer array
    _pa = Int32List(maxLists);

    // allocate key lists
    _al = List<Int64List?>.filled(maxLists, null);
    _al[0] = Int64List(1); // make the first array (the transient buffer)

    // same for the values
    _vla = List<List<V?>?>.filled(maxLists, null);
    _vla[0] = List<V?>.filled(1, null);
  }

  late List<Int64List?> _al;
  late Int32List _pa;
  int _size = 0;
  final int _maxKeepExponent =
      14; // the maximum exponent to keep the invalid arrays

  /// `protected V value_in`.
  V? valueIn;

  /// `protected V value_out`.
  V? valueOut;

  static const int maxLists = 31; // enough for size Integer.MAX_VALUE

  /// `-DearlyDuplicateCheck=true` of the JVM version.
  static bool earlyDuplicateCheck = false;

  late List<List<V?>?> _vla; // value list array

  bool put(int id, V value) {
    try {
      valueIn = value;
      if (containsPut(id, true)) {
        return true;
      }
      _vla[0]![0] = value;
      _add(id);
      return false;
    } finally {
      valueIn = null;
      valueOut = null;
    }
  }

  /// Same as put( id, value ) but duplicate check
  /// is skipped for performance. Be aware that you
  /// can get a duplicate exception later on if the
  /// map is restructured!
  /// with System parameter earlyDuplicateCheck=true you
  /// can enforce the early duplicate check for debugging
  void fastPut(int id, V value) {
    if (earlyDuplicateCheck && contains(id)) {
      throw ArgumentError('duplicate key found in early check: $id');
    }
    _vla[0]![0] = value;
    _add(id);
  }

  /// Get the value for the given id
  ///
  /// Returns the object, or null if id not known
  V? get(int id) {
    try {
      if (containsPut(id, false)) {
        return valueOut;
      }
      return null;
    } finally {
      valueOut = null;
    }
  }

  /// Returns the number of entries in this map
  int size() {
    return _size;
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
      _vla[idx] = List<V?>.filled(n, null);
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

  /// Returns true if "id" is contained in this set.
  bool contains(int id) {
    try {
      return containsPut(id, false);
    } finally {
      valueOut = null;
    }
  }

  /// `protected boolean contains(long id, boolean doPut)`.
  bool containsPut(int id, bool doPut) {
    // determine the first empty array
    var bp = _size; // treat size as bitpattern
    var idx = 1;

    while (bp != 0) {
      if ((bp & 1) == 1) {
        // array at idx is valid, check
        if (_containsIn(idx, id, doPut)) {
          return true;
        }
      }
      idx++;
      bp >>= 1;
    }
    return false;
  }

  // does sorted array "a" contain "id" ?
  bool _containsIn(int idx, int id, bool doPut) {
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
      valueOut = _vla[idx]![n];
      if (doPut) _vla[idx]![n] = valueIn;
      return true;
    }
    return false;
  }

  /// `protected void moveToFrozenArrays(long[] faid, List<V> flv)`.
  void moveToFrozenArrays(Int64List faid, List<V> flv) {
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
      flv.add(_vla[minIdx]![_pa[minIdx]] as V);
      _pa[minIdx]++;

      if (ti > 0 && faid[ti - 1] == minId) {
        throw ArgumentError('duplicate key found in late check: $minId');
      }
    }

    // free the non-frozen arrays
    _al = List<Int64List?>.filled(0, null);
    _vla = List<List<V?>?>.filled(0, null);
  }
}

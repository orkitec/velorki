// Port of btools.util.FrozenLongMap (BRouter v1.7.10).

import 'dart:typed_data';

import 'compact_long_map.dart';

/// Frozen instance of Memory efficient Map
///
/// This one is readily sorted into a singe array for faster access
class FrozenLongMap<V> extends CompactLongMap<V> {
  FrozenLongMap(CompactLongMap<V> map) {
    _size = map.size();

    _faid = Int64List(_size);
    _flv = <V>[];

    map.moveToFrozenArrays(_faid, _flv);

    _p2size = 0x40000000;
    while (_p2size > _size) {
      _p2size >>= 1;
    }
  }

  late Int64List _faid;
  late List<V> _flv;
  int _size = 0;
  late int _p2size; // next power of 2 of size

  @override
  bool put(int id, V value) {
    try {
      valueIn = value;
      if (containsPut(id, true)) {
        return true;
      }
      throw StateError('cannot only put on existing key in FrozenLongIntMap');
    } finally {
      valueIn = null;
      valueOut = null;
    }
  }

  @override
  void fastPut(int id, V value) {
    throw StateError('cannot put on FrozenLongIntMap');
  }

  /// Returns the number of entries in this set
  @override
  int size() {
    return _size;
  }

  /// Returns true if "id" is contained in this set.
  @override
  bool containsPut(int id, bool doPut) {
    if (_size == 0) {
      return false;
    }
    final a = _faid;
    var offset = _p2size;
    var n = 0;

    while (offset > 0) {
      final nn = n + offset;
      if (nn < _size && a[nn] <= id) {
        n = nn;
      }
      offset >>= 1;
    }
    if (a[n] == id) {
      valueOut = _flv[n];
      if (doPut) {
        _flv[n] = valueIn as V;
      }
      return true;
    }
    return false;
  }

  /// Returns the value for "id", or null if key unknown
  @override
  V? get(int id) {
    if (_size == 0) {
      return null;
    }
    final a = _faid;
    var offset = _p2size;
    var n = 0;

    while (offset > 0) {
      final nn = n + offset;
      if (nn < _size && a[nn] <= id) {
        n = nn;
      }
      offset >>= 1;
    }
    if (a[n] == id) {
      return _flv[n];
    }
    return null;
  }

  List<V> getValueList() {
    return _flv;
  }

  Int64List getKeyArray() {
    return _faid;
  }
}

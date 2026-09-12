// Port of btools.util.FrozenLongSet (BRouter v1.7.10).

import 'dart:typed_data';

import 'compact_long_set.dart';

/// Frozen instance of Memory efficient Set
///
/// This one is readily sorted into a singe array for faster access
class FrozenLongSet extends CompactLongSet {
  FrozenLongSet(CompactLongSet set) {
    _size = set.size();

    _faid = Int64List(_size);

    set.moveToFrozenArray(_faid);

    _p2size = 0x40000000;
    while (_p2size > _size) {
      _p2size >>= 1;
    }
  }

  late Int64List _faid;
  int _size = 0;
  late int _p2size; // next power of 2 of size

  @override
  bool add(int id) {
    throw StateError('cannot add on FrozenLongSet');
  }

  @override
  void fastAdd(int id) {
    throw StateError('cannot add on FrozenLongSet');
  }

  /// Returns the number of entries in this set
  @override
  int size() {
    return _size;
  }

  /// Returns true if "id" is contained in this set.
  @override
  bool contains(int id) {
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
    return a[n] == id;
  }
}

// Port of btools.util.LongList (BRouter v1.7.10).

import 'dart:typed_data';

/// dynamic list of primitive longs
class LongList {
  LongList(int capacity) : _a = Int64List(capacity < 4 ? 4 : capacity);

  Int64List _a;
  int _size = 0;

  void add(int value) {
    if (_size == _a.length) {
      final aa = Int64List(2 * _size);
      aa.setRange(0, _size, _a);
      _a = aa;
    }
    _a[_size++] = value;
  }

  int get(int idx) {
    if (idx >= _size) {
      throw RangeError('list size=$_size idx=$idx');
    }
    return _a[idx];
  }

  int size() {
    return _size;
  }
}

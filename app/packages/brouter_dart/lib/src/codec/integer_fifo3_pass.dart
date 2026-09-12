// Port of btools.codec.IntegerFifo3Pass (BRouter v1.7.10).

import 'dart:typed_data';

/// Special integer fifo suitable for 3-pass encoding
class IntegerFifo3Pass {
  IntegerFifo3Pass(int capacity) : _a = Int32List(capacity < 4 ? 4 : capacity);

  Int32List _a;
  int _size = 0;
  int _pos = 0;

  int _pass = 0;

  /// Starts a new encoding pass and resets the reading pointer
  /// from the stats collected in pass2 and writes that to the given context
  void init() {
    _pass++;
    _pos = 0;
  }

  /// writes to the fifo in pass2
  void add(int value) {
    if (_pass == 2) {
      if (_size == _a.length) {
        final aa = Int32List(2 * _size);
        aa.setRange(0, _size, _a);
        _a = aa;
      }
      _a[_size++] = value;
    }
  }

  /// reads from the fifo in pass3 (in pass1/2 returns just 1)
  int getNext() {
    return _pass == 3 ? _get(_pos++) : 1;
  }

  int _get(int idx) {
    if (idx >= _size) {
      throw RangeError('list size=$_size idx=$idx');
    }
    return _a[idx];
  }
}

// Port of btools.util.SortedHeap (BRouter v1.7.10).

import 'dart:typed_data';

/// Memory efficient and lightning fast heap to get the lowest-key value of a
/// set of key-object pairs
class SortedHeap<V> {
  SortedHeap() {
    clear();
  }

  int _size = 0;
  int _peaksize = 0;
  late _SortedBin<V> _first;
  late _SortedBin<V> _second;
  _SortedBin<V>? _firstNonEmpty;

  /// Returns the lowest key value, or null if none
  V? popLowestKeyValue() {
    final bin = _firstNonEmpty;
    if (bin == null) {
      return null;
    }
    _size--;
    final minBin = bin.getMinBin();
    return minBin.dropLowest();
  }

  /// add a key value pair to the heap
  void add(int key, V value) {
    _size++;

    if (_first.lp == 0 && _second.lp == 0) {
      // both full ?
      _sortUp();
    }
    if (_first.lp > 0) {
      _first.add4(key, value);
      if (_firstNonEmpty != _first) {
        _first.nextNonEmpty = _firstNonEmpty;
        _firstNonEmpty = _first;
      }
    } else {
      // second bin not full
      _second.add4(key, value);
      if (_first.nextNonEmpty != _second) {
        _second.nextNonEmpty = _first.nextNonEmpty;
        _first.nextNonEmpty = _second;
      }
    }
  }

  void _sortUp() {
    if (_size > _peaksize) {
      _peaksize = _size;
    }

    // determine the first array big enough to take them all
    var cnt = 8; // value count of first 2 bins is always 8
    var tbin = _second; // target bin
    var lastNonEmpty = _second;
    do {
      tbin = tbin.next();
      final nentries = tbin.binsize - tbin.lp;
      if (nentries > 0) {
        cnt += nentries;
        lastNonEmpty = tbin;
      }
    } while (cnt > tbin.binsize);

    final alT = tbin.al;
    final vlaT = tbin.vla;
    var tp = tbin.binsize - cnt; // target pointer

    // unlink any higher, non-empty arrays
    final otherNonEmpty = lastNonEmpty.nextNonEmpty;
    lastNonEmpty.nextNonEmpty = null;

    // now merge the content of these non-empty bins into the target bin
    while (_firstNonEmpty != null) {
      // copy current minimum to target array
      final minBin = _firstNonEmpty!.getMinBin();
      alT[tp] = minBin.lv;
      vlaT[tp++] = minBin.dropLowest();
    }

    tp = tbin.binsize - cnt;
    tbin.lp = tp; // new target low pointer
    tbin.lv = tbin.al[tp];
    tbin.nextNonEmpty = otherNonEmpty;
    _firstNonEmpty = tbin;
  }

  void clear() {
    _size = 0;
    _first = _SortedBin<V>(4, this);
    _second = _SortedBin<V>(4, this);
    _firstNonEmpty = null;
  }

  int getSize() {
    return _size;
  }

  int getPeakSize() {
    return _peaksize;
  }

  int getExtract(List<V?> targetArray) {
    final tsize = targetArray.length;
    final div = _size ~/ tsize + 1;
    var tp = 0;

    var lpi = 0;
    var bin = _firstNonEmpty;
    while (bin != null) {
      lpi += bin.lp;
      final vlai = bin.vla;
      final n = bin.binsize;
      while (lpi < n) {
        targetArray[tp++] = vlai[lpi];
        lpi += div;
      }
      lpi -= n;
      bin = bin.nextNonEmpty;
    }
    return tp;
  }
}

class _SortedBin<V> {
  _SortedBin(this.binsize, this.parent)
    : al = Int32List(binsize),
      vla = List<V?>.filled(binsize, null),
      lp = binsize;

  final SortedHeap<V> parent;
  _SortedBin<V>? _next;
  _SortedBin<V>? nextNonEmpty;
  final int binsize;
  final Int32List al; // key array
  final List<V?> vla; // value array
  int lv = 0; // low value
  int lp; // low pointer

  _SortedBin<V> next() {
    return _next ??= _SortedBin<V>(binsize << 1, parent);
  }

  V? dropLowest() {
    final lpOld = lp;
    if (++lp == binsize) {
      unlink();
    } else {
      lv = al[lp];
    }
    final res = vla[lpOld];
    vla[lpOld] = null;
    return res;
  }

  void unlink() {
    var neBin = parent._firstNonEmpty!;
    if (neBin == this) {
      parent._firstNonEmpty = nextNonEmpty;
      return;
    }
    for (;;) {
      final next = neBin.nextNonEmpty!;
      if (next == this) {
        neBin.nextNonEmpty = nextNonEmpty;
        return;
      }
      neBin = next;
    }
  }

  void add(int key, V? value) {
    var p = lp;
    for (;;) {
      if (p == binsize || key < al[p]) {
        al[p - 1] = key;
        vla[p - 1] = value;
        lv = al[--lp];
        return;
      }
      al[p - 1] = al[p];
      vla[p - 1] = vla[p];
      p++;
    }
  }

  // unrolled version of above for binsize = 4
  void add4(int key, V? value) {
    var p = lp--;
    if (p == 4 || key < al[p]) {
      lv = al[p - 1] = key;
      vla[p - 1] = value;
      return;
    }
    lv = al[p - 1] = al[p];
    vla[p - 1] = vla[p];
    p++;

    if (p == 4 || key < al[p]) {
      al[p - 1] = key;
      vla[p - 1] = value;
      return;
    }
    al[p - 1] = al[p];
    vla[p - 1] = vla[p];
    p++;

    if (p == 4 || key < al[p]) {
      al[p - 1] = key;
      vla[p - 1] = value;
      return;
    }
    al[p - 1] = al[p];
    vla[p - 1] = vla[p];

    al[p] = key;
    vla[p] = value;
  }

  /// The JVM version unrolls this loop for 32 bins; a heap can never have more
  /// than 31 bins (bin sizes double, 2^33 entries), so the loop is equivalent.
  _SortedBin<V> getMinBin() {
    var minBin = this;
    var bin = this;
    for (var i = 0; i < 32; i++) {
      final nb = bin.nextNonEmpty;
      if (nb == null) return minBin;
      bin = nb;
      if (bin.lv < minBin.lv) minBin = bin;
    }
    return minBin;
  }
}

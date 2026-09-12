// Port of btools.util.LruMap (BRouter v1.7.10).

import '../jvm.dart';
import 'lru_map_node.dart';

/// Something like LinkedHashMap, but purpose build, less dynamic and memory
/// efficient
class LruMap {
  LruMap(int bins, int size)
    : _hashbins = bins,
      _maxsize = size,
      _binArray = List<LruMapNode?>.filled(bins, null);

  final int _hashbins;
  final int _maxsize;
  int _size = 0;

  LruMapNode? _lru;
  LruMapNode? _mru;

  final List<LruMapNode?> _binArray;

  LruMapNode? get(LruMapNode key) {
    final bin = rem(key.hash & 0xfffffff, _hashbins);

    var e = _binArray[bin];
    while (e != null) {
      if (key == e) {
        return e;
      }
      e = e.nextInBin;
    }
    return null;
  }

  // put e to the mru end of the queue
  void touch(LruMapNode e) {
    final n = e.next;
    final p = e.previous;

    if (n == null) {
      return; // already at mru
    }
    n.previous = p;
    if (p != null) {
      p.next = n;
    } else {
      _lru = n;
    }

    _mru!.next = e;
    e.previous = _mru;
    e.next = null;
    _mru = e;
  }

  LruMapNode? removeLru() {
    if (_size < _maxsize) {
      return null;
    }
    _size--;
    final lru = _lru!;
    // unlink the lru from it's bin-queue
    final bin = rem(lru.hashCode & 0xfffffff, _hashbins);
    var e = _binArray[bin];
    if (e == lru) {
      _binArray[bin] = lru.nextInBin;
    } else {
      while (e != null) {
        final prev = e;
        e = e.nextInBin;
        if (e == lru) {
          prev.nextInBin = lru.nextInBin;
          break;
        }
      }
    }

    final res = lru;
    _lru = lru.next;
    _lru!.previous = null;
    return res;
  }

  void put(LruMapNode val) {
    final bin = rem(val.hashCode & 0xfffffff, _hashbins);
    val.nextInBin = _binArray[bin];
    _binArray[bin] = val;

    val.previous = _mru;
    val.next = null;
    if (_mru == null) {
      _lru = val;
    } else {
      _mru!.next = val;
    }
    _mru = val;
    _size++;
  }
}

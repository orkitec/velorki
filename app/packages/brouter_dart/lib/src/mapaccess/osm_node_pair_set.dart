// Port of btools.mapaccess.OsmNodePairSet (BRouter v1.7.10).

import 'dart:typed_data';

import '../util/compact_long_map.dart';

class _OsmNodePair {
  int node2 = 0;
  _OsmNodePair? next;
}

/// Set holding pairs of osm nodes
class OsmNodePairSet {
  OsmNodePairSet(int maxTempNodeCount)
    : _maxTempNodes = maxTempNodeCount,
      _n1a = Int64List(maxTempNodeCount),
      _n2a = Int64List(maxTempNodeCount);

  final Int64List _n1a;
  final Int64List _n2a;
  int _tempNodes = 0;
  final int _maxTempNodes;
  int _npairs = 0;
  int _freezecount = 0;

  CompactLongMap<_OsmNodePair>? _map;

  void addTempPair(int n1, int n2) {
    if (_tempNodes < _maxTempNodes) {
      _n1a[_tempNodes] = n1;
      _n2a[_tempNodes] = n2;
      _tempNodes++;
    }
  }

  void freezeTempPairs() {
    _freezecount++;
    for (var i = 0; i < _tempNodes; i++) {
      _addPair(_n1a[i], _n2a[i]);
    }
    _tempNodes = 0;
  }

  void clearTempPairs() {
    _tempNodes = 0;
  }

  void _addPair(int n1, int n2) {
    final map = _map ??= CompactLongMap<_OsmNodePair>();
    _npairs++;

    var e = _getElement(n1, n2);
    if (e == null) {
      e = _OsmNodePair();
      e.node2 = n2;

      var e0 = map.get(n1);
      if (e0 != null) {
        while (e0!.next != null) {
          e0 = e0.next;
        }
        e0.next = e;
      } else {
        map.fastPut(n1, e);
      }
    }
  }

  int size() {
    return _npairs;
  }

  int tempSize() {
    return _tempNodes;
  }

  int getMaxTmpNodes() {
    return _maxTempNodes;
  }

  int getFreezeCount() {
    return _freezecount;
  }

  bool hasPair(int n1, int n2) {
    return _map != null &&
        (_getElement(n1, n2) != null || _getElement(n2, n1) != null);
  }

  _OsmNodePair? _getElement(int n1, int n2) {
    var e = _map!.get(n1);
    while (e != null) {
      if (e.node2 == n2) {
        return e;
      }
      e = e.next;
    }
    return null;
  }
}

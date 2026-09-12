// Port of btools.expressions.CacheNode (BRouter v1.7.10).

import 'dart:typed_data';

import '../util/lru_map_node.dart';

class CacheNode extends LruMapNode {
  Uint8List? ab;
  Float32List? vars;

  @override
  int get hashCode => hash;

  @override
  bool operator ==(Object other) {
    final n = other as CacheNode;
    if (hash != n.hash) {
      return false;
    }
    final a = ab;
    if (a == null) {
      return true; // hack: null = crc match only
    }
    final b = n.ab;
    // Arrays.equals(ab, n.ab)
    if (b == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

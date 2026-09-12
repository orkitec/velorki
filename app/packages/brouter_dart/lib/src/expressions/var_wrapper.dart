// Port of btools.expressions.VarWrapper (BRouter v1.7.10).

import 'dart:typed_data';

import '../jfloat.dart';
import '../util/lru_map_node.dart';

class VarWrapper extends LruMapNode {
  Float32List? vars;

  @override
  int get hashCode => hash;

  @override
  bool operator ==(Object other) {
    final n = other as VarWrapper;
    if (hash != n.hash) {
      return false;
    }
    // Arrays.equals(vars, n.vars): element-wise with Float.floatToIntBits
    final a = vars;
    final b = n.vars;
    if (a == null || b == null) return a == null && b == null;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (floatToIntBits(a[i]) != floatToIntBits(b[i])) return false;
    }
    return true;
  }
}

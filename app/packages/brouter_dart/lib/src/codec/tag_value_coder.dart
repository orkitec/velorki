// Port of btools.codec.TagValueCoder (BRouter v1.7.10).

import 'dart:typed_data';

import '../jvm.dart';
import '../util/bit_coder_context.dart';
import 'data_buffers.dart';
import 'tag_value_validator.dart';
import 'tag_value_wrapper.dart';

/// Encoder/Decoder for way-/node-descriptions
///
/// It detects identical descriptions and sorts them
/// into a huffman-tree according to their frequencies
///
/// Adapted for 3-pass encoding (counters -> statistics -> encoding )
/// but doesn't do anything at pass1
class TagValueCoder {
  /// The decoder constructor.
  TagValueCoder.decoder(
    BitCoderContext bc,
    DataBuffers buffers,
    TagValueValidator? validator,
  ) {
    _tree = _decodeTree(bc, buffers, validator);
    _bc = bc;
  }

  /// The encoder constructor.
  TagValueCoder() {
    _identityMap = <TagValueSet, TagValueSet>{};
  }

  Map<TagValueSet, TagValueSet>? _identityMap;
  Object? _tree; // TreeNode | TagValueWrapper | null
  BitCoderContext? _bc;
  int _pass = 0;
  int _nextTagValueSetId = 0;

  void encodeTagValueSet(Uint8List? data) {
    if (_pass == 1) {
      return;
    }
    final tvsProbe = TagValueSet(_nextTagValueSetId);
    tvsProbe.data = data;
    final identityMap = _identityMap!;
    var tvs = identityMap[tvsProbe];
    if (_pass == 3) {
      _bc!.encodeBounded(tvs!.range - 1, tvs.code);
    } else if (_pass == 2) {
      if (tvs == null) {
        tvs = tvsProbe;
        _nextTagValueSetId++;
        identityMap[tvs] = tvs;
      }
      tvs.frequency++;
    }
  }

  TagValueWrapper? decodeTagValueSet() {
    var node = _tree;
    while (node is TreeNode) {
      final tn = node;
      final nextBit = _bc!.decodeBit();
      node = nextBit ? tn.child2 : tn.child1;
    }
    return node as TagValueWrapper?;
  }

  void encodeDictionary(BitCoderContext bc) {
    if (++_pass == 3) {
      final identityMap = _identityMap!;
      if (identityMap.isEmpty) {
        final dummy = TagValueSet(_nextTagValueSetId++);
        identityMap[dummy] = dummy;
      }
      final queue = PriorityQueue<TagValueSet>(FrequencyComparator.compare);
      queue.addAll(identityMap.values);
      while (queue.length > 1) {
        final node = TagValueSet(_nextTagValueSetId++);
        node.child1 = queue.poll();
        node.child2 = queue.poll();
        node.frequency = node.child1!.frequency + node.child2!.frequency;
        queue.add(node);
      }
      final root = queue.poll()!;
      root.encode(bc, 1, 0);
    }
    _bc = bc;
  }

  Object? _decodeTree(
    BitCoderContext bc,
    DataBuffers buffers,
    TagValueValidator? validator,
  ) {
    final isNode = bc.decodeBit();
    if (isNode) {
      final node = TreeNode();
      node.child1 = _decodeTree(bc, buffers, validator);
      node.child2 = _decodeTree(bc, buffers, validator);
      return node;
    }

    final buffer = buffers.tagbuf1;
    final ctx = buffers.bctx1;
    ctx.reset(buffer);

    var inum = 0;
    var lastEncodedInum = 0;

    var hasdata = false;
    for (;;) {
      final delta = bc.decodeVarBits();
      if (!hasdata) {
        if (delta == 0) {
          return null;
        }
      }
      if (delta == 0) {
        ctx.encodeVarBits(0);
        break;
      }
      inum += delta;

      final data = bc.decodeVarBits();

      if (validator == null || validator.isLookupIdxUsed(inum)) {
        hasdata = true;
        ctx.encodeVarBits(inum - lastEncodedInum);
        ctx.encodeVarBits(data);
        lastEncodedInum = inum;
      }
    }

    Uint8List res;
    final len = ctx.closeAndGetEncodedLength();
    if (validator == null) {
      res = Uint8List(len);
      res.setRange(0, len, buffer);
    } else {
      res = validator.unify(buffer, 0, len);
    }

    final accessType = validator == null ? 2 : validator.accessType(res);
    if (accessType > 0) {
      final w = TagValueWrapper();
      w.data = res;
      w.accessType = accessType;
      return w;
    }
    return null;
  }
}

class TreeNode {
  Object? child1;
  Object? child2;
}

class TagValueSet {
  TagValueSet(this._id);

  Uint8List? data;
  int frequency = 0;
  int code = 0;
  int range = 0;
  TagValueSet? child1;
  TagValueSet? child2;
  final int _id; // serial number to make the comparator well defined in case of equal frequencies

  int get id => _id;

  void encode(BitCoderContext bc, int range, int code) {
    this.range = range;
    this.code = code;
    final isNode = child1 != null;
    bc.encodeBit(isNode);
    if (isNode) {
      child1!.encode(bc, shl32(range, 1), code);
      child2!.encode(bc, shl32(range, 1), i32(code + range));
    } else {
      final d = data;
      if (d == null) {
        bc.encodeVarBits(0);
        return;
      }
      final src = BitCoderContext(d);
      for (;;) {
        final delta = src.decodeVarBits();
        bc.encodeVarBits(delta);
        if (delta == 0) {
          break;
        }
        final data = src.decodeVarBits();
        bc.encodeVarBits(data);
      }
    }
  }

  @override
  bool operator ==(Object other) {
    if (other is TagValueSet) {
      final d = data;
      final od = other.data;
      if (d == null) {
        return od == null;
      }
      if (od == null) {
        return false;
      }
      if (d.length != od.length) {
        return false;
      }
      for (var i = 0; i < d.length; i++) {
        if (d[i] != od[i]) {
          return false;
        }
      }
      return true;
    }
    return false;
  }

  @override
  int get hashCode {
    final d = data;
    if (d == null) {
      return 0;
    }
    var h = 17;
    for (var i = 0; i < d.length; i++) {
      h = i32(shl32(h, 8) + toByte(d[i]));
    }
    return h;
  }
}

class FrequencyComparator {
  FrequencyComparator._();

  static int compare(TagValueSet tvs1, TagValueSet tvs2) {
    if (tvs1.frequency < tvs2.frequency) return -1;
    if (tvs1.frequency > tvs2.frequency) return 1;

    // to avoid ordering instability, decide on the id if frequency is equal
    if (tvs1._id < tvs2._id) return -1;
    if (tvs1._id > tvs2._id) return 1;

    if (!identical(tvs1, tvs2)) {
      throw StateError('identity corruption!');
    }
    return 0;
  }
}

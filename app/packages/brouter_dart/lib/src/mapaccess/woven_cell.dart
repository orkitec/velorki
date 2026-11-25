// Port of btools.mapaccess.WovenCell (upstream pull request
// abrensch/brouter#1015, not in a release yet).

import 'dart:typed_data';

/// The decoded content of one micro-cache, kept by its OsmFile so that a later
/// routing pass can weave the same cell into its node graph without decoding
/// the bit stream and the tag sets again (see DirectWeaver).
///
/// It is a flat recording of what DirectWeaver read, in the order it read it:
/// the numbers in one int array, the node descriptions, way tags and
/// geometries in one object array. None of these are modified after decoding,
/// so they are shared between the passes.
class WovenCell {
  Int32List ints = Int32List(256);
  List<Object?> objs = List<Object?>.filled(64, null);
  int nints = 0;
  int nobjs = 0;
  int _geometryBytes = 0;

  @pragma('vm:prefer-inline')
  void add(int value) {
    if (nints == ints.length) {
      final grown = Int32List(2 * nints);
      grown.setRange(0, nints, ints);
      ints = grown;
    }
    ints[nints++] = value;
  }

  @pragma('vm:prefer-inline')
  void addObject(Object? value) {
    if (nobjs == objs.length) {
      final grown = List<Object?>.filled(2 * nobjs, null);
      grown.setRange(0, nobjs, objs);
      objs = grown;
    }
    objs[nobjs++] = value;
  }

  void addGeometry(Uint8List? geometry) {
    addObject(geometry);
    if (geometry != null) {
      _geometryBytes += 16 + geometry.length;
    }
  }

  /// Trim the arrays once the cell is complete.
  void freeze() {
    if (nints < ints.length) {
      ints = Int32List.sublistView(ints, 0, nints).sublist(0);
    }
    if (nobjs < objs.length) {
      objs = objs.sublist(0, nobjs);
    }
  }

  /// The memory this recording holds on its own, in bytes. Node descriptions
  /// and way tags are not counted: they are the shared arrays of the tag
  /// value cache.
  int getDataSize() {
    return 48 + 4 * ints.length + 8 * objs.length + _geometryBytes;
  }
}

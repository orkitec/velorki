// Port of btools.codec.MicroCache (BRouter v1.7.10).

import 'dart:typed_data';

import '../jvm.dart';
import '../util/byte_data_writer.dart';

/// a micro-cache is a data cache for an area of some square kilometers or some
/// hundreds or thousands nodes
///
/// This is the basic io-unit: always a full microcache is loaded from the
/// data-file if a node is requested at a position not yet covered by the caches
/// already loaded
///
/// The nodes are represented in a compact way (typical 20-50 bytes per node),
/// but in a way that they do not depend on each other, and garbage collection is
/// supported to remove the nodes already consumed from the cache.
///
/// The cache-internal data representation is different from that in the
/// data-files, where a cache is encoded as a whole, allowing more
/// redundancy-removal for a more compact encoding
class MicroCache extends ByteDataWriter {
  /// `protected MicroCache(byte[] ab)`.
  MicroCache(super.ab);

  /// `protected int[] faid` (an empty list stands for Java `null`).
  Int32List faid = Int32List(0);

  /// `protected int[] fapos`.
  Int32List fapos = Int32List(0);

  /// `protected int size`.
  int size = 0;

  int _delcount = 0;
  int _delbytes = 0;
  int _p2size = 0; // next power of 2 of size

  // cache control: a virgin cache can be
  // put to ghost state for later recovery
  bool virgin = true;
  bool ghost = false;

  static bool debug = false;

  static final MicroCache emptyNonVirgin = MicroCache(null)..virgin = false;

  static MicroCache emptyCache() {
    return MicroCache(null); // TODO: singleton?
  }

  /// `protected void init(int size)`.
  void init(int size) {
    this.size = size;
    _delcount = 0;
    _delbytes = 0;
    _p2size = 0x40000000;
    while (_p2size > size) {
      _p2size >>= 1;
    }
  }

  void finishNode(int id) {
    fapos[size] = aboffset;
    faid[size] = shrinkId(id);
    size++;
  }

  void discardNode() {
    aboffset = startPos(size);
  }

  int getSize() {
    return size;
  }

  int getDataSize() {
    return ab.length;
  }

  /// Set the internal reader (aboffset, aboffsetEnd) to the body data for the
  /// given id
  ///
  /// If a node is not found in an empty cache, this is usually an edge-effect
  /// (data-file does not exist or neighboured data-files of differnt age),
  /// but is can as well be a symptom of a node-identity breaking bug.
  ///
  /// Returns true if id was found
  bool getAndClear(int id64) {
    if (size == 0) {
      return false;
    }
    final id = shrinkId(id64);
    final a = faid;
    var offset = _p2size;
    var n = 0;

    while (offset > 0) {
      final nn = n + offset;
      if (nn < size && a[nn] <= id) {
        n = nn;
      }
      offset >>= 1;
    }
    if (a[n] == id) {
      if ((fapos[n] & 0x80000000) == 0) {
        aboffset = startPos(n);
        aboffsetEnd = fapos[n];
        fapos[n] = i32(fapos[n] | 0x80000000); // mark deleted
        _delbytes += aboffsetEnd - aboffset;
        _delcount++;
        return true;
      } else {
        // .. marked as deleted
        // throw new RuntimeException( "MicroCache: node already consumed: id=" + id );
      }
    }
    return false;
  }

  /// `protected final int startPos(int n)`.
  int startPos(int n) {
    return n > 0 ? fapos[n - 1] & 0x7fffffff : 0;
  }

  int collect(int threshold) {
    if (_delcount <= threshold) {
      return 0;
    }

    virgin = false;

    final nsize = size - _delcount;
    if (nsize == 0) {
      faid = Int32List(0);
      fapos = Int32List(0);
    } else {
      final nfaid = Int32List(nsize);
      final nfapos = Int32List(nsize);
      var idx = 0;

      final nab = Uint8List(ab.length - _delbytes);
      var nabOff = 0;
      for (var i = 0; i < size; i++) {
        final pos = fapos[i];
        if ((pos & 0x80000000) == 0) {
          final start = startPos(i);
          final end = fapos[i];
          final len = end - start;
          nab.setRange(nabOff, nabOff + len, ab, start);
          nfaid[idx] = faid[i];
          nabOff += len;
          nfapos[idx] = nabOff;
          idx++;
        }
      }
      faid = nfaid;
      fapos = nfapos;
      ab = nab;
    }
    final deleted = _delbytes;
    init(nsize);
    return deleted;
  }

  void unGhost() {
    ghost = false;
    _delcount = 0;
    _delbytes = 0;
    for (var i = 0; i < size; i++) {
      fapos[i] &= 0x7fffffff; // clear deleted flags
    }
  }

  /// Returns the 64-bit global id for the given cache-position
  int getIdForIndex(int i) {
    final id32 = faid[i];
    return expandId(id32);
  }

  /// expand a 32-bit micro-cache-internal id into a 64-bit (lon|lat) global-id
  int expandId(int id32) {
    throw ArgumentError('expandId for empty cache');
  }

  /// shrink a 64-bit (lon|lat) global-id into a a 32-bit micro-cache-internal id
  int shrinkId(int id64) {
    throw ArgumentError('shrinkId for empty cache');
  }

  /// Returns true if the given lon/lat position is internal for that micro-cache
  bool isInternal(int ilon, int ilat) {
    throw ArgumentError('isInternal for empty cache');
  }

  /// (stasticially) encode the micro-cache into the format used in the datafiles
  ///
  /// Returns the size of the encoded data
  int encodeMicroCache(Uint8List buffer) {
    throw ArgumentError('encodeMicroCache for empty cache');
  }

  /// Compare the content of this microcache to another
  ///
  /// Returns null if equals, else a diff-report
  String? compareWith(MicroCache mc) {
    final msg = _compareWith(mc);
    if (msg != null) {
      final sb = StringBuffer(msg);
      sb
        ..write('\nencode cache:\n')
        ..write(_summary());
      sb
        ..write('\ndecode cache:\n')
        ..write(mc._summary());
      return sb.toString();
    }
    return null;
  }

  String _summary() {
    final sb = StringBuffer('size=$size aboffset=$aboffset');
    for (var i = 0; i < size; i++) {
      sb.write('\nidx=$i faid=${faid[i]} fapos=${fapos[i]}');
    }
    return sb.toString();
  }

  String? _compareWith(MicroCache mc) {
    if (size != mc.size) {
      return 'size mismatch: $size->${mc.size}';
    }
    for (var i = 0; i < size; i++) {
      if (faid[i] != mc.faid[i]) {
        return 'faid mismatch at index $i:${faid[i]}->${mc.faid[i]}';
      }
      final start = i > 0 ? fapos[i - 1] : 0;
      final end = fapos[i] < mc.fapos[i] ? fapos[i] : mc.fapos[i];
      final len = end - start;
      for (var offset = 0; offset < len; offset++) {
        if (mc.ab.length <= start + offset) {
          return 'data buffer too small';
        }
        if (ab[start + offset] != mc.ab[start + offset]) {
          return 'data mismatch at index $i offset=$offset';
        }
      }
      if (fapos[i] != mc.fapos[i]) {
        return 'fapos mismatch at index $i:${fapos[i]}->${mc.fapos[i]}';
      }
    }
    if (aboffset != mc.aboffset) {
      return 'datasize mismatch: $aboffset->${mc.aboffset}';
    }
    return null;
  }

  void calcDelta(MicroCache mc1, MicroCache mc2) {
    var idx1 = 0;
    var idx2 = 0;

    while (idx1 < mc1.size || idx2 < mc2.size) {
      final id1 = idx1 < mc1.size ? mc1.faid[idx1] : intMaxValue;
      final id2 = idx2 < mc2.size ? mc2.faid[idx2] : intMaxValue;
      int id;
      if (id1 >= id2) {
        id = id2;
        final start2 = idx2 > 0 ? mc2.fapos[idx2 - 1] : 0;
        final len2 = mc2.fapos[idx2++] - start2;

        if (id1 == id2) {
          // id exists in both caches, compare data
          final start1 = idx1 > 0 ? mc1.fapos[idx1 - 1] : 0;
          final len1 = mc1.fapos[idx1++] - start1;
          if (len1 == len2) {
            var i = 0;
            while (i < len1) {
              if (mc1.ab[start1 + i] != mc2.ab[start2 + i]) {
                break;
              }
              i++;
            }
            if (i == len1) {
              continue; // same data -> do nothing
            }
          }
        }
        write(mc2.ab, start2, len2);
      } else {
        idx1++;
        id = id1; // deleted node
      }
      fapos[size] = aboffset;
      faid[size] = id;
      size++;
    }
  }

  void addDelta(MicroCache mc1, MicroCache mc2, bool keepEmptyNodes) {
    var idx1 = 0;
    var idx2 = 0;

    while (idx1 < mc1.size || idx2 < mc2.size) {
      final id1 = idx1 < mc1.size ? mc1.faid[idx1] : intMaxValue;
      final id2 = idx2 < mc2.size ? mc2.faid[idx2] : intMaxValue;
      if (id1 >= id2) {
        // data from diff file wins
        final start2 = idx2 > 0 ? mc2.fapos[idx2 - 1] : 0;
        final len2 = mc2.fapos[idx2++] - start2;
        if (keepEmptyNodes || len2 > 0) {
          write(mc2.ab, start2, len2);
          fapos[size] = aboffset;
          faid[size++] = id2;
        }
        if (id1 == id2) {
          // id exists in both caches
          idx1++;
        }
      } else {
        // use data from base file
        final start1 = idx1 > 0 ? mc1.fapos[idx1 - 1] : 0;
        final len1 = mc1.fapos[idx1++] - start1;
        write(mc1.ab, start1, len1);
        fapos[size] = aboffset;
        faid[size++] = id1;
      }
    }
  }
}

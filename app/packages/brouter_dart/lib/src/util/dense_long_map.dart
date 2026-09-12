// Port of btools.util.DenseLongMap (BRouter v1.7.10).

import 'dart:typed_data';

import '../jvm.dart';

/// Special Memory efficient Map to map a long-key to
/// a "small" value (some bits only) where it is expected
/// that the keys are dense, so that we can use more or less
/// a simple array as the best-fit data model (except for
/// the 32-bit limit of arrays!)
///
/// Target application are osm-node ids which are in the
/// range 0...3 billion and basically dense (=only few
/// nodes deleted)
class DenseLongMap {
  /// Creates a DenseLongMap for the given block size
  /// (default 512 bytes per bitplane, covering a key range of 4096 keys).
  /// Note that one value range is limited to 0..254
  DenseLongMap([int blocksize = 512]) {
    var bits = 4;
    while (bits < 28 && (1 << bits) != blocksize) {
      bits++;
    }
    if (bits == 28) {
      throw StateError(
        'not a valid blocksize: $blocksize ( expected 1 << bits with bits in (4..27) )',
      );
    }
    _blocksizeBits = bits + 3;
    _blocksizeBitsMask = (1 << _blocksizeBits) - 1;
    _blocksize = blocksize;
  }

  final List<Uint8List?> _blocklist = <Uint8List?>[];

  late int _blocksize; // bytes per bitplane in one block
  late int _blocksizeBits;
  late int _blocksizeBitsMask;
  final int _maxvalue = 254; // fixed due to 8 bit lookup table
  final Int32List _bitplaneCount = Int32List(8);
  int _putCount = 0;
  int _getCount = 0;

  /// `putCount` / `getCount` / `bitplaneCount`: the statistics the JVM version
  /// prints to stdout on the first `getInt`. The print is not ported.
  int get putCount => _putCount;
  int get getCount => _getCount;
  Int32List get bitplaneCount => _bitplaneCount;

  void put(int key, int value) {
    _putCount++;

    if (value < 0 || value > _maxvalue) {
      throw ArgumentError('value out of range (0..$_maxvalue): $value');
    }

    final blockn = i32(key >> _blocksizeBits);
    final offset = i32(key & _blocksizeBitsMask);

    var block = blockn < _blocklist.length ? _blocklist[blockn] : null;

    var valuebits = 1;
    if (block == null) {
      block = Uint8List(_sizeForBits(valuebits));
      _bitplaneCount[0]++;

      while (_blocklist.length < blockn + 1) {
        _blocklist.add(null);
      }
      _blocklist[blockn] = block;
    } else {
      // check how many bitplanes we have from the arraysize
      while (_sizeForBits(valuebits) < block.length) {
        valuebits++;
      }
    }
    var headersize = 1 << valuebits;

    final v = (value + 1) & 0xff; // 0 is reserved (=unset)

    // find the index in the lookup table or the first entry
    var idx = 1;
    while (idx < headersize) {
      if (block[idx] == 0) {
        block[idx] = v; // create new entry
      }
      if (block[idx] == v) {
        break;
      }
      idx++;
    }
    if (idx == headersize) {
      block = _expandBlock(block, valuebits);
      block[idx] = v; // create new entry
      _blocklist[blockn] = block;
      valuebits++;
      headersize = 1 << valuebits;
    }

    final bitmask = 1 << (offset & 0x7);
    final invmask = bitmask ^ 0xff;
    var probebit = 1;
    var blockidx = (offset >> 3) + headersize;

    for (var i = 0; i < valuebits; i++) {
      if ((idx & probebit) != 0) {
        block[blockidx] |= bitmask;
      } else {
        block[blockidx] &= invmask;
      }
      probebit <<= 1;
      blockidx += _blocksize;
    }
  }

  int _sizeForBits(int bits) {
    // size is lookup table + datablocks
    return (1 << bits) + _blocksize * bits;
  }

  Uint8List _expandBlock(Uint8List block, int valuebits) {
    _bitplaneCount[valuebits]++;
    final newblock = Uint8List(_sizeForBits(valuebits + 1));
    final headersize = 1 << valuebits;
    newblock.setRange(0, headersize, block); // copy header
    newblock.setRange(
      2 * headersize,
      2 * headersize + block.length - headersize,
      block,
      headersize,
    ); // copy data
    return newblock;
  }

  int getInt(int key) {
    _getCount++;

    if (key < 0) {
      return -1;
    }
    final blockn = i32(key >> _blocksizeBits);
    final offset = i32(key & _blocksizeBitsMask);

    final block = blockn < _blocklist.length ? _blocklist[blockn] : null;

    if (block == null) {
      return -1;
    }

    // check how many bitplanes we have from the arrayzize
    var valuebits = 1;
    while (_sizeForBits(valuebits) < block.length) {
      valuebits++;
    }
    final headersize = 1 << valuebits;

    final bitmask = 1 << (offset & 7);
    var probebit = 1;
    var blockidx = (offset >> 3) + headersize;
    var idx = 0; // 0 is reserved (=unset)

    for (var i = 0; i < valuebits; i++) {
      if ((block[blockidx] & bitmask) != 0) {
        idx |= probebit;
      }
      probebit <<= 1;
      blockidx += _blocksize;
    }

    // lookup that value in the lookup header
    return ((256 + toByte(block[idx])) & 0xff) - 1;
  }
}

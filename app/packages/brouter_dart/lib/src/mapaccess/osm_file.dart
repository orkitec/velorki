// Port of btools.mapaccess.OsmFile (BRouter v1.7.10).

import 'dart:io';
import 'dart:typed_data';

import '../codec/data_buffers.dart';
import '../codec/micro_cache.dart';
import '../codec/micro_cache2.dart';
import '../codec/stat_coder_context.dart';
import '../codec/tag_value_validator.dart';
import '../codec/waypoint_matcher.dart';
import '../jvm.dart';
import '../util/byte_data_reader.dart';
import '../util/crc32.dart';
import 'direct_weaver.dart';
import 'osm_nodes_map.dart';
import 'physical_file.dart';

/// cache for a single square
class OsmFile {
  OsmFile(
    PhysicalFile? rafile,
    this.lonDegree,
    this.latDegree,
    DataBuffers dataBuffers,
  ) {
    final lonMod5 = rem(lonDegree, 5);
    final latMod5 = rem(latDegree, 5);
    final tileIndex = lonMod5 * 5 + latMod5;

    if (rafile != null) {
      _divisor = rafile.divisor;
      elevationType = rafile.elevationType;

      _cellsize = 1000000 ~/ _divisor;
      final ncaches = _divisor * _divisor;
      _indexsize = ncaches * 4;

      final iobuffer = dataBuffers.iobuffer;
      filename = rafile.fileName;

      final index = rafile.fileIndex;
      _fileOffset = tileIndex > 0 ? index[tileIndex - 1] : 200;
      if (_fileOffset == index[tileIndex]) return; // empty

      final ra = _is = rafile.ra;
      final posIdx = _posIdx = Int32List(ncaches);
      _microCaches = List<MicroCache?>.filled(ncaches, null);
      ra!.setPositionSync(_fileOffset);
      readFullySync(ra, iobuffer, 0, _indexsize);

      final crcs = rafile.fileHeaderCrcs;
      if (crcs != null) {
        final headerCrc = Crc32.crc(iobuffer, 0, _indexsize);
        if (crcs[tileIndex] != headerCrc) {
          throw IOException('sub index checksum error');
        }
      }

      final dis = ByteDataReader(iobuffer);
      for (var i = 0; i < ncaches; i++) {
        posIdx[i] = dis.readInt();
      }
    }
  }

  RandomAccessFile? _is;
  int _fileOffset = 0;

  Int32List? _posIdx;
  List<MicroCache?>? _microCaches;

  int lonDegree;
  int latDegree;

  String? filename;

  int _divisor = 0;
  int _cellsize = 0;
  int _indexsize = 0;
  int elevationType = 3;

  /// The byte offset of this degree square's index inside the rd5 (not
  /// upstream API; for the oracle comparison).
  int get fileOffset => _fileOffset;

  /// The per-micro-cache end positions (not upstream API; for the oracle
  /// comparison).
  Int32List? get posIdx => _posIdx;

  bool hasData() {
    return _microCaches != null;
  }

  MicroCache? getMicroCache(int ilon, int ilat) {
    final lonIdx = ilon ~/ _cellsize;
    final latIdx = ilat ~/ _cellsize;
    final subIdx =
        (latIdx - _divisor * latDegree) * _divisor +
        (lonIdx - _divisor * lonDegree);
    return _microCaches![subIdx];
  }

  /// `createMicroCache(int ilon, int ilat, DataBuffers, TagValueValidator,
  /// WaypointMatcher, OsmNodesMap hollowNodes)`.
  MicroCache createMicroCache(
    int ilon,
    int ilat,
    DataBuffers dataBuffers,
    TagValueValidator? wayValidator,
    WaypointMatcher? waypointMatcher,
    OsmNodesMap? hollowNodes,
  ) {
    final lonIdx = ilon ~/ _cellsize;
    final latIdx = ilat ~/ _cellsize;
    final segment = createMicroCacheForIdx(
      lonIdx,
      latIdx,
      dataBuffers,
      wayValidator,
      waypointMatcher,
      true,
      hollowNodes,
    )!;
    final subIdx =
        (latIdx - _divisor * latDegree) * _divisor +
        (lonIdx - _divisor * lonDegree);
    _microCaches![subIdx] = segment;
    return segment;
  }

  int _getPosIdx(int idx) {
    return idx == -1 ? _indexsize : _posIdx![idx];
  }

  int getDataInputForSubIdx(int subIdx, Uint8List iobuffer) {
    final startPos = _getPosIdx(subIdx - 1);
    final endPos = _getPosIdx(subIdx);
    final size = endPos - startPos;
    if (size > 0) {
      _is!.setPositionSync(_fileOffset + startPos);
      if (size <= iobuffer.length) {
        readFullySync(_is!, iobuffer, 0, size);
      }
    }
    return size;
  }

  /// `createMicroCache(int lonIdx, int latIdx, DataBuffers, TagValueValidator,
  /// WaypointMatcher, boolean reallyDecode, OsmNodesMap hollowNodes)`: null
  /// when `reallyDecode` is false.
  MicroCache? createMicroCacheForIdx(
    int lonIdx,
    int latIdx,
    DataBuffers dataBuffers,
    TagValueValidator? wayValidator,
    WaypointMatcher? waypointMatcher,
    bool reallyDecode,
    OsmNodesMap? hollowNodes,
  ) {
    final subIdx =
        (latIdx - _divisor * latDegree) * _divisor +
        (lonIdx - _divisor * lonDegree);

    var ab = dataBuffers.iobuffer;
    var asize = getDataInputForSubIdx(subIdx, ab);

    if (asize == 0) {
      return MicroCache.emptyCache();
    }
    if (asize > ab.length) {
      ab = Uint8List(asize);
      asize = getDataInputForSubIdx(subIdx, ab);
    }

    final bc = StatCoderContext(ab);

    try {
      if (!reallyDecode) {
        return null;
      }
      if (hollowNodes == null) {
        return MicroCache2.decode(
          bc,
          dataBuffers,
          lonIdx,
          latIdx,
          _divisor,
          wayValidator,
          waypointMatcher,
        );
      }
      DirectWeaver(
        bc,
        dataBuffers,
        lonIdx,
        latIdx,
        _divisor,
        wayValidator,
        waypointMatcher,
        hollowNodes,
      );
      return MicroCache.emptyNonVirgin;
    } finally {
      // crc check only if the buffer has not been fully read
      final readBytes = (bc.getReadingBitPosition() + 7) >> 3;
      if (readBytes != asize - 4) {
        final crcData = Crc32.crc(ab, 0, asize - 4);
        final crcFooter = ByteDataReader(ab, asize - 4).readInt();
        if (crcData == crcFooter) {
          throw IOException('old, unsupported data-format');
        } else if ((crcData ^ 2) != crcFooter) {
          throw IOException('checkum error');
        }
      }
    }
  }

  // set this OsmFile to ghost-state:
  int setGhostState() {
    var sum = 0;
    final caches = _microCaches;
    final nc = caches == null ? 0 : caches.length;
    for (var i = 0; i < nc; i++) {
      final mc = caches![i];
      if (mc == null) continue;
      if (mc.virgin) {
        mc.ghost = true;
        sum += mc.getDataSize();
      } else {
        caches[i] = null;
      }
    }
    return sum;
  }

  int collectAll() {
    var deleted = 0;
    final caches = _microCaches;
    final nc = caches == null ? 0 : caches.length;
    for (var i = 0; i < nc; i++) {
      final mc = caches![i];
      if (mc == null) continue;
      if (!mc.ghost) {
        deleted += mc.collect(0);
      }
    }
    return deleted;
  }

  int cleanGhosts() {
    const deleted = 0;
    final caches = _microCaches;
    final nc = caches == null ? 0 : caches.length;
    for (var i = 0; i < nc; i++) {
      final mc = caches![i];
      if (mc == null) continue;
      if (mc.ghost) {
        caches[i] = null;
      }
    }
    return deleted;
  }

  void clean(bool all) {
    final caches = _microCaches;
    final nc = caches == null ? 0 : caches.length;
    for (var i = 0; i < nc; i++) {
      final mc = caches![i];
      if (mc == null) continue;
      if (all || !mc.virgin) {
        caches[i] = null;
      }
    }
  }
}

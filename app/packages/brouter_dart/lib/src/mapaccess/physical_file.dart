// Port of btools.mapaccess.PhysicalFile (BRouter v1.7.10).

import 'dart:io';
import 'dart:typed_data';

import '../codec/data_buffers.dart';
import '../codec/micro_cache.dart';
import '../jvm.dart';
import '../util/byte_data_reader.dart';
import '../util/crc32.dart';
import 'osm_file.dart';

/// `RandomAccessFile.readFully(b, off, len)`: a synchronous full read at the
/// current position; an [EofException] when the file ends first.
void readFullySync(RandomAccessFile ra, Uint8List b, int off, int len) {
  var done = 0;
  while (done < len) {
    final n = ra.readIntoSync(b, off + done, off + len);
    if (n <= 0) throw EofException();
    done += n;
  }
}

/// cache for a single square
///
/// One synchronous `dart:io` [RandomAccessFile] per rd5, seek + read like
/// upstream; nothing is mapped or read as a whole.
class PhysicalFile {
  PhysicalFile(
    File f,
    DataBuffers dataBuffers,
    int lookupVersion,
    int lookupMinorVersion,
  ) : fileName = f.uri.pathSegments.last {
    final iobuffer = dataBuffers.iobuffer;
    final raf = f.openSync(mode: FileMode.read);
    ra = raf;
    readFullySync(raf, iobuffer, 0, 200);
    final fileIndexCrc = Crc32.crc(iobuffer, 0, 200);
    var dis = ByteDataReader(iobuffer);
    for (var i = 0; i < 25; i++) {
      final lv = dis.readLong();
      final readVersion = toShort(lv >> 48);
      if (i == 0) {
        headerLookupVersion = readVersion;
        if (lookupVersion != -1 && readVersion != lookupVersion) {
          throw IOException(
            'lookup version mismatch (old rd5?) lookups.dat=$lookupVersion $fileName=$readVersion',
          );
        }
      }
      fileIndex[i] = lv & 0xffffffffffff;
    }

    // read some extra info from the end of the file, if present
    final len = raf.lengthSync();

    final pos = fileIndex[24];
    var extraLen = 8 + 26 * 4;

    if (len == pos) return; // old format o.k.

    if ((len - pos) > extraLen) {
      extraLen++;
    }

    if (len < pos + extraLen) {
      // > is o.k. for future extensions!
      throw IOException(
        'file of size $len too short, should be ${pos + extraLen}',
      );
    }

    raf.setPositionSync(pos);
    readFullySync(raf, iobuffer, 0, extraLen);
    dis = ByteDataReader(iobuffer);
    creationTime = dis.readLong();

    final crcData = dis.readInt();
    if (crcData == fileIndexCrc) {
      divisor = 80; // old format
    } else if ((crcData ^ 2) == fileIndexCrc) {
      divisor = 32; // new format
    } else {
      throw IOException('top index checksum error');
    }
    final crcs = fileHeaderCrcs = Int32List(25);
    for (var i = 0; i < 25; i++) {
      crcs[i] = dis.readInt();
    }
    try {
      elevationType = dis.readByte();
    } catch (_) {}
  }

  /// `RandomAccessFile ra` (package-private upstream).
  RandomAccessFile? ra;
  final Int64List fileIndex = Int64List(25);
  Int32List? fileHeaderCrcs;

  int creationTime = 0;

  String fileName;

  int divisor = 80;
  int elevationType = 3;

  /// The lookup version the tile was built with: `(short) (fileIndex[0] >> 48)`.
  /// Upstream only compares it with `lookups.dat` and throws on a mismatch
  /// (when `lookupVersion != -1`); the port keeps it so a caller can inspect
  /// it (the 1.7.10 tiles carry 11, `lookups.dat` 11.2).
  int headerLookupVersion = -1;

  static int checkVersionIntegrity(File f) {
    var version = -1;
    RandomAccessFile? raf;
    try {
      final iobuffer = Uint8List(200);
      raf = f.openSync(mode: FileMode.read);
      readFullySync(raf, iobuffer, 0, 200);
      final dis = ByteDataReader(iobuffer);
      final lv = dis.readLong();
      version = i32(lv >> 48);
    } catch (_) {
      // IOException: version stays -1
    } finally {
      raf?.closeSync();
    }
    return version;
  }

  /// Checks the integrity of the file using the build-in checksums
  ///
  /// Returns the error message if file corrupt, else null
  static String? checkFileIntegrity(File f) {
    PhysicalFile? pf;
    try {
      final dataBuffers = DataBuffers();
      pf = PhysicalFile(f, dataBuffers, -1, -1);
      final div = pf.divisor;
      for (var lonDegree = 0; lonDegree < 5; lonDegree++) {
        // doesn't really matter..
        for (var latDegree = 0; latDegree < 5; latDegree++) {
          // ..where on earth we are
          final osmf = OsmFile(pf, lonDegree, latDegree, dataBuffers);
          if (osmf.hasData()) {
            for (var lonIdx = 0; lonIdx < div; lonIdx++) {
              for (var latIdx = 0; latIdx < div; latIdx++) {
                osmf.createMicroCacheForIdx(
                  lonDegree * div + lonIdx,
                  latDegree * div + latIdx,
                  dataBuffers,
                  null,
                  null,
                  MicroCache.debug,
                  null,
                );
              }
            }
          }
        }
      }
    } finally {
      if (pf != null) {
        try {
          pf.ra?.closeSync();
        } catch (_) {}
      }
    }
    return null;
  }

  void close() {
    final raf = ra;
    if (raf != null) {
      try {
        raf.closeSync();
      } catch (_) {}
    }
  }
}

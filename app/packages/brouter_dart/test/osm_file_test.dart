// L2-mapaccess parity of PhysicalFile / OsmFile against the oracle's
// `osmfile-index`: the rd5 header, the per-square index and every micro-cache
// position, size and crc; plus a full decode of every cache in both tiles.

import 'dart:io';
import 'dart:typed_data';

import 'package:brouter_dart/brouter_dart.dart';
import 'package:test/test.dart';

import 'mapaccess_support.dart';

void main() {
  final skip = tilesMissing;

  for (final tile in tiles) {
    group(tile, () {
      final v = loadMapaccessVector('osmfile-index-$tile.json');
      final file = File('${segmentsDir.path}/$tile.rd5');
      final dataBuffers = DataBuffers();
      late PhysicalFile pf;

      test('PhysicalFile reads the header, trailer, divisor and crcs', () {
        expect(file.lengthSync(), v['length']);
        expect(
          PhysicalFile.checkVersionIntegrity(file),
          v['checkVersionIntegrity'],
        );
        pf = PhysicalFile(file, dataBuffers, -1, -1);
        expect(pf.fileName, '$tile.rd5');
        expect(pf.headerLookupVersion, v['headerLookupVersion']);
        expect(pf.creationTime, v['creationTime']);
        expect(pf.divisor, v['divisor']);
        expect(pf.elevationType, v['elevationType']);
        expect(pf.fileIndex.toList(), v['fileIndex']);
        expect(pf.fileHeaderCrcs?.toList(), v['fileHeaderCrcs']);
      });

      test('the lookup version is checked against lookups.dat', () {
        final lv = v['headerLookupVersion'] as int;
        PhysicalFile(file, DataBuffers(), lv, 2).close();
        expect(
          () => PhysicalFile(file, DataBuffers(), lv + 1, 0),
          throwsA(
            isA<IOException>().having(
              (e) => e.message,
              'message',
              'lookup version mismatch (old rd5?) lookups.dat=${lv + 1} $tile.rd5=$lv',
            ),
          ),
        );
      });

      test('OsmFile: every degree square, every micro-cache size and crc', () {
        final div = pf.divisor;
        final squares = (v['squares'] as List).cast<Map<String, dynamic>>();
        expect(squares.length, 25);
        final buf = Uint8List(4 * 1024 * 1024);
        var decoded = 0;
        for (final sq in squares) {
          final lonDegree = sq['lonDegree'] as int;
          final latDegree = sq['latDegree'] as int;
          final osmf = OsmFile(pf, lonDegree, latDegree, dataBuffers);
          final where = 'square $lonDegree/$latDegree';
          expect(osmf.hasData(), sq['hasData'], reason: where);
          expect(osmf.fileOffset, sq['fileOffset'], reason: where);
          expect(osmf.elevationType, sq['elevationType'], reason: where);
          expect(osmf.filename, '$tile.rd5');
          if (!osmf.hasData()) continue;
          final caches = <String>[];
          var total = 0;
          for (var subIdx = 0; subIdx < div * div; subIdx++) {
            final size = osmf.getDataInputForSubIdx(subIdx, buf);
            if (size == 0) continue;
            caches.add('$subIdx $size ${Crc32.crc(buf, 0, size)}');
            total += size;
            // decode it (MicroCache2 path, no validator): crc footer checked
            final lonIdx = lonDegree * div + subIdx % div;
            final latIdx = latDegree * div + subIdx ~/ div;
            final mc = osmf.createMicroCacheForIdx(
              lonIdx,
              latIdx,
              dataBuffers,
              null,
              null,
              true,
              null,
            );
            expect(mc, isA<MicroCache2>(), reason: '$where sub $subIdx');
            expect(mc!.getSize(), greaterThan(0), reason: '$where sub $subIdx');
            expect(
              osmf.createMicroCacheForIdx(
                lonIdx,
                latIdx,
                dataBuffers,
                null,
                null,
                false,
                null,
              ),
              isNull,
              reason: 'reallyDecode=false returns null after the crc check',
            );
            decoded++;
          }
          expect(caches, sq['caches'], reason: where);
          expect(caches.length, sq['cacheCount'], reason: where);
          expect(total, sq['cacheBytes'], reason: where);
          expect(
            osmf.getMicroCache(lonDegree * 1000000, latDegree * 1000000),
            isNull,
            reason: 'nothing cached through createMicroCacheForIdx',
          );
        }
        expect(decoded, greaterThan(0));
      });

      test('checkFileIntegrity decodes the whole tile', () {
        expect(PhysicalFile.checkFileIntegrity(file), isNull);
      });

      test('NodesCache: empty squares give no segment, elevation type', () {
        final cache = NodesCache(
          segmentsDir,
          allWaysValidator(),
          false,
          64 << 20,
          null,
          false,
        );
        final sq = (v['squares'] as List).cast<Map<String, dynamic>>();
        final empty = sq.firstWhere((s) => s['hasData'] == false);
        final ilon = (empty['lonDegree'] as int) * 1000000 + 500000;
        final ilat = (empty['latDegree'] as int) * 1000000 + 500000;
        expect(cache.loadSegmentFor(ilon, ilat), 0);
        expect(cache.getSegmentFor(ilon, ilat), isNull);
        expect(cache.getElevationType(ilon, ilat), v['elevationType']);
        expect(cache.getElevationType(0, 0), 3, reason: 'no file row yet');
        expect(cache.firstFileAccessFailed, isFalse);
        expect(cache.firstFileAccessName, '$tile.rd5');
        cache.close();
      });

      tearDownAll(() => pf.close());
    }, skip: skip);
  }

  test('a missing tile is reported through first_file_access_*', () {
    final cache = NodesCache(
      segmentsDir,
      allWaysValidator(),
      false,
      64 << 20,
      null,
      false,
    );
    // E0_N0 is not in the segments dir
    expect(cache.loadSegmentFor(180500000, 90500000), 0);
    expect(cache.firstFileAccessFailed, isTrue);
    expect(cache.firstFileAccessName, 'E0_N0.rd5');
    final mwp = MatchedWaypoint()
      ..waypoint = OsmNode(180500000, 90500000)
      ..name = 'nowhere';
    // the flags are only set by the first fileForSegment; a second access of
    // the same (cached, empty) OsmFile does not re-set them -> no match, no throw
    expect(
      cache.matchWaypointsToNodes([mwp], 250.0, OsmNodePairSet(10)),
      isFalse,
    );
    expect(mwp.crosspoint, isNull);
    cache.close();
    final fresh = NodesCache(
      segmentsDir,
      allWaysValidator(),
      false,
      64 << 20,
      null,
      false,
    );
    expect(
      () => fresh.matchWaypointsToNodes([mwp], 250.0, OsmNodePairSet(10)),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          'datafile E0_N0.rd5 not found',
        ),
      ),
    );
    fresh.close();
  }, skip: skip);

  test('a missing segment directory is rejected', () {
    expect(
      () => NodesCache(
        Directory('/nonexistent/segments'),
        allWaysValidator(),
        false,
        1,
        null,
        false,
      ),
      throwsA(isA<StateError>()),
    );
  });
}

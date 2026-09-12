// L1 parity of MicroCache2 against two real micro-caches from the committed
// rd5 tiles of the oracle (see tools/brouter-oracle/README.md).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:brouter_dart/brouter_dart.dart';
import 'package:test/test.dart';

import 'vectors.dart';

/// The link view of a node the way `Dump.java` prints it: `OsmNode.parseNodeBody`
/// on a fresh node, i.e. links are prepended and merged by `OsmNode.addLink`.
class _Link {
  _Link(
    this.targetIlon,
    this.targetIlat,
    this.reverse,
    this.desc,
    this.geometry,
  );

  final int targetIlon;
  final int targetIlat;
  final bool reverse;
  Uint8List? desc;
  Uint8List? geometry;
}

class _Node {
  int selev = 0;
  Uint8List? nodeDescription;
  final turnRestrictions = <Map<String, Object>>[];
  final links = <_Link>[];

  /// `OsmNode.addLink(int, int, byte[], byte[], OsmNodesMap, boolean)` for a
  /// node that owns no links yet (hollow nodes only ever get fresh links).
  void addLink(
    int ilon,
    int ilat,
    int linklon,
    int linklat,
    Uint8List? description,
    Uint8List? geometry,
    bool isReverse,
  ) {
    if (linklon == ilon && linklat == ilat) return; // skip self-ref
    _Link? link;
    for (final l in links) {
      if (l.targetIlon == linklon && l.targetIlat == linklat) {
        if (isReverse || (l.desc == null && !l.reverse)) {
          link = l;
          break;
        }
      }
    }
    if (link == null) {
      link = _Link(linklon, linklat, isReverse, null, null);
      links.insert(0, link); // OsmNode.addLink prepends
    }
    if (!isReverse) {
      link.desc = description;
      link.geometry = geometry;
    }
  }
}

_Node _parseNodeBody(MicroCache2 mc, int ilon, int ilat) {
  final node = _Node();
  while (mc.readBoolean()) {
    final exceptions = mc.readShort();
    final isPositive = mc.readBoolean();
    node.turnRestrictions.add({
      'isPositive': isPositive,
      'exceptions': exceptions,
      'fromLon': mc.readInt(),
      'fromLat': mc.readInt(),
      'toLon': mc.readInt(),
      'toLat': mc.readInt(),
    });
  }
  node.selev = mc.readShort();
  final nodeDescSize = mc.readVarLengthUnsigned();
  node.nodeDescription = nodeDescSize == 0
      ? null
      : (Uint8List(nodeDescSize)..also(mc.readFully));
  while (mc.hasMoreData()) {
    final endPointer = mc.getEndPointer();
    final linklon = ilon + mc.readVarLengthSigned();
    final linklat = ilat + mc.readVarLengthSigned();
    final sizecode = mc.readVarLengthUnsigned();
    final isReverse = (sizecode & 1) != 0;
    Uint8List? description;
    final descSize = sizecode >> 1;
    if (descSize > 0) {
      description = Uint8List(descSize);
      mc.readFully(description);
    }
    final geometry = mc.readDataUntil(endPointer);
    node.addLink(
      ilon,
      ilat,
      linklon,
      linklat,
      description,
      geometry,
      isReverse,
    );
  }
  return node;
}

extension<T> on T {
  T also(void Function(T) f) {
    f(this);
    return this;
  }
}

void main() {
  const cells = [
    (
      'microcache-W20_N30-funchal',
      '../../../tools/brouter-oracle/dump/samples/microcache-W20_N30-funchal.json',
    ),
    (
      'microcache-W25_N60-reykjavik',
      '../../../tools/brouter-oracle/dump/samples/microcache-W25_N60-reykjavik.json',
    ),
  ];

  for (final (name, samplePath) in cells) {
    group(name, () {
      final listing = loadVector('$name.listing.json');
      final raw = loadBinary('$name.bin');
      final lonIdx = listing['lonIdx'] as int;
      final latIdx = listing['latIdx'] as int;
      final divisor = listing['divisor'] as int;

      test('raw bytes carry the OsmFile crc footer (crc ^ 2)', () {
        expect(raw.length, listing['encodedSize']);
        final crcData = Crc32.crc(raw, 0, raw.length - 4);
        final crcFooter = ByteDataReader(raw, raw.length - 4).readInt();
        expect(crcData, listing['encodedCrc']);
        expect(crcFooter, listing['footerCrc']);
        expect(
          crcData ^ 2,
          crcFooter,
          reason: 'the 1.7.10 format marks the footer with crc ^ 2',
        );
      });

      late MicroCache2 mc;
      late StatCoderContext bc;
      late List<Uint8List> bodies;
      late List<int> ids;

      test('decodes to the same node count, data size and read position', () {
        bc = StatCoderContext(raw);
        mc = MicroCache2.decode(
          bc,
          DataBuffers(),
          lonIdx,
          latIdx,
          divisor,
          null,
          null,
        );
        expect((bc.getReadingBitPosition() + 7) >> 3, listing['readBytes']);
        expect(mc.getSize(), listing['size']);
        expect(mc.getDataSize(), listing['dataSize']);
        expect(mc.virgin, isTrue);
      });

      test('every node id and every node body is byte-identical', () {
        final size = mc.getSize();
        ids = [for (var i = 0; i < size; i++) mc.getIdForIndex(i)];
        final idw = ByteDataWriter(Uint8List(8 * size));
        for (final id in ids) {
          idw.writeLong(id);
        }
        expect(
          Crc32.crc(idw.toByteArray(), 0, 8 * size),
          listing['idsCrc'],
          reason: 'crc of all 64-bit ids',
        );

        bodies = <Uint8List>[];
        final expectedNodes = (listing['nodes'] as List<dynamic>)
            .cast<String>();
        var total = 0;
        for (var i = 0; i < size; i++) {
          expect(
            mc.getAndClear(ids[i]),
            isTrue,
            reason: 'getAndClear index $i',
          );
          final body = Uint8List(mc.aboffsetEnd - mc.aboffset);
          for (var k = 0; k < body.length; k++) {
            body[k] = mc.readByte() & 0xff;
          }
          expect(mc.hasMoreData(), isFalse);
          bodies.add(body);
          total += body.length;
          final parts = expectedNodes[i].split(' ');
          expect(
            body.length,
            int.parse(parts[0]),
            reason: 'body length of node $i (id ${ids[i]})',
          );
          expect(
            Crc32.crc(body, 0, body.length),
            int.parse(parts[1]),
            reason: 'body crc of node $i (id ${ids[i]})',
          );
        }
        expect(total, listing['bodiesTotal']);
        final all = Uint8List(total);
        var off = 0;
        for (final b in bodies) {
          all.setRange(off, off + b.length, b);
          off += b.length;
        }
        expect(Crc32.crc(all, 0, total), listing['bodiesCrc']);
        expect(
          mc.getAndClear(ids[0]),
          isFalse,
          reason: 'a consumed node is not found again',
        );
      });

      test(
        'the first ${(listing['heads'] as List).length} nodes match the Java body hex',
        () {
          final heads = (listing['heads'] as List<dynamic>).cast<String>();
          for (var i = 0; i < heads.length; i++) {
            final parts = heads[i].split(' ');
            expect(ids[i], int.parse(parts[0]));
            expect(hex(bodies[i]), parts[1], reason: 'body of node $i');
          }
        },
      );

      test(
        'the node/link listing equals the committed dump-microcache sample',
        () {
          final sample = jsonDecode(
            File(samplePath).readAsStringSync(),
          ) as Map<String, dynamic>;
          expect(sample['lonIdx'], lonIdx);
          expect(sample['latIdx'], latIdx);
          expect(sample['microcacheNodes'], listing['size']);
          expect(sample['microcacheDataSize'], listing['dataSize']);
          final nodes = (sample['nodes'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
          expect(nodes.length, sample['limit']);

          // walk a fresh decode the way Dump.java does
          final fresh = MicroCache2.decode(
            StatCoderContext(raw),
            DataBuffers(),
            lonIdx,
            latIdx,
            divisor,
            null,
            null,
          );
          for (var i = 0; i < nodes.length; i++) {
            final id = fresh.getIdForIndex(i);
            expect(fresh.getAndClear(id), isTrue);
            final ilon = i32(id >> 32);
            final ilat = i32(id & 0xffffffff);
            final n = _parseNodeBody(fresh, ilon, ilat);
            final exp = nodes[i];
            expect(id, exp['id64'], reason: 'node $i id');
            expect(ilon, exp['ilon']);
            expect(ilat, exp['ilat']);
            expect(n.selev, exp['selev'], reason: 'node $i selev');
            expect(
              n.nodeDescription == null ? null : hex(n.nodeDescription!),
              exp['nodeDescription'],
              reason: 'node $i nodeDescription',
            );
            expect(
              n.turnRestrictions,
              exp['turnRestrictions'],
              reason: 'node $i turnRestrictions',
            );
            final expLinks = (exp['links'] as List<dynamic>)
                .cast<Map<String, dynamic>>();
            expect(
              n.links.length,
              expLinks.length,
              reason: 'node $i link count',
            );
            for (var k = 0; k < expLinks.length; k++) {
              final l = n.links[k];
              final e = expLinks[k];
              expect(l.targetIlon, e['targetIlon'], reason: 'node $i link $k');
              expect(l.targetIlat, e['targetIlat'], reason: 'node $i link $k');
              expect(
                l.reverse,
                e['reverse'],
                reason: 'node $i link $k reverse',
              );
              expect(
                l.desc == null ? null : hex(l.desc!),
                e['descriptionBitmap'],
                reason: 'node $i link $k descriptionBitmap',
              );
              expect(
                l.geometry == null ? null : hex(l.geometry!),
                e['geometryBytes'],
                reason: 'node $i link $k geometryBytes',
              );
            }
          }
        },
      );

      test(
        'encodeMicroCache reproduces the rd5 bytes and survives a round trip',
        () {
          final re = (listing['reencoded'] as Map<String, dynamic>);
          final mc2 = MicroCache2.decode(
            StatCoderContext(raw),
            DataBuffers(),
            lonIdx,
            latIdx,
            divisor,
            null,
            null,
          );
          final encbuf = Uint8List(2 * raw.length + 65536);
          final enclen = mc2.encodeMicroCache(encbuf);
          expect(enclen, re['length']);
          expect(Crc32.crc(encbuf, 0, enclen), re['crc']);
          expect(hex(encbuf, 64), re['head']);
          // Java produced exactly the rd5 data again; so must we
          expect(enclen, raw.length - 4);
          expect(hex(encbuf, enclen), hex(raw, raw.length - 4));
          final mc3 = MicroCache2.decode(
            StatCoderContext(Uint8List.sublistView(encbuf, 0, enclen + 8)),
            DataBuffers(),
            lonIdx,
            latIdx,
            divisor,
            null,
            null,
          );
          expect(mc2.compareWith(mc3), re['compare']);
        },
      );

      test(
        'shrinkId / expandId / isInternal are consistent for every node',
        () {
          final size = mc.getSize();
          for (var i = 0; i < size; i++) {
            final id = ids[i];
            expect(mc.expandId(mc.shrinkId(id)), id);
            expect(mc.isInternal(i32(id >> 32), i32(id & 0xffffffff)), isTrue);
          }
          expect(
            mc.isInternal(
              lonIdx * (1000000 ~/ divisor) - 1,
              latIdx * (1000000 ~/ divisor),
            ),
            isFalse,
          );
        },
      );

      test('collect() after consuming every node empties the cache', () {
        final deleted = mc.collect(0);
        expect(deleted, listing['dataSize']);
        expect(mc.getSize(), 0);
        expect(mc.virgin, isFalse);
      });
    });
  }
}

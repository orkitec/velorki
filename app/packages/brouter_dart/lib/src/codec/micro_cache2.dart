// Port of btools.codec.MicroCache2 (BRouter v1.7.10).

import 'dart:typed_data';

import '../jvm.dart';
import '../util/byte_data_reader.dart';
import '../util/i_byte_array_unifier.dart';
import 'data_buffers.dart';
import 'integer_fifo3_pass.dart';
import 'linked_list_container.dart';
import 'micro_cache.dart';
import 'noisy_diff_coder.dart';
import 'stat_coder_context.dart';
import 'tag_value_coder.dart';
import 'tag_value_validator.dart';
import 'tag_value_wrapper.dart';
import 'waypoint_matcher.dart';

/// MicroCache2 is the new format that uses statistical encoding and
/// is able to do access filtering and waypoint matching during encoding
class MicroCache2 extends MicroCache {
  /// `MicroCache2(int size, byte[] databuffer, int lonIdx, int latIdx, int divisor)`:
  /// an empty cache to be filled through the writer methods.
  MicroCache2(
    int size,
    Uint8List databuffer,
    int lonIdx,
    int latIdx,
    int divisor,
  ) : _cellsize = 1000000 ~/ divisor,
      _lonBase = lonIdx * (1000000 ~/ divisor),
      _latBase = latIdx * (1000000 ~/ divisor),
      super(databuffer) {
    // sets ab=databuffer, aboffset=0
    faid = Int32List(size);
    fapos = Int32List(size);
    this.size = 0;
  }

  final int _lonBase;
  final int _latBase;
  final int _cellsize;

  Uint8List readUnified(int len, IByteArrayUnifier u) {
    final b = u.unify(ab, aboffset, len);
    aboffset += len;
    return b;
  }

  /// `MicroCache2(StatCoderContext bc, DataBuffers dataBuffers, int lonIdx, int latIdx,
  /// int divisor, TagValueValidator wayValidator, WaypointMatcher waypointMatcher)`:
  /// decode a cache from the data-file format.
  MicroCache2.decode(
    StatCoderContext bc,
    DataBuffers dataBuffers,
    int lonIdx,
    int latIdx,
    int divisor,
    TagValueValidator? wayValidator,
    WaypointMatcher? waypointMatcher,
  ) : _cellsize = 1000000 ~/ divisor,
      _lonBase = lonIdx * (1000000 ~/ divisor),
      _latBase = latIdx * (1000000 ~/ divisor),
      super(null) {
    final wayTagCoder = TagValueCoder.decoder(bc, dataBuffers, wayValidator);
    final nodeTagCoder = TagValueCoder.decoder(bc, dataBuffers, null);
    final nodeIdxDiff = NoisyDiffCoder.decoder(bc);
    final nodeEleDiff = NoisyDiffCoder.decoder(bc);
    final extLonDiff = NoisyDiffCoder.decoder(bc);
    final extLatDiff = NoisyDiffCoder.decoder(bc);
    final transEleDiff = NoisyDiffCoder.decoder(bc);

    size = bc.decodeNoisyNumber(5);
    faid = size > dataBuffers.ibuf2.length
        ? Int32List(size)
        : dataBuffers.ibuf2;
    fapos = size > dataBuffers.ibuf3.length
        ? Int32List(size)
        : dataBuffers.ibuf3;

    final alon = size > dataBuffers.alon.length
        ? Int32List(size)
        : dataBuffers.alon;
    final alat = size > dataBuffers.alat.length
        ? Int32List(size)
        : dataBuffers.alat;

    if (MicroCache.debug) {
      print(
        '*** decoding cache of size=$size for lonIdx=$lonIdx latIdx=$latIdx',
      );
    }

    bc.decodeSortedArray(faid, 0, size, 29, 0);

    for (var n = 0; n < size; n++) {
      final id64 = expandId(faid[n]);
      alon[n] = i32(id64 >> 32);
      alat[n] = i32(id64 & 0xffffffff);
    }

    final netdatasize = bc.decodeNoisyNumber(10);
    ab = netdatasize > dataBuffers.bbuf1.length
        ? Uint8List(netdatasize)
        : dataBuffers.bbuf1;
    aboffset = 0;

    final validBits = Int32List((size + 31) >> 5);

    var finaldatasize = 0;

    final reverseLinks = LinkedListContainer(size, dataBuffers.ibuf1);

    var selev = 0;
    for (var n = 0; n < size; n++) {
      // loop over nodes
      final ilon = alon[n];
      final ilat = alat[n];

      // future escapes (turn restrictions?)
      var trExceptions = 0;
      var featureId = bc.decodeVarBits();
      if (featureId == 13) {
        fapos[n] = aboffset;
        validBits[n >> 5] |= shl32(1, n); // mark dummy-node valid
        continue; // empty node escape (delta files only)
      }
      while (featureId != 0) {
        final bitsize = bc.decodeNoisyNumber(5);

        if (featureId == 2) {
          // exceptions to turn-restriction
          trExceptions = toShort(bc.decodeBounded(1023));
        } else if (featureId == 1) {
          // turn-restriction
          writeBoolean(true);
          writeShort(trExceptions); // exceptions from previous feature
          trExceptions = 0;

          writeBoolean(bc.decodeBit()); // isPositive
          writeInt(i32(ilon + bc.decodeNoisyDiff(10))); // fromLon
          writeInt(i32(ilat + bc.decodeNoisyDiff(10))); // fromLat
          writeInt(i32(ilon + bc.decodeNoisyDiff(10))); // toLon
          writeInt(i32(ilat + bc.decodeNoisyDiff(10))); // toLat
        } else {
          for (var i = 0; i < bitsize; i++) {
            bc.decodeBit(); // unknown feature, just skip
          }
        }
        featureId = bc.decodeVarBits();
      }
      writeBoolean(false);

      selev = i32(selev + nodeEleDiff.decodeSignedValue());
      writeShort(toShort(selev));
      final nodeTags = nodeTagCoder.decodeTagValueSet();
      writeVarBytes(nodeTags?.data);

      final links = bc.decodeNoisyNumber(1);
      if (MicroCache.debug) {
        print('***   decoding node $ilon/$ilat with links=$links');
      }
      for (var li = 0; li < links; li++) {
        var sizeoffset = 0;
        final nodeIdx = i32(n + nodeIdxDiff.decodeSignedValue());

        int dlonRemaining;
        int dlatRemaining;

        var isReverse = false;
        if (nodeIdx != n) {
          // internal (forward-) link
          dlonRemaining = i32(alon[nodeIdx] - ilon);
          dlatRemaining = i32(alat[nodeIdx] - ilat);
        } else {
          isReverse = bc.decodeBit();
          dlonRemaining = extLonDiff.decodeSignedValue();
          dlatRemaining = extLatDiff.decodeSignedValue();
        }
        if (MicroCache.debug) {
          print(
            '***     decoding link to ${ilon + dlonRemaining}/${ilat + dlatRemaining} extern=${nodeIdx == n}',
          );
        }

        final TagValueWrapper? wayTags = wayTagCoder.decodeTagValueSet();

        final linkValid = wayTags != null || wayValidator == null;
        if (linkValid) {
          final startPointer = aboffset;
          sizeoffset = writeSizePlaceHolder();

          writeVarLengthSigned(dlonRemaining);
          writeVarLengthSigned(dlatRemaining);

          validBits[n >> 5] |= shl32(1, n); // mark source-node valid
          if (nodeIdx != n) {
            // valid internal (forward-) link
            reverseLinks.addDataElement(nodeIdx, n); // register reverse link
            finaldatasize +=
                1 + aboffset - startPointer; // reserve place for reverse
            validBits[nodeIdx >> 5] |= shl32(
              1,
              nodeIdx,
            ); // mark target-node valid
          }
          writeModeAndDesc(isReverse, wayTags?.data);
        }

        if (!isReverse) {
          // write geometry for forward links only
          var matcher = wayTags == null || wayTags.accessType < 2
              ? null
              : waypointMatcher;
          final ilontarget = i32(ilon + dlonRemaining);
          final ilattarget = i32(ilat + dlatRemaining);
          if (matcher != null) {
            final useAsStartWay = wayValidator!.checkStartWay(wayTags!.data!);
            if (!matcher.start(
              ilon,
              ilat,
              ilontarget,
              ilattarget,
              useAsStartWay,
            )) {
              matcher = null;
            }
          }

          final transcount = bc.decodeVarBits();
          if (MicroCache.debug) {
            print('***       decoding geometry with count=$transcount');
          }
          var count = transcount + 1;
          for (var i = 0; i < transcount; i++) {
            final dlon = bc.decodePredictedValue(dlonRemaining ~/ count);
            final dlat = bc.decodePredictedValue(dlatRemaining ~/ count);
            dlonRemaining = i32(dlonRemaining - dlon);
            dlatRemaining = i32(dlatRemaining - dlat);
            count--;
            final elediff = transEleDiff.decodeSignedValue();
            if (wayTags != null) {
              writeVarLengthSigned(dlon);
              writeVarLengthSigned(dlat);
              writeVarLengthSigned(elediff);
            }

            if (matcher != null) {
              matcher.transferNode(
                i32(ilontarget - dlonRemaining),
                i32(ilattarget - dlatRemaining),
              );
            }
          }
          if (matcher != null) matcher.end();
        }
        if (linkValid) {
          injectSize(sizeoffset);
        }
      }
      fapos[n] = aboffset;
    }

    // calculate final data size
    var finalsize = 0;
    var startpos = 0;
    for (var i = 0; i < size; i++) {
      final endpos = fapos[i];
      if ((validBits[i >> 5] & shl32(1, i)) != 0) {
        finaldatasize += endpos - startpos;
        finalsize++;
      }
      startpos = endpos;
    }
    // append the reverse links at the end of each node
    final abOld = ab;
    final faidOld = faid;
    final faposOld = fapos;
    final sizeOld = size;
    ab = Uint8List(finaldatasize);
    faid = Int32List(finalsize);
    fapos = Int32List(finalsize);
    aboffset = 0;
    size = 0;

    startpos = 0;
    for (var n = 0; n < sizeOld; n++) {
      final endpos = faposOld[n];
      if ((validBits[n >> 5] & shl32(1, n)) != 0) {
        final len = endpos - startpos;
        ab.setRange(aboffset, aboffset + len, abOld, startpos);
        if (MicroCache.debug) {
          print('*** copied $len bytes from $aboffset for node $n');
        }
        aboffset += len;

        final cnt = reverseLinks.initList(n);
        if (MicroCache.debug) {
          print('*** appending $cnt reverse links for node $n');
        }

        for (var ri = 0; ri < cnt; ri++) {
          final nodeIdx = reverseLinks.getDataElement();
          final sizeoffset = writeSizePlaceHolder();
          writeVarLengthSigned(i32(alon[nodeIdx] - alon[n]));
          writeVarLengthSigned(i32(alat[nodeIdx] - alat[n]));
          writeModeAndDesc(true, null);
          injectSize(sizeoffset);
        }
        faid[size] = faidOld[n];
        fapos[size] = aboffset;
        size++;
      }
      startpos = endpos;
    }
    init(size);
  }

  @override
  int expandId(int id32) {
    var dlon = 0;
    var dlat = 0;

    for (var bm = 1; bm < 0x8000; bm <<= 1) {
      if ((id32 & 1) != 0) dlon |= bm;
      if ((id32 & 2) != 0) dlat |= bm;
      id32 = shr32(id32, 2);
    }

    final lon32 = i32(_lonBase + dlon);
    final lat32 = i32(_latBase + dlat);

    return (lon32 << 32) | lat32;
  }

  @override
  int shrinkId(int id64) {
    final lon32 = i32(id64 >> 32);
    final lat32 = i32(id64 & 0xffffffff);
    final dlon = i32(lon32 - _lonBase);
    final dlat = i32(lat32 - _latBase);
    var id32 = 0;

    for (var bm = 0x4000; bm > 0; bm >>= 1) {
      id32 = shl32(id32, 2);
      if ((dlon & bm) != 0) id32 |= 1;
      if ((dlat & bm) != 0) id32 |= 2;
    }
    return id32;
  }

  @override
  bool isInternal(int ilon, int ilat) {
    return ilon >= _lonBase &&
        ilon < _lonBase + _cellsize &&
        ilat >= _latBase &&
        ilat < _latBase + _cellsize;
  }

  @override
  int encodeMicroCache(Uint8List buffer) {
    final idMap = <int, int>{};
    for (var n = 0; n < size; n++) {
      // loop over nodes
      idMap[expandId(faid[n])] = n;
    }

    final linkCounts = IntegerFifo3Pass(256);
    final transCounts = IntegerFifo3Pass(256);
    final restrictionBits = IntegerFifo3Pass(16);

    final wayTagCoder = TagValueCoder();
    final nodeTagCoder = TagValueCoder();
    final nodeIdxDiff = NoisyDiffCoder();
    final nodeEleDiff = NoisyDiffCoder();
    final extLonDiff = NoisyDiffCoder();
    final extLatDiff = NoisyDiffCoder();
    final transEleDiff = NoisyDiffCoder();

    var netdatasize = 0;

    for (var pass = 1; ; pass++) {
      // 3 passes: counters, stat-collection, encoding
      final dostats = pass == 3;
      final dodebug = MicroCache.debug && pass == 3;

      if (pass < 3) netdatasize = fapos[size - 1];

      final bc = StatCoderContext(buffer);

      linkCounts.init();
      transCounts.init();
      restrictionBits.init();

      wayTagCoder.encodeDictionary(bc);
      if (dostats) bc.assignBits('wayTagDictionary');
      nodeTagCoder.encodeDictionary(bc);
      if (dostats) bc.assignBits('nodeTagDictionary');
      nodeIdxDiff.encodeDictionary(bc);
      nodeEleDiff.encodeDictionary(bc);
      extLonDiff.encodeDictionary(bc);
      extLatDiff.encodeDictionary(bc);
      transEleDiff.encodeDictionary(bc);
      if (dostats) bc.assignBits('noisebits');
      bc.encodeNoisyNumber(size, 5);
      if (dostats) bc.assignBits('nodecount');
      bc.encodeSortedArray(faid, 0, size, 0x20000000, 0);
      if (dostats) bc.assignBits('node-positions');
      bc.encodeNoisyNumber(netdatasize, 10); // net-size
      if (dostats) bc.assignBits('netdatasize');
      if (dodebug) print('*** encoding cache of size=$size');
      var lastSelev = 0;

      for (var n = 0; n < size; n++) {
        // loop over nodes
        aboffset = startPos(n);
        aboffsetEnd = fapos[n];
        if (dodebug) {
          print('*** encoding node $n from $aboffset to $aboffsetEnd');
        }

        final id64 = expandId(faid[n]);
        final ilon = i32(id64 >> 32);
        final ilat = i32(id64 & 0xffffffff);

        if (aboffset == aboffsetEnd) {
          bc.encodeVarBits(13); // empty node escape (delta files only)
          continue;
        }

        // write turn restrictions
        while (readBoolean()) {
          final exceptions = readShort(); // except bikes, psv, ...
          if (exceptions != 0) {
            bc.encodeVarBits(2); // 2 = tr exceptions
            bc.encodeNoisyNumber(10, 5); // bit-count
            bc.encodeBounded(1023, exceptions & 1023);
          }
          bc.encodeVarBits(1); // 1 = turn restriction
          bc.encodeNoisyNumber(
            restrictionBits.getNext(),
            5,
          ); // bit-count using look-ahead fifo
          final b0 = bc.getWritingBitPosition();
          bc.encodeBit(readBoolean()); // isPositive
          bc.encodeNoisyDiff(i32(readInt() - ilon), 10); // fromLon
          bc.encodeNoisyDiff(i32(readInt() - ilat), 10); // fromLat
          bc.encodeNoisyDiff(i32(readInt() - ilon), 10); // toLon
          bc.encodeNoisyDiff(i32(readInt() - ilat), 10); // toLat
          restrictionBits.add(i32(bc.getWritingBitPosition() - b0));
        }
        bc.encodeVarBits(0); // end of extra data

        if (dostats) bc.assignBits('extradata');

        final selev = readShort();
        nodeEleDiff.encodeSignedValue(selev - lastSelev);
        if (dostats) bc.assignBits('nodeele');
        lastSelev = selev;
        nodeTagCoder.encodeTagValueSet(readVarBytes());
        if (dostats) bc.assignBits('nodeTagIdx');
        var nlinks = linkCounts.getNext();
        if (dodebug) print('*** nlinks=$nlinks');
        bc.encodeNoisyNumber(nlinks, 1);
        if (dostats) bc.assignBits('link-counts');

        nlinks = 0;
        while (hasMoreData()) {
          // loop over links
          // read link data
          final startPointer = aboffset;
          final endPointer = getEndPointer();

          final ilonlink = i32(ilon + readVarLengthSigned());
          final ilatlink = i32(ilat + readVarLengthSigned());

          final sizecode = readVarLengthUnsigned();
          final isReverse = (sizecode & 1) != 0;
          final descSize = sizecode >> 1;
          Uint8List? description;
          if (descSize > 0) {
            description = Uint8List(descSize);
            readFully(description);
          }

          final link64 = (ilonlink << 32) | ilatlink;
          final idx = idMap[link64];
          final isInternal = idx != null;

          if (isReverse && isInternal) {
            if (dodebug) {
              print(
                '*** NOT encoding link reverse=$isReverse internal=$isInternal',
              );
            }
            netdatasize -= aboffset - startPointer;
            continue; // do not encode internal reverse links
          }
          if (dodebug) {
            print('*** encoding link reverse=$isReverse internal=$isInternal');
          }
          nlinks++;

          if (isInternal) {
            final nodeIdx = idx;
            if (dodebug) print('*** target nodeIdx=$nodeIdx');
            if (nodeIdx == n) throw StateError('ups: self ref?');
            nodeIdxDiff.encodeSignedValue(nodeIdx - n);
            if (dostats) bc.assignBits('nodeIdx');
          } else {
            nodeIdxDiff.encodeSignedValue(0);
            bc.encodeBit(isReverse);
            extLonDiff.encodeSignedValue(i32(ilonlink - ilon));
            extLatDiff.encodeSignedValue(i32(ilatlink - ilat));
            if (dostats) bc.assignBits('externalNode');
          }
          wayTagCoder.encodeTagValueSet(description);
          if (dostats) bc.assignBits('wayDescIdx');

          if (!isReverse) {
            final geometry = readDataUntil(endPointer);
            // write transition nodes
            var count = transCounts.getNext();
            if (dodebug) print('*** encoding geometry with count=$count');
            bc.encodeVarBits(count++);
            if (dostats) bc.assignBits('transcount');
            var transcount = 0;
            if (geometry != null) {
              var dlonRemaining = i32(ilonlink - ilon);
              var dlatRemaining = i32(ilatlink - ilat);

              final r = ByteDataReader(geometry);
              while (r.hasMoreData()) {
                transcount++;

                final dlon = r.readVarLengthSigned();
                final dlat = r.readVarLengthSigned();
                bc.encodePredictedValue(dlon, dlonRemaining ~/ count);
                bc.encodePredictedValue(dlat, dlatRemaining ~/ count);
                dlonRemaining = i32(dlonRemaining - dlon);
                dlatRemaining = i32(dlatRemaining - dlat);
                if (count > 1) count--;
                if (dostats) bc.assignBits('transpos');
                transEleDiff.encodeSignedValue(r.readVarLengthSigned());
                if (dostats) bc.assignBits('transele');
              }
            }
            transCounts.add(transcount);
          }
        }
        linkCounts.add(nlinks);
      }
      if (pass == 3) {
        return bc.closeAndGetEncodedLength();
      }
    }
  }
}

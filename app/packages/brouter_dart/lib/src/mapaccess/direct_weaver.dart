// Port of btools.mapaccess.DirectWeaver (BRouter v1.7.10).

import 'dart:typed_data';

import '../codec/data_buffers.dart';
import '../codec/noisy_diff_coder.dart';
import '../codec/stat_coder_context.dart';
import '../codec/tag_value_coder.dart';
import '../codec/tag_value_validator.dart';
import '../codec/tag_value_wrapper.dart';
import '../codec/waypoint_matcher.dart';
import '../jvm.dart';
import '../util/byte_data_writer.dart';
import 'osm_link.dart';
import 'osm_node.dart';
import 'osm_nodes_map.dart';
import 'turn_restriction.dart';

/// DirectWeaver does the same decoding as MicroCache2, but decodes directly
/// into the instance-graph, not into the intermediate nodes-cache
///
/// This is the path the router takes in 1.7.10 (`NodesCache.directWeaving`
/// defaults to true); `MicroCache2` decoding is only used with
/// `-DdisableDirectWeaving=true`, by `AreaReader` and by the dump tools.
class DirectWeaver extends ByteDataWriter {
  DirectWeaver(
    StatCoderContext bc,
    DataBuffers dataBuffers,
    int lonIdx,
    int latIdx,
    int divisor,
    TagValueValidator? wayValidator,
    WaypointMatcher? waypointMatcher,
    OsmNodesMap hollowNodes,
  ) : super(null) {
    final cellsize = 1000000 ~/ divisor;
    _id64Base = (i32(lonIdx * cellsize) << 32) | i32(latIdx * cellsize);

    final wayTagCoder = TagValueCoder.decoder(bc, dataBuffers, wayValidator);
    final nodeTagCoder = TagValueCoder.decoder(bc, dataBuffers, null);
    final nodeIdxDiff = NoisyDiffCoder.decoder(bc);
    final nodeEleDiff = NoisyDiffCoder.decoder(bc);
    final extLonDiff = NoisyDiffCoder.decoder(bc);
    final extLatDiff = NoisyDiffCoder.decoder(bc);
    final transEleDiff = NoisyDiffCoder.decoder(bc);

    final size = bc.decodeNoisyNumber(5);

    final faid = size > dataBuffers.ibuf2.length
        ? Int32List(size)
        : dataBuffers.ibuf2;

    bc.decodeSortedArray(faid, 0, size, 29, 0);

    final nodes = List<OsmNode>.generate(size, (n) {
      final id = expandId(faid[n]);
      final ilon = i32(id >> 32);
      final ilat = i32(id & 0xffffffff);
      var node = hollowNodes.get(ilon, ilat);
      if (node == null) {
        node = OsmNode(ilon, ilat);
      } else {
        node.visitID = 1;
        hollowNodes.remove(node);
      }
      return node;
    }, growable: false);

    bc.decodeNoisyNumber(10); // netdatasize (not needed for direct weaving)
    ab = dataBuffers.bbuf1;
    aboffset = 0;

    var selev = 0;
    for (var n = 0; n < size; n++) {
      // loop over nodes
      final node = nodes[n];
      final ilon = node.ilon;
      final ilat = node.ilat;

      // future escapes (turn restrictions?)
      var trExceptions = 0;
      for (;;) {
        final featureId = bc.decodeVarBits();
        if (featureId == 0) break;
        final bitsize = bc.decodeNoisyNumber(5);

        if (featureId == 2) {
          // exceptions to turn-restriction
          trExceptions = toShort(bc.decodeBounded(1023));
        } else if (featureId == 1) {
          // turn-restriction
          final tr = TurnRestriction();
          tr.exceptions = trExceptions;
          trExceptions = 0;
          tr.isPositive = bc.decodeBit();
          tr.fromLon = i32(ilon + bc.decodeNoisyDiff(10));
          tr.fromLat = i32(ilat + bc.decodeNoisyDiff(10));
          tr.toLon = i32(ilon + bc.decodeNoisyDiff(10));
          tr.toLat = i32(ilat + bc.decodeNoisyDiff(10));
          node.addTurnRestriction(tr);
        } else {
          for (var i = 0; i < bitsize; i++) {
            bc.decodeBit(); // unknown feature, just skip
          }
        }
      }

      selev = i32(selev + nodeEleDiff.decodeSignedValue());
      node.selev = toShort(selev);
      final nodeTags = nodeTagCoder.decodeTagValueSet();
      node.nodeDescription = nodeTags?.data; // TODO: unified?

      final links = bc.decodeNoisyNumber(1);
      for (var li = 0; li < links; li++) {
        final nodeIdx = i32(n + nodeIdxDiff.decodeSignedValue());

        int dlonRemaining;
        int dlatRemaining;

        var isReverse = false;
        if (nodeIdx != n) {
          // internal (forward-) link
          dlonRemaining = i32(nodes[nodeIdx].ilon - ilon);
          dlatRemaining = i32(nodes[nodeIdx].ilat - ilat);
        } else {
          isReverse = bc.decodeBit();
          dlonRemaining = extLonDiff.decodeSignedValue();
          dlatRemaining = extLatDiff.decodeSignedValue();
        }

        final TagValueWrapper? wayTags = wayTagCoder.decodeTagValueSet();

        final linklon = i32(ilon + dlonRemaining);
        final linklat = i32(ilat + dlatRemaining);
        aboffset = 0;
        if (!isReverse) {
          // write geometry for forward links only
          var matcher = wayTags == null || wayTags.accessType < 2
              ? null
              : waypointMatcher;
          final ilontarget = i32(ilon + dlonRemaining);
          final ilattarget = i32(ilat + dlatRemaining);
          if (matcher != null) {
            final useAsStartWay =
                wayTags == null || wayValidator!.checkStartWay(wayTags.data!);
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

        if (wayTags != null) {
          Uint8List? geometry;
          if (aboffset > 0) {
            geometry = Uint8List(aboffset);
            geometry.setRange(0, aboffset, ab);
          }

          if (nodeIdx != n) {
            // valid internal (forward-) link
            final node2 = nodes[nodeIdx];
            final link = node.isLinkUnused()
                ? node
                : (node2.isLinkUnused() ? node2 : OsmLink());
            link.descriptionBitmap = wayTags.data;
            link.geometry = geometry;
            node.addLink(link, isReverse, node2);
          } else {
            // weave external link
            node.addLinkTo(
              linklon,
              linklat,
              wayTags.data,
              geometry,
              hollowNodes,
              isReverse,
            );
            node.visitID = 1;
          }
        }
      } // ... loop over links
    } // ... loop over nodes

    hollowNodes.cleanupAndCount(nodes);
  }

  late final int _id64Base;

  static final Int64List _id32_00 = _buildTable(0);
  static final Int64List _id32_10 = _buildTable(10);
  static final Int64List _id32_20 = _buildTable(20);

  static Int64List _buildTable(int shift) {
    final t = Int64List(1024);
    for (var i = 0; i < 1024; i++) {
      t[i] = _expandId(i << shift);
    }
    return t;
  }

  static int _expandId(int id32) {
    var dlon = 0;
    var dlat = 0;

    for (var bm = 1; bm < 0x8000; bm <<= 1) {
      if ((id32 & 1) != 0) dlon |= bm;
      if ((id32 & 2) != 0) dlat |= bm;
      id32 = shr32(id32, 2);
    }
    return (dlon << 32) | dlat;
  }

  int expandId(int id32) {
    return _id64Base +
        _id32_00[id32 & 1023] +
        _id32_10[shr32(id32, 10) & 1023] +
        _id32_20[shr32(id32, 20) & 1023];
  }
}

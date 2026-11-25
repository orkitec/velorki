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
import 'woven_cell.dart';

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
    OsmNodesMap hollowNodes, [
    WovenCell? rec,
  ]) : super(null) {
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

    if (rec != null) rec.add(size);
    final nodes = List<OsmNode>.generate(size, (n) {
      final id = expandId(faid[n]);
      final ilon = i32(id >> 32);
      final ilat = i32(id & 0xffffffff);
      if (rec != null) {
        rec.add(ilon);
        rec.add(ilat);
      }
      return _obtainNode(ilon, ilat, hollowNodes);
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
          if (rec != null) {
            rec.add(1);
            rec.add(tr.exceptions);
            rec.add(tr.isPositive ? 1 : 0);
            rec.add(tr.fromLon);
            rec.add(tr.fromLat);
            rec.add(tr.toLon);
            rec.add(tr.toLat);
          }
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
      if (rec != null) {
        rec.add(0); // no more turn restrictions
        rec.add(selev);
        rec.addObject(node.nodeDescription);
        rec.add(links);
      }
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

        Uint8List? geometry;
        if (wayTags != null && aboffset > 0) {
          geometry = Uint8List(aboffset);
          geometry.setRange(0, aboffset, ab);
        }
        if (rec != null) {
          rec.add(nodeIdx);
          rec.add(isReverse ? 1 : 0);
          rec.add(linklon);
          rec.add(linklat);
          rec.addObject(wayTags);
          if (wayTags != null) rec.addGeometry(geometry);
        }
        if (wayTags != null) {
          _weaveLink(
            node,
            n,
            nodeIdx,
            nodes,
            linklon,
            linklat,
            wayTags,
            geometry,
            isReverse,
            hollowNodes,
          );
        }
      } // ... loop over links
    } // ... loop over nodes

    hollowNodes.cleanupAndCount(nodes);
    if (rec != null) rec.freeze();
  }

  /// Weave a micro-cache that was decoded before into the instance-graph,
  /// from its recording: the same nodes, links and turn restrictions in the
  /// same order as the decoding constructor creates them.
  DirectWeaver.fromWovenCell(WovenCell cell, OsmNodesMap hollowNodes)
    : super(null) {
    final ints = cell.ints;
    final objs = cell.objs;
    var ii = 0;
    var oi = 0;

    final size = ints[ii++];
    final nodes = List<OsmNode>.generate(size, (n) {
      final ilon = ints[ii++];
      final ilat = ints[ii++];
      return _obtainNode(ilon, ilat, hollowNodes);
    }, growable: false);

    for (var n = 0; n < size; n++) {
      // loop over nodes
      final node = nodes[n];

      while (ints[ii++] != 0) {
        final tr = TurnRestriction();
        tr.exceptions = toShort(ints[ii++]);
        tr.isPositive = ints[ii++] != 0;
        tr.fromLon = ints[ii++];
        tr.fromLat = ints[ii++];
        tr.toLon = ints[ii++];
        tr.toLat = ints[ii++];
        node.addTurnRestriction(tr);
      }

      node.selev = toShort(ints[ii++]);
      node.nodeDescription = objs[oi++] as Uint8List?;

      final links = ints[ii++];
      for (var li = 0; li < links; li++) {
        final nodeIdx = ints[ii++];
        final isReverse = ints[ii++] != 0;
        final linklon = ints[ii++];
        final linklat = ints[ii++];
        final wayTags = objs[oi++] as TagValueWrapper?;
        if (wayTags != null) {
          final geometry = objs[oi++] as Uint8List?;
          _weaveLink(
            node,
            n,
            nodeIdx,
            nodes,
            linklon,
            linklat,
            wayTags,
            geometry,
            isReverse,
            hollowNodes,
          );
        }
      } // ... loop over links
    } // ... loop over nodes

    hollowNodes.cleanupAndCount(nodes);
  }

  static OsmNode _obtainNode(int ilon, int ilat, OsmNodesMap hollowNodes) {
    var node = hollowNodes.get(ilon, ilat);
    if (node == null) {
      node = OsmNode(ilon, ilat);
    } else {
      node.visitID = 1;
      hollowNodes.remove(node);
    }
    return node;
  }

  static void _weaveLink(
    OsmNode node,
    int n,
    int nodeIdx,
    List<OsmNode> nodes,
    int linklon,
    int linklat,
    TagValueWrapper wayTags,
    Uint8List? geometry,
    bool isReverse,
    OsmNodesMap hollowNodes,
  ) {
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

// Port of btools.router.OsmTrack (BRouter v1.7.10).
//
// Container for a track

import 'dart:io';
import 'dart:typed_data';

import '../jvm.dart';
import '../mapaccess/matched_waypoint.dart';
import '../mapaccess/osm_pos.dart';
import '../util/compact_long_map.dart';
import '../util/frozen_long_map.dart';
import '../version.dart';
import 'message_data.dart';
import 'osm_node_named.dart';
import 'osm_path_element.dart';
import 'routing_context.dart';
import 'voice_hint.dart';
import 'voice_hint_list.dart';
import 'voice_hint_processor.dart';

class OsmPathElementHolder {
  OsmPathElement? node;
  OsmPathElementHolder? nextHolder;
}

final class OsmTrack {
  /// `OsmTrack.class.getPackage().getImplementationVersion()`: the version of
  /// the upstream jar (the tag without its `v`).
  static final String version = upstreamVersion.startsWith('v')
      ? upstreamVersion.substring(1)
      : upstreamVersion;

  // csv-header-line
  static const String messagesHeader =
      'Longitude\tLatitude\tElevation\tDistance\tCostPerKm\tElevCost\tTurnCost\tNodeCost\tInitialCost\tWayTags\tNodeTags\tTime\tEnergy';

  MatchedWaypoint? endPoint;
  Int64List? nogoChecksums;
  int profileTimestamp = 0;
  bool isDirty = false;

  bool showspeed = false;
  bool showSpeedProfile = false;
  bool showTime = false;

  Map<String, String>? params;

  List<OsmNodeNamed> pois = <OsmNodeNamed>[];

  List<OsmPathElement> nodes = <OsmPathElement>[];

  CompactLongMap<OsmPathElementHolder>? _nodesMap;

  CompactLongMap<OsmPathElementHolder>? _detourMap;

  VoiceHintList? voiceHints;

  String? message;
  List<String>? messageList;

  String name = 'unset';

  List<MatchedWaypoint>? matchedWaypoints;
  bool exportWaypoints = false;
  bool exportCorrectedWaypoints = false;

  void addNode(OsmPathElement node) {
    nodes.insert(0, node);
  }

  void registerDetourForId(int id, OsmPathElement? detour) {
    _detourMap ??= CompactLongMap<OsmPathElementHolder>();
    final nh = OsmPathElementHolder();
    nh.node = detour;
    var h = _detourMap!.get(id);
    if (h != null) {
      while (h!.nextHolder != null) {
        h = h.nextHolder;
      }
      h.nextHolder = nh;
    } else {
      _detourMap!.fastPut(id, nh);
    }
  }

  void copyDetours(OsmTrack source) {
    _detourMap = source._detourMap == null
        ? null
        : FrozenLongMap<OsmPathElementHolder>(source._detourMap!);
  }

  void addDetours(OsmTrack source) {
    if (_detourMap != null) {
      final tmpDetourMap = CompactLongMap<OsmPathElementHolder>();

      final oldidlist = (_detourMap as FrozenLongMap<OsmPathElementHolder>)
          .getKeyArray();
      for (var i = 0; i < oldidlist.length; i++) {
        final id = oldidlist[i];
        final v = _detourMap!.get(id)!;

        tmpDetourMap.put(id, v);
      }

      if (source._detourMap != null) {
        final idlist =
            (source._detourMap as FrozenLongMap<OsmPathElementHolder>)
                .getKeyArray();
        for (var i = 0; i < idlist.length; i++) {
          final id = idlist[i];
          final v = source._detourMap!.get(id)!;
          if (!tmpDetourMap.contains(id) && source._nodesMap!.contains(id)) {
            tmpDetourMap.put(id, v);
          }
        }
      }
      _detourMap = FrozenLongMap<OsmPathElementHolder>(tmpDetourMap);
    }
  }

  OsmPathElement? lastorigin;

  void appendDetours(OsmTrack source) {
    _detourMap ??= source._detourMap == null
        ? null
        : CompactLongMap<OsmPathElementHolder>();
    if (source._detourMap != null) {
      final pos = nodes.length - source.nodes.length + 1;
      OsmPathElement? origin;
      if (pos > 0) origin = nodes[pos];
      assert(origin == null || true); // (unused upstream as well)
      for (final node in source.nodes) {
        final id = node.getIdFromPos();
        final nh = OsmPathElementHolder();
        if (node.origin == null && lastorigin != null) node.origin = lastorigin;
        nh.node = node;
        lastorigin = node;
        var h = _detourMap!.get(id);
        if (h != null) {
          while (h!.nextHolder != null) {
            h = h.nextHolder;
          }
          h.nextHolder = nh;
        } else {
          _detourMap!.fastPut(id, nh);
        }
      }
    }
  }

  void buildMap() {
    var nodesMap = CompactLongMap<OsmPathElementHolder>();
    for (final node in nodes) {
      final id = node.getIdFromPos();
      final nh = OsmPathElementHolder();
      nh.node = node;
      var h = nodesMap.get(id);
      if (h != null) {
        while (h!.nextHolder != null) {
          h = h.nextHolder;
        }
        h.nextHolder = nh;
      } else {
        nodesMap.fastPut(id, nh);
      }
    }
    nodesMap = FrozenLongMap<OsmPathElementHolder>(nodesMap);
    _nodesMap = nodesMap;
  }

  List<String> aggregateMessages() {
    final res = <String>[];
    MessageData? current;
    for (final n in nodes) {
      if (n.message != null && n.message!.wayKeyValues != null) {
        final md = n.message!.copy();
        if (current != null) {
          if (current.nodeKeyValues != null ||
              current.wayKeyValues != md.wayKeyValues) {
            res.add(current.toMessage()!);
          } else {
            md.add(current);
          }
        }
        current = md;
      }
    }
    if (current != null) {
      res.add(current.toMessage()!);
    }
    return res;
  }

  List<String> aggregateSpeedProfile() {
    final res = <String>[];
    var vmax = -1;
    var vmaxe = -1;
    var vmin = -1;
    var extraTime = 0;
    for (var i = nodes.length - 1; i > 0; i--) {
      final n = nodes[i];
      final m = n.message;
      final vnode = _getVNode(i);
      if (m != null &&
          (vmax != m.vmax ||
              vmin != m.vmin ||
              vmaxe != m.vmaxExplicit ||
              vnode < m.vmax ||
              extraTime != m.extraTime)) {
        vmax = m.vmax;
        vmin = m.vmin;
        vmaxe = m.vmaxExplicit;
        extraTime = m.extraTime;
        res.add('$i,$vmaxe,$vmax,$vmin,$vnode,$extraTime');
      }
    }
    return res;
  }

  /// writes the track in binary-format to a file
  void writeBinary(String filename) {
    final dos = DataOutputStream();

    endPoint!.writeToStream(dos);
    dos.writeInt(nodes.length);
    for (final node in nodes) {
      node.writeToStream(dos);
    }
    dos.writeLong(nogoChecksums![0]);
    dos.writeLong(nogoChecksums![1]);
    dos.writeLong(nogoChecksums![2]);
    dos.writeBoolean(isDirty);
    dos.writeLong(profileTimestamp);
    File(filename).writeAsBytesSync(dos.toByteArray());
  }

  static OsmTrack? readBinary(
    String? filename,
    OsmNodeNamed newEp,
    Int64List nogoChecksums,
    int profileChecksum,
    StringBuffer? debugInfo,
  ) {
    OsmTrack? t;
    if (filename != null) {
      final f = File(filename);
      if (f.existsSync()) {
        try {
          final dis = DataInputStream(f.readAsBytesSync());
          final ep = MatchedWaypoint.readFromStream(dis);
          final dlon = ep.waypoint!.ilon - newEp.ilon;
          final dlat = ep.waypoint!.ilat - newEp.ilat;
          final targetMatch =
              dlon < 20 && dlon > -20 && dlat < 20 && dlat > -20;
          if (debugInfo != null) {
            debugInfo.write(
              'target-delta = $dlon/$dlat targetMatch=$targetMatch',
            );
          }
          if (targetMatch) {
            t = OsmTrack();
            t.endPoint = ep;
            final n = dis.readInt();
            OsmPathElement? lastPe;
            for (var i = 0; i < n; i++) {
              final pe = OsmPathElement.readFromStream(dis);
              pe.origin = lastPe;
              lastPe = pe;
              t.nodes.add(pe);
            }
            t.cost = lastPe!.cost;
            t.buildMap();

            // check cheecksums, too
            final al = Int64List(3);
            var pchecksum = 0;
            try {
              al[0] = dis.readLong();
              al[1] = dis.readLong();
              al[2] = dis.readLong();
            } on EofException {
              /* kind of expected */
            }
            try {
              t.isDirty = dis.readBoolean();
            } on EofException {
              /* kind of expected */
            }
            try {
              pchecksum = dis.readLong();
            } on EofException {
              /* kind of expected */
            }
            final nogoCheckOk =
                (al[0] - nogoChecksums[0]).abs() <= 20 &&
                (al[1] - nogoChecksums[1]).abs() <= 20 &&
                (al[2] - nogoChecksums[2]).abs() <= 20;
            final profileCheckOk = pchecksum == profileChecksum;

            if (debugInfo != null) {
              debugInfo.write(
                ' nogoCheckOk=$nogoCheckOk profileCheckOk=$profileCheckOk',
              );
              debugInfo.write(
                ' al=${_formatLongs(al)} nogoChecksums=${_formatLongs(nogoChecksums)}',
              );
            }
            if (!(nogoCheckOk && profileCheckOk)) return null;
          }
        } catch (e) {
          if (debugInfo != null) {
            debugInfo.write('Error reading rawTrack: $e');
          }
        }
      }
    }
    return t;
  }

  static String _formatLongs(Int64List al) {
    final sb = StringBuffer();
    sb.write('{');
    for (final l in al) {
      sb.write(l);
      sb.write(' ');
    }
    sb.write('}');
    return sb.toString();
  }

  void addNodes(OsmTrack t) {
    for (final n in t.nodes) {
      addNode(n);
    }
    buildMap();
  }

  bool containsNode(OsmPos node) {
    return _nodesMap!.contains(node.getIdFromPos());
  }

  OsmPathElement? getLink(int n1, int n2) {
    var h = _nodesMap!.get(n2);
    while (h != null) {
      final e1 = h.node!.origin;
      if (e1 != null && e1.getIdFromPos() == n1) {
        return h.node;
      }
      h = h.nextHolder;
    }
    return null;
  }

  void appendTrack(OsmTrack t) {
    var i = 0;

    final ourSize = nodes.length;
    if (ourSize > 0 && t.nodes.length > 1) {
      final olde = nodes[ourSize - 1];
      t.nodes[1].origin = olde;
    }
    final t0 = ourSize > 0 ? nodes[ourSize - 1].getTime() : 0.0;
    final e0 = ourSize > 0 ? nodes[ourSize - 1].getEnergy() : 0.0;
    final c0 = ourSize > 0 ? nodes[ourSize - 1].cost : 0;
    for (i = 0; i < t.nodes.length; i++) {
      final e = t.nodes[i];
      if (i == 0 &&
          ourSize > 0 &&
          nodes[ourSize - 1].getSElev() == shortMinValue) {
        nodes[ourSize - 1].setSElev(e.getSElev());
      }
      if (i > 0 || ourSize == 0) {
        e.setTime(f32(e.getTime() + t0));
        e.setEnergy(f32(e.getEnergy() + e0));
        e.cost = e.cost + c0;
        if (e.message != null) {
          if (!(e.message!.lon == e.getILon() &&
              e.message!.lat == e.getILat())) {
            e.message!.lon = e.getILon();
            e.message!.lat = e.getILat();
          }
        }
        nodes.add(e);
      }
    }

    if (t.voiceHints != null) {
      if (ourSize > 0) {
        for (final hint in t.voiceHints!.list) {
          hint.indexInTrack = hint.indexInTrack + ourSize - 1;
        }
      }
      if (voiceHints == null) {
        voiceHints = t.voiceHints;
      } else {
        voiceHints!.list.addAll(t.voiceHints!.list);
      }
    } else {
      if (_detourMap == null) {
        //copyDetours( t );
        _detourMap = t._detourMap;
      } else {
        addDetours(t);
      }
    }

    distance += t.distance;
    ascend += t.ascend;
    plainAscend += t.plainAscend;
    cost += t.cost;
    energy = d2i(nodes[nodes.length - 1].getEnergy());

    showspeed |= t.showspeed;
    showSpeedProfile |= t.showSpeedProfile;
  }

  int distance = 0;
  int ascend = 0;
  int plainAscend = 0;
  int cost = 0;
  int energy = 0;
  List<String>? iternity;

  VoiceHint? getVoiceHint(int i) {
    if (voiceHints == null) return null;
    for (final hint in voiceHints!.list) {
      if (hint.indexInTrack == i) {
        return hint;
      }
    }
    return null;
  }

  MatchedWaypoint? getMatchedWaypoint(int idx) {
    if (matchedWaypoints == null) return null;
    for (final wp in matchedWaypoints!) {
      if (idx == wp.indexInTrack) {
        return wp;
      }
    }
    return null;
  }

  int _getVNode(int i) {
    final m1 = i + 1 < nodes.length ? nodes[i + 1].message : null;
    final m0 = i < nodes.length ? nodes[i].message : null;
    final vnode0 = m1 == null ? 999 : m1.vnode0;
    final vnode1 = m0 == null ? 999 : m0.vnode1;
    return vnode0 < vnode1 ? vnode0 : vnode1;
  }

  int getTotalSeconds() {
    final s = nodes.length < 2
        ? 0.0
        : f32(nodes[nodes.length - 1].getTime() - nodes[0].getTime());
    return d2i(s + 0.5);
  }

  bool equalsTrack(OsmTrack t) {
    if (nodes.length != t.nodes.length) return false;
    for (var i = 0; i < nodes.length; i++) {
      final e1 = nodes[i];
      final e2 = t.nodes[i];
      if (e1.getILon() != e2.getILon() || e1.getILat() != e2.getILat()) {
        return false;
      }
    }
    return true;
  }

  OsmPathElementHolder? getFromDetourMap(int id) {
    if (_detourMap == null) return null;
    return _detourMap!.get(id);
  }

  void prepareSpeedProfile(RoutingContext rc) {
    // sendSpeedProfile = rc.keyValues != null && rc.keyValues.containsKey( "vmax" );
  }

  void processVoiceHints(RoutingContext rc) {
    final voiceHints = VoiceHintList();
    this.voiceHints = voiceHints;
    voiceHints.setTransportMode(rc.carMode, rc.bikeMode);
    voiceHints.turnInstructionMode = rc.turnInstructionMode;

    if (_detourMap == null && !rc.hasDirectRouting) {
      // only when no direct way points
      return;
    }
    var nodeNr = nodes.length - 1;
    OsmPathElement? node = nodes[nodeNr];
    while (node != null) {
      node = node.origin;
    }

    node = nodes[nodeNr];
    final inputs = <VoiceHint>[];
    while (node != null) {
      if (node.origin != null) {
        if (nodeNr == nodes.length - 1) {
          final input = VoiceHint();
          inputs.insert(0, input);
          input.ilat = node.getILat();
          input.ilon = node.getILon();
          input.selev = node.getSElev();
          input.goodWay = node.message;
          input.oldWay = node.message;
          input.indexInTrack = nodes.length - 1;
          input.cmd = VoiceHint.end;
        }
        final input = VoiceHint();
        inputs.add(input);
        input.ilat = node.origin!.getILat();
        input.ilon = node.origin!.getILon();
        input.selev = node.origin!.getSElev();
        input.indexInTrack = --nodeNr;
        input.goodWay = node.message;
        input.oldWay = node.origin!.message ?? node.message;
        if (rc.turnInstructionMode == 8 ||
            rc.turnInstructionMode == 4 ||
            rc.turnInstructionMode == 2 ||
            rc.turnInstructionMode == 9) {
          final mwpt = getMatchedWaypoint(nodeNr);
          if (mwpt != null &&
              mwpt.wpttype == MatchedWaypoint.waypointTypeDirect) {
            input.cmd = VoiceHint.bl;
            input.angle = f32(
              nodeNr == 0
                  ? node.origin!.message!.turnangle
                  : node.message!.turnangle,
            );
            input.distanceToNext = node.calcDistance(node.origin!).toDouble();
          }
        }
        if (_detourMap != null) {
          final detours = _detourMap!.get(node.origin!.getIdFromPos());
          if (nodeNr >= 0 && detours != null) {
            OsmPathElementHolder? h = detours;
            while (h != null) {
              final e = h.node!;
              input.addBadWay(_startSection(e, node.origin!));
              h = h.nextHolder;
            }
          }
        }
      }
      node = node.origin;
    }

    final transportMode = voiceHints.transportMode();
    final vproc = VoiceHintProcessor(
      rc.turnInstructionCatchingRange,
      rc.turnInstructionRoundabouts,
      transportMode,
    );
    final results = vproc.process(inputs);

    final minDistance = getMinDistance().toDouble();
    final resultsLast = vproc.postProcess(
      results,
      rc.turnInstructionCatchingRange,
      minDistance,
    );
    for (final hint in resultsLast) {
      voiceHints.list.add(hint);
    }
  }

  int getMinDistance() {
    if (voiceHints != null) {
      switch (voiceHints!.transportMode()) {
        case VoiceHintList.transModeCar:
          return 20;
        case VoiceHintList.transModeFoot:
          return 3;
        case VoiceHintList.transModeBike:
        default:
          return 5;
      }
    }
    return 2;
  }

  /// `float`
  double getVoiceHintTime(int i) {
    if (voiceHints!.list.isNotEmpty && i < voiceHints!.list.length) {
      return voiceHints!.list[i].getTime();
    }
    if (nodes.isEmpty) {
      return 0.0;
    }
    return nodes[nodes.length - 1].getTime();
  }

  void removeVoiceHint(int i) {
    if (voiceHints != null) {
      VoiceHint? remove;
      for (final vh in voiceHints!.list) {
        if (vh.indexInTrack == i) remove = vh;
      }
      if (remove != null) voiceHints!.list.remove(remove);
    }
  }

  MessageData? _startSection(OsmPathElement element, OsmPathElement root) {
    OsmPathElement? e = element;
    var cnt = 0;
    while (e != null && e.origin != null) {
      if (e.origin!.getILat() == root.getILat() &&
          e.origin!.getILon() == root.getILon()) {
        return e.message;
      }
      e = e.origin;
      if (cnt++ == 1000000) {
        throw ArgumentError('ups: $root->$element');
      }
    }
    return null;
  }
}

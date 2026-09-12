// Port of btools.mapaccess.MatchedWaypoint (BRouter v1.7.10).

import 'dart:convert';
import 'dart:typed_data';

import '../jvm.dart';
import 'osm_node.dart';

/// Information on matched way point
class MatchedWaypoint {
  static const int waypointTypeShaping = 1; // route next to this point
  static const int waypointTypeMeeting = 2; // visit this point
  static const int waypointTypeDirect =
      3; // from this point go direct to next = beeline routing

  OsmNode? node1;
  OsmNode? node2;
  OsmNode? crosspoint;
  OsmNode? waypoint;
  OsmNode? correctedpoint;
  String? name; // waypoint name used in error messages
  double radius = 0; // distance in meter between waypoint and crosspoint
  int wpttype = waypointTypeShaping;
  int indexInTrack = 0;
  double directionToNext = -1;
  double directionDiff = 361;

  List<MatchedWaypoint> wayNearest = <MatchedWaypoint>[];
  bool hasUpdate = false;

  void writeToStream(DataOutputStream dos) {
    dos.writeInt(node1!.ilat);
    dos.writeInt(node1!.ilon);
    dos.writeInt(node2!.ilat);
    dos.writeInt(node2!.ilon);
    dos.writeInt(crosspoint!.ilat);
    dos.writeInt(crosspoint!.ilon);
    dos.writeInt(waypoint!.ilat);
    dos.writeInt(waypoint!.ilon);
    dos.writeDouble(radius);
    dos.writeByte(wpttype);
    dos.writeShort(name!.length);
    dos.writeStringBytes(name!);
  }

  static MatchedWaypoint readFromStream(DataInputStream dis) {
    final mwp = MatchedWaypoint();
    mwp.node1 = OsmNode();
    mwp.node2 = OsmNode();
    mwp.crosspoint = OsmNode();
    mwp.waypoint = OsmNode();

    mwp.node1!.ilat = dis.readInt();
    mwp.node1!.ilon = dis.readInt();
    mwp.node2!.ilat = dis.readInt();
    mwp.node2!.ilon = dis.readInt();
    mwp.crosspoint!.ilat = dis.readInt();
    mwp.crosspoint!.ilon = dis.readInt();
    mwp.waypoint!.ilat = dis.readInt();
    mwp.waypoint!.ilon = dis.readInt();
    mwp.radius = dis.readDouble();
    mwp.wpttype = dis.readByte();
    final len = dis.readShort();
    final bytes = Uint8List(len);
    dis.readFully(bytes);
    mwp.name = latin1.decode(
      bytes,
    ); // `new String(bytes)` of a writeBytes() string
    return mwp;
  }
}

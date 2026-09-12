// Port of btools.router.OsmPathElement (BRouter v1.7.10).
//
// Container for link between two Osm nodes

import 'dart:math' as math;

import '../jvm.dart';
import '../mapaccess/osm_pos.dart';
import '../util/cheap_ruler.dart';
import 'message_data.dart';
import 'osm_path.dart';

class OsmPathElement implements OsmPos {
  int _ilat = 0; // latitude
  int _ilon = 0; // longitude
  int _selev = 0; // short

  MessageData? message; // description

  int cost = 0;

  // interface OsmPos
  @override
  int getILat() {
    return _ilat;
  }

  @override
  int getILon() {
    return _ilon;
  }

  @override
  int getSElev() {
    return _selev;
  }

  void setSElev(int s) {
    _selev = toShort(s);
  }

  @override
  double getElev() {
    return _selev / 4.0;
  }

  /// `float`
  double getTime() {
    return message == null ? 0.0 : message!.time;
  }

  void setTime(double t) {
    if (message != null) {
      message!.time = f32(t);
    }
  }

  /// `float`
  double getEnergy() {
    return message == null ? 0.0 : message!.energy;
  }

  void setEnergy(double e) {
    if (message != null) {
      message!.energy = f32(e);
    }
  }

  void setAngle(double e) {
    if (message != null) {
      message!.turnangle = f32(e);
    }
  }

  @override
  int getIdFromPos() {
    return (_ilon << 32) | _ilat;
  }

  @override
  int calcDistance(OsmPos p) {
    return d2i(
      math.max(
        1.0,
        javaRound(
          CheapRuler.distance(_ilon, _ilat, p.getILon(), p.getILat()),
        ).toDouble(),
      ),
    );
  }

  OsmPathElement? origin;

  /// construct a path element from a path
  static OsmPathElement create(OsmPath path) {
    final n = path.getTargetNode();
    final pe = createAt(n.getILon(), n.getILat(), n.getSElev(), path.originElement);
    pe.cost = path.cost;
    pe.message = path.message;
    return pe;
  }

  /// `create(int ilon, int ilat, short selev, OsmPathElement origin)`
  static OsmPathElement createAt(
    int ilon,
    int ilat,
    int selev,
    OsmPathElement? origin,
  ) {
    final pe = OsmPathElement();
    pe._ilon = ilon;
    pe._ilat = ilat;
    pe._selev = selev;
    pe.origin = origin;
    return pe;
  }

  OsmPathElement();

  @override
  String toString() {
    return '${_ilon}_$_ilat';
  }

  bool positionEquals(OsmPathElement e) {
    return _ilat == e._ilat && _ilon == e._ilon;
  }

  void writeToStream(DataOutputStream dos) {
    dos.writeInt(_ilat);
    dos.writeInt(_ilon);
    dos.writeShort(_selev);
    dos.writeInt(cost);
  }

  static OsmPathElement readFromStream(DataInputStream dis) {
    final pe = OsmPathElement();
    pe._ilat = dis.readInt();
    pe._ilon = dis.readInt();
    pe._selev = dis.readShort();
    pe.cost = dis.readInt();
    return pe;
  }
}

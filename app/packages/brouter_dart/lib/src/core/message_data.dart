// Port of btools.router.MessageData (BRouter v1.7.10).
//
// Information on matched way point

import '../jfloat.dart';
import '../jvm.dart';

final class MessageData {
  int linkdist = 0;
  int linkelevationcost = 0;
  int linkturncost = 0;
  int linknodecost = 0;
  int linkinitcost = 0;

  /// `float`
  double costfactor = 0;
  int priorityclassifier = 0;
  int classifiermask = 0;

  /// `float`
  double turnangle = 0;
  String? wayKeyValues;
  String? nodeKeyValues;

  int lon = 0;
  int lat = 0;

  /// `short`
  int ele = 0;

  /// `float`
  double time = 0;

  /// `float`
  double energy = 0;

  // speed profile
  int vmaxExplicit = -1;
  int vmax = -1;
  int vmin = -1;
  int vnode0 = 999;
  int vnode1 = 999;
  int extraTime = 0;

  String? toMessage() {
    if (wayKeyValues == null) {
      return null;
    }

    // (int) (costfactor * 1000 + 0.5f): float arithmetic
    final iCost = d2i(f32(f32(costfactor * 1000) + 0.5));
    return '${lon - 180000000}\t'
        '${lat - 90000000}\t'
        '${ele ~/ 4}\t'
        '$linkdist\t'
        '$iCost\t'
        '$linkelevationcost'
        '\t$linkturncost'
        '\t$linknodecost'
        '\t$linkinitcost'
        '\t$wayKeyValues'
        '\t${nodeKeyValues ?? ''}'
        '\t${d2i(time)}'
        '\t${d2i(energy)}';
  }

  void add(MessageData d) {
    linkdist += d.linkdist;
    linkelevationcost += d.linkelevationcost;
    linkturncost += d.linkturncost;
    linknodecost += d.linknodecost;
    linkinitcost += d.linkinitcost;
  }

  /// `clone()`
  MessageData copy() {
    return MessageData()
      ..linkdist = linkdist
      ..linkelevationcost = linkelevationcost
      ..linkturncost = linkturncost
      ..linknodecost = linknodecost
      ..linkinitcost = linkinitcost
      ..costfactor = costfactor
      ..priorityclassifier = priorityclassifier
      ..classifiermask = classifiermask
      ..turnangle = turnangle
      ..wayKeyValues = wayKeyValues
      ..nodeKeyValues = nodeKeyValues
      ..lon = lon
      ..lat = lat
      ..ele = ele
      ..time = time
      ..energy = energy
      ..vmaxExplicit = vmaxExplicit
      ..vmax = vmax
      ..vmin = vmin
      ..vnode0 = vnode0
      ..vnode1 = vnode1
      ..extraTime = extraTime;
  }

  @override
  String toString() {
    return 'dist=$linkdist prio=$priorityclassifier turn=${javaFloatToString(turnangle)}';
  }

  int getPrio() {
    return priorityclassifier;
  }

  bool isBadOneway() {
    return (classifiermask & 1) != 0;
  }

  bool isGoodOneway() {
    return (classifiermask & 2) != 0;
  }

  bool isRoundabout() {
    return (classifiermask & 4) != 0;
  }

  bool isLinktType() {
    return (classifiermask & 8) != 0;
  }

  bool isGoodForCars() {
    return (classifiermask & 16) != 0;
  }
}

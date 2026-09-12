// Port of btools.router.VoiceHint (BRouter v1.7.10).
//
// Container for a voice hint
// (both input- and result data for voice hint processing)

import '../jvm.dart';
import 'message_data.dart';

class VoiceHint {
  static const int c = 1; // continue (go straight)
  static const int tl = 2; // turn left
  static const int tsll = 3; // turn slightly left
  static const int tshl = 4; // turn sharply left
  static const int tr = 5; // turn right
  static const int tslr = 6; // turn slightly right
  static const int tshr = 7; // turn sharply right
  static const int kl = 8; // keep left
  static const int kr = 9; // keep right
  static const int tlu = 10; // U-turn
  static const int tru = 11; // Right U-turn
  static const int offr = 12; // Off route
  static const int rndb = 13; // Roundabout
  static const int rnlb = 14; // Roundabout left
  static const int tu = 15; // 180 degree u-turn
  static const int bl = 16; // Beeline routing
  static const int el = 17; // exit left
  static const int er = 18; // exit right

  static const int end = 100; // end point

  int ilon = 0;
  int ilat = 0;
  int selev = 0; // short
  int cmd = 0;
  MessageData? oldWay;
  MessageData? goodWay;
  List<MessageData>? badWays;
  double distanceToNext = 0;
  int indexInTrack = 0;

  /// `float`
  double getTime() {
    return oldWay == null ? 0.0 : oldWay!.time;
  }

  double angle = floatMaxValue; // float
  double lowerBadWayAngle = -181; // float
  double higherBadWayAngle = 181; // float

  bool turnAngleConsumed = false;
  bool needsRealTurn = false;
  int maxBadPrio = -1;

  int roundaboutExit = 0;

  bool isRoundabout() {
    return roundaboutExit != 0;
  }

  void addBadWay(MessageData? badWay) {
    if (badWay == null) {
      return;
    }
    badWays ??= <MessageData>[];
    badWays!.add(badWay);
  }

  int getExitNumber() {
    return roundaboutExit;
  }

  void calcCommand() {
    if (badWays != null) {
      for (final badWay in badWays!) {
        if (badWay.isBadOneway()) {
          continue;
        }
        if (lowerBadWayAngle < badWay.turnangle &&
            badWay.turnangle < goodWay!.turnangle) {
          lowerBadWayAngle = badWay.turnangle;
        }
        if (higherBadWayAngle > badWay.turnangle &&
            badWay.turnangle > goodWay!.turnangle) {
          higherBadWayAngle = badWay.turnangle;
        }
      }
    }

    var cmdAngle = angle;

    // fall back to local angle if otherwise inconsistent
    //if ( lowerBadWayAngle > angle || higherBadWayAngle < angle )
    //{
    //cmdAngle = goodWay.turnangle;
    //}
    if (angle == floatMaxValue) {
      cmdAngle = goodWay!.turnangle;
    }
    if (cmd == bl) return;

    if (roundaboutExit > 0) {
      cmd = rndb;
    } else if (roundaboutExit < 0) {
      cmd = rnlb;
    } else if (is180DegAngle(cmdAngle) &&
        cmdAngle <= -179.0 &&
        higherBadWayAngle == 181.0 &&
        lowerBadWayAngle == -181.0) {
      cmd = tu;
    } else if (cmdAngle < -159.0) {
      cmd = tlu;
    } else if (cmdAngle < -135.0) {
      cmd = tshl;
    } else if (cmdAngle < -45.0) {
      // a TL can be pushed in either direction by a close-by alternative
      if (cmdAngle < -95.0 &&
          higherBadWayAngle < -30.0 &&
          lowerBadWayAngle < -180.0) {
        cmd = tshl;
      } else if (cmdAngle > -85.0 &&
          lowerBadWayAngle > -180.0 &&
          higherBadWayAngle > -10.0) {
        cmd = tsll;
      } else {
        if (cmdAngle < -110.0) {
          cmd = tshl;
        } else if (cmdAngle > -60.0) {
          cmd = tsll;
        } else {
          cmd = tl;
        }
      }
    } else if (cmdAngle < -21.0) {
      if (cmd != kr) {
        // don't overwrite KR with TSLL
        cmd = tsll;
      }
    } else if (cmdAngle < -5.0) {
      if (lowerBadWayAngle < -100.0 && higherBadWayAngle < 45.0) {
        cmd = tsll;
      } else if (lowerBadWayAngle >= -100.0 && higherBadWayAngle < 45.0) {
        cmd = kl;
      } else {
        if (lowerBadWayAngle > -35.0 && higherBadWayAngle > 55.0) {
          cmd = kr;
        } else {
          cmd = c;
        }
      }
    } else if (cmdAngle < 5.0) {
      if (lowerBadWayAngle > -30.0) {
        cmd = kr;
      } else if (higherBadWayAngle < 30.0) {
        cmd = kl;
      } else {
        cmd = c;
      }
    } else if (cmdAngle < 21.0) {
      // a TR can be pushed in either direction by a close-by alternative
      if (lowerBadWayAngle > -45.0 && higherBadWayAngle > 100.0) {
        cmd = tslr;
      } else if (lowerBadWayAngle > -45.0 && higherBadWayAngle <= 100.0) {
        cmd = kr;
      } else {
        if (lowerBadWayAngle < -55.0 && higherBadWayAngle < 35.0) {
          cmd = kl;
        } else {
          cmd = c;
        }
      }
    } else if (cmdAngle < 45.0) {
      cmd = tslr;
    } else if (cmdAngle < 135.0) {
      if (cmdAngle < 85.0 &&
          higherBadWayAngle < 180.0 &&
          lowerBadWayAngle < 10.0) {
        cmd = tslr;
      } else if (cmdAngle > 95.0 &&
          lowerBadWayAngle > 30.0 &&
          higherBadWayAngle > 180.0) {
        cmd = tshr;
      } else {
        if (cmdAngle > 110.0) {
          cmd = tshr;
        } else if (cmdAngle < 60.0) {
          cmd = tslr;
        } else {
          cmd = tr;
        }
      }
    } else if (cmdAngle < 159.0) {
      cmd = tshr;
    } else if (is180DegAngle(cmdAngle) &&
        cmdAngle >= 179.0 &&
        higherBadWayAngle == 181.0 &&
        lowerBadWayAngle == -181.0) {
      cmd = tu;
    } else {
      cmd = tru;
    }
  }

  static bool is180DegAngle(double angle) {
    return (angle.abs() <= 180.0 && angle.abs() >= 179.0);
  }

  String formatGeometry() {
    final oldPrio = oldWay == null
        ? 0.0
        : f32(oldWay!.priorityclassifier.toDouble());
    final sb = StringBuffer();
    sb.write(' ');
    sb.write(d2i(oldPrio));
    _appendTurnGeometry(sb, goodWay!);
    if (badWays != null) {
      for (final badWay in badWays!) {
        sb.write(' ');
        _appendTurnGeometry(sb, badWay);
      }
    }
    return sb.toString();
  }

  void _appendTurnGeometry(StringBuffer sb, MessageData msg) {
    sb.write('(');
    sb.write(d2i(msg.turnangle + 0.5));
    sb.write(')');
    sb.write(msg.priorityclassifier);
  }

  bool hasGiveWay() {
    if (oldWay != null && oldWay!.nodeKeyValues != null) {
      final nkv = oldWay!.nodeKeyValues!;
      if (oldWay!.wayKeyValues!.contains('reversedirection=yes')) {
        return (nkv.contains('highway=give_way') ||
                nkv.contains('highway=stop')) &&
            nkv.contains('direction=backward');
      } else {
        return (nkv.contains('highway=give_way') ||
                nkv.contains('highway=stop')) &&
            !nkv.contains('direction=backward');
      }
    }
    return false;
  }
}

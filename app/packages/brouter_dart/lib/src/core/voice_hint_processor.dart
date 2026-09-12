// Port of btools.router.VoiceHintProcessor (BRouter v1.7.10).
//
// Processor for Voice Hints
//
// `float` sums (`angle`, `roundAboutTurnAngle`, `tmpangle`) round through
// `f32()`; the distances are doubles like upstream.

import 'dart:math' as math;

import '../jvm.dart';
import 'message_data.dart';
import 'voice_hint.dart';
import 'voice_hint_list.dart';

final class VoiceHintProcessor {
  static const double significantAngle = 22.5;
  static const double internalCatchingRangeNear = 2.0;
  static const double internalCatchingRangeWide = 10.0;

  // private double catchingRange; // range to catch angles and merge turns
  final bool _explicitRoundabouts;
  final int _transportMode;

  VoiceHintProcessor(
    double catchingRange,
    bool explicitRoundabouts,
    int transportMode,
  ) : _explicitRoundabouts = explicitRoundabouts,
      _transportMode = transportMode;

  /// `float`
  double _sumNonConsumedWithinCatchingRange(
    List<VoiceHint> inputs,
    int offset,
    double range,
  ) {
    var distance = 0.0;
    var angle = 0.0;
    while (offset >= 0 && distance < range) {
      final input = inputs[offset--];
      if (input.turnAngleConsumed ||
          input.cmd == VoiceHint.bl ||
          input.cmd == VoiceHint.end) {
        break;
      }
      angle = f32(angle + input.goodWay!.turnangle);
      distance += input.goodWay!.linkdist;
      input.turnAngleConsumed = true;
    }
    return angle;
  }

  /// process voice hints. Uses VoiceHint objects
  /// for both input and output. Input is in reverse
  /// order (from target to start), but output is
  /// returned in travel-direction and only for
  /// those nodes that trigger a voice hint.
  List<VoiceHint> process(List<VoiceHint> inputs) {
    final results = <VoiceHint>[];
    var distance = 0.0;
    var roundAboutTurnAngle = 0.0; // sums up angles in roundabout, float

    var roundaboutExit = 0;
    var roundaboudStartIdx = -1;

    for (var hintIdx = 0; hintIdx < inputs.length; hintIdx++) {
      final input = inputs[hintIdx];

      if (input.cmd == VoiceHint.bl) {
        results.add(input);
        continue;
      }

      final turnAngle = input.goodWay!.turnangle;
      if (hintIdx != 0) distance += input.goodWay!.linkdist;

      final currentPrio = input.goodWay!.getPrio();
      final oldPrio = input.oldWay!.getPrio();
      final minPrio = math.min(oldPrio, currentPrio);

      final isLink2Highway =
          input.oldWay!.isLinktType() && !input.goodWay!.isLinktType();
      final isHighway2Link =
          !input.oldWay!.isLinktType() && input.goodWay!.isLinktType();

      if (_explicitRoundabouts && input.oldWay!.isRoundabout()) {
        if (roundaboudStartIdx == -1) roundaboudStartIdx = hintIdx;
        roundAboutTurnAngle = f32(
          roundAboutTurnAngle +
              _sumNonConsumedWithinCatchingRange(
                inputs,
                hintIdx,
                internalCatchingRangeNear,
              ),
        );
        if (roundaboudStartIdx == hintIdx) {
          if (input.badWays != null) {
            // remove goodWay
            roundAboutTurnAngle = f32(
              roundAboutTurnAngle - input.goodWay!.turnangle,
            );
            // add a badWay
            for (final badWay in input.badWays!) {
              if (!badWay.isBadOneway()) {
                roundAboutTurnAngle = f32(roundAboutTurnAngle + badWay.turnangle);
              }
            }
          }
        }
        var isExit = roundaboutExit == 0; // exit point is always exit
        if (input.badWays != null) {
          for (final badWay in input.badWays!) {
            if (!badWay.isBadOneway() && badWay.isGoodForCars()) {
              isExit = true;
              break;
            }
          }
        }
        if (isExit) {
          roundaboutExit++;
        }
        continue;
      }
      if (roundaboutExit > 0) {
        input.angle = roundAboutTurnAngle;
        input.goodWay!.turnangle = roundAboutTurnAngle;
        input.distanceToNext = distance;
        input.turnAngleConsumed = true;
        //input.roundaboutExit = startTurn < 0 ? roundaboutExit : -roundaboutExit;
        input.roundaboutExit = roundAboutTurnAngle < 0
            ? roundaboutExit
            : -roundaboutExit;
        var tmpangle = 0.0;
        final tmpRndAbt = VoiceHint();
        tmpRndAbt.badWays = <MessageData>[];
        for (var i = hintIdx - 1; i > roundaboudStartIdx; i--) {
          final vh = inputs[i];
          tmpangle = f32(tmpangle + inputs[i].goodWay!.turnangle);
          if (vh.badWays != null) {
            for (final badWay in vh.badWays!) {
              if (!badWay.isBadOneway()) {
                final md = MessageData();
                md.linkdist = vh.goodWay!.linkdist;
                md.priorityclassifier = vh.goodWay!.priorityclassifier;
                md.turnangle = tmpangle;
                tmpRndAbt.badWays!.add(md);
              }
            }
          }
        }
        distance = 0.0;

        input.badWays = tmpRndAbt.badWays;

        results.add(input);
        roundAboutTurnAngle = 0.0;
        roundaboutExit = 0;
        roundaboudStartIdx = -1;
        continue;
      }

      final inputNext = hintIdx + 1 < inputs.length ? inputs[hintIdx + 1] : null;

      var maxPrioAll = -1; // max prio of all detours
      var maxPrioCandidates = -1; // max prio of real candidates

      var maxAngle = -180.0;
      var minAngle = 180.0;
      var minAbsAngeRaw = 180.0;

      var isBadwayLink = false;

      if (input.badWays != null) {
        for (final badWay in input.badWays!) {
          final badPrio = badWay.getPrio();
          final badTurn = badWay.turnangle;
          if (badWay.isLinktType()) {
            isBadwayLink = true;
          }
          // boolean isBadHighway2Link = !input.oldWay.isLinktType() && badWay.isLinktType();

          if (badPrio > maxPrioAll) {
            maxPrioAll = badPrio;
            input.maxBadPrio = math.max(input.maxBadPrio, badPrio);
          }

          if (badWay.isBadOneway()) {
            if (minAbsAngeRaw == 180.0) {
              minAbsAngeRaw = turnAngle.abs(); // disable hasSomethingMoreStraight
            }
            continue; // ignore wrong oneways
          }

          if (f32(badTurn.abs() - turnAngle.abs()) > 80.0) {
            if (minAbsAngeRaw == 180.0) {
              minAbsAngeRaw = turnAngle.abs(); // disable hasSomethingMoreStraight
            }
            continue; // ways from the back should not trigger a slight turn
          }

          if (badWay.costfactor < 20.0 && badTurn.abs() < minAbsAngeRaw) {
            minAbsAngeRaw = badTurn.abs();
          }

          if (badPrio > maxPrioCandidates) {
            maxPrioCandidates = badPrio;
            input.maxBadPrio = math.max(input.maxBadPrio, badPrio);
          }
          if (badTurn > maxAngle) {
            maxAngle = badTurn;
          }
          if (badTurn < minAngle) {
            minAngle = badTurn;
          }
        }
      }

      // has a significant angle and one or more bad ways around
      final hasSomethingMoreStraight =
          (turnAngle.abs() > 35.0) && input.badWays != null;

      // bad way has more prio, but is not a link
      final noLinkButBadWayPrio = (maxPrioAll > minPrio && !isLink2Highway);

      // bad way has more prio
      final badWayHasPrio = (maxPrioCandidates > currentPrio);

      // is a u-turn - same way back
      final isUTurn = VoiceHint.is180DegAngle(turnAngle);

      // way has prio, but also has an angle
      final isBadWayLinkButNoLink =
          (!isHighway2Link && isBadwayLink && turnAngle.abs() > 5.0);

      final isLinkButNoBadWayLink =
          (isHighway2Link && !isBadwayLink && turnAngle.abs() < 5.0);

      // way has same prio, but bad way has smaller angle and is not a bad link and prio is near
      final samePrioSmallBadAngle =
          (currentPrio == oldPrio) &&
          (minPrio - maxPrioAll <= 2) &&
          !isBadwayLink &&
          minAbsAngeRaw != 180.0 &&
          minAbsAngeRaw < 35.0;

      // way has prio, but has to give way
      final mustGiveWay =
          _transportMode != VoiceHintList.transModeFoot &&
          input.badWays != null &&
          !badWayHasPrio &&
          (input.hasGiveWay() || (inputNext != null && inputNext.hasGiveWay()));

      // unconditional triggers are all junctions with
      // - higher detour prios than the minimum route prio (except link->highway junctions)
      // - or candidate detours with higher prio then the route exit leg
      final unconditionalTrigger =
          hasSomethingMoreStraight ||
          noLinkButBadWayPrio ||
          badWayHasPrio ||
          isUTurn ||
          isBadWayLinkButNoLink ||
          isLinkButNoBadWayLink ||
          samePrioSmallBadAngle ||
          mustGiveWay;

      // conditional triggers (=real turning angle required) are junctions
      // with candidate detours equal in priority than the route exit leg
      final conditionalTrigger = maxPrioCandidates >= minPrio;

      if (unconditionalTrigger || conditionalTrigger) {
        input.angle = turnAngle;
        input.calcCommand();
        final isStraight = input.cmd == VoiceHint.c;
        input.needsRealTurn = (!unconditionalTrigger) && isStraight;

        // check for KR/KL
        if (turnAngle.abs() > 5.0) {
          // don't use too small angles
          if (maxAngle < turnAngle &&
              maxAngle >
                  f32(f32(turnAngle - 45.0) - (math.max(turnAngle, 0.0)))) {
            input.cmd = VoiceHint.kr;
          }
          if (minAngle > turnAngle &&
              minAngle <
                  f32(f32(turnAngle + 45.0) - (math.min(turnAngle, 0.0)))) {
            input.cmd = VoiceHint.kl;
          }
        }

        if (_explicitRoundabouts) {
          input.angle = _sumNonConsumedWithinCatchingRange(
            inputs,
            hintIdx,
            internalCatchingRangeWide,
          );
        } else {
          input.turnAngleConsumed = true;
        }
        input.distanceToNext = distance;
        distance = 0.0;
        results.add(input);
      }
      if (results.isNotEmpty && distance < internalCatchingRangeNear) {
        //catchingRange
        final last = results[results.length - 1];
        last.angle = f32(
          last.angle +
              _sumNonConsumedWithinCatchingRange(
                inputs,
                hintIdx,
                internalCatchingRangeNear,
              ),
        );
      }
    }

    // go through the hint list again in reverse order (=travel direction)
    // and filter out non-significant hints and hints too close to its predecessor

    final results2 = <VoiceHint>[];
    var i = results.length;
    while (i > 0) {
      var hint = results[--i];
      if (hint.cmd == 0) {
        hint.calcCommand();
      }
      if (hint.cmd == VoiceHint.end) {
        results2.add(hint);
        continue;
      }
      if (!(hint.needsRealTurn &&
          (hint.cmd == VoiceHint.c || hint.cmd == VoiceHint.bl))) {
        var dist = hint.distanceToNext;
        // sum up other hints within the catching range (e.g. 40m)
        while (dist < internalCatchingRangeNear && i > 0) {
          final h2 = results[i - 1];
          dist = h2.distanceToNext;
          hint.distanceToNext += dist;
          hint.angle = f32(hint.angle + h2.angle);
          i--;
          if (h2.isRoundabout()) {
            // if we hit a roundabout, use that as the trigger
            h2.angle = hint.angle;
            hint = h2;
            break;
          }
        }

        if (!_explicitRoundabouts) {
          hint.roundaboutExit = 0; // use an angular hint instead
        }
        hint.calcCommand();
        results2.add(hint);
      } else if (hint.cmd == VoiceHint.bl) {
        results2.add(hint);
      } else {
        if (results2.isNotEmpty) {
          results2[results2.length - 1].distanceToNext += hint.distanceToNext;
        }
      }
    }
    return results2;
  }

  List<VoiceHint> postProcess(
    List<VoiceHint> inputs,
    double catchingRange,
    double minRange,
  ) {
    final results = <VoiceHint>[];
    VoiceHint? inputLast;
    VoiceHint? inputLastSaved;
    for (var hintIdx = 0; hintIdx < inputs.length; hintIdx++) {
      final input = inputs[hintIdx];
      VoiceHint? nextInput;
      if (hintIdx + 1 < inputs.length) {
        nextInput = inputs[hintIdx + 1];
      }

      if (input.cmd == VoiceHint.bl) {
        results.add(input);
        continue;
      }

      if (nextInput == null) {
        if (input.cmd == VoiceHint.end) {
          continue;
        } else if ((input.cmd == VoiceHint.c ||
                input.cmd == VoiceHint.kr ||
                input.cmd == VoiceHint.kl) &&
            !input.goodWay!.isLinktType()) {
          if (checkStraightHold(input, inputLastSaved, minRange)) {
            results.add(input);
          } else {
            if (inputLast != null) {
              // when drop add distance to last
              inputLast.distanceToNext += input.distanceToNext;
            }
            continue;
          }
        } else {
          results.add(input);
        }
      } else {
        if ((inputLastSaved != null &&
                inputLastSaved.distanceToNext > catchingRange) ||
            input.distanceToNext > catchingRange) {
          if ((input.cmd == VoiceHint.c ||
              input.cmd == VoiceHint.kr ||
              input.cmd == VoiceHint.kl)) {
            if (checkStraightHold(input, inputLastSaved, minRange)) {
              // add only on prio
              results.add(input);
              inputLastSaved = input;
            } else {
              if (inputLastSaved != null) {
                // when drop add distance to last
                inputLastSaved.distanceToNext += input.distanceToNext;
              }
            }
          } else if ((input.goodWay!.getPrio() == 29 && input.maxBadPrio == 30) &&
              checkForNextNoneMotorway(inputs, hintIdx, 3)) {
            // leave motorway
            if (input.cmd == VoiceHint.kr || input.cmd == VoiceHint.tslr) {
              input.cmd = VoiceHint.er;
            } else if (input.cmd == VoiceHint.kl ||
                input.cmd == VoiceHint.tsll) {
              input.cmd = VoiceHint.el;
            }
            results.add(input);
            inputLastSaved = input;
          } else {
            // add all others
            // ignore motorway / primary continue
            if (((input.goodWay!.getPrio() != 28) &&
                    (input.goodWay!.getPrio() != 30) &&
                    (input.goodWay!.getPrio() != 26)) ||
                input.isRoundabout() ||
                input.angle.abs() > 21.0 ||
                f32(input.angle.abs() - input.lowerBadWayAngle) < 21.0) {
              results.add(input);
              inputLastSaved = input;
            } else {
              if (inputLastSaved != null) {
                // when drop add distance to last
                inputLastSaved.distanceToNext += input.distanceToNext;
              }
            }
          }
        } else if (input.distanceToNext < catchingRange) {
          var dist = input.distanceToNext;
          var angles = input.angle;
          var save = false;

          dist += nextInput.distanceToNext;
          angles = f32(angles + nextInput.angle);

          if ((input.cmd == VoiceHint.c ||
                  input.cmd == VoiceHint.kr ||
                  input.cmd == VoiceHint.kl) &&
              !input.goodWay!.isLinktType()) {
            if (input.goodWay!.getPrio() < input.maxBadPrio) {
              if (inputLastSaved != null &&
                  inputLastSaved.cmd != VoiceHint.c &&
                  (inputLastSaved.distanceToNext > minRange) &&
                  _transportMode != VoiceHintList.transModeCar) {
                // add when straight and not linktype
                // and last vh not straight
                save = true;
                // remove when next straight and not linktype
                if (nextInput.cmd == VoiceHint.c &&
                    !nextInput.goodWay!.isLinktType()) {
                  input.distanceToNext += nextInput.distanceToNext;
                  hintIdx++;
                }
              }
            } else {
              if (inputLastSaved != null) {
                // when drop add distance to last
                inputLastSaved.distanceToNext += input.distanceToNext;
              }
            }
          } else if ((input.goodWay!.getPrio() == 29 && input.maxBadPrio == 30)) {
            // leave motorway
            if (input.cmd == VoiceHint.kr || input.cmd == VoiceHint.tslr) {
              input.cmd = VoiceHint.er;
            } else if (input.cmd == VoiceHint.kl ||
                input.cmd == VoiceHint.tsll) {
              input.cmd = VoiceHint.el;
            }
            save = true;
          } else if (VoiceHint.is180DegAngle(input.angle)) {
            // add u-turn, 180 degree
            save = true;
          } else if (_transportMode == VoiceHintList.transModeCar &&
              angles.abs() > 180 - significantAngle) {
            // add when inc car mode and u-turn, collects e.g. two left turns in range
            input.angle = angles;
            input.calcCommand();
            input.distanceToNext += nextInput.distanceToNext;
            save = true;
            hintIdx++;
          } else if (angles.abs() < significantAngle &&
              input.distanceToNext < minRange) {
            input.angle = angles;
            input.calcCommand();
            input.distanceToNext += nextInput.distanceToNext;
            save = true;
            hintIdx++;
          } else if (input.angle.abs() > significantAngle) {
            // add when angle above 22.5 deg
            save = true;
          } else if (input.angle.abs() < significantAngle) {
            // add when angle below 22.5 deg ???
            // save = true;
          } else {
            // otherwise ignore but add distance to next
            // when drop add distance to last
            nextInput.distanceToNext += input.distanceToNext;
            save = false;
          }

          if (save) {
            results.add(input); // add when last
            inputLastSaved = input;
          }
        } else {
          results.add(input);
          inputLastSaved = input;
        }
      }
      inputLast = input;
    }
    if (results.isNotEmpty) {
      // don't use END tag
      if (results[results.length - 1].cmd == VoiceHint.end) {
        results.removeLast();
      }
    }

    return results;
  }

  bool checkForNextNoneMotorway(List<VoiceHint> inputs, int offset, int testsize) {
    for (var i = 1; i < testsize + 1 && offset + i < inputs.length; i++) {
      final prio = inputs[offset + i].goodWay!.getPrio();
      if (prio < 29) return true;
      if (prio == 30) return false;
    }
    return false;
  }

  bool checkStraightHold(VoiceHint input, VoiceHint? inputLastSaved, double minRange) {
    if (input.indexInTrack == 0) return false;

    var badOneWay = false;
    if (input.badWays != null) {
      for (final md in input.badWays!) {
        if (md.isBadOneway()) badOneWay = true;
      }
    }
    if (badOneWay &&
        input.lowerBadWayAngle == -181.0 &&
        input.higherBadWayAngle == 181.0) {
      return false;
    }
    if ((input.lowerBadWayAngle != -181.0 &&
            input.lowerBadWayAngle.abs() > 135.0 &&
            input.higherBadWayAngle.abs() > 35.0) ||
        (input.higherBadWayAngle != 181.0 &&
            input.higherBadWayAngle > 135.0 &&
            input.lowerBadWayAngle.abs() > 35.0)) {
      return false;
    }

    return ((input.lowerBadWayAngle.abs() < 35.0 ||
                input.higherBadWayAngle < 35.0) ||
            input.goodWay!.getPrio() < input.maxBadPrio ||
            input.goodWay!.getPrio() > input.oldWay!.getPrio()) &&
        (inputLastSaved == null || inputLastSaved.distanceToNext > minRange) &&
        (input.distanceToNext > minRange);
  }
}

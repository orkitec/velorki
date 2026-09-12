// Port of btools.router.StdPath (BRouter v1.7.10).
//
// Container for link between two Osm nodes
//
// Every `float` field and intermediate is a double holding a float value and
// rounds through `f32()` after each float operation; `int += float` is
// `(int) ((float) int + float)` like the JVM.

import 'dart:math' as math;

import '../jmath.dart';
import '../jvm.dart';
import 'osm_path.dart';
import 'routing_context.dart';

final class StdPath extends OsmPath {
  /// The elevation-hysteresis-buffer (0-10 m)
  int _ehbd = 0; // in micrometer
  int _ehbu = 0; // in micrometer

  double _totalTime = 0; // travel time (seconds), float
  double _totalEnergy = 0; // total route energy (Joule), float
  double _elevationBuffer = 0; // just another elevation buffer (for travel time), float

  int _uphillcostdiv = 0;
  int _downhillcostdiv = 0;

  // Gravitational constant, g
  static const double _gravity = 9.81; // in meters per second^(-2)

  @override
  void init(OsmPath orig) {
    final origin = orig as StdPath;
    _ehbd = origin._ehbd;
    _ehbu = origin._ehbu;
    _totalTime = origin._totalTime;
    _totalEnergy = origin._totalEnergy;
    _elevationBuffer = origin._elevationBuffer;
  }

  @override
  void resetState() {
    _ehbd = 0;
    _ehbu = 0;
    _totalTime = 0.0;
    _totalEnergy = 0.0;
    _uphillcostdiv = 0;
    _downhillcostdiv = 0;
    _elevationBuffer = 0.0;
  }

  /// `Math.min(float, float)`.
  static double _fmin(double a, double b) => a != a ? a : (a <= b ? a : b);

  /// `Math.max(float, float)`.
  static double _fmax(double a, double b) => a != a ? a : (a >= b ? a : b);

  @override
  double processWaySection(
    RoutingContext rc,
    double distance,
    double deltaH,
    double elevation,
    double angle,
    double cosangle,
    bool isStartpoint,
    int nsection,
    int lastpriorityclassifier,
  ) {
    final w = rc.expctxWay!;
    // calculate the costfactor inputs
    final turncostbase = w.getTurncost();
    final uphillcutoff = f32(w.getUphillcutoff() * 10000);
    final downhillcutoff = f32(w.getDownhillcutoff() * 10000);
    final uphillmaxslope = f32(w.getUphillmaxslope() * 10000);
    final downhillmaxslope = f32(w.getDownhillmaxslope() * 10000);
    var cfup = w.getUphillCostfactor();
    var cfdown = w.getDownhillCostfactor();
    final cf = w.getCostfactor();
    cfup = cfup == 0.0 ? cf : cfup;
    cfdown = cfdown == 0.0 ? cf : cfdown;

    _downhillcostdiv = d2i(w.getDownhillcost());
    if (_downhillcostdiv > 0) {
      _downhillcostdiv = 1000000 ~/ _downhillcostdiv;
    }

    var downhillmaxslopecostdiv = d2i(w.getDownhillmaxslopecost());
    if (downhillmaxslopecostdiv > 0) {
      downhillmaxslopecostdiv = 1000000 ~/ downhillmaxslopecostdiv;
    } else {
      // if not given, use legacy behavior
      downhillmaxslopecostdiv = _downhillcostdiv;
    }

    _uphillcostdiv = d2i(w.getUphillcost());
    if (_uphillcostdiv > 0) {
      _uphillcostdiv = 1000000 ~/ _uphillcostdiv;
    }

    var uphillmaxslopecostdiv = d2i(w.getUphillmaxslopecost());
    if (uphillmaxslopecostdiv > 0) {
      uphillmaxslopecostdiv = 1000000 ~/ uphillmaxslopecostdiv;
    } else {
      // if not given, use legacy behavior
      uphillmaxslopecostdiv = _uphillcostdiv;
    }

    final dist = d2i(distance); // legacy arithmetics needs int
    final fdist = f32(dist.toDouble()); // dist promoted to float

    // penalty for turning angle
    var turncost = d2i(
      (1.0 - cosangle) * turncostbase + 0.2,
    ); // e.g. turncost=90 -> 90 degree = 90m penalty

    final newPrio = d2i(w.getPriorityClassifier());
    final oldPrio = lastpriorityclassifier;

    if (rc.bikeMode) {
      //   If the turn is LEFT and coming from "primary|secondary" to a lower priority highway
      //   AND estimated_crossing_class is defined on the node, than penalty!!!

      if (rc.considerCrossing &&
          oldPrio > 0 &&
          nsection == 0 &&
          angle < 0 &&
          oldPrio >= rc.crossingPrioH &&
          newPrio <= rc.crossingPrioL) {
        var classIndex = 0;
        if (sourceNode.nodeDescription != null) {
          final nodeAccessGranted = w.getNodeAccessGranted() != 0.0;
          final nodeTags = rc.expctxNode!.getKeyValueDescription(
            nodeAccessGranted,
            sourceNode.nodeDescription!,
          );
          classIndex = nodeTags.indexOf('estimated_crossing_class=');
          if (classIndex > -1) {
            final crossingClass = nodeTags.substring(
              classIndex + 25,
              classIndex + 26,
            );
            var additionalTurnCost = 0;
            if (crossingClass == '1') additionalTurnCost = rc.costToLeftFromHClass1;
            if (crossingClass == '2') additionalTurnCost = rc.costToLeftFromHClass2;
            if (crossingClass == '3') additionalTurnCost = rc.costToLeftFromHClass3;
            if (crossingClass == '4') additionalTurnCost = rc.costToLeftFromHClass4;
            if (crossingClass == '5') additionalTurnCost = rc.costToLeftFromHClass5;
            if (crossingClass == '6') additionalTurnCost = rc.costToLeftFromHClass6;
            turncost += additionalTurnCost;
          }
        }
      }

      // for left-hand traffic
      // If the turn is RIGHT and coming from "primary|secondary" to a lower priority HW AND estimated_crossing_class is defined on the node, than penalty!!!

      if (rc.considerCrossing &&
          oldPrio > 0 &&
          nsection == 0 &&
          angle > 0 &&
          oldPrio >= rc.crossingPrioH &&
          newPrio <= rc.crossingPrioL) {
        var classIndex = 0;
        if (sourceNode.nodeDescription != null) {
          final nodeAccessGranted = w.getNodeAccessGranted() != 0.0;
          final nodeTags = rc.expctxNode!.getKeyValueDescription(
            nodeAccessGranted,
            sourceNode.nodeDescription!,
          );
          classIndex = nodeTags.indexOf('estimated_crossing_class=');
          if (classIndex > -1) {
            final crossingClass = nodeTags.substring(
              classIndex + 25,
              classIndex + 26,
            );
            var additionalTurnCost = 0;
            if (crossingClass == '1') additionalTurnCost = rc.costToRightFromHClass1;
            if (crossingClass == '2') additionalTurnCost = rc.costToRightFromHClass2;
            if (crossingClass == '3') additionalTurnCost = rc.costToRightFromHClass3;
            if (crossingClass == '4') additionalTurnCost = rc.costToRightFromHClass4;
            if (crossingClass == '5') additionalTurnCost = rc.costToRightFromHClass5;
            if (crossingClass == '6') additionalTurnCost = rc.costToRightFromHClass6;
            turncost += additionalTurnCost;
          }
        }
      }
    }

    if (message != null) {
      message!.linkturncost += turncost;
      message!.turnangle = f32(angle);
    }

    var sectionCost = turncost.toDouble();

    // *** penalty for elevation
    // only the part of the descend that does not fit into the elevation-hysteresis-buffers
    // leads to an immediate penalty

    final deltaHMicros = d2i(1000000.0 * deltaH);
    // ehbd += -delta_h_micros - dist * downhillcutoff (float arithmetic, then (int))
    _ehbd = d2i(
      f32(
        f32(_ehbd.toDouble()) +
            f32(f32((-deltaHMicros).toDouble()) - f32(fdist * downhillcutoff)),
      ),
    );
    _ehbu = d2i(
      f32(
        f32(_ehbu.toDouble()) +
            f32(f32(deltaHMicros.toDouble()) - f32(fdist * uphillcutoff)),
      ),
    );

    var downweight = 0.0;
    if (_ehbd > rc.elevationpenaltybuffer) {
      downweight = 1.0;

      var excess = _ehbd - rc.elevationpenaltybuffer;
      var reduce = mul32(dist, rc.elevationbufferreduce);
      if (reduce > excess) {
        downweight = f32(f32(excess.toDouble()) / f32(reduce.toDouble()));
        reduce = excess;
      }
      excess = _ehbd - rc.elevationmaxbuffer;
      if (reduce < excess) {
        reduce = excess;
      }
      _ehbd -= reduce;
      var elevationCost = 0.0;
      if (_downhillcostdiv > 0) {
        elevationCost = f32(
          elevationCost +
              f32(
                _fmin(f32(reduce.toDouble()), f32(fdist * downhillmaxslope)) /
                    f32(_downhillcostdiv.toDouble()),
              ),
        );
      }
      if (downhillmaxslopecostdiv > 0) {
        elevationCost = f32(
          elevationCost +
              f32(
                _fmax(
                      0.0,
                      f32(f32(reduce.toDouble()) - f32(fdist * downhillmaxslope)),
                    ) /
                    f32(downhillmaxslopecostdiv.toDouble()),
              ),
        );
      }
      if (elevationCost > 0) {
        sectionCost += elevationCost;
        if (message != null) {
          message!.linkelevationcost = d2i(
            f32(f32(message!.linkelevationcost.toDouble()) + elevationCost),
          );
        }
      }
    } else if (_ehbd < 0) {
      _ehbd = 0;
    }

    var upweight = 0.0;
    if (_ehbu > rc.elevationpenaltybuffer) {
      upweight = 1.0;

      var excess = _ehbu - rc.elevationpenaltybuffer;
      var reduce = mul32(dist, rc.elevationbufferreduce);
      if (reduce > excess) {
        upweight = f32(f32(excess.toDouble()) / f32(reduce.toDouble()));
        reduce = excess;
      }
      excess = _ehbu - rc.elevationmaxbuffer;
      if (reduce < excess) {
        reduce = excess;
      }
      _ehbu -= reduce;
      var elevationCost = 0.0;
      if (_uphillcostdiv > 0) {
        elevationCost = f32(
          elevationCost +
              f32(
                _fmin(f32(reduce.toDouble()), f32(fdist * uphillmaxslope)) /
                    f32(_uphillcostdiv.toDouble()),
              ),
        );
      }
      if (uphillmaxslopecostdiv > 0) {
        elevationCost = f32(
          elevationCost +
              f32(
                _fmax(
                      0.0,
                      f32(f32(reduce.toDouble()) - f32(fdist * uphillmaxslope)),
                    ) /
                    f32(uphillmaxslopecostdiv.toDouble()),
              ),
        );
      }
      if (elevationCost > 0) {
        sectionCost += elevationCost;
        if (message != null) {
          message!.linkelevationcost = d2i(
            f32(f32(message!.linkelevationcost.toDouble()) + elevationCost),
          );
        }
      }
    } else if (_ehbu < 0) {
      _ehbu = 0;
    }

    // get the effective costfactor (slope dependent)
    final costfactor = f32(
      f32(
            f32(cfup * upweight) +
                f32(cf * f32(f32(1.0 - upweight) - downweight)),
          ) +
          f32(cfdown * downweight),
    );

    if (message != null) {
      message!.costfactor = costfactor;
    }

    sectionCost += f32(f32(fdist * costfactor) + 0.5);

    return sectionCost;
  }

  @override
  double processTargetNode(RoutingContext rc) {
    // finally add node-costs for target node
    if (targetNode.nodeDescription != null) {
      final nodeAccessGranted = rc.expctxWay!.getNodeAccessGranted() != 0.0;
      rc.expctxNode!.evaluate(nodeAccessGranted, targetNode.nodeDescription!);
      final initialcost = rc.expctxNode!.getInitialcost();
      if (initialcost >= 1000000.0) {
        return -1.0;
      }
      if (message != null) {
        message!.linknodecost += d2i(initialcost);
        message!.nodeKeyValues = rc.expctxNode!.getKeyValueDescription(
          nodeAccessGranted,
          targetNode.nodeDescription!,
        );
      }
      return initialcost;
    }
    return 0.0;
  }

  @override
  int elevationCorrection() {
    return (_downhillcostdiv > 0 ? _ehbd ~/ _downhillcostdiv : 0) +
        (_uphillcostdiv > 0 ? _ehbu ~/ _uphillcostdiv : 0);
  }

  @override
  bool definitlyWorseThan(OsmPath path) {
    final p = path as StdPath;

    var c = p.cost;
    if (p._downhillcostdiv > 0) {
      final delta =
          p._ehbd ~/ p._downhillcostdiv -
          (_downhillcostdiv > 0 ? _ehbd ~/ _downhillcostdiv : 0);
      if (delta > 0) c += delta;
    }
    if (p._uphillcostdiv > 0) {
      final delta =
          p._ehbu ~/ p._uphillcostdiv -
          (_uphillcostdiv > 0 ? _ehbu ~/ _uphillcostdiv : 0);
      if (delta > 0) c += delta;
    }

    return cost > c;
  }

  double _calcIncline(double dist) {
    const minDelta = 3.0;
    var shift = 0.0;
    if (_elevationBuffer > minDelta) {
      shift = -minDelta;
    } else if (_elevationBuffer < -minDelta) {
      shift = minDelta;
    }
    final decayFactor = JMath.exp(-dist / 100.0);
    final newElevationBuffer = f32(
      (_elevationBuffer + shift) * decayFactor - shift,
    );
    final incline = f32(_elevationBuffer - newElevationBuffer) / dist;
    _elevationBuffer = newElevationBuffer;
    return incline;
  }

  @override
  void computeKinematic(
    RoutingContext rc,
    double dist,
    double deltaH,
    bool detailMode,
  ) {
    if (!detailMode) {
      return;
    }

    // compute incline
    _elevationBuffer = f32(_elevationBuffer + deltaH);
    final incline = _calcIncline(dist);

    var maxSpeed = rc.maxSpeed;
    final speedLimit = f32(rc.expctxWay!.getMaxspeed() / f32(3.6));
    if (speedLimit > 0) {
      maxSpeed = math.min(maxSpeed, speedLimit);
    }

    var speed = maxSpeed; // Travel speed
    final fRoll = rc.totalMass * _gravity * (rc.defaultCr + incline);
    if (rc.footMode) {
      // Use Tobler's hiking function for walking sections
      speed = rc.maxSpeed * JMath.exp(-3.5 * (incline + 0.05).abs());
    } else if (rc.bikeMode) {
      speed = _solveCubic(rc.sCx, fRoll, rc.bikerPower);
      speed = math.min(speed, maxSpeed);
    }
    final dt = f32(dist / speed);
    _totalTime = f32(_totalTime + dt);
    // Calc energy assuming biking (no good model yet for hiking)
    // (Count only positive, negative would mean breaking to enforce maxspeed)
    final energy = dist * (rc.sCx * speed * speed + fRoll);
    if (energy > 0.0) {
      _totalEnergy = f32(_totalEnergy + energy);
    }
  }

  static double _solveCubic(double a, double c, double d) {
    // Solves a * v^3 + c * v = d with a Newton method
    // to get the speed v for the section.

    var v = 8.0;
    var findingStartvalue = true;
    for (var i = 0; i < 10; i++) {
      final y = (a * v * v + c) * v - d;
      if (y < .1) {
        if (findingStartvalue) {
          v *= 2.0;
          continue;
        }
        break;
      }
      findingStartvalue = false;
      final yPrime = 3 * a * v * v + c;
      v -= y / yPrime;
    }
    return v;
  }

  @override
  double getTotalTime() {
    return _totalTime;
  }

  @override
  double getTotalEnergy() {
    return _totalEnergy;
  }
}

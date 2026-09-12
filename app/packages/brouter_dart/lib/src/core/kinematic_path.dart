// Port of btools.router.KinematicPath (BRouter v1.7.10).
//
// The path-instance of the kinematic model

import 'dart:math' as math;

import '../jmath.dart';
import '../jvm.dart';
import 'kinematic_model.dart';
import 'kinematic_pre_path.dart';
import 'osm_path.dart';
import 'osm_pre_path.dart';
import 'routing_context.dart';

final class KinematicPath extends OsmPath {
  double _ekin = 0; // kinetic energy (Joule)
  double _totalTime = 0; // travel time (seconds)
  double _totalEnergy = 0; // total route energy (Joule)
  double _floatingAngleLeft = 0; // sliding average left bend (degree), float
  double _floatingAngleRight = 0; // sliding average right bend (degree), float

  @override
  void init(OsmPath orig) {
    final origin = orig as KinematicPath;
    _ekin = origin._ekin;
    _totalTime = origin._totalTime;
    _totalEnergy = origin._totalEnergy;
    _floatingAngleLeft = origin._floatingAngleLeft;
    _floatingAngleRight = origin._floatingAngleRight;
  }

  @override
  void resetState() {
    _ekin = 0.0;
    _totalTime = 0.0;
    _totalEnergy = 0.0;
    _floatingAngleLeft = 0.0;
    _floatingAngleRight = 0.0;
  }

  @override
  double processWaySection(
    RoutingContext rc,
    double dist,
    double deltaH,
    double elevation,
    double angle,
    double cosangle,
    bool isStartpoint,
    int nsection,
    int lastpriorityclassifier,
  ) {
    final km = rc.pm as KinematicModel;

    var cost = 0.0;
    var extraTime = 0.0;

    if (isStartpoint) {
      // for forward direction, we start with target speed
      if (!rc.inverseDirection) {
        extraTime = 0.5 * (1.0 - cosangle) * 40.0; // 40 seconds turn penalty
      }
    } else {
      var turnspeed = 999.0; // just high

      if (km.turnAngleDecayTime != 0.0) {
        // process turn-angle slowdown
        if (angle < 0) {
          _floatingAngleLeft = f32(_floatingAngleLeft - f32(angle));
        } else {
          _floatingAngleRight = f32(_floatingAngleRight + f32(angle));
        }
        final aa = math.max(_floatingAngleLeft, _floatingAngleRight);

        final curveSpeed = aa > 10.0 ? 200.0 / aa : 20.0;
        final distanceTime = dist / curveSpeed;
        final decayFactor = JMath.exp(-distanceTime / km.turnAngleDecayTime);
        _floatingAngleLeft = f32(_floatingAngleLeft * decayFactor);
        _floatingAngleRight = f32(_floatingAngleRight * decayFactor);

        if (curveSpeed < 20.0) {
          turnspeed = curveSpeed;
        }
      }

      if (nsection == 0) {
        // process slowdown by crossing geometry
        var junctionspeed = 999.0; // just high

        final classifiermask = d2i(rc.expctxWay!.getClassifierMask());

        // penalty for equal priority crossing
        var hasLeftWay = false;
        var hasRightWay = false;
        var hasResidential = false;
        for (
          OsmPrePath? prePath = rc.firstPrePath;
          prePath != null;
          prePath = prePath.next
        ) {
          final pp = prePath as KinematicPrePath;

          if (((pp.classifiermask ^ classifiermask) & 8) != 0) {
            // exactly one is linktype
            continue;
          }

          if ((pp.classifiermask & 32) != 0) {
            // touching a residential?
            hasResidential = true;
          }

          if (pp.priorityclassifier > priorityclassifier ||
              pp.priorityclassifier == priorityclassifier &&
                  priorityclassifier < 20) {
            final diff = pp.angle - angle;
            if (diff < -40.0 && diff > -140.0) hasLeftWay = true;
            if (diff > 40.0 && diff < 140.0) hasRightWay = true;
          }
        }
        const residentialSpeed = 13.0;

        if (hasLeftWay && junctionspeed > km.leftWaySpeed) {
          junctionspeed = km.leftWaySpeed;
        }
        if (hasRightWay && junctionspeed > km.rightWaySpeed) {
          junctionspeed = km.rightWaySpeed;
        }
        if (hasResidential && junctionspeed > residentialSpeed) {
          junctionspeed = residentialSpeed;
        }

        if ((lastpriorityclassifier < 20) ^ (priorityclassifier < 20)) {
          extraTime += 10.0;
          junctionspeed = 0; // full stop for entering or leaving road network
        }

        if (lastpriorityclassifier != priorityclassifier &&
            (classifiermask & 8) != 0) {
          extraTime += 2.0; // two seconds for entering a link-type
        }
        turnspeed = turnspeed > junctionspeed ? junctionspeed : turnspeed;

        if (message != null) {
          message!.vnode0 = d2i(junctionspeed * 3.6 + 0.5);
        }
      }
      _cutEkin(km.totalweight, turnspeed); // apply turnspeed
    }

    // linear temperature correction
    final tcorr = (20.0 - km.outsideTemp) * 0.0035;

    // air_pressure down 1mb/8m
    final ecorr = 0.0001375 * (elevation - 100.0);

    final fAir = km.fAir * (1.0 + tcorr - ecorr);

    final distanceCost = evolveDistance(km, dist, deltaH, fAir);

    final cf = rc.expctxWay!.getCostfactor();

    if (message != null) {
      message!.costfactor = f32(distanceCost / dist);
      message!.vmax = d2i(km.getWayMaxspeed() * 3.6 + 0.5);
      message!.vmaxExplicit = d2i(km.getWayMaxspeedExplicit() * 3.6 + 0.5);
      message!.vmin = d2i(km.getWayMinspeed() * 3.6 + 0.5);
      message!.extraTime = d2i(extraTime * 1000);
    }

    cost += dist * cf + 0.5;

    cost += (extraTime * km.pw / km.cost0);
    _totalTime += extraTime;

    cost += distanceCost;

    return cost;
  }

  double evolveDistance(
    KinematicModel km,
    double dist,
    double deltaH,
    double fAir,
  ) {
    // elevation force
    final fh = deltaH * km.totalweight * 9.81 / dist;

    final effectiveSpeedLimit = km.getEffectiveSpeedLimit();
    final emax =
        0.5 * km.totalweight * effectiveSpeedLimit * effectiveSpeedLimit;
    if (emax <= 0.0) {
      return -1.0;
    }
    final vb = km.getBreakingSpeed(effectiveSpeedLimit);
    final elow = 0.5 * km.totalweight * vb * vb;

    var elapsedTime = 0.0;
    var dissipatedEnergy = 0.0;

    var v = math.sqrt(2.0 * _ekin / km.totalweight);
    var d = dist;
    while (d > 0.0) {
      final slow = _ekin < elow;
      final fast = _ekin >= emax;
      final etarget = slow ? elow : emax;
      var f = km.fRoll + fAir * v * v + fh;
      final fRecup = math.max(
        0.0,
        fast ? -f : (slow ? km.fRecup : 0) - fh,
      ); // additional recup for slow part
      f += fRecup;

      double deltaEkin;
      double timeStep;
      double x;
      if (fast) {
        x = d;
        deltaEkin = x * f;
        timeStep = x / v;
        _ekin = etarget;
      } else {
        deltaEkin = etarget - _ekin;
        final b = 2.0 * fAir / km.totalweight;
        final x0 = deltaEkin / f;
        final x0b = x0 * b;
        x =
            x0 *
            (1.0 -
                x0b *
                    (0.5 +
                        x0b *
                            (0.333333333 -
                                x0b *
                                    0.25))); // = ln( delta_ekin*b/f + 1.) / b;
        final maxstep = math.min(50.0, d);
        if (x >= maxstep) {
          x = maxstep;
          final xb = x * b;
          deltaEkin =
              x *
              f *
              (1.0 +
                  xb *
                      (0.5 +
                          xb *
                              (0.166666667 +
                                  xb * 0.0416666667))); // = f/b* exp(xb-1)
          _ekin += deltaEkin;
        } else {
          _ekin = etarget;
        }
        final v2 = math.sqrt(2.0 * _ekin / km.totalweight);
        final a = f / km.totalweight; // TODO: average force?
        timeStep = (v2 - v) / a;
        v = v2;
      }
      d -= x;
      elapsedTime += timeStep;

      // dissipated energy does not contain elevation and efficient recup
      dissipatedEnergy += deltaEkin - x * (fh + fRecup * km.recupEfficiency);

      // correction: inefficient recup going into heating is half efficient
      final ieRecup = x * fRecup * (1.0 - km.recupEfficiency);
      final eaux = timeStep * km.pStandby;
      dissipatedEnergy -= math.max(ieRecup, eaux) * 0.5;
    }

    dissipatedEnergy += elapsedTime * km.pStandby;

    _totalTime += elapsedTime;
    _totalEnergy += dissipatedEnergy + dist * fh;

    return (km.pw * elapsedTime + dissipatedEnergy) / km.cost0; // =cost
  }

  @override
  double processTargetNode(RoutingContext rc) {
    final km = rc.pm as KinematicModel;

    // finally add node-costs for target node
    if (targetNode.nodeDescription != null) {
      rc.expctxNode!.evaluate(false, targetNode.nodeDescription!);
      final initialcost = rc.expctxNode!.getInitialcost();
      if (initialcost >= 1000000.0) {
        return -1.0;
      }
      _cutEkin(km.totalweight, km.getNodeMaxspeed()); // apply node maxspeed

      if (message != null) {
        message!.linknodecost += d2i(initialcost);
        message!.nodeKeyValues = rc.expctxNode!.getKeyValueDescription(
          false,
          targetNode.nodeDescription!,
        );

        message!.vnode1 = d2i(km.getNodeMaxspeed() * 3.6 + 0.5);
      }
      return initialcost;
    }
    return 0.0;
  }

  void _cutEkin(double weight, double speed) {
    final e = 0.5 * weight * speed * speed;
    if (_ekin > e) _ekin = e;
  }

  @override
  int elevationCorrection() {
    return 0;
  }

  @override
  bool definitlyWorseThan(OsmPath path) {
    final p = path as KinematicPath;

    final c = p.cost;
    return cost > c + 100;
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

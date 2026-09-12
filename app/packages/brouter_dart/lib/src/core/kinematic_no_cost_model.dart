// Port of btools.router.KinematicNoCostModel (BRouter v1.7.10).
//
// Container for link between two Osm nodes

import '../expressions/b_expression_context_node.dart';
import '../expressions/b_expression_context_way.dart';
import '../jfloat.dart';
import '../jvm.dart';
import 'kinematic_no_cost_path.dart';
import 'kinematic_pre_path.dart';
import 'osm_path.dart';
import 'osm_path_model.dart';
import 'osm_pre_path.dart';

final class KinematicNoCostModel extends OsmPathModel {
  @override
  OsmPrePath? createPrePath() {
    return KinematicPrePath();
  }

  @override
  OsmPath createPath() {
    return KinematicNoCostPath();
  }

  double turnAngleDecayTime = 0;
  double fRoll = 0;
  double fAir = 0;
  double fRecup = 0;
  double pStandby = 0;
  double outsideTemp = 0;
  double recupEfficiency = 0;
  double totalweight = 0;
  double vmax = 0;
  double leftWaySpeed = 0;
  double rightWaySpeed = 0;

  // derived values
  double pw = 0; // balance power
  double cost0 = 0; // minimum possible cost per meter

  int _wayIdxMaxspeed = 0;
  int _wayIdxMaxspeedExplicit = 0;
  int _wayIdxMinspeed = 0;

  int _nodeIdxMaxspeed = 0;

  late BExpressionContextWay ctxWay;
  late BExpressionContextNode ctxNode;
  Map<String, String>? params;

  bool _initDone = false;

  double _lastEffectiveLimit = 0;
  double _lastBreakingSpeed = 0;

  @override
  void init(
    BExpressionContextWay expctxWay,
    BExpressionContextNode expctxNode,
    Map<String, String>? extraParams,
  ) {
    if (!_initDone) {
      ctxWay = expctxWay;
      ctxNode = expctxNode;
      _wayIdxMaxspeed = ctxWay.getOutputVariableIndex('maxspeed', false);
      _wayIdxMaxspeedExplicit = ctxWay.getOutputVariableIndex(
        'maxspeed_explicit',
        false,
      );
      _wayIdxMinspeed = ctxWay.getOutputVariableIndex('minspeed', false);
      _nodeIdxMaxspeed = ctxNode.getOutputVariableIndex('maxspeed', false);
      _initDone = true;
    }

    params = extraParams;

    turnAngleDecayTime = getParam('turnAngleDecayTime', 5.0);
    fRoll = getParam('f_roll', 232.0);
    fAir = getParam('f_air', f32(0.4));
    fRecup = getParam('f_recup', 400.0);
    pStandby = getParam('p_standby', 250.0);
    outsideTemp = getParam('outside_temp', 20.0);
    recupEfficiency = getParam('recup_efficiency', f32(0.7));
    totalweight = getParam('totalweight', 1640.0);
    vmax = getParam('vmax', 80.0) / 3.6;
    leftWaySpeed = getParam('leftWaySpeed', 12.0) / 3.6;
    rightWaySpeed = getParam('rightWaySpeed', 12.0) / 3.6;

    pw = 2.0 * fAir * vmax * vmax * vmax - pStandby;
    cost0 = (pw + pStandby) / vmax + fRoll + fAir * vmax * vmax;
  }

  /// `float`
  double getParam(String name, double defaultValue) {
    final sval = params == null ? null : params![name];
    if (sval != null) {
      return javaParseFloat(sval);
    }
    final v = ctxWay.getVariableValue(name, defaultValue);
    if (params != null) {
      params![name] = javaFloatToString(v);
    }
    return v;
  }

  double getWayMaxspeed() {
    return f32(ctxWay.getBuildInVariable(_wayIdxMaxspeed) / f32(3.6));
  }

  double getWayMaxspeedExplicit() {
    return f32(ctxWay.getBuildInVariable(_wayIdxMaxspeedExplicit) / f32(3.6));
  }

  double getWayMinspeed() {
    return f32(ctxWay.getBuildInVariable(_wayIdxMinspeed) / f32(3.6));
  }

  double getNodeMaxspeed() {
    return f32(ctxNode.getBuildInVariable(_nodeIdxMaxspeed) / f32(3.6));
  }

  /// get the effective speed limit from the way-limit and vmax/vmin
  double getEffectiveSpeedLimit() {
    // performance related inline coding
    final minspeed = getWayMinspeed();
    final espeed = minspeed > vmax ? minspeed : vmax;
    final maxspeed = getWayMaxspeed();
    return maxspeed < espeed ? maxspeed : espeed;
  }

  /// get the breaking speed for current balance-power (pw) and effective speed limit (vl)
  double getBreakingSpeed(double vl) {
    if (vl == _lastEffectiveLimit) {
      return _lastBreakingSpeed;
    }

    var v = vl * 0.8;
    final pw2 = pw + pStandby;
    final e = recupEfficiency;
    final x0 = pw2 / vl + fAir * e * vl * vl + (1.0 - e) * fRoll;
    for (var i = 0; i < 5; i++) {
      final v2 = v * v;
      final x = pw2 / v + fAir * e * v2 - x0;
      final dx = 2.0 * e * fAir * v - pw2 / v2;
      v -= x / dx;
    }
    _lastEffectiveLimit = vl;
    _lastBreakingSpeed = v;

    return v;
  }
}

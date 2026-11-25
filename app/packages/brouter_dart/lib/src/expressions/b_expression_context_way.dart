// Port of btools.expressions.BExpressionContextWay (BRouter v1.7.10).

import 'dart:typed_data';

import '../codec/tag_value_validator.dart';
import 'b_expression_context.dart';
import 'b_expression_meta_data.dart';

final class BExpressionContextWay extends BExpressionContext
    implements TagValueValidator {
  /// `BExpressionContextWay(BExpressionMetaData meta)` (hashSize 4096) and
  /// `BExpressionContextWay(int hashSize, BExpressionMetaData meta)`.
  BExpressionContextWay(BExpressionMetaData? meta, [int hashSize = 4096])
    : super('way', hashSize, meta);

  bool _decodeForbidden = true;

  static const List<String> _buildInVariables = <String>[
    'costfactor',
    'turncost',
    'uphillcostfactor',
    'downhillcostfactor',
    'initialcost',
    'nodeaccessgranted',
    'initialclassifier',
    'trafficsourcedensity',
    'istrafficbackbone',
    'priorityclassifier',
    'classifiermask',
    'maxspeed',
    'uphillcost',
    'downhillcost',
    'uphillcutoff',
    'downhillcutoff',
    'uphillmaxslope',
    'downhillmaxslope',
    'uphillmaxslopecost',
    'downhillmaxslopecost',
  ];

  @override
  List<String> getBuildInVariableNames() => _buildInVariables;

  @pragma('vm:prefer-inline')
  double getCostfactor() => getBuildInVariable(0);

  @pragma('vm:prefer-inline')
  double getTurncost() => getBuildInVariable(1);

  @pragma('vm:prefer-inline')
  double getUphillCostfactor() => getBuildInVariable(2);

  @pragma('vm:prefer-inline')
  double getDownhillCostfactor() => getBuildInVariable(3);

  @pragma('vm:prefer-inline')
  double getInitialcost() => getBuildInVariable(4);

  @pragma('vm:prefer-inline')
  double getNodeAccessGranted() => getBuildInVariable(5);

  @pragma('vm:prefer-inline')
  double getInitialClassifier() => getBuildInVariable(6);

  @pragma('vm:prefer-inline')
  double getTrafficSourceDensity() => getBuildInVariable(7);

  @pragma('vm:prefer-inline')
  double getIsTrafficBackbone() => getBuildInVariable(8);

  @pragma('vm:prefer-inline')
  double getPriorityClassifier() => getBuildInVariable(9);

  @pragma('vm:prefer-inline')
  double getClassifierMask() => getBuildInVariable(10);

  @pragma('vm:prefer-inline')
  double getMaxspeed() => getBuildInVariable(11);

  @pragma('vm:prefer-inline')
  double getUphillcost() => getBuildInVariable(12);

  @pragma('vm:prefer-inline')
  double getDownhillcost() => getBuildInVariable(13);

  @pragma('vm:prefer-inline')
  double getUphillcutoff() => getBuildInVariable(14);

  @pragma('vm:prefer-inline')
  double getDownhillcutoff() => getBuildInVariable(15);

  @pragma('vm:prefer-inline')
  double getUphillmaxslope() => getBuildInVariable(16);

  @pragma('vm:prefer-inline')
  double getDownhillmaxslope() => getBuildInVariable(17);

  @pragma('vm:prefer-inline')
  double getUphillmaxslopecost() => getBuildInVariable(18);

  @pragma('vm:prefer-inline')
  double getDownhillmaxslopecost() => getBuildInVariable(19);

  @override
  int accessType(Uint8List description) {
    evaluate(false, description);
    var minCostFactor = getCostfactor();
    if (minCostFactor >= 9999.0) {
      setInverseVars();
      final reverseCostFactor = getCostfactor();
      if (reverseCostFactor < minCostFactor) {
        minCostFactor = reverseCostFactor;
      }
    }
    return minCostFactor < 9999.0
        ? 2
        : (_decodeForbidden ? (minCostFactor < 10000.0 ? 1 : 0) : 0);
  }

  @override
  void setDecodeForbidden(bool decodeForbidden) {
    _decodeForbidden = decodeForbidden;
  }
}

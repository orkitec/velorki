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

  double getCostfactor() => getBuildInVariable(0);

  double getTurncost() => getBuildInVariable(1);

  double getUphillCostfactor() => getBuildInVariable(2);

  double getDownhillCostfactor() => getBuildInVariable(3);

  double getInitialcost() => getBuildInVariable(4);

  double getNodeAccessGranted() => getBuildInVariable(5);

  double getInitialClassifier() => getBuildInVariable(6);

  double getTrafficSourceDensity() => getBuildInVariable(7);

  double getIsTrafficBackbone() => getBuildInVariable(8);

  double getPriorityClassifier() => getBuildInVariable(9);

  double getClassifierMask() => getBuildInVariable(10);

  double getMaxspeed() => getBuildInVariable(11);

  double getUphillcost() => getBuildInVariable(12);

  double getDownhillcost() => getBuildInVariable(13);

  double getUphillcutoff() => getBuildInVariable(14);

  double getDownhillcutoff() => getBuildInVariable(15);

  double getUphillmaxslope() => getBuildInVariable(16);

  double getDownhillmaxslope() => getBuildInVariable(17);

  double getUphillmaxslopecost() => getBuildInVariable(18);

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

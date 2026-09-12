// Port of btools.expressions.BExpressionContextNode (BRouter v1.7.10).

import 'b_expression_context.dart';
import 'b_expression_meta_data.dart';

final class BExpressionContextNode extends BExpressionContext {
  /// `BExpressionContextNode(BExpressionMetaData meta)` (hashSize 4096) and
  /// `BExpressionContextNode(int hashSize, BExpressionMetaData meta)`.
  BExpressionContextNode(BExpressionMetaData? meta, [int hashSize = 4096])
    : super('node', hashSize, meta);

  static const List<String> _buildInVariables = <String>['initialcost'];

  @override
  List<String> getBuildInVariableNames() => _buildInVariables;

  double getInitialcost() => getBuildInVariable(0);
}

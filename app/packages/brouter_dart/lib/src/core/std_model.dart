// Port of btools.router.StdModel (BRouter v1.7.10).
//
// Container for link between two Osm nodes

import '../expressions/b_expression_context_node.dart';
import '../expressions/b_expression_context_way.dart';
import 'osm_path.dart';
import 'osm_path_model.dart';
import 'osm_pre_path.dart';
import 'std_path.dart';

final class StdModel extends OsmPathModel {
  @override
  OsmPrePath? createPrePath() {
    return null;
  }

  @override
  OsmPath createPath() {
    return StdPath();
  }

  BExpressionContextWay? ctxWay;
  BExpressionContextNode? ctxNode;

  @override
  void init(
    BExpressionContextWay expctxWay,
    BExpressionContextNode expctxNode,
    Map<String, String>? keyValues,
  ) {
    ctxWay = expctxWay;
    ctxNode = expctxNode;
  }
}

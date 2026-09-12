// Port of btools.router.OsmPathModel (BRouter v1.7.10).
//
// Container for link between two Osm nodes

import '../expressions/b_expression_context_node.dart';
import '../expressions/b_expression_context_way.dart';
import 'osm_path.dart';
import 'osm_pre_path.dart';

abstract class OsmPathModel {
  OsmPrePath? createPrePath();

  OsmPath createPath();

  void init(
    BExpressionContextWay expctxWay,
    BExpressionContextNode expctxNode,
    Map<String, String>? keyValues,
  );
}

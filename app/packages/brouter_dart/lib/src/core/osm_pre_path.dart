// Port of btools.router.OsmPrePath (BRouter v1.7.10).
//
// Simple version of OsmPath just to get angle and priority of first segment

import '../mapaccess/osm_link.dart';
import '../mapaccess/osm_node.dart';
import 'osm_path.dart';
import 'routing_context.dart';

abstract class OsmPrePath {
  late OsmNode sourceNode;
  late OsmNode targetNode;
  late OsmLink link;

  OsmPrePath? next;

  void init(OsmPath origin, OsmLink link, RoutingContext rc) {
    this.link = link;
    sourceNode = origin.getTargetNode();
    targetNode = link.getTarget(sourceNode);
    initPrePath(origin, rc);
  }

  void initPrePath(OsmPath origin, RoutingContext rc);
}

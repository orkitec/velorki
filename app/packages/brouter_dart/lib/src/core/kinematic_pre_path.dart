// Port of btools.router.KinematicPrePath (BRouter v1.7.10).
//
// Simple version of OsmPath just to get angle and priority of first segment

import '../jvm.dart';
import '../mapaccess/osm_transfer_node.dart';
import 'osm_path.dart';
import 'osm_pre_path.dart';
import 'routing_context.dart';

final class KinematicPrePath extends OsmPrePath {
  double angle = 0;
  int priorityclassifier = 0;
  int classifiermask = 0;

  @override
  void initPrePath(OsmPath origin, RoutingContext rc) {
    //throw new IllegalArgumentException("null description for: " + link);
    final description =
        link.descriptionBitmap ??
        targetNode.descriptionBitmap ??
        defaultDescription();

    // extract the 3 positions of the first section
    final lon0 = origin.originLon;
    final lat0 = origin.originLat;

    final p1 = sourceNode;
    final lon1 = p1.getILon();
    final lat1 = p1.getILat();

    final isReverse = link.isReverse(sourceNode);

    // evaluate the way tags
    rc.expctxWay!.evaluate(rc.inverseDirection ^ isReverse, description);

    final OsmTransferNode? transferNode = link.geometry == null
        ? null
        : rc.geometryDecoder.decodeGeometry(
            link.geometry,
            p1,
            targetNode,
            isReverse,
          );

    int lon2;
    int lat2;

    if (transferNode == null) {
      lon2 = targetNode.ilon;
      lat2 = targetNode.ilat;
    } else {
      lon2 = transferNode.ilon;
      lat2 = transferNode.ilat;
    }

    rc.calcDistance(lon1, lat1, lon2, lat2);

    angle = rc.anglemeter.calcAngle(lon0, lat0, lon1, lat1, lon2, lat2);
    priorityclassifier = d2i(rc.expctxWay!.getPriorityClassifier());
    classifiermask = d2i(rc.expctxWay!.getClassifierMask());
  }
}

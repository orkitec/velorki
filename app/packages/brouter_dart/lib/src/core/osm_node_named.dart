// Port of btools.router.OsmNodeNamed (BRouter v1.7.10).
//
// Container for an osm node

import 'dart:math' as math;

import '../jfloat.dart';
import '../jvm.dart';
import '../mapaccess/matched_waypoint.dart';
import '../mapaccess/osm_node.dart';
import '../util/cheap_ruler.dart';

class OsmNodeNamed extends OsmNode {
  String? name;
  double radius = 0; // radius of nogopoint (in meters)
  double nogoWeight = 0; // weight for nogopoint
  bool isNogo = false;
  int wpttype = MatchedWaypoint.waypointTypeShaping; // set default type

  /// `OsmNodeNamed()` and `OsmNodeNamed(OsmNode n)`.
  OsmNodeNamed([OsmNode? n]) : super(n?.ilon ?? 0, n?.ilat ?? 0);

  @override
  String toString() {
    if (nogoWeight.isNaN) {
      return '$ilon,$ilat,$name';
    } else {
      return '$ilon,$ilat,$name,${javaDoubleToString(nogoWeight)}';
    }
  }

  double distanceWithinRadius(
    int lon1,
    int lat1,
    int lon2,
    int lat2,
    double totalSegmentLength,
  ) {
    final lonlat2m = CheapRuler.getLonLatToMeterScales((lat1 + lat2) >> 1);

    var isFirstPointWithinCircle =
        CheapRuler.distance(lon1, lat1, ilon, ilat) < radius;
    var isLastPointWithinCircle =
        CheapRuler.distance(lon2, lat2, ilon, ilat) < radius;
    // First point is within the circle
    if (isFirstPointWithinCircle) {
      // Last point is within the circle
      if (isLastPointWithinCircle) {
        return totalSegmentLength;
      }
      // Last point is not within the circle
      // Just swap points and go on with first first point not within the
      // circle now.
      // Swap longitudes
      var tmp = lon2;
      lon2 = lon1;
      lon1 = tmp;
      // Swap latitudes
      tmp = lat2;
      lat2 = lat1;
      lat1 = tmp;
      // Fix boolean values
      isLastPointWithinCircle = isFirstPointWithinCircle;
      isFirstPointWithinCircle = false;
    }
    // Distance between the initial point and projection of center of
    // the circle on the current segment.
    final initialToProject =
        (mul32(lon2 - lon1, ilon - lon1) * lonlat2m[0] * lonlat2m[0] +
            mul32(lat2 - lat1, ilat - lat1) * lonlat2m[1] * lonlat2m[1]) /
        totalSegmentLength;
    // Distance between the initial point and the center of the circle.
    final initialToCenter = CheapRuler.distance(ilon, ilat, lon1, lat1);
    // Half length of the segment within the circle
    final halfDistanceWithin = math.sqrt(
      radius * radius -
          (initialToCenter * initialToCenter -
              initialToProject * initialToProject),
    );
    // Last point is within the circle
    if (isLastPointWithinCircle) {
      return halfDistanceWithin + (totalSegmentLength - initialToProject);
    }
    return 2 * halfDistanceWithin;
  }

  static OsmNodeNamed decodeNogo(String s) {
    final n = OsmNodeNamed();
    final idx1 = s.indexOf(',');
    n.ilon = javaParseInt(s.substring(0, idx1));
    final idx2 = s.indexOf(',', idx1 + 1);
    n.ilat = javaParseInt(s.substring(idx1 + 1, idx2));
    final idx3 = s.indexOf(',', idx2 + 1);
    if (idx3 == -1) {
      n.name = s.substring(idx2 + 1);
      n.nogoWeight = double.nan;
    } else {
      n.name = s.substring(idx2 + 1, idx3);
      n.nogoWeight = javaParseDouble(s.substring(idx3 + 1));
    }
    n.isNogo = true;
    return n;
  }
}

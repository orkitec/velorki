// Port of btools.router.OsmNogoPolygon (BRouter v1.7.10).
//
// Copyright (C) 2018 Norbert Truchsess norbert.truchsess@t-online.de
//
// The following methods are based on work of Dan Sunday published at:
// http://geomalgorithms.com/a03-_inclusion.html
//
// cn_PnPoly, wn_PnPoly, inSegment, intersect2D_2Segments

import 'dart:math' as math;

import '../jvm.dart';
import '../util/cheap_ruler.dart';
import 'osm_node_named.dart';

final class Point {
  final int y;
  final int x;

  Point(int lon, int lat) : x = lon, y = lat;
}

class OsmNogoPolygon extends OsmNodeNamed {
  final List<Point> points = <Point>[];

  final bool isClosed;

  OsmNogoPolygon(bool closed) : isClosed = closed {
    isNogo = true;
    name = '';
  }

  void addVertex(int lon, int lat) {
    points.add(Point(lon, lat));
  }

  /// calcBoundingCircle is inspired by the algorithm described on
  /// http://geomalgorithms.com/a08-_containers.html
  /// (fast computation of bounding circly in c). It is not as fast (the original
  /// algorithm runs in linear time), as it may do more iterations but it takes
  /// into account the coslat-factor being used for the linear approximation that
  /// is also used in other places of brouter does change when moving the centerpoint
  /// with each iteration.
  /// This is done to ensure the calculated radius being used
  /// in RoutingContext.calcDistance will actually contain the whole polygon.
  ///
  /// For reasonable distributed vertices the implemented algorithm runs in O(n*ln(n)).
  /// As this is only run once on initialization of OsmNogoPolygon this methods
  /// overall usage of cpu is neglegible in comparism to the cpu-usage of the
  /// actual routing algoritm.
  void calcBoundingCircle() {
    var cxmin = intMaxValue;
    var cymin = intMaxValue;
    var cxmax = intMinValue;
    var cymax = intMinValue;

    // first calculate a starting center point as center of boundingbox
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      if (p.x < cxmin) {
        cxmin = p.x;
      }
      if (p.x > cxmax) {
        cxmax = p.x;
      }
      if (p.y < cymin) {
        cymin = p.y;
      }
      if (p.y > cymax) {
        cymax = p.y;
      }
    }

    var cx = i32(cxmax + cxmin) ~/ 2; // center of circle
    var cy = i32(cymax + cymin) ~/ 2;

    var lonlat2m = CheapRuler.getLonLatToMeterScales(
      cy,
    ); // conversion-factors at the center of circle
    var dlon2m = lonlat2m[0];
    var dlat2m = lonlat2m[1];

    var rad = 0.0; // radius

    var dmax = 0.0; // length of vector from center to point
    var iMax = -1;

    do {
      // now identify the point outside of the circle that has the greatest distance
      for (var i = 0; i < points.length; i++) {
        final p = points[i];

        // to get precisely the same results as in RoutingContext.calcDistance()
        // it's crucial to use the factors of the center!
        final x1 = (cx - p.x) * dlon2m;
        final y1 = (cy - p.y) * dlat2m;
        final dist = math.sqrt(x1 * x1 + y1 * y1);

        if (dist <= rad) {
          continue;
        }
        if (dist > dmax) {
          // new maximum distance found
          dmax = dist;
          iMax = i;
        }
      }
      if (iMax < 0) {
        break; // leave loop when no point outside the circle is found any more.
      }
      final dd = 0.5 * (1 - rad / dmax);

      final p = points[iMax]; // calculate new radius to just include this point
      cx = i32(cx + d2i(dd * (p.x - cx) + 0.5)); // shift center toward point
      cy = i32(cy + d2i(dd * (p.y - cy) + 0.5));

      // get new factors at shifted centerpoint
      lonlat2m = CheapRuler.getLonLatToMeterScales(cy);
      dlon2m = lonlat2m[0];
      dlat2m = lonlat2m[1];

      final x1 = (cx - p.x) * dlon2m;
      final y1 = (cy - p.y) * dlat2m;
      dmax = rad = math.sqrt(x1 * x1 + y1 * y1);
      iMax = -1;
    } while (true);

    ilon = cx;
    ilat = cy;
    radius =
        rad * 1.001 +
        1.0; // ensure the outside-of-enclosing-circle test in RoutingContext.calcDistance() is not passed by segments ending very close to the radius due to limited numerical precision
  }

  /// tests whether a segment defined by lon and lat of two points does either
  /// intersect the polygon or any of the endpoints (or both) are enclosed by
  /// the polygon. For this test the winding-number algorithm is
  /// being used. That means a point being within an overlapping region of the
  /// polygon is also taken as being 'inside' the polygon.
  bool intersects(int lon0, int lat0, int lon1, int lat1) {
    final p0 = Point(lon0, lat0);
    final p1 = Point(lon1, lat1);
    final iLast = points.length - 1;
    var p2 = points[isClosed ? iLast : 0];
    for (var i = isClosed ? 0 : 1; i <= iLast; i++) {
      final p3 = points[i];
      // does it intersect with at least one of the polygon's segments?
      if (_intersect2D2Segments(p0, p1, p2, p3) > 0) {
        return true;
      }
      p2 = p3;
    }
    return false;
  }

  bool isOnPolyline(int px, int py) {
    final iLast = points.length - 1;
    var p1 = points[0];
    for (var i = 1; i <= iLast; i++) {
      final p2 = points[i];
      if (isOnLine(px, py, p1.x, p1.y, p2.x, p2.y)) {
        return true;
      }
      p1 = p2;
    }
    return false;
  }

  static bool isOnLine(int px, int py, int p0x, int p0y, int p1x, int p1y) {
    final v10x = (px - p0x).toDouble();
    final v10y = (py - p0y).toDouble();
    final v12x = (p1x - p0x).toDouble();
    final v12y = (p1y - p0y).toDouble();

    if (v10x == 0) {
      // P0->P1 vertical?
      if (v10y == 0) {
        // P0 == P1?
        return true;
      }
      if (v12x != 0) {
        // P1->P2 not vertical?
        return false;
      }
      return (v12y / v10y) >= 1; // P1->P2 at least as long as P1->P0?
    }
    if (v10y == 0) {
      // P0->P1 horizontal?
      if (v12y != 0) {
        // P1->P2 not horizontal?
        return false;
      }
      // if ( P10x == 0 ) // P0 == P1? already tested
      return (v12x / v10x) >= 1; // P1->P2 at least as long as P1->P0?
    }
    final kx = v12x / v10x;
    if (kx < 1) {
      return false;
    }
    return kx == v12y / v10y;
  }

  /// winding number test for a point in a polygon
  bool isWithin(int px, int py) {
    var wn = 0; // the winding number counter

    // loop through all edges of the polygon
    final iLast = points.length - 1;
    final p0 = points[isClosed ? iLast : 0];
    var p0x = p0.x; // need to use long to avoid overflow in products
    var p0y = p0.y;

    for (var i = isClosed ? 0 : 1; i <= iLast; i++) {
      // edge from v[i] to v[i+1]
      final p1 = points[i];

      final p1x = p1.x;
      final p1y = p1.y;

      if (isOnLine(px, py, p0x, p0y, p1x, p1y)) {
        return true;
      }

      if (p0y <= py) {
        // start y <= p.y
        if (p1y > py) {
          // an upward crossing, p left of edge
          if (((p1x - p0x) * (py - p0y) - (px - p0x) * (p1y - p0y)) > 0) {
            ++wn; // have a valid up intersect
          }
        }
      } else {
        // start y > p.y (no test needed)
        if (p1y <= py) {
          // a downward crossing, p right of edge
          if (((p1x - p0x) * (py - p0y) - (px - p0x) * (p1y - p0y)) < 0) {
            --wn; // have a valid down intersect
          }
        }
      }
      p0x = p1x;
      p0y = p1y;
    }
    return wn != 0;
  }

  /// Compute the length of the segment within the polygon.
  double distanceWithinPolygon(int lon1, int lat1, int lon2, int lat2) {
    var distance = 0.0;

    // Extremities of the segments
    final p1 = Point(lon1, lat1);
    final p2 = Point(lon2, lat2);

    Point? previousIntersectionOnSegment;
    if (isWithin(lon1, lat1)) {
      // Start point of the segment is within the polygon, this is the first
      // "intersection".
      previousIntersectionOnSegment = p1;
    }

    // Loop over edges of the polygon to find intersections
    final iLast = points.length - 1;
    for (
      int i = (isClosed ? 0 : 1), j = (isClosed ? iLast : 0);
      i <= iLast;
      j = i++
    ) {
      final edgePoint1 = points[j];
      final edgePoint2 = points[i];
      final intersectsEdge = _intersect2D2Segments(
        p1,
        p2,
        edgePoint1,
        edgePoint2,
      );

      if (isClosed && intersectsEdge == 1) {
        // Intersects with a (closed) polygon edge on a single point
        // Distance is zero when crossing a polyline.
        // Let's find this intersection point
        final xdiffSegment = i32(lon1 - lon2);
        final xdiffEdge = i32(edgePoint1.x - edgePoint2.x);
        final ydiffSegment = i32(lat1 - lat2);
        final ydiffEdge = i32(edgePoint1.y - edgePoint2.y);
        final div = i32(
          mul32(xdiffSegment, ydiffEdge) - mul32(xdiffEdge, ydiffSegment),
        );
        final dSegment = lon1 * lat2 - lon2 * lat1;
        final dEdge = edgePoint1.x * edgePoint2.y - edgePoint2.x * edgePoint1.y;
        // Coordinates of the intersection
        final intersection = Point(
          i32((dSegment * xdiffEdge - dEdge * xdiffSegment) ~/ div),
          i32((dSegment * ydiffEdge - dEdge * ydiffSegment) ~/ div),
        );
        if (previousIntersectionOnSegment != null &&
            isWithin(
              i32(intersection.x + previousIntersectionOnSegment.x) >> 1,
              i32(intersection.y + previousIntersectionOnSegment.y) >> 1,
            )) {
          // There was a previous match within the polygon and this part of the
          // segment is within the polygon.
          distance += CheapRuler.distance(
            previousIntersectionOnSegment.x,
            previousIntersectionOnSegment.y,
            intersection.x,
            intersection.y,
          );
        }
        previousIntersectionOnSegment = intersection;
      } else if (intersectsEdge == 2) {
        // Segment and edge overlaps
        // FIXME: Could probably be done in a smarter way
        distance += math.min(
          CheapRuler.distance(p1.x, p1.y, p2.x, p2.y),
          math.min(
            CheapRuler.distance(
              edgePoint1.x,
              edgePoint1.y,
              edgePoint2.x,
              edgePoint2.y,
            ),
            math.min(
              CheapRuler.distance(p1.x, p1.y, edgePoint2.x, edgePoint2.y),
              CheapRuler.distance(edgePoint1.x, edgePoint1.y, p2.x, p2.y),
            ),
          ),
        );
        // FIXME: We could store intersection.
        previousIntersectionOnSegment = null;
      }
    }

    if (previousIntersectionOnSegment != null && isWithin(lon2, lat2)) {
      // Last point is within the polygon, add the remaining missing distance.
      distance += CheapRuler.distance(
        previousIntersectionOnSegment.x,
        previousIntersectionOnSegment.y,
        lon2,
        lat2,
      );
    }
    return distance;
  }

  /// inSegment(): determine if a point is inside a segment
  static bool _inSegment(Point p, Point segP0, Point segP1) {
    final sp0x = segP0.x;
    final sp1x = segP1.x;

    if (sp0x != sp1x) {
      // S is not vertical
      final px = p.x;
      if (sp0x <= px && px <= sp1x) {
        return true;
      }
      if (sp0x >= px && px >= sp1x) {
        return true;
      }
    } else {
      // S is vertical, so test y coordinate
      final sp0y = segP0.y;
      final sp1y = segP1.y;
      final py = p.y;

      if (sp0y <= py && py <= sp1y) {
        return true;
      }
      if (sp0y >= py && py >= sp1y) {
        return true;
      }
    }
    return false;
  }

  /// intersect2D_2Segments(): find the 2D intersection of 2 finite segments
  ///
  /// Returns 0=disjoint (no intersect), 1=intersect in unique point I0,
  /// 2=overlap in segment from I0 to I1
  static int _intersect2D2Segments(Point s1p0, Point s1p1, Point s2p0, Point s2p1) {
    final ux = s1p1.x - s1p0.x; // vector u = S1P1-S1P0 (segment 1)
    final uy = s1p1.y - s1p0.y;
    final vx = s2p1.x - s2p0.x; // vector v = S2P1-S2P0 (segment 2)
    final vy = s2p1.y - s2p0.y;
    final wx = s1p0.x - s2p0.x; // vector w = S1P0-S2P0 (from start of segment 2 to start of segment 1
    final wy = s1p0.y - s2p0.y;

    final d = (ux * vy - uy * vx).toDouble();

    // test if  they are parallel (includes either being a point)
    if (d == 0) {
      // S1 and S2 are parallel
      if ((ux * wy - uy * wx) != 0 || (vx * wy - vy * wx) != 0) {
        return 0; // they are NOT collinear
      }

      // they are collinear or degenerate
      // check if they are degenerate  points
      final du = ((ux == 0) && (uy == 0));
      final dv = ((vx == 0) && (vy == 0));
      if (du && dv) {
        // both segments are points
        return (wx == 0 && wy == 0) ? 0 : 1; // return 0 if they are distinct points
      }
      if (du) {
        // S1 is a single point
        return _inSegment(s1p0, s2p0, s2p1) ? 1 : 0; // is it part of S2?
      }
      if (dv) {
        // S2 a single point
        return _inSegment(s2p0, s1p0, s1p1) ? 1 : 0; // is it part of S1?
      }
      // they are collinear segments - get  overlap (or not)
      double t0, t1; // endpoints of S1 in eqn for S2
      final w2x = i32(s1p1.x - s2p0.x); // vector w2 = S1P1-S2P0 (from start of segment 2 to end of segment 1)
      final w2y = i32(s1p1.y - s2p0.y);
      if (vx != 0) {
        t0 = (wx ~/ vx).toDouble(); // long division
        t1 = (w2x ~/ vx).toDouble();
      } else {
        t0 = (wy ~/ vy).toDouble();
        t1 = (w2y ~/ vy).toDouble();
      }
      if (t0 > t1) {
        // must have t0 smaller than t1
        final t = t0; // swap if not
        t0 = t1;
        t1 = t;
      }
      if (t0 > 1 || t1 < 0) {
        return 0; // NO overlap
      }
      t0 = t0 < 0 ? 0 : t0; // clip to min 0
      t1 = t1 > 1 ? 1 : t1; // clip to max 1

      return (t0 == t1) ? 1 : 2; // return 1 if intersect is a point
    }

    // the segments are skew and may intersect in a point
    // get the intersect parameter for S1

    final sI = (vx * wy - vy * wx) / d;
    if (sI < 0 || sI > 1) {
      // no intersect with S1
      return 0;
    }

    // get the intersect parameter for S2
    final tI = (ux * wy - uy * wx) / d;
    return (tI < 0 || tI > 1) ? 0 : 1; // return 0 if no intersect with S2
  }
}

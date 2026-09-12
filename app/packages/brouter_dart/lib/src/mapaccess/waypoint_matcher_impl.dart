// Port of btools.mapaccess.WaypointMatcherImpl (BRouter v1.7.10).

import 'dart:math' as math;

import '../codec/waypoint_matcher.dart';
import '../jvm.dart';
import '../util/cheap_angle_meter.dart';
import '../util/cheap_ruler.dart';
import 'matched_waypoint.dart';
import 'osm_node.dart';
import 'osm_node_pair_set.dart';

/// the WaypointMatcher is feeded by the decoder with geoemtries of ways that are
/// already check for allowed access according to the current routing profile
///
/// It matches these geometries against the list of waypoints to find the best
/// match for each waypoint
class WaypointMatcherImpl implements WaypointMatcher {
  WaypointMatcherImpl(this._waypoints, double maxDistance, this._islandPairs) {
    MatchedWaypoint? last;
    _maxDistance = maxDistance;
    if (maxDistance < 0.0) {
      _maxDistance *= -1;
      maxDistance *= -1;
      useDynamicRange = true;
    }

    for (final mwp in _waypoints) {
      mwp.radius = maxDistance;
      if (last != null && mwp.directionToNext == -1) {
        last.directionToNext = CheapAngleMeter.getDirection(
          last.waypoint!.ilon,
          last.waypoint!.ilat,
          mwp.waypoint!.ilon,
          mwp.waypoint!.ilat,
        );
      }
      last = mwp;
    }
    // last point has no angle so we are looking back
    final lastidx = _waypoints.length - 2;
    if (lastidx < 0) {
      last!.directionToNext = -1;
    } else {
      last!.directionToNext = CheapAngleMeter.getDirection(
        last.waypoint!.ilon,
        last.waypoint!.ilat,
        _waypoints[lastidx].waypoint!.ilon,
        _waypoints[lastidx].waypoint!.ilat,
      );
    }
    _maxWptIdx = _waypoints.length - 1;
  }

  static const int _maxPoints = 5;

  final List<MatchedWaypoint> _waypoints;
  final OsmNodePairSet _islandPairs;

  int _lonStart = 0;
  int _latStart = 0;
  int _lonTarget = 0;
  int _latTarget = 0;
  bool _anyUpdate = false;
  int _lonLast = 0;
  int _latLast = 0;
  bool useAsStartWay = true;
  // ignore: unused_field
  late final int _maxWptIdx; // NOPMD assigned but never read upstream either
  late double _maxDistance;
  bool useDynamicRange = false;

  // sort result list
  static int _compare(MatchedWaypoint mw1, MatchedWaypoint mw2) {
    final cmpDist = javaDoubleCompare(mw1.radius, mw2.radius);
    if (cmpDist != 0) return cmpDist;
    return javaDoubleCompare(mw1.directionDiff, mw2.directionDiff);
  }

  void _checkSegment(int lon1, int lat1, int lon2, int lat2) {
    // todo: bounding-box pre-filter

    final lonlat2m = CheapRuler.getLonLatToMeterScales(
      shr32(i32(lat1 + lat2), 1),
    );
    final dlon2m = lonlat2m[0];
    final dlat2m = lonlat2m[1];

    final dx = (lon2 - lon1) * dlon2m;
    final dy = (lat2 - lat1) * dlat2m;
    final d = math.sqrt(dy * dy + dx * dx);

    if (d == 0.0) return;

    // for ( MatchedWaypoint mwp : waypoints )
    for (var i = 0; i < _waypoints.length; i++) {
      if (!useAsStartWay && i == 0) continue;
      final mwp = _waypoints[i];

      if (mwp.wpttype == MatchedWaypoint.waypointTypeDirect &&
          (i == 0 ||
              _waypoints[i - 1].wpttype ==
                  MatchedWaypoint.waypointTypeDirect)) {
        if (mwp.crosspoint == null) {
          final cp = mwp.crosspoint = OsmNode();
          cp.ilon = mwp.waypoint!.ilon;
          cp.ilat = mwp.waypoint!.ilat;
          mwp.hasUpdate = true;
          _anyUpdate = true;
        }
        continue;
      }

      final wp = mwp.waypoint!;
      final x1 = (lon1 - wp.ilon) * dlon2m;
      final y1 = (lat1 - wp.ilat) * dlat2m;
      final x2 = (lon2 - wp.ilon) * dlon2m;
      final y2 = (lat2 - wp.ilat) * dlat2m;
      final r12 = x1 * x1 + y1 * y1;
      final r22 = x2 * x2 + y2 * y2;
      var radius =
          (r12 < r22 ? y1 * dx - x1 * dy : y2 * dx - x2 * dy).abs() / d;

      if (radius <= mwp.radius) {
        var s1 = x1 * dx + y1 * dy;
        var s2 = x2 * dx + y2 * dy;

        if (s1 < 0.0) {
          s1 = -s1;
          s2 = -s2;
        }
        if (s2 > 0.0) {
          radius = math.sqrt(s1 < s2 ? r12 : r22);

          if (radius > mwp.radius) {
            continue;
          }
        }
        // new match for that waypoint
        mwp.radius = radius; // shortest distance to way
        mwp.hasUpdate = true;
        _anyUpdate = true;
        // calculate crosspoint
        final cp = mwp.crosspoint ??= OsmNode();
        if (s2 < 0.0) {
          final wayfraction = -s2 / (d * d);
          final xm = x2 - wayfraction * dx;
          final ym = y2 - wayfraction * dy;
          cp.ilon = d2i(xm / dlon2m + wp.ilon);
          cp.ilat = d2i(ym / dlat2m + wp.ilat);
        } else if (s1 > s2) {
          cp.ilon = lon2;
          cp.ilat = lat2;
        } else {
          cp.ilon = lon1;
          cp.ilat = lat1;
        }
      }
    }
  }

  @override
  bool start(
    int ilonStart,
    int ilatStart,
    int ilonTarget,
    int ilatTarget,
    bool useAsStartWay,
  ) {
    if (_islandPairs.size() > 0) {
      final n1 = (ilonStart << 32) | ilatStart;
      final n2 = (ilonTarget << 32) | ilatTarget;
      if (_islandPairs.hasPair(n1, n2)) {
        return false;
      }
    }
    _lonLast = _lonStart = ilonStart;
    _latLast = _latStart = ilatStart;
    _lonTarget = ilonTarget;
    _latTarget = ilatTarget;
    _anyUpdate = false;
    this.useAsStartWay = useAsStartWay;
    return true;
  }

  @override
  void transferNode(int ilon, int ilat) {
    _checkSegment(_lonLast, _latLast, ilon, ilat);
    _lonLast = ilon;
    _latLast = ilat;
  }

  @override
  void end() {
    _checkSegment(_lonLast, _latLast, _lonTarget, _latTarget);
    if (_anyUpdate) {
      for (final mwp in _waypoints) {
        if (mwp.hasUpdate) {
          var angle = CheapAngleMeter.getDirection(
            _lonStart,
            _latStart,
            _lonTarget,
            _latTarget,
          );
          var diff = CheapAngleMeter.getDifferenceFromDirection(
            mwp.directionToNext,
            angle,
          );

          mwp.hasUpdate = false;

          var mw = MatchedWaypoint();
          mw.waypoint = OsmNode();
          mw.waypoint!.ilon = mwp.waypoint!.ilon;
          mw.waypoint!.ilat = mwp.waypoint!.ilat;
          mw.crosspoint = OsmNode();
          mw.crosspoint!.ilon = mwp.crosspoint!.ilon;
          mw.crosspoint!.ilat = mwp.crosspoint!.ilat;
          mw.node1 = OsmNode(_lonStart, _latStart);
          mw.node2 = OsmNode(_lonTarget, _latTarget);
          mw.name = '${mwp.name}_w_${OsmNode.posHashCode(mwp.crosspoint!)}';
          mw.radius = mwp.radius;
          mw.directionDiff = diff;
          mw.directionToNext = mwp.directionToNext;

          updateWayList(mwp.wayNearest, mw);

          // revers
          angle = CheapAngleMeter.getDirection(
            _lonTarget,
            _latTarget,
            _lonStart,
            _latStart,
          );
          diff = CheapAngleMeter.getDifferenceFromDirection(
            mwp.directionToNext,
            angle,
          );
          mw = MatchedWaypoint();
          mw.waypoint = OsmNode();
          mw.waypoint!.ilon = mwp.waypoint!.ilon;
          mw.waypoint!.ilat = mwp.waypoint!.ilat;
          mw.crosspoint = OsmNode();
          mw.crosspoint!.ilon = mwp.crosspoint!.ilon;
          mw.crosspoint!.ilat = mwp.crosspoint!.ilat;
          mw.node1 = OsmNode(_lonTarget, _latTarget);
          mw.node2 = OsmNode(_lonStart, _latStart);
          mw.name = '${mwp.name}_w2_${OsmNode.posHashCode(mwp.crosspoint!)}';
          mw.radius = mwp.radius;
          mw.directionDiff = diff;
          mw.directionToNext = mwp.directionToNext;

          updateWayList(mwp.wayNearest, mw);

          final way = mwp.wayNearest[0];
          mwp.crosspoint!.ilon = way.crosspoint!.ilon;
          mwp.crosspoint!.ilat = way.crosspoint!.ilat;
          mwp.node1 = OsmNode(way.node1!.ilon, way.node1!.ilat);
          mwp.node2 = OsmNode(way.node2!.ilon, way.node2!.ilat);
          mwp.directionDiff = way.directionDiff;
          mwp.radius = way.radius;
        }
      }
    }
  }

  @override
  bool hasMatch(int lon, int lat) {
    for (final mwp in _waypoints) {
      if (mwp.waypoint!.ilon == lon &&
          mwp.waypoint!.ilat == lat &&
          (mwp.radius < _maxDistance || mwp.crosspoint != null)) {
        return true;
      }
    }
    return false;
  }

  // check limit of list size (avoid long runs)
  void updateWayList(List<MatchedWaypoint> ways, MatchedWaypoint mw) {
    ways.add(mw);
    // use only shortest distances by smallest direction difference
    _stableSort(ways, _compare);
    if (ways.length > _maxPoints) ways.removeAt(_maxPoints);
  }

  /// `Collections.sort` is stable; `List.sort` is not. The list never holds
  /// more than six entries.
  static void _stableSort(
    List<MatchedWaypoint> a,
    int Function(MatchedWaypoint, MatchedWaypoint) cmp,
  ) {
    for (var i = 1; i < a.length; i++) {
      final x = a[i];
      var j = i - 1;
      while (j >= 0 && cmp(a[j], x) > 0) {
        a[j + 1] = a[j];
        j--;
      }
      a[j + 1] = x;
    }
  }
}

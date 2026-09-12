// Port of btools.router.RoutingContext (BRouter v1.7.10).
//
// Container for routig configs
//
// Implements the `ProfileCacheClient` seam of the R3 `ProfileCache`.
// `setModel(className)` cannot use reflection: the three upstream path models
// are resolved by name. `localFunction` is a non-null String (empty for the
// Java `null`, which `getProfileName` reports as "unknown").

import 'dart:math' as math;
import 'dart:typed_data';

import '../expressions/b_expression_context.dart';
import '../expressions/b_expression_context_node.dart';
import '../expressions/b_expression_context_way.dart';
import '../expressions/profile_cache.dart';
import '../jfloat.dart';
import '../jvm.dart';
import '../mapaccess/geometry_decoder.dart';
import '../mapaccess/matched_waypoint.dart';
import '../mapaccess/osm_link.dart';
import '../mapaccess/osm_node.dart';
import '../util/cheap_angle_meter.dart';
import '../util/cheap_ruler.dart';
import 'area_info.dart';
import 'kinematic_model.dart';
import 'kinematic_no_cost_model.dart';
import 'osm_node_named.dart';
import 'osm_nogo_polygon.dart';
import 'osm_path.dart';
import 'osm_path_model.dart';
import 'osm_pre_path.dart';
import 'osm_track.dart';
import 'std_model.dart';

final class RoutingContext implements ProfileCacheClient {
  void setAlternativeIdx(int idx) {
    alternativeIdx = idx;
  }

  int getAlternativeIdx(int min, int max) {
    return alternativeIdx < min
        ? min
        : (alternativeIdx > max ? max : alternativeIdx);
  }

  int alternativeIdx = 0;

  @override
  String localFunction = '';

  @override
  int profileTimestamp = 0;

  @override
  Map<String, String>? keyValues;

  String? rawTrackPath;
  String? rawAreaPath;

  String getProfileName() {
    var name = localFunction.isEmpty ? 'unknown' : localFunction;
    if (name.endsWith('.brf')) {
      name = name.substring(0, localFunction.length - 4);
    }
    final idx = name.lastIndexOf('/');
    if (idx >= 0) name = name.substring(idx + 1);
    return name;
  }

  @override
  BExpressionContextWay? expctxWay;

  @override
  BExpressionContextNode? expctxNode;

  GeometryDecoder geometryDecoder = GeometryDecoder();

  @override
  int memoryclass = 64;

  bool carMode = false;
  bool bikeMode = false;
  bool footMode = false;
  bool considerTurnRestrictions = false;

  @override
  bool processUnusedTags = false;
  bool forceSecondaryData = false;
  double pass1coefficient = 0;
  double pass2coefficient = 0;
  int elevationpenaltybuffer = 0;
  int elevationmaxbuffer = 0;
  int elevationbufferreduce = 0;

  double cost1speed = 0;
  double additionalcostfactor = 0;
  double changetime = 0;
  double buffertime = 0;
  double waittimeadjustment = 0;
  double inittimeadjustment = 0;
  double starttimeoffset = 0;
  bool transitonly = false;

  double waypointCatchingRange = 0;
  bool correctMisplacedViaPoints = false;
  double correctMisplacedViaPointsDistance = 0;
  bool continueStraight = false;
  bool useDynamicDistance = false;
  bool buildBeelineOnRange = false;

  AreaInfo? ai;

  void _setModel(String? className) {
    if (className == null) {
      pm = StdModel();
    } else {
      switch (className) {
        case 'btools.router.StdModel':
          pm = StdModel();
          break;
        case 'btools.router.KinematicModel':
          pm = KinematicModel();
          break;
        case 'btools.router.KinematicNoCostModel':
          pm = KinematicNoCostModel();
          break;
        default:
          throw StateError(
            'Cannot create path-model: java.lang.ClassNotFoundException: $className',
          );
      }
    }
    initModel();
  }

  void initModel() {
    pm!.init(expctxWay!, expctxNode!, keyValues);
  }

  @override
  int getKeyValueChecksum() {
    var s = 0;
    if (keyValues != null) {
      for (final e in keyValues!.entries) {
        s += i32(javaStringHashCode(e.key) + javaStringHashCode(e.value));
      }
    }
    return s;
  }

  @override
  void readGlobalConfig() {
    final BExpressionContext expctxGlobal = expctxWay!; // just one of them...
    _setModel(expctxGlobal.modelClass);

    carMode = 0.0 != expctxGlobal.getVariableValue('validForCars', 0.0);
    bikeMode = 0.0 != expctxGlobal.getVariableValue('validForBikes', 0.0);
    footMode = 0.0 != expctxGlobal.getVariableValue('validForFoot', 0.0);

    considerCrossing =
        0.0 != expctxGlobal.getVariableValue('consider_crossing', 0.0);

    crossingPrioH = d2i(expctxGlobal.getVariableValue('crossing_Prio_H', 0.0));
    crossingPrioL = d2i(expctxGlobal.getVariableValue('crossing_Prio_L', 0.0));

    costToLeftFromHClass1 = d2i(
      expctxGlobal.getVariableValue('cost_ToLeft_from_H_class1', 0.0),
    );
    costToLeftFromHClass2 = d2i(
      expctxGlobal.getVariableValue('cost_ToLeft_from_H_class2', 0.0),
    );
    costToLeftFromHClass3 = d2i(
      expctxGlobal.getVariableValue('cost_ToLeft_from_H_class3', 0.0),
    );
    costToLeftFromHClass4 = d2i(
      expctxGlobal.getVariableValue('cost_ToLeft_from_H_class4', 0.0),
    );
    costToLeftFromHClass5 = d2i(
      expctxGlobal.getVariableValue('cost_ToLeft_from_H_class5', 0.0),
    );
    costToLeftFromHClass6 = d2i(
      expctxGlobal.getVariableValue('cost_ToLeft_from_H_class6', 0.0),
    );

    // for left-hand traffic
    costToRightFromHClass1 = d2i(
      expctxGlobal.getVariableValue('cost_ToRight_from_H_class1', 0.0),
    );
    costToRightFromHClass2 = d2i(
      expctxGlobal.getVariableValue('cost_ToRight_from_H_class2', 0.0),
    );
    costToRightFromHClass3 = d2i(
      expctxGlobal.getVariableValue('cost_ToRight_from_H_class3', 0.0),
    );
    costToRightFromHClass4 = d2i(
      expctxGlobal.getVariableValue('cost_ToRight_from_H_class4', 0.0),
    );
    costToRightFromHClass5 = d2i(
      expctxGlobal.getVariableValue('cost_ToRight_from_H_class5', 0.0),
    );
    costToRightFromHClass6 = d2i(
      expctxGlobal.getVariableValue('cost_ToRight_from_H_class6', 0.0),
    );

    waypointCatchingRange = expctxGlobal.getVariableValue(
      'waypointCatchingRange',
      250.0,
    );

    // turn-restrictions not used per default for foot profiles
    considerTurnRestrictions =
        0.0 !=
        expctxGlobal.getVariableValue(
          'considerTurnRestrictions',
          footMode ? 0.0 : 1.0,
        );

    correctMisplacedViaPoints =
        0.0 != expctxGlobal.getVariableValue('correctMisplacedViaPoints', 0.0);
    correctMisplacedViaPointsDistance = expctxGlobal.getVariableValue(
      'correctMisplacedViaPointsDistance',
      400.0,
    ); // 0 == don't use distance

    continueStraight =
        0.0 != expctxGlobal.getVariableValue('continueStraight', 0.0);

    // process tags not used in the profile (to have them in the data-tab)
    processUnusedTags =
        0.0 != expctxGlobal.getVariableValue('processUnusedTags', 0.0);

    forceSecondaryData =
        0.0 != expctxGlobal.getVariableValue('forceSecondaryData', 0.0);
    pass1coefficient = expctxGlobal.getVariableValue('pass1coefficient', 1.5);
    pass2coefficient = expctxGlobal.getVariableValue('pass2coefficient', 0.0);
    elevationpenaltybuffer = d2i(
      f32(
        expctxGlobal.getVariableValue('elevationpenaltybuffer', 5.0) * 1000000,
      ),
    );
    elevationmaxbuffer = d2i(
      f32(expctxGlobal.getVariableValue('elevationmaxbuffer', 10.0) * 1000000),
    );
    elevationbufferreduce = d2i(
      f32(expctxGlobal.getVariableValue('elevationbufferreduce', 0.0) * 10000),
    );

    cost1speed = expctxGlobal.getVariableValue('cost1speed', 22.0);
    additionalcostfactor = expctxGlobal.getVariableValue(
      'additionalcostfactor',
      1.5,
    );
    changetime = expctxGlobal.getVariableValue('changetime', 180.0);
    buffertime = expctxGlobal.getVariableValue('buffertime', 120.0);
    waittimeadjustment = expctxGlobal.getVariableValue(
      'waittimeadjustment',
      f32(0.9),
    );
    inittimeadjustment = expctxGlobal.getVariableValue(
      'inittimeadjustment',
      f32(0.2),
    );
    starttimeoffset = expctxGlobal.getVariableValue('starttimeoffset', 0.0);
    transitonly = expctxGlobal.getVariableValue('transitonly', 0.0) != 0.0;

    showspeed = 0.0 != expctxGlobal.getVariableValue('showspeed', 0.0);
    showSpeedProfile =
        0.0 != expctxGlobal.getVariableValue('showSpeedProfile', 0.0);
    inverseRouting =
        0.0 != expctxGlobal.getVariableValue('inverseRouting', 0.0);
    showTime = 0.0 != expctxGlobal.getVariableValue('showtime', 0.0);

    final tiMode = d2i(
      expctxGlobal.getVariableValue('turnInstructionMode', 0.0),
    );
    if (tiMode != 1) {
      // automatic selection from coordinate source
      turnInstructionMode = tiMode;
    }
    turnInstructionCatchingRange = expctxGlobal.getVariableValue(
      'turnInstructionCatchingRange',
      40.0,
    );
    turnInstructionRoundabouts =
        expctxGlobal.getVariableValue(
          'turnInstructionRoundabouts',
          footMode ? 0.0 : 1.0,
        ) !=
        0.0;

    // Speed computation model (for bikes)
    // Total mass (biker + bike + luggages or hiker), in kg
    totalMass = expctxGlobal.getVariableValue('totalMass', 90.0);
    // Max speed (before braking), in km/h in profile and m/s in code
    if (footMode) {
      maxSpeed = expctxGlobal.getVariableValue('maxSpeed', 6.0) / 3.6;
    } else {
      maxSpeed = expctxGlobal.getVariableValue('maxSpeed', 45.0) / 3.6;
    }
    // Equivalent surface for wind, S * C_x, F = -1/2 * S * C_x * v^2 = - S_C_x * v^2
    sCx = expctxGlobal.getVariableValue('S_C_x', f32(f32(0.5) * f32(0.45)));
    // Default resistance of the road, F = - m * g * C_r (for good quality road)
    defaultCr = expctxGlobal.getVariableValue('C_r', f32(0.01));
    // Constant power of the biker (in W)
    bikerPower = expctxGlobal.getVariableValue('bikerPower', 100.0);

    useDynamicDistance =
        expctxGlobal.getVariableValue('use_dynamic_range', 1.0) == 1.0;
    buildBeelineOnRange =
        expctxGlobal.getVariableValue('add_beeline', 0.0) == 1.0;

    final test = expctxGlobal.getVariableValue('check_start_way', 1.0) == 1.0;
    if (!test) freeNoWays();
  }

  void freeNoWays() {
    final BExpressionContext? expctxGlobal = expctxWay;
    if (expctxGlobal != null) expctxGlobal.freeNoWays();
  }

  List<OsmNodeNamed>? poipoints;

  List<OsmNodeNamed>? nogopoints;
  List<OsmNodeNamed>?
  _nogopointsAll; // full list not filtered for wayoints-in-nogos
  List<OsmNodeNamed>? _keepnogopoints;
  OsmNodeNamed? _pendingEndpoint;

  int? startDirection;
  bool startDirectionValid = false;
  bool forceUseStartDirection = false;
  int? roundTripDistance;
  int? roundTripDirectionAdd;
  int? roundTripPoints;
  bool allowSamewayback = false;

  CheapAngleMeter anglemeter = CheapAngleMeter();

  double nogoCost = 0.0;
  bool isEndpoint = false;

  bool shortestmatch = false;
  double wayfraction = 0;
  int ilatshortest = 0;
  int ilonshortest = 0;

  bool inverseDirection = false;

  bool showspeed = false;
  bool showSpeedProfile = false;
  bool inverseRouting = false;
  bool showTime = false;
  bool hasDirectRouting = false;

  String outputFormat = 'gpx';
  bool exportWaypoints = false;
  bool exportCorrectedWaypoints = false;

  OsmPrePath? firstPrePath;

  int turnInstructionMode =
      0; // 0=none, 1=auto, 2=locus, 3=osmand, 4=comment-style, 5=gpsies-style
  double turnInstructionCatchingRange = 0;
  bool turnInstructionRoundabouts = false;

  // Speed computation model (for bikes)
  double totalMass = 0;
  double maxSpeed = 0;
  double sCx = 0; // S_C_x
  double defaultCr = 0; // defaultC_r
  double bikerPower = 0;

  // variables in the profile to activate "crossing costs" at nodes with "estimated_crossing_class" not null
  bool considerCrossing = false; // consider crossing

  int crossingPrioH = 0; // min value to considered a HW as "highprio"
  int crossingPrioL = 0; // max value to considered a HW as "lowprio"

  // cost when turning left from a Highprio to a lowprio
  int costToLeftFromHClass1 = 0;
  int costToLeftFromHClass2 = 0;
  int costToLeftFromHClass3 = 0;
  int costToLeftFromHClass4 = 0;
  int costToLeftFromHClass5 = 0;
  int costToLeftFromHClass6 = 0;

  // cost when turning Right from a Highprio to a lowprio
  int costToRightFromHClass1 = 0;
  int costToRightFromHClass2 = 0;
  int costToRightFromHClass3 = 0;
  int costToRightFromHClass4 = 0;
  int costToRightFromHClass5 = 0;
  int costToRightFromHClass6 = 0;

  static void prepareNogoPoints(List<OsmNodeNamed> nogos) {
    for (final nogo in nogos) {
      if (nogo is OsmNogoPolygon) {
        continue;
      }
      var s = nogo.name!;
      final idx = s.indexOf(' ');
      if (idx > 0) s = s.substring(0, idx);
      var ir = 20; // default radius
      if (s.length > 4) {
        try {
          ir = javaParseInt(s.substring(4));
        } catch (e) {
          /* ignore */
        }
      }
      // Radius of the nogo point in meters
      nogo.radius = ir.toDouble();
    }
  }

  /// restore the full nogolist previously saved by cleanNogoList
  void restoreNogoList() {
    nogopoints = _nogopointsAll;
  }

  /// clean the nogolist (previoulsy saved by saveFullNogolist())
  /// by removing nogos with waypoints within
  void cleanNogoList(List<OsmNode> waypoints) {
    _nogopointsAll = nogopoints;
    if (nogopoints == null) return;
    final nogos = <OsmNodeNamed>[];
    for (final nogo in nogopoints!) {
      var goodGuy = true;
      for (final wp in waypoints) {
        if (wp.calcDistance(nogo) < nogo.radius &&
            (nogo is! OsmNogoPolygon ||
                (nogo.isClosed
                    ? nogo.isWithin(wp.ilon, wp.ilat)
                    : nogo.isOnPolyline(wp.ilon, wp.ilat)))) {
          goodGuy = false;
        }
      }
      if (goodGuy) nogos.add(nogo);
    }
    nogopoints = nogos.isEmpty ? null : nogos;
  }

  void checkMatchedWaypointAgainstNogos(
    List<MatchedWaypoint> matchedWaypoints,
  ) {
    if (nogopoints == null) return;
    final theSize = matchedWaypoints.length;
    if (theSize < 2) return;
    var removed = 0;
    final newMatchedWaypoints = <MatchedWaypoint>[];
    MatchedWaypoint? prevMwp;
    var prevMwpIsInside = false;
    for (var i = 0; i < theSize; i++) {
      final mwp = matchedWaypoints[i];
      var isInsideNogo = false;
      final wp = mwp.crosspoint!;
      for (final nogo in nogopoints!) {
        if (nogo.nogoWeight.isNaN &&
            wp.calcDistance(nogo) < nogo.radius &&
            (nogo is! OsmNogoPolygon ||
                (nogo.isClosed
                    ? nogo.isWithin(wp.ilon, wp.ilat)
                    : nogo.isOnPolyline(wp.ilon, wp.ilat)))) {
          isInsideNogo = true;
          break;
        }
      }
      if (isInsideNogo) {
        var useAnyway = false;
        if (prevMwp == null) {
          useAnyway = true;
        } else if (mwp.wpttype == MatchedWaypoint.waypointTypeDirect) {
          useAnyway = true;
        } else if (prevMwp.wpttype == MatchedWaypoint.waypointTypeDirect) {
          useAnyway = true;
        } else if (prevMwpIsInside) {
          useAnyway = true;
        } else if (i == theSize - 1) {
          throw ArgumentError('last wpt in restricted area ');
        }
        if (useAnyway) {
          prevMwpIsInside = true;
          newMatchedWaypoints.add(mwp);
        } else {
          removed++;
          prevMwpIsInside = false;
        }
      } else {
        prevMwpIsInside = false;
        newMatchedWaypoints.add(mwp);
      }
      prevMwp = mwp;
    }
    if (newMatchedWaypoints.length < 2) {
      throw ArgumentError('a wpt in restricted area ');
    }
    if (removed > 0) {
      matchedWaypoints.clear();
      matchedWaypoints.addAll(newMatchedWaypoints);
    }
  }

  bool allInOneNogo(List<OsmNode> waypoints) {
    if (nogopoints == null) return false;
    var allInTotal = false;
    for (final nogo in nogopoints!) {
      var allIn = nogo.nogoWeight.isNaN;
      for (final wp in waypoints) {
        final dist = wp.calcDistance(nogo);
        if (dist < nogo.radius &&
            (nogo is! OsmNogoPolygon ||
                (nogo.isClosed
                    ? nogo.isWithin(wp.ilon, wp.ilat)
                    : nogo.isOnPolyline(wp.ilon, wp.ilat)))) {
          continue;
        }
        allIn = false;
      }
      allInTotal |= allIn;
    }
    return allInTotal;
  }

  Int64List getNogoChecksums() {
    final cs = Int64List(3);
    final n = nogopoints == null ? 0 : nogopoints!.length;
    for (var i = 0; i < n; i++) {
      final nogo = nogopoints![i];
      cs[0] += nogo.ilon;
      cs[1] += nogo.ilat;
      // 10 is an arbitrary constant to get sub-integer precision in the checksum
      cs[2] += d2l(nogo.radius * 10.0);
    }
    return cs;
  }

  /// `setWaypoint(wp, endpoint)` and `setWaypoint(wp, pendingEndpoint, endpoint)`.
  void setWaypoint(
    OsmNodeNamed wp,
    bool endpoint, [
    OsmNodeNamed? pendingEndpoint,
  ]) {
    _keepnogopoints = nogopoints;
    nogopoints = <OsmNodeNamed>[];
    nogopoints!.add(wp);
    if (_keepnogopoints != null) nogopoints!.addAll(_keepnogopoints!);
    isEndpoint = endpoint;
    _pendingEndpoint = pendingEndpoint;
  }

  bool checkPendingEndpoint() {
    if (_pendingEndpoint != null) {
      isEndpoint = true;
      nogopoints![0] = _pendingEndpoint!;
      _pendingEndpoint = null;
      return true;
    }
    return false;
  }

  void unsetWaypoint() {
    nogopoints = _keepnogopoints;
    _pendingEndpoint = null;
    isEndpoint = false;
  }

  int calcDistance(int lon1, int lat1, int lon2, int lat2) {
    final lonlat2m = CheapRuler.getLonLatToMeterScales((lat1 + lat2) >> 1);
    final dlon2m = lonlat2m[0];
    final dlat2m = lonlat2m[1];
    var dx = (lon2 - lon1) * dlon2m;
    var dy = (lat2 - lat1) * dlat2m;
    var d = math.sqrt(dy * dy + dx * dx);

    shortestmatch = false;

    if (nogopoints != null && nogopoints!.isNotEmpty && d > 0.0) {
      for (var ngidx = 0; ngidx < nogopoints!.length; ngidx++) {
        final nogo = nogopoints![ngidx];
        final x1 = (lon1 - nogo.ilon) * dlon2m;
        final y1 = (lat1 - nogo.ilat) * dlat2m;
        final x2 = (lon2 - nogo.ilon) * dlon2m;
        final y2 = (lat2 - nogo.ilat) * dlat2m;
        final r12 = x1 * x1 + y1 * y1;
        final r22 = x2 * x2 + y2 * y2;
        var radius =
            (r12 < r22 ? y1 * dx - x1 * dy : y2 * dx - x2 * dy).abs() / d;

        if (radius < nogo.radius) {
          // 20m
          var s1 = x1 * dx + y1 * dy;
          var s2 = x2 * dx + y2 * dy;

          if (s1 < 0.0) {
            s1 = -s1;
            s2 = -s2;
          }
          if (s2 > 0.0) {
            radius = math.sqrt(s1 < s2 ? r12 : r22);
            if (radius > nogo.radius) continue;
          }
          if (nogo.isNogo) {
            if (nogo is! OsmNogoPolygon) {
              // nogo is a circle
              if (nogo.nogoWeight.isNaN) {
                // default nogo behaviour (ignore completely)
                nogoCost = -1;
              } else {
                // nogo weight, compute distance within the circle
                nogoCost =
                    nogo.distanceWithinRadius(lon1, lat1, lon2, lat2, d) *
                    nogo.nogoWeight;
              }
            } else if (nogo.intersects(lon1, lat1, lon2, lat2)) {
              // nogo is a polyline/polygon, we have to check there is indeed
              // an intersection in this case (radius check is not enough).
              if (nogo.nogoWeight.isNaN) {
                // default nogo behaviour (ignore completely)
                nogoCost = -1;
              } else {
                if (nogo.isClosed) {
                  // compute distance within the polygon
                  nogoCost =
                      nogo.distanceWithinPolygon(lon1, lat1, lon2, lat2) *
                      nogo.nogoWeight;
                } else {
                  // for a polyline, just add a constant penalty
                  nogoCost = nogo.nogoWeight;
                }
              }
            }
          } else {
            shortestmatch = true;
            nogo.radius = radius; // shortest distance to way
            // calculate remaining distance
            if (s2 < 0.0) {
              wayfraction = -s2 / (d * d);
              final xm = x2 - wayfraction * dx;
              final ym = y2 - wayfraction * dy;
              ilonshortest = d2i(xm / dlon2m + nogo.ilon);
              ilatshortest = d2i(ym / dlat2m + nogo.ilat);
            } else if (s1 > s2) {
              wayfraction = 0.0;
              ilonshortest = lon2;
              ilatshortest = lat2;
            } else {
              wayfraction = 1.0;
              ilonshortest = lon1;
              ilatshortest = lat1;
            }

            // here it gets nasty: there can be nogo-points in the list
            // *after* the shortest distance point. In case of a shortest-match
            // we use the reduced way segment for nogo-matching, in order not
            // to cut our escape-way if we placed a nogo just in front of where we are
            if (isEndpoint) {
              wayfraction = 1.0 - wayfraction;
              lon2 = ilonshortest;
              lat2 = ilatshortest;
            } else {
              nogoCost = 0.0;
              lon1 = ilonshortest;
              lat1 = ilatshortest;
            }
            dx = (lon2 - lon1) * dlon2m;
            dy = (lat2 - lat1) * dlat2m;
            d = math.sqrt(dy * dy + dx * dx);
          }
        }
      }
    }
    return d2i(math.max(1.0, javaRound(d).toDouble()));
  }

  OsmPathModel? pm;

  OsmPrePath? createPrePath(OsmPath origin, OsmLink link) {
    final p = pm!.createPrePath();
    if (p != null) {
      p.init(origin, link, this);
    }
    return p;
  }

  /// `createPath(OsmLink link)`
  OsmPath createStartPath(OsmLink link) {
    final p = pm!.createPath();
    p.initLink(link);
    return p;
  }

  /// `createPath(OsmPath origin, OsmLink link, OsmTrack refTrack, boolean detailMode)`
  OsmPath createPath(
    OsmPath origin,
    OsmLink link,
    OsmTrack? refTrack,
    bool detailMode,
  ) {
    final p = pm!.createPath();
    p.initFrom(origin, link, refTrack, detailMode, this);
    return p;
  }
}

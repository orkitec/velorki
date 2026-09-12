// Port of btools.router.RoutingEngine (BRouter v1.7.10).
//
// Deviations from upstream, all outside the search itself:
//
// * The engine is not a `Thread`. The search loop of `_findTrack` is `async`
//   so that a host isolate can cancel it cooperatively: every
//   [yieldInterval] node expansions the optional [yieldHook] is awaited (the
//   `RoutingWorker` yields to its event loop there and `terminate()` takes
//   effect like the thread-priority watchdog upstream). Without a hook the
//   loop never suspends. [progressListener] is called at the same cadence.
// * `maxRunningTime` is ported with its `> 0` guard: 0 disables every
//   timeout, which is how the oracle runs (`-DmaxRunningTime=0`).
// * The debug.txt / stacks.txt hooks of the constructor and the
//   `StackSampler` are not ported; `logInfo` goes to the optional [infoLog]
//   sink (upstream: stdout when an outfile base is given).
// * `Math.random()` (round trips without `direction`) is `dart:math`
//   `Random`; the results are not reproducible on either side.

import 'dart:io';
import 'dart:math' as math;

import '../expressions/profile_cache.dart';
import '../jfloat.dart';
import '../jvm.dart';
import '../profile.dart';
import '../mapaccess/matched_waypoint.dart';
import '../mapaccess/nodes_cache.dart';
import '../mapaccess/osm_link.dart';
import '../mapaccess/osm_link_holder.dart';
import '../mapaccess/osm_node.dart';
import '../mapaccess/osm_node_pair_set.dart';
import '../mapaccess/osm_pos.dart';
import '../mapaccess/raw_cell_cache.dart';
import '../util/cheap_angle_meter.dart';
import '../util/cheap_ruler.dart';
import '../util/compact_long_map.dart';
import '../util/sorted_heap.dart';
import 'area_info.dart';
import 'area_reader.dart';
import 'format_csv.dart';
import 'format_gpx.dart';
import 'format_json.dart';
import 'format_kml.dart';
import 'formatter.dart';
import 'message_data.dart';
import 'osm_node_named.dart';
import 'osm_nogo_polygon.dart';
import 'osm_path.dart';
import 'osm_path_element.dart';
import 'osm_track.dart';
import 'routing_context.dart';
import 'routing_island_exception.dart';
import 'search_boundary.dart';

int _currentTimeMillis() => DateTime.now().millisecondsSinceEpoch;

class RoutingEngine {
  static const int brouterEngineModeRouting = 0;
  static const int brouterEngineModeSeed = 1;
  static const int brouterEngineModeGetElev = 2;
  static const int brouterEngineModeGetInfo = 3;
  static const int brouterEngineModeRoundTrip = 4;

  NodesCache? nodesCache;
  final SortedHeap<OsmPath> _openSet = SortedHeap<OsmPath>();
  bool _finished = false;

  List<OsmNodeNamed> waypoints;
  List<OsmNodeNamed>? extraWaypoints;
  List<MatchedWaypoint>? matchedWaypoints;
  int _linksProcessed = 0;

  int _nodeLimit = 0; // used for target island search
  static const int _maxnodesIslandCheck = 500;
  final OsmNodePairSet _islandNodePairs = OsmNodePairSet(_maxnodesIslandCheck);
  final bool _useNodePoints =
      false; // use the start/end nodes  instead of crosspoint

  int engineMode = 0;

  static const int _maxStepsCheck = 500;

  static const int _roundtripDefaultDirectionadd = 45;

  static const int _maxDynamicRange = 60000;

  OsmTrack foundTrack = OsmTrack();
  OsmTrack? _foundRawTrack;
  int _alternativeIndex = 0;

  String? outputMessage;
  String? errorMessage;

  bool _terminated = false;

  Directory segmentDir;
  final String? _outfileBase;
  final String? _logfileBase;
  RoutingContext routingContext;

  double airDistanceCostFactor = 0;
  double lastAirDistanceCostFactor = 0;

  OsmTrack? _guideTrack;

  OsmPathElement? _matchPath;

  int _startTime = 0;
  int _maxRunningTime = 0;
  SearchBoundary? boundary;

  bool quite = false;

  List<OsmPath?>? _extract;

  final bool _directWeaving = !NodesCache.disableDirectWeaving;
  String? _outfile;

  /// `System.getProperty("reportFormat")`.
  static String? reportFormat;

  /// Where `logInfo` goes (upstream prints to stdout with an outfile base and
  /// appends to `debug.txt` if it exists). Null: no logging at all.
  void Function(String line)? infoLog;

  /// Awaited every [yieldInterval] node expansions of the search when set.
  Future<void> Function()? yieldHook;
  int yieldInterval = 2000;
  int _expansions = 0;

  /// Called every [yieldInterval] expansions with the links processed so far
  /// and the size of the open set.
  void Function(int linksProcessed, int openSetSize)? progressListener;

  /// The R5 byte-level cell cache handed to every `NodesCache` of this
  /// engine (null: no byte-level caching, upstream behaviour).
  RawCellCache? rawCache;

  RoutingEngine(
    String? outfileBase,
    String? logfileBase,
    this.segmentDir,
    this.waypoints,
    RoutingContext rc, [
    this.engineMode = 0,
  ]) : _outfileBase = outfileBase,
       _logfileBase = logfileBase,
       routingContext = rc {
    // (debug.txt / stacks.txt hooks of the profile's base folder: not ported)
    final cachedProfile = ProfileCache.parseProfile(rc);
    if (_hasInfo()) {
      _logInfo('parsed profile ${rc.localFunction} cached=$cachedProfile');
    }
  }

  bool _hasInfo() {
    return infoLog != null;
  }

  void _logInfo(String s) {
    final sink = infoLog;
    if (sink != null) sink(s);
  }

  void _logThrowable(Object t, StackTrace st) {
    _logInfo('$t\n$st');
  }

  /// `run()`
  Future<void> run() {
    return doRun(0);
  }

  Future<void> doRun(int maxRunningTime) async {
    switch (engineMode) {
      case brouterEngineModeRouting:
        if (waypoints.length < 2) {
          throw ArgumentError('we need two lat/lon points at least!');
        }
        await doRouting(maxRunningTime);
        break;
      case brouterEngineModeSeed:
        /* do nothing, handled the old way */
        throw ArgumentError('not a valid engine mode');
      case brouterEngineModeGetElev:
      case brouterEngineModeGetInfo:
        if (waypoints.isEmpty) {
          throw ArgumentError('we need one lat/lon point at least!');
        }
        await doGetInfo();
        break;
      case brouterEngineModeRoundTrip:
        if (waypoints.isEmpty) {
          throw ArgumentError('we need one lat/lon point at least!');
        }
        await doRoundTrip();
        break;
      default:
        throw ArgumentError('not a valid engine mode');
    }
  }

  Future<void> doRouting(int maxRunningTime) async {
    try {
      _startTime = _currentTimeMillis();
      final startTime0 = _startTime;
      _maxRunningTime = maxRunningTime;

      if (routingContext.allowSamewayback) {
        if (waypoints.length == 2) {
          final onn = OsmNodeNamed(
            OsmNode(waypoints[0].ilon, waypoints[0].ilat),
          );
          onn.name = 'to';
          waypoints.add(onn);
        } else {
          waypoints[waypoints.length - 1].name =
              'via${waypoints.length - 1}_center';
          final newpoints = <OsmNodeNamed>[];
          for (var i = waypoints.length - 2; i >= 0; i--) {
            final onn = OsmNodeNamed(
              OsmNode(waypoints[i].ilon, waypoints[i].ilat),
            );
            onn.name = 'via';
            newpoints.add(onn);
          }
          newpoints[newpoints.length - 1].name = 'to';
          waypoints.addAll(newpoints);
        }
      }

      final nsections = waypoints.length - 1;
      final refTracks = List<OsmTrack?>.filled(
        nsections,
        null,
      ); // used ways for alternatives
      final lastTracks = List<OsmTrack?>.filled(nsections, null);
      OsmTrack? track;
      final messageList = <String>[];
      for (var i = 0; ; i++) {
        track = await findTrack(refTracks, lastTracks);

        // we are only looking for info
        if (routingContext.ai != null) return;

        track!.message =
            'track-length = ${track.distance} filtered ascend = ${track.ascend} plain-ascend = ${track.plainAscend} cost=${track.cost}';
        if (track.energy != 0) {
          track.message =
              '${track.message} energy=${Formatter.getFormattedEnergy(track.energy)} time=${Formatter.getFormattedTime2(track.getTotalSeconds())}';
        }
        track.name = 'brouter_${routingContext.getProfileName()}_$i';

        messageList.add(track.message!);
        track.messageList = messageList;
        if (_outfileBase != null) {
          var filename = '$_outfileBase$i.${routingContext.outputFormat}';
          OsmTrack? oldTrack;
          switch (routingContext.outputFormat) {
            case 'gpx':
              oldTrack = FormatGpx(routingContext).read(filename);
              break;
            case 'geojson': // read only gpx at the moment
            case 'json':
              // oldTrack = new FormatJson(routingContext).read(filename);
              break;
            case 'kml':
              // oldTrack = new FormatJson(routingContext).read(filename);
              break;
            default:
              break;
          }
          if (oldTrack != null && track.equalsTrack(oldTrack)) {
            continue;
          }
          oldTrack = null;
          track.exportWaypoints = routingContext.exportWaypoints;
          track.exportCorrectedWaypoints =
              routingContext.exportCorrectedWaypoints;
          filename = '$_outfileBase$i.${routingContext.outputFormat}';
          switch (routingContext.outputFormat) {
            case 'gpx':
              outputMessage = FormatGpx(routingContext).format(track);
              break;
            case 'geojson':
            case 'json':
              outputMessage = FormatJson(routingContext).format(track);
              break;
            case 'kml':
              outputMessage = FormatKml(routingContext).format(track);
              break;
            case 'csv':
            default:
              outputMessage = null;
              break;
          }
          if (outputMessage != null) {
            File(filename).writeAsStringSync(outputMessage!);
            outputMessage = null;
          }

          foundTrack = track;
          _alternativeIndex = i;
          _outfile = filename;
        } else {
          if (i == routingContext.getAlternativeIdx(0, 3)) {
            if ('CSV' == reportFormat) {
              final filename = '$_outfileBase$i.csv';
              FormatCsv(routingContext).write(filename, track);
            } else {
              if (!quite) {
                print(FormatGpx(routingContext).format(track));
              }
            }
            foundTrack = track;
          } else {
            continue;
          }
        }
        if (_logfileBase != null) {
          final logfilename = '$_logfileBase$i.csv';
          FormatCsv(routingContext).write(logfilename, track);
        }
        break;
      }
      final endTime = _currentTimeMillis();
      _logInfo('execution time = ${(endTime - startTime0) / 1000.0} seconds');
    } on ArgumentError catch (e) {
      _logException(e);
    } catch (e, st) {
      _logException(e);
      _logThrowable(e, st);
    } finally {
      if (_hasInfo() && routingContext.expctxWay != null) {
        _logInfo(
          'expression cache stats=${routingContext.expctxWay!.cacheStats()}',
        );
      }

      ProfileCache.releaseProfile(routingContext);

      if (nodesCache != null) {
        if (_hasInfo() && nodesCache != null) {
          _logInfo(
            'NodesCache status before close=${nodesCache!.formatStatus()}',
          );
        }
        nodesCache!.close();
        nodesCache = null;
      }
      _openSet.clear();
      _finished = true; // this signals termination to outside
    }
  }

  Future<void> doGetInfo() async {
    try {
      _startTime = _currentTimeMillis();

      routingContext.freeNoWays();

      final wpt1 = MatchedWaypoint();
      wpt1.waypoint = waypoints[0];
      wpt1.name = 'wpt_info';
      final listOne = <MatchedWaypoint>[];
      listOne.add(wpt1);
      _matchWaypointsToNodes(listOne);

      _resetCache(true);
      nodesCache!.nodesMap.cleanupMode = 0;

      final start1 = nodesCache!.getGraphNode(listOne[0].node1!);
      nodesCache!.obtainNonHollowNode(start1);

      _guideTrack = OsmTrack();
      _guideTrack!.addNode(
        OsmPathElement.createAt(wpt1.node2!.ilon, wpt1.node2!.ilat, 0, null),
      );
      _guideTrack!.addNode(
        OsmPathElement.createAt(wpt1.node1!.ilon, wpt1.node1!.ilat, 0, null),
      );

      matchedWaypoints = <MatchedWaypoint>[];
      final wp1 = MatchedWaypoint();
      wp1.crosspoint = OsmNode(wpt1.node1!.ilon, wpt1.node1!.ilat);
      wp1.node1 = OsmNode(wpt1.node1!.ilon, wpt1.node1!.ilat);
      wp1.node2 = OsmNode(wpt1.node2!.ilon, wpt1.node2!.ilat);
      matchedWaypoints!.add(wp1);
      final wp2 = MatchedWaypoint();
      wp2.crosspoint = OsmNode(wpt1.node2!.ilon, wpt1.node2!.ilat);
      wp2.node1 = OsmNode(wpt1.node1!.ilon, wpt1.node1!.ilat);
      wp2.node2 = OsmNode(wpt1.node2!.ilon, wpt1.node2!.ilat);
      matchedWaypoints!.add(wp2);

      final t = await findTrackSegment('getinfo', wp1, wp2, null, null, false);
      if (t != null) {
        t.messageList = <String>[];
        t.matchedWaypoints = matchedWaypoints;
        t.name = _outfileBase ?? 'getinfo';

        // find nearest point
        var mindist = 99999;
        var minIdx = -1;
        for (var i = 0; i < t.nodes.length; i++) {
          final ope = t.nodes[i];
          final dist = ope.calcDistance(listOne[0].crosspoint!);
          if (mindist > dist) {
            mindist = dist;
            minIdx = i;
          }
        }
        var otherIdx = 0;
        if (minIdx == t.nodes.length - 1) {
          otherIdx = minIdx - 1;
        } else {
          otherIdx = minIdx + 1;
        }
        final otherdist = t.nodes[otherIdx].calcDistance(
          listOne[0].crosspoint!,
        );
        final minSElev = t.nodes[minIdx].getSElev();
        final otherSElev = t.nodes[otherIdx].getSElev();
        var diffSElev = 0;
        diffSElev = otherSElev - minSElev;
        final diff = mindist / (mindist + otherdist) * diffSElev;

        final n = OsmNodeNamed(listOne[0].crosspoint);
        n.name = wpt1.name;
        n.selev = minIdx != -1 ? toShort(minSElev + d2i(diff)) : shortMinValue;
        if (engineMode == brouterEngineModeGetInfo) {
          n.nodeDescription = start1.firstlink?.descriptionBitmap;
          t.pois.add(n);
          //t.message = "get_info";
          //t.messageList.add(t.message);
          t.matchedWaypoints = listOne;
          t.exportWaypoints = routingContext.exportWaypoints;
        }

        switch (routingContext.outputFormat) {
          case 'gpx':
            if (engineMode == brouterEngineModeGetElev) {
              outputMessage = FormatGpx(routingContext).formatAsWaypoint(n);
            } else {
              outputMessage = FormatGpx(routingContext).format(t);
            }
            break;
          case 'geojson':
          case 'json':
            if (engineMode == brouterEngineModeGetElev) {
              outputMessage = FormatJson(routingContext).formatAsWaypoint(n);
            } else {
              outputMessage = FormatJson(routingContext).format(t);
            }
            break;
          case 'kml':
          case 'csv':
          default:
            outputMessage = null;
            break;
        }
        if (_outfileBase != null) {
          final filename = '$_outfileBase.${routingContext.outputFormat}';
          File(filename).writeAsStringSync(outputMessage!);
          outputMessage = null;
        } else {
          if (!quite && outputMessage != null) {
            print(outputMessage);
          }
        }
      } else {
        errorMessage ??= 'no track found';
      }
      final endTime = _currentTimeMillis();
      _logInfo('execution time = ${(endTime - _startTime) / 1000.0} seconds');
    } catch (e) {
      _logException(e);
    }
  }

  Future<void> doRoundTrip() async {
    try {
      final startTime = _currentTimeMillis();

      routingContext.useDynamicDistance = true;
      final searchRadius = (routingContext.roundTripDistance ?? 1500)
          .toDouble();
      var direction = (routingContext.startDirection ?? -1).toDouble();
      final directionAdd =
          (routingContext.roundTripDirectionAdd ??
                  _roundtripDefaultDirectionadd)
              .toDouble();
      assert(directionAdd.isFinite); // (unused upstream as well)
      if (direction == -1) {
        direction = getRandomDirectionFromData(
          waypoints[0],
          searchRadius,
        ).toDouble();
      }

      if (routingContext.allowSamewayback) {
        final pos = CheapRuler.destination(
          waypoints[0].ilon,
          waypoints[0].ilat,
          searchRadius,
          direction,
        );
        final wpt2 = MatchedWaypoint();
        wpt2.waypoint = OsmNode(pos[0], pos[1]);
        wpt2.name = 'rt1_$direction';

        final onn = OsmNodeNamed(OsmNode(pos[0], pos[1]));
        onn.name = 'rt1';
        waypoints.add(onn);
      } else {
        buildPointsFromCircle(
          waypoints,
          direction,
          searchRadius,
          routingContext.roundTripPoints ?? 5,
        );
      }

      routingContext.waypointCatchingRange = 250;

      await doRouting(0);

      final endTime = _currentTimeMillis();
      _logInfo(
        'round trip execution time = ${(endTime - startTime) / 1000.0} seconds',
      );
    } catch (e) {
      _logException(e);
    }
  }

  void buildPointsFromCircle(
    List<OsmNodeNamed> waypoints,
    double startAngle,
    double searchRadius,
    int points,
  ) {
    //startAngle -= 90;
    for (var i = 1; i < points; i++) {
      final anAngle = 90 - (180.0 * i / points);
      final pos = CheapRuler.destination(
        waypoints[0].ilon,
        waypoints[0].ilat,
        searchRadius,
        startAngle - anAngle,
      );
      final onn = OsmNodeNamed(OsmNode(pos[0], pos[1]));
      onn.name = 'rt$i';
      waypoints.add(onn);
    }

    final onn = OsmNodeNamed(waypoints[0]);
    onn.name = 'to_rt';
    waypoints.add(onn);
  }

  int getRandomDirectionFromData(OsmNodeNamed wp, double searchRadius) {
    final start = _currentTimeMillis();
    final random = math.Random();

    var preferredRandomType = 0;
    final considerElevation =
        routingContext.expctxWay!.getVariableValue('consider_elevation', 0.0) ==
        1.0;
    final considerForest =
        routingContext.expctxWay!.getVariableValue('consider_forest', 0.0) ==
        1.0;
    final considerRiver =
        routingContext.expctxWay!.getVariableValue('consider_river', 0.0) ==
        1.0;
    if (considerElevation) {
      preferredRandomType = AreaInfo.resultTypeElev50;
    } else if (considerForest) {
      preferredRandomType = AreaInfo.resultTypeGreen;
    } else if (considerRiver) {
      preferredRandomType = AreaInfo.resultTypeRiver;
    } else {
      return d2i(random.nextDouble() * 360);
    }

    final wpt1 = MatchedWaypoint();
    wpt1.waypoint = wp;
    wpt1.name = 'info';
    wpt1.radius = searchRadius * 1.5;

    final ais = <AreaInfo>[];
    final areareader = AreaReader();
    if (routingContext.rawAreaPath != null) {
      final fai = File(routingContext.rawAreaPath!);
      if (fai.existsSync()) {
        areareader.readAreaInfo(fai, wpt1, ais);
      }
    }

    if (ais.isEmpty) {
      final listStart = <MatchedWaypoint>[];
      listStart.add(wpt1);

      final wpliststart = <OsmNodeNamed>[];
      wpliststart.add(wp);

      final listOne = <OsmNodeNamed>[];

      for (var a = 45; a < 360; a += 90) {
        final pos = CheapRuler.destination(
          wp.ilon,
          wp.ilat,
          searchRadius * 1.5,
          a.toDouble(),
        );
        final onn = OsmNodeNamed(OsmNode(pos[0], pos[1]));
        onn.name = 'via$a';
        listOne.add(onn);

        final wpt = MatchedWaypoint();
        wpt.waypoint = onn;
        wpt.name = onn.name;
        listStart.add(wpt);
      }

      final rc = RoutingContext();
      final name = routingContext.localFunction;
      final idx = name.lastIndexOf('/');
      rc.localFunction = idx == -1
          ? 'dummy'
          : '${name.substring(0, idx + 1)}dummy.brf';

      final re = RoutingEngine(
        null,
        null,
        segmentDir,
        wpliststart,
        rc,
        brouterEngineModeRoundTrip,
      );
      re.rawCache = rawCache;
      rc.useDynamicDistance = true;
      re._matchWaypointsToNodes(listStart);
      re._resetCache(true);

      final numForest = rc.expctxWay!.getLookupKey('estimated_forest_class');
      final numRiver = rc.expctxWay!.getLookupKey('estimated_river_class');

      final start1 = re.nodesCache!.getStartNode(
        listStart[0].node1!.getIdFromPos(),
      );

      final elev = (start1 == null
          ? 0.0
          : start1.getElev()); // listOne.get(0).crosspoint.getElev();

      var maxlon = intMinValue;
      var minlon = intMaxValue;
      var maxlat = intMinValue;
      var minlat = intMaxValue;
      for (final on in listOne) {
        maxlon = math.max(on.ilon, maxlon);
        minlon = math.min(on.ilon, minlon);
        maxlat = math.max(on.ilat, maxlat);
        minlat = math.min(on.ilat, minlat);
      }
      final searchRect = OsmNogoPolygon(true);
      searchRect.addVertex(maxlon, maxlat);
      searchRect.addVertex(maxlon, minlat);
      searchRect.addVertex(minlon, minlat);
      searchRect.addVertex(minlon, maxlat);

      for (var a = 0; a < 4; a++) {
        rc.ai = AreaInfo(a * 90 + 90);
        rc.ai!.elevStart = elev;
        rc.ai!.numForest = numForest;
        rc.ai!.numRiver = numRiver;

        rc.ai!.polygon = OsmNogoPolygon(true);
        rc.ai!.polygon!.addVertex(wp.ilon, wp.ilat);
        rc.ai!.polygon!.addVertex(listOne[a].ilon, listOne[a].ilat);
        if (a == 3) {
          rc.ai!.polygon!.addVertex(listOne[0].ilon, listOne[0].ilat);
        } else {
          rc.ai!.polygon!.addVertex(listOne[a + 1].ilon, listOne[a + 1].ilat);
        }

        ais.add(rc.ai!);
      }

      var maxscale = (searchRect.points[2].x - searchRect.points[0].x).abs();
      maxscale = math.max(1, javaRound(f32(f32(maxscale / 31250.0) / 2)) + 1);

      areareader.getDirectAllData(
        segmentDir,
        rc,
        wp,
        maxscale,
        rc.expctxWay!,
        searchRect,
        ais,
      );

      if (routingContext.rawAreaPath != null) {
        try {
          wpt1.radius = searchRadius * 1.5;
          areareader.writeAreaInfo(routingContext.rawAreaPath!, wpt1, ais);
        } catch (e) {
          // ignore
        }
      }
      rc.ai = null;
    }

    _logInfo(
      'round trip execution time = ${(_currentTimeMillis() - start) / 1000.0} seconds',
    );

    switch (preferredRandomType) {
      case AreaInfo.resultTypeElev50:
        _stableSort(
          ais,
          (o1, o2) => o2.getElev50Weight() - o1.getElev50Weight(),
        );
        break;
      case AreaInfo.resultTypeGreen:
        _stableSort(ais, (o1, o2) => o2.getGreen() - o1.getGreen());
        break;
      case AreaInfo.resultTypeRiver:
        _stableSort(ais, (o1, o2) => o2.getRiver() - o1.getRiver());
        break;
      default:
        return d2i(random.nextDouble() * 360);
    }

    final angle = ais[0].direction;
    return angle - 30 + d2i(random.nextDouble() * 60);
  }

  /// `Collections.sort` (stable) on a small list.
  static void _stableSort<T>(List<T> list, int Function(T a, T b) cmp) {
    for (var i = 1; i < list.length; i++) {
      final v = list[i];
      var j = i - 1;
      while (j >= 0 && cmp(list[j], v) > 0) {
        list[j + 1] = list[j];
        j--;
      }
      list[j + 1] = v;
    }
  }

  void _postElevationCheck(OsmTrack track) {
    OsmPathElement? lastPt;
    OsmPathElement? startPt;
    var lastElev = shortMinValue;
    var startElev = shortMinValue;
    var endElev = shortMinValue;
    var startIdx = 0;
    var endIdx = -1;
    var dist = 0;
    final ourSize = track.nodes.length;
    for (var idx = 0; idx < ourSize; idx++) {
      final n = track.nodes[idx];
      if (n.getSElev() == shortMinValue &&
          lastElev != shortMinValue &&
          idx < ourSize - 1) {
        // start one point before entry point to get better elevation results
        if (idx > 1) startElev = track.nodes[idx - 2].getSElev();
        if (startElev == shortMinValue) startElev = lastElev;
        startIdx = idx;
        startPt = lastPt;
        dist = 0;
        if (lastPt != null) dist += n.calcDistance(lastPt);
      } else if (n.getSElev() != shortMinValue &&
          lastElev == shortMinValue &&
          startElev != shortMinValue) {
        // end one point behind exit point to get better elevation results
        if (idx + 1 < track.nodes.length) {
          endElev = track.nodes[idx + 1].getSElev();
        }
        if (endElev == shortMinValue) endElev = n.getSElev();
        endIdx = idx;
        var tmpPt = track.nodes[startIdx > 1 ? startIdx - 2 : startIdx - 1];
        final diffElev = endElev - startElev;
        dist += tmpPt.calcDistance(startPt!);
        dist += n.calcDistance(lastPt!);
        var distRest = dist;
        var incline = diffElev / (dist / 100.0);
        var lastMsg = '';
        var tmpincline = 0.0;
        var startincline = 0.0;
        var selev = track.nodes[startIdx > 1 ? startIdx - 2 : startIdx - 1]
            .getSElev()
            .toDouble();
        var hasInclineTags = false;
        for (var i = startIdx - 1; i < endIdx + 1; i++) {
          final tmp = track.nodes[i];
          if (tmp.message != null) {
            final md = tmp.message!.copy();
            final msg = md.wayKeyValues!;
            if (msg != lastMsg) {
              final revers = msg.contains('reversedirection=yes');
              var pos = msg.indexOf('incline=');
              if (pos != -1) {
                hasInclineTags = true;
                var s = msg.substring(pos + 8);
                pos = s.indexOf(' ');
                if (pos != -1) s = s.substring(0, pos);

                if (s.isNotEmpty) {
                  try {
                    var ind = s.indexOf('%');
                    if (ind != -1) s = s.substring(0, ind);
                    ind = s.indexOf('°');
                    if (ind != -1) s = s.substring(0, ind);
                    tmpincline = javaParseDouble(javaTrim(s));
                    if (revers) tmpincline *= -1;
                  } on NumberFormatException {
                    tmpincline = 0;
                  }
                }
              } else {
                tmpincline = 0;
              }
              if (startincline == 0) {
                startincline = tmpincline;
              } else if (startincline < 0 && tmpincline > 0) {
                // for the way up find the exit point
                final diff = endElev - selev;
                tmpincline = diff / (distRest / 100.0);
              }
            }
            lastMsg = msg;
          }
          final tmpdist = tmp.calcDistance(tmpPt);
          distRest -= tmpdist;
          if (hasInclineTags) incline = tmpincline;
          selev = (selev + (tmpdist / 100.0 * incline));
          tmp.setSElev(toShort(d2i(selev)));
          tmp.message!.ele = toShort(d2i(selev));
          tmpPt = tmp;
        }
        dist = 0;
      } else if (n.getSElev() != shortMinValue &&
          lastElev == shortMinValue &&
          startIdx == 0) {
        // fill at start
        for (var i = 0; i < idx; i++) {
          track.nodes[i].setSElev(n.getSElev());
        }
      } else if (n.getSElev() == shortMinValue &&
          idx == track.nodes.length - 1) {
        // fill at end
        startIdx = idx;
        for (var i = startIdx; i < track.nodes.length; i++) {
          track.nodes[i].setSElev(lastElev);
        }
      } else if (n.getSElev() == shortMinValue) {
        if (lastPt != null) dist += n.calcDistance(lastPt);
      }
      lastElev = n.getSElev();
      lastPt = n;
    }
  }

  void _logException(Object t) {
    errorMessage = _messageOf(t);
    _logInfo(
      'Error (linksProcessed=$_linksProcessed open paths: ${_openSet.getSize()}): $errorMessage',
    );
  }

  /// `t instanceof RuntimeException ? t.getMessage() : t.toString()`.
  static String _messageOf(Object t) {
    if (t is ArgumentError) return '${t.message}';
    if (t is StateError) return t.message;
    if (t is UnsupportedError) return '${t.message}';
    if (t is RangeError) return '${t.message}';
    return t.toString();
  }

  Future<void> doSearch() async {
    try {
      final seedPoint = MatchedWaypoint();
      seedPoint.waypoint = waypoints[0];
      final listOne = <MatchedWaypoint>[];
      listOne.add(seedPoint);
      _matchWaypointsToNodes(listOne);

      await findTrackSegment(
        'seededSearch',
        seedPoint,
        null,
        null,
        null,
        false,
      );
    } on ArgumentError catch (e) {
      _logException(e);
    } catch (e, st) {
      _logException(e);
      _logThrowable(e, st);
    } finally {
      ProfileCache.releaseProfile(routingContext);
      if (nodesCache != null) {
        nodesCache!.close();
        nodesCache = null;
      }
      _openSet.clear();
      _finished = true; // this signals termination to outside
    }
  }

  void cleanOnOOM() {
    terminate();
  }

  /// `findTrack(OsmTrack[] refTracks, OsmTrack[] lastTracks)`
  Future<OsmTrack?> findTrack(
    List<OsmTrack?> refTracks,
    List<OsmTrack?> lastTracks,
  ) async {
    for (;;) {
      try {
        return await _tryFindTrack(refTracks, lastTracks);
      } on RoutingIslandException {
        if (routingContext.useDynamicDistance) {
          for (final mwp in matchedWaypoints!) {
            if (mwp.name!.contains('_add')) {
              final n1 = mwp.node1!.getIdFromPos();
              final n2 = mwp.node2!.getIdFromPos();
              _islandNodePairs.addTempPair(n1, n2);
            }
          }
        }
        _islandNodePairs.freezeTempPairs();
        nodesCache!.clean(true);
        matchedWaypoints = null;
      }
    }
  }

  Future<OsmTrack?> _tryFindTrack(
    List<OsmTrack?> refTracks,
    List<OsmTrack?> lastTracks,
  ) async {
    final totaltrack = OsmTrack();
    var nUnmatched = waypoints.length;
    var hasDirectRouting = false;

    if (_useNodePoints && extraWaypoints != null) {
      // add extra waypoints from the last broken round
      for (final wp in extraWaypoints!) {
        if (wp.wpttype == MatchedWaypoint.waypointTypeDirect) {
          hasDirectRouting = true;
        }
        if (wp.name!.startsWith('from')) {
          waypoints.insert(1, wp);
          waypoints[0].wpttype = MatchedWaypoint.waypointTypeDirect;
          nUnmatched++;
        } else {
          waypoints.insert(waypoints.length - 1, wp);
          waypoints[waypoints.length - 2].wpttype =
              MatchedWaypoint.waypointTypeDirect;
          nUnmatched++;
        }
      }
      extraWaypoints = null;
    }
    if (lastTracks.length < waypoints.length - 1) {
      refTracks = List<OsmTrack?>.filled(
        waypoints.length - 1,
        null,
      ); // used ways for alternatives
      lastTracks = List<OsmTrack?>.filled(waypoints.length - 1, null);
      hasDirectRouting = true;
    }
    for (final wp in waypoints) {
      if (_hasInfo()) {
        _logInfo(
          'wp=$wp${wp.wpttype == MatchedWaypoint.waypointTypeDirect ? ' beeline' : (wp.wpttype == MatchedWaypoint.waypointTypeMeeting ? ' via' : '')}',
        );
      }
      if (wp.wpttype == MatchedWaypoint.waypointTypeDirect) {
        hasDirectRouting = true;
      }
    }

    // check for a track for that target
    OsmTrack? nearbyTrack;
    if (!hasDirectRouting && lastTracks[waypoints.length - 2] == null) {
      final debugInfo = _hasInfo() ? StringBuffer() : null;
      nearbyTrack = OsmTrack.readBinary(
        routingContext.rawTrackPath,
        waypoints[waypoints.length - 1],
        routingContext.getNogoChecksums(),
        routingContext.profileTimestamp,
        debugInfo,
      );
      if (nearbyTrack != null) {
        nUnmatched--;
      }
      if (_hasInfo()) {
        final found = nearbyTrack != null;
        final dirty = found && nearbyTrack.isDirty;
        _logInfo('read referenceTrack, found=$found dirty=$dirty $debugInfo');
      }
    }

    if (matchedWaypoints == null) {
      // could exist from the previous alternative level
      final mwps = <MatchedWaypoint>[];
      matchedWaypoints = mwps;
      for (var i = 0; i < nUnmatched; i++) {
        final mwp = MatchedWaypoint();
        mwp.waypoint = waypoints[i];
        mwp.name = waypoints[i].name;
        mwp.wpttype = waypoints[i].wpttype;
        mwps.add(mwp);
      }
      final startSize = mwps.length;
      _matchWaypointsToNodes(mwps);
      if (startSize < mwps.length) {
        refTracks = List<OsmTrack?>.filled(
          mwps.length - 1,
          null,
        ); // used ways for alternatives
        lastTracks = List<OsmTrack?>.filled(mwps.length - 1, null);
        hasDirectRouting = true;
      }

      for (final mwp in mwps) {
        if (_hasInfo() && mwps.length != nUnmatched) {
          _logInfo(
            'new wp=${mwp.waypoint} ${mwp.crosspoint}${mwp.wpttype == MatchedWaypoint.waypointTypeDirect ? ' beeline' : (mwp.wpttype == MatchedWaypoint.waypointTypeMeeting ? ' via' : '')}',
          );
        }
      }

      routingContext.checkMatchedWaypointAgainstNogos(mwps);

      // detect target islands: restricted search in inverse direction
      routingContext.inverseDirection = !routingContext.inverseRouting;
      airDistanceCostFactor = 0.0;
      for (var i = 0; i < mwps.length - 1; i++) {
        _nodeLimit = _maxnodesIslandCheck;
        if (mwps[i].wpttype == MatchedWaypoint.waypointTypeDirect) continue;
        if (routingContext.inverseRouting) {
          final seg = await findTrackSegment(
            'start-island-check',
            mwps[i],
            mwps[i + 1],
            null,
            null,
            false,
          );
          if (seg == null && _nodeLimit > 0) {
            throw ArgumentError('start island detected for section $i');
          }
        } else {
          final seg = await findTrackSegment(
            'target-island-check',
            mwps[i + 1],
            mwps[i],
            null,
            null,
            false,
          );
          if (seg == null && _nodeLimit > 0) {
            throw ArgumentError('target island detected for section $i');
          }
        }
      }
      routingContext.inverseDirection = false;
      _nodeLimit = 0;

      if (nearbyTrack != null) {
        mwps.add(nearbyTrack.endPoint!);
      }
    } else {
      if (lastTracks.length < matchedWaypoints!.length - 1) {
        refTracks = List<OsmTrack?>.filled(
          matchedWaypoints!.length - 1,
          null,
        ); // used ways for alternatives
        lastTracks = List<OsmTrack?>.filled(matchedWaypoints!.length - 1, null);
        hasDirectRouting = true;
      }
    }
    final mwps = matchedWaypoints!;

    routingContext.hasDirectRouting = hasDirectRouting;

    OsmPath.seg = 1; // set segment counter
    for (var i = 0; i < mwps.length - 1; i++) {
      if (lastTracks[i] != null) {
        refTracks[i] ??= OsmTrack();
        refTracks[i]!.addNodes(lastTracks[i]!);
      }

      OsmTrack? seg;
      int wptIndex;
      if (routingContext.inverseRouting) {
        routingContext.inverseDirection = true;
        seg = await _searchTrack(mwps[i + 1], mwps[i], null, refTracks[i]);
        routingContext.inverseDirection = false;
        wptIndex = i + 1;
      } else {
        seg = await _searchTrack(
          mwps[i],
          mwps[i + 1],
          i == mwps.length - 2 ? nearbyTrack : null,
          refTracks[i],
        );
        wptIndex = i;
        if (routingContext.continueStraight) {
          if (i < mwps.length - 2) {
            final lastPoint = seg!.containsNode(mwps[i + 1].node1!)
                ? mwps[i + 1].node1!
                : mwps[i + 1].node2!;
            final nogo = OsmNodeNamed(lastPoint);
            nogo.radius = 5;
            nogo.name = 'nogo${i + 1}';
            nogo.nogoWeight = 9999.0;
            nogo.isNogo = true;
            routingContext.nogopoints ??= <OsmNodeNamed>[];
            routingContext.nogopoints!.add(nogo);
          }
        }
      }
      if (seg == null) return null;

      if (routingContext.ai != null) return null;

      if (routingContext.correctMisplacedViaPoints &&
          mwps[i].wpttype != MatchedWaypoint.waypointTypeDirect &&
          mwps[i].wpttype != MatchedWaypoint.waypointTypeMeeting &&
          !routingContext.allowSamewayback) {
        await _snapPathConnection(
          totaltrack,
          seg,
          routingContext.inverseRouting ? mwps[i + 1] : mwps[i],
        );
      }
      if (wptIndex > 0) {
        mwps[wptIndex].indexInTrack = totaltrack.nodes.length - 1;
      }

      totaltrack.appendTrack(seg);
      lastTracks[i] = seg;
    }

    _postElevationCheck(totaltrack);

    _recalcTrack(totaltrack);

    mwps[mwps.length - 1].indexInTrack = totaltrack.nodes.length - 1;
    totaltrack.matchedWaypoints = mwps;
    totaltrack.processVoiceHints(routingContext);
    totaltrack.prepareSpeedProfile(routingContext);

    totaltrack.showTime = routingContext.showTime;
    totaltrack.params = routingContext.keyValues;

    if (routingContext.poipoints != null) {
      totaltrack.pois = routingContext.poipoints!;
    }

    return totaltrack;
  }

  Future<OsmTrack?> getExtraSegment(
    OsmPathElement? start,
    OsmPathElement? end,
  ) async {
    if (start == null || end == null) return null;

    final wptlist = <MatchedWaypoint>[];
    final wpt1 = MatchedWaypoint();
    wpt1.waypoint = OsmNode(start.getILon(), start.getILat());
    wpt1.name = 'wptx1';
    wpt1.crosspoint = OsmNode(start.getILon(), start.getILat());
    wpt1.node1 = OsmNode(start.getILon(), start.getILat());
    wpt1.node2 = OsmNode(end.getILon(), end.getILat());
    wptlist.add(wpt1);
    final wpt2 = MatchedWaypoint();
    wpt2.waypoint = OsmNode(end.getILon(), end.getILat());
    wpt2.name = 'wptx2';
    wpt2.crosspoint = OsmNode(end.getILon(), end.getILat());
    wpt2.node2 = OsmNode(start.getILon(), start.getILat());
    wpt2.node1 = OsmNode(end.getILon(), end.getILat());
    wptlist.add(wpt2);

    final mwp1 = wptlist[0];
    final mwp2 = wptlist[1];

    OsmTrack? mid;

    final corr = routingContext.correctMisplacedViaPoints;
    routingContext.correctMisplacedViaPoints = false;

    _guideTrack = OsmTrack();
    _guideTrack!.addNode(start);
    _guideTrack!.addNode(end);

    mid = await findTrackSegment('getinfo', mwp1, mwp2, null, null, false);

    _guideTrack = null;
    routingContext.correctMisplacedViaPoints = corr;

    return mid;
  }

  Future<int> _snapRoundaboutConnection(
    OsmTrack tt,
    OsmTrack t,
    int indexStart,
    int indexEnd,
    int indexMeeting,
    MatchedWaypoint startWp,
  ) async {
    final indexMeetingBack = (indexMeeting == -1
        ? tt.nodes.length - 1
        : indexMeeting);
    var indexMeetingFore = 0;
    var indexStartBack = indexStart;
    var indexStartFore = 0;

    final ptStart = tt.nodes[indexStartBack];
    final ptMeeting = tt.nodes[indexMeetingBack];
    final ptEnd = t.nodes[indexEnd];

    final bMeetingIsOnRoundabout = ptMeeting.message!.isRoundabout();
    var bMeetsRoundaboutStart = false;
    var wayDistance = 0;

    int i;
    OsmPathElement? lastN;

    for (i = 0; i < indexEnd; i++) {
      final n = t.nodes[i];
      if (lastN != null) wayDistance += n.calcDistance(lastN);
      lastN = n;
      if (n.positionEquals(ptStart)) {
        indexStartFore = i;
        bMeetsRoundaboutStart = true;
      }
      if (n.positionEquals(ptMeeting)) {
        indexMeetingFore = i;
      }
    }

    if (routingContext.correctMisplacedViaPointsDistance > 0 &&
        wayDistance > routingContext.correctMisplacedViaPointsDistance) {
      return 0;
    }

    if (!bMeetsRoundaboutStart && bMeetingIsOnRoundabout) {
      indexEnd = indexMeetingFore;
    }
    if (bMeetsRoundaboutStart && bMeetingIsOnRoundabout) {
      indexEnd = indexStartFore;
    }

    final removeList = <OsmPathElement>[];
    if (!bMeetsRoundaboutStart) {
      indexStartBack = indexMeetingBack;
      while (!tt.nodes[indexStartBack].message!.isRoundabout()) {
        indexStartBack--;
        if (indexStartBack == 2) break;
      }
    }

    for (i = indexStartBack + 1; i < tt.nodes.length; i++) {
      final n = tt.nodes[i];
      final detours = tt.getFromDetourMap(n.getIdFromPos());
      if (detours != null) {
        OsmPathElementHolder? h = detours;
        while (h != null) {
          h = h.nextHolder;
        }
      }
      removeList.add(n);
    }

    OsmPathElement? ttend;
    if (!bMeetingIsOnRoundabout && !bMeetsRoundaboutStart) {
      ttend = tt.nodes[indexStartBack];
      final ttendDetours = tt.getFromDetourMap(ttend.getIdFromPos());
      if (ttendDetours != null) {
        tt.registerDetourForId(ttend.getIdFromPos(), null);
      }
    }

    for (final e in removeList) {
      tt.nodes.remove(e);
    }
    removeList.clear();

    for (i = 0; i < indexEnd; i++) {
      final n = t.nodes[i];
      if (n.positionEquals(bMeetsRoundaboutStart ? ptStart : ptEnd)) break;
      if (!bMeetingIsOnRoundabout &&
          !bMeetsRoundaboutStart &&
          n.message!.isRoundabout()) {
        break;
      }

      final detours = t.getFromDetourMap(n.getIdFromPos());
      if (detours != null) {
        OsmPathElementHolder? h = detours;
        while (h != null) {
          h = h.nextHolder;
        }
      }
      removeList.add(n);
    }

    // time hold
    var atime = 0.0;
    var aenergy = 0.0;
    var acost = 0;
    if (i > 1) {
      atime = t.nodes[i].getTime();
      aenergy = t.nodes[i].getEnergy();
      acost = t.nodes[i].cost;
    }

    for (final e in removeList) {
      t.nodes.remove(e);
    }
    removeList.clear();

    if (atime > 0.0) {
      for (final e in t.nodes) {
        e.setTime(f32(e.getTime() - atime));
        e.setEnergy(f32(e.getEnergy() - aenergy));
        e.cost = e.cost - acost;
      }
    }

    if (!bMeetingIsOnRoundabout && !bMeetsRoundaboutStart) {
      final ttendDetours = tt.getFromDetourMap(ttend!.getIdFromPos());

      OsmTrack? mid;
      if (ttendDetours != null && ttendDetours.node != null) {
        mid = await getExtraSegment(ttend, ttendDetours.node);
      }
      final ttEnd = tt.nodes[tt.nodes.length - 1];

      final lastCost = ttEnd.cost;
      final lastTime = ttEnd.getTime();
      final lastEnergy = ttEnd.getEnergy();
      var tmpCost = 0;
      var tmpTime = 0.0;
      var tmpEnergy = 0.0;

      if (mid != null) {
        var start = false;
        for (final e in mid.nodes) {
          if (start) {
            if (e.positionEquals(ttendDetours!.node!)) {
              tmpCost = e.cost;
              tmpTime = e.getTime();
              tmpEnergy = e.getEnergy();
              break;
            }
            e.cost = lastCost + e.cost;
            e.setTime(f32(lastTime + e.getTime()));
            e.setEnergy(f32(lastEnergy + e.getEnergy()));
            tt.nodes.add(e);
          }
          if (e.positionEquals(ttEnd)) start = true;
        }

        ttendDetours!.node!.cost = lastCost + tmpCost;
        ttendDetours.node!.setTime(f32(lastTime + tmpTime));
        ttendDetours.node!.setEnergy(f32(lastEnergy + tmpEnergy));
        tt.nodes.add(ttendDetours.node!);
        t.nodes.insert(0, ttendDetours.node!);
      }
    }

    tt.cost = tt.nodes[tt.nodes.length - 1].cost;
    t.cost = t.nodes[t.nodes.length - 1].cost;

    startWp.correctedpoint = OsmNode(ptStart.getILon(), ptStart.getILat());

    return (t.nodes.length);
  }

  // check for way back on way point
  Future<bool> _snapPathConnection(
    OsmTrack tt,
    OsmTrack t,
    MatchedWaypoint startWp,
  ) async {
    if (!startWp.name!.startsWith('via') && !startWp.name!.startsWith('rt')) {
      return false;
    }

    final ourSize = tt.nodes.length;
    if (ourSize > 0) {
      if (routingContext.poipoints != null) {
        for (final node in routingContext.poipoints!) {
          final lon0 = tt.nodes[ourSize - 2].getILon();
          final lat0 = tt.nodes[ourSize - 2].getILat();
          final lon1 = startWp.crosspoint!.ilon;
          final lat1 = startWp.crosspoint!.ilat;
          final lon2 = node.ilon;
          final lat2 = node.ilat;
          routingContext.anglemeter.calcAngle(
            lon0,
            lat0,
            lon1,
            lat1,
            lon2,
            lat2,
          );
          final dist = node.calcDistance(startWp.crosspoint!);
          if (dist < routingContext.waypointCatchingRange) return false;
        }
      }
      final removeBackList = <OsmPathElement>[];
      final removeForeList = <OsmPathElement>[];
      final removeVoiceHintList = <int>[];
      final lastJunctions = CompactLongMap<OsmPathElementHolder>();
      OsmPathElement newJunction;
      OsmPathElement? tmpback;
      OsmPathElement? tmpfore;
      OsmPathElement? tmpStart;
      var indexback = ourSize - 1;
      var indexfore = 0;
      final stop = (indexback - _maxStepsCheck > 1
          ? indexback - _maxStepsCheck
          : 1);
      var wayDistance = 0.0;
      var nextDist = 0.0;
      var bCheckRoundAbout = false;
      var bBackRoundAbout = false;
      var bForeRoundAbout = false;
      var indexBackFound = 0;
      var indexForeFound = 0;
      var differentLanePoints = 0;
      var indexMeeting = -1;
      while (indexback >= 1 &&
          indexback >= stop &&
          indexfore < t.nodes.length) {
        tmpback = tt.nodes[indexback];
        tmpfore = t.nodes[indexfore];
        if (!bBackRoundAbout &&
            tmpback.message != null &&
            tmpback.message!.isRoundabout()) {
          bBackRoundAbout = true;
          indexBackFound = indexfore;
        }
        if (!bForeRoundAbout &&
                tmpfore.message != null &&
                tmpfore.message!.isRoundabout() ||
            (tmpback.positionEquals(tmpfore) &&
                tmpback.message!.isRoundabout())) {
          bForeRoundAbout = true;
          indexForeFound = indexfore;
        }
        if (indexfore == 0) {
          tmpStart = t.nodes[0];
        } else {
          final dirback = CheapAngleMeter.getDirection(
            tmpStart!.getILon(),
            tmpStart.getILat(),
            tmpback.getILon(),
            tmpback.getILat(),
          );
          final dirfore = CheapAngleMeter.getDirection(
            tmpStart.getILon(),
            tmpStart.getILat(),
            tmpfore.getILon(),
            tmpfore.getILat(),
          );
          final dirdiff = CheapAngleMeter.getDifferenceFromDirection(
            dirback,
            dirfore,
          );
          // walking wrong direction
          if (dirdiff > 60 && !bBackRoundAbout && !bForeRoundAbout) break;
        }
        // seems no roundabout, only on one end
        if (bBackRoundAbout != bForeRoundAbout &&
            indexfore - (indexForeFound - indexBackFound).abs() > 8) {
          break;
        }
        if (!tmpback.positionEquals(tmpfore)) differentLanePoints++;
        if (tmpback.positionEquals(tmpfore)) indexMeeting = indexback;
        bCheckRoundAbout = bBackRoundAbout && bForeRoundAbout;
        if (bCheckRoundAbout) break;
        indexback--;
        indexfore++;
      }
      assert(differentLanePoints >= 0); // (only printed upstream)
      if (bCheckRoundAbout) {
        tmpback = tt.nodes[--indexback];
        while (tmpback!.message != null && tmpback.message!.isRoundabout()) {
          tmpback = tt.nodes[--indexback];
        }

        var ifore = ++indexfore;
        var testfore = t.nodes[ifore];
        while (ifore < t.nodes.length &&
            testfore.message != null &&
            testfore.message!.isRoundabout()) {
          testfore = t.nodes[ifore];
          ifore++;
        }

        await _snapRoundaboutConnection(
          tt,
          t,
          indexback,
          --ifore,
          indexMeeting,
          startWp,
        );

        // remove filled arrays
        removeVoiceHintList.clear();
        removeBackList.clear();
        removeForeList.clear();
        return true;
      }
      indexback = ourSize - 1;
      indexfore = 0;
      while (indexback >= 1 &&
          indexback >= stop &&
          indexfore < t.nodes.length) {
        var junctions = 0;
        tmpback = tt.nodes[indexback];
        tmpfore = t.nodes[indexfore];
        if (tmpback.message != null && tmpback.message!.isRoundabout()) {
          bCheckRoundAbout = true;
        }
        if (tmpfore.message != null && tmpfore.message!.isRoundabout()) {
          bCheckRoundAbout = true;
        }
        {
          final dist = tmpback.calcDistance(tmpfore);
          final detours = tt.getFromDetourMap(tmpback.getIdFromPos());
          OsmPathElementHolder? h = detours;
          while (h != null) {
            junctions++;
            lastJunctions.put(h.node!.getIdFromPos(), h);
            h = h.nextHolder;
          }
          assert(junctions >= 0);

          if (dist == 1 && indexfore > 0) {
            if (indexfore == 1) {
              removeBackList.add(tt.nodes[tt.nodes.length - 1]); // last and first should be equal, so drop only on second also equal
              removeForeList.add(t.nodes[0]);
              removeBackList.add(tmpback);
              removeForeList.add(tmpfore);
              removeVoiceHintList.add(tt.nodes.length - 1);
              removeVoiceHintList.add(indexback);
            } else {
              removeBackList.add(tmpback);
              removeForeList.add(tmpfore);
              removeVoiceHintList.add(indexback);
            }
            nextDist = t.nodes[indexfore - 1].calcDistance(tmpfore).toDouble();
            wayDistance += nextDist;
          }
          if (dist > 1 || indexback == 1) {
            if (removeBackList.isNotEmpty) {
              // recover last - should be the cross point
              removeBackList.remove(removeBackList[removeBackList.length - 1]);
              removeForeList.remove(removeForeList[removeForeList.length - 1]);
              break;
            } else {
              return false;
            }
          }
          indexback--;
          indexfore++;

          if (routingContext.correctMisplacedViaPointsDistance > 0 &&
              wayDistance > routingContext.correctMisplacedViaPointsDistance) {
            removeVoiceHintList.clear();
            removeBackList.clear();
            removeForeList.clear();
            return false;
          }
        }
      }

      // time hold
      var atime = 0.0;
      var aenergy = 0.0;
      var acost = 0;
      if (removeForeList.length > 1) {
        atime = t.nodes[indexfore - 1].getTime();
        aenergy = t.nodes[indexfore - 1].getEnergy();
        acost = t.nodes[indexfore - 1].cost;
      }

      for (final e in removeBackList) {
        tt.nodes.remove(e);
      }
      for (final e in removeForeList) {
        t.nodes.remove(e);
      }
      for (final e in removeVoiceHintList) {
        tt.removeVoiceHint(e);
      }
      removeVoiceHintList.clear();
      removeBackList.clear();
      removeForeList.clear();

      if (atime > 0.0) {
        for (final e in t.nodes) {
          e.setTime(f32(e.getTime() - atime));
          e.setEnergy(f32(e.getEnergy() - aenergy));
          e.cost = e.cost - acost;
        }
      }

      if (t.nodes.length < 2) return true;
      if (tt.nodes.isEmpty) return true;
      newJunction = t.nodes[0];

      tt.cost = tt.nodes[tt.nodes.length - 1].cost;
      t.cost = t.nodes[t.nodes.length - 1].cost;

      // fill to correctedpoint
      startWp.correctedpoint = OsmNode(
        newJunction.getILon(),
        newJunction.getILat(),
      );

      return true;
    }
    return false;
  }

  void _recalcTrack(OsmTrack t) {
    var totaldist = 0;
    var totaltime = 0;
    var lasttime = 0.0;
    var lastenergy = 0.0;
    var speedMin = 9999.0; // float
    final directMap = <int, int>{};
    var tmptime = 1.0; // float
    var speed = 1.0; // float
    int dist;
    double angle;

    var ascend = 0.0;
    var ehb = 0.0;
    final ourSize = t.nodes.length;

    var eleStart = shortMinValue;
    var eleEnd = shortMinValue;
    final eleFactor = routingContext.inverseRouting ? 0.25 : -0.25;

    for (var i = 0; i < ourSize; i++) {
      final n = t.nodes[i];
      n.message ??= MessageData();
      OsmPathElement? nLast;
      if (i == 0) {
        angle = 0;
        dist = 0;
      } else if (i == 1) {
        angle = 0;
        nLast = t.nodes[0];
        dist = nLast.calcDistance(n);
      } else {
        final lon0 = t.nodes[i - 2].getILon();
        final lat0 = t.nodes[i - 2].getILat();
        final lon1 = t.nodes[i - 1].getILon();
        final lat1 = t.nodes[i - 1].getILat();
        final lon2 = t.nodes[i].getILon();
        final lat2 = t.nodes[i].getILat();
        angle = routingContext.anglemeter.calcAngle(
          lon0,
          lat0,
          lon1,
          lat1,
          lon2,
          lat2,
        );
        nLast = t.nodes[i - 1];
        dist = nLast.calcDistance(n);
      }
      n.message!.linkdist = dist;
      n.message!.turnangle = f32(angle);
      totaldist += dist;
      totaltime = d2i(f32(f32(totaltime.toDouble()) + n.getTime()));
      tmptime = f32(n.getTime() - lasttime);
      if (dist > 0) {
        speed = f32(f32(f32(dist.toDouble()) / tmptime) * f32(3.6));
        speedMin = math.min(speedMin, speed);
      }
      if (tmptime == 1.0) {
        // no time used here
        directMap[i] = dist;
      }

      lastenergy = n.getEnergy();
      lasttime = n.getTime();

      final ele = n.getSElev();
      if (ele != shortMinValue) eleEnd = ele;
      if (eleStart == shortMinValue) eleStart = ele;

      if (nLast != null) {
        final eleLast = nLast.getSElev();
        if (eleLast != shortMinValue) {
          ehb = ehb + (eleLast - ele) * eleFactor;
        }
        final filter = elevationFilter(n);
        if (ehb > 0) {
          ascend += ehb;
          ehb = 0;
        } else if (ehb < filter) {
          ehb = filter;
        }
      }
    }
    assert(lastenergy.isFinite && totaltime.isFinite); // (unused upstream)

    t.ascend = d2i(ascend);
    t.plainAscend = d2i((eleStart - eleEnd) * eleFactor + 0.5);

    t.distance = totaldist;
    //t.energy = totalenergy;

    final keys = directMap.keys.toList()..sort();
    for (final key in keys) {
      final value = directMap[key]!;
      final addTime = f32(f32(value.toDouble()) / f32(speedMin / f32(3.6)));

      var addEnergy = 0.0;
      if (key > 0) {
        const gravity = 9.81; // in meters per second^(-2)
        final incline =
            (t.nodes[key - 1].getSElev() == shortMinValue ||
                t.nodes[key].getSElev() == shortMinValue
            ? 0
            : (t.nodes[key - 1].getElev() - t.nodes[key].getElev()) / value);
        final fRoll =
            routingContext.totalMass *
            gravity *
            (routingContext.defaultCr + incline);
        final spd = speedMin / 3.6;
        addEnergy = value * (routingContext.sCx * spd * spd + fRoll);
      }
      for (var j = key; j < ourSize; j++) {
        final n = t.nodes[j];
        n.setTime(f32(n.getTime() + addTime));
        n.setEnergy(f32(n.getEnergy() + f32(addEnergy)));
      }
    }
    t.energy = d2i(t.nodes[t.nodes.length - 1].getEnergy());

    _logInfo('track-length total = ${t.distance}');
    _logInfo('filtered ascend = ${t.ascend}');
  }

  /// find the elevation type for position
  /// to determine the filter value
  double elevationFilter(OsmPos n) {
    if (nodesCache != null) {
      final r = nodesCache!.getElevationType(n.getILon(), n.getILat());
      if (r == 1) return -5.0;
    }
    return -10.0;
  }

  // geometric position matching finding the nearest routable way-section
  void _matchWaypointsToNodes(List<MatchedWaypoint> unmatchedWaypoints) {
    if (kProfile) Prof.match.start();
    try {
      _matchWaypointsToNodes0(unmatchedWaypoints);
    } finally {
      if (kProfile) Prof.match.stop();
    }
  }

  void _matchWaypointsToNodes0(List<MatchedWaypoint> unmatchedWaypoints) {
    _resetCache(false);
    final useDynamicDistance = routingContext.useDynamicDistance;
    final bAddBeeline = routingContext.buildBeelineOnRange;
    var range = routingContext.waypointCatchingRange;
    var ok = nodesCache!.matchWaypointsToNodes(
      unmatchedWaypoints,
      range,
      _islandNodePairs,
    );
    if (!ok && useDynamicDistance) {
      _logInfo('second check for way points');
      _resetCache(false);
      range = -_maxDynamicRange.toDouble();
      final tmp = <MatchedWaypoint>[];
      for (final mwp in unmatchedWaypoints) {
        if (mwp.crosspoint == null ||
            mwp.radius >= routingContext.waypointCatchingRange) {
          tmp.add(mwp);
        }
      }
      ok = nodesCache!.matchWaypointsToNodes(tmp, range, _islandNodePairs);
    }
    if (!ok) {
      for (final mwp in unmatchedWaypoints) {
        if (mwp.crosspoint == null) {
          throw ArgumentError(
            '${mwp.name}-position not mapped in existing datafile',
          );
        }
      }
    }
    // add beeline points when not already done
    if (useDynamicDistance && !_useNodePoints && bAddBeeline) {
      final waypoints = <MatchedWaypoint>[];
      for (var i = 0; i < unmatchedWaypoints.length; i++) {
        final wp = unmatchedWaypoints[i];
        if (wp.waypoint!.calcDistance(wp.crosspoint!) >
            routingContext.waypointCatchingRange) {
          final nmw = MatchedWaypoint();
          if (i == 0) {
            var onn = OsmNodeNamed(wp.waypoint);
            onn.name = 'from';
            nmw.waypoint = onn;
            nmw.name = onn.name;
            nmw.crosspoint = OsmNode(wp.waypoint!.ilon, wp.waypoint!.ilat);
            nmw.wpttype = MatchedWaypoint.waypointTypeDirect;
            onn = OsmNodeNamed(wp.crosspoint);
            onn.name = '${wp.name}_add';
            wp.waypoint = onn;
            waypoints.add(nmw);
            wp.name = '${wp.name}_add';
            waypoints.add(wp);
          } else {
            final onn = OsmNodeNamed(wp.crosspoint);
            onn.name = '${wp.name}_add';
            nmw.waypoint = onn;
            nmw.crosspoint = OsmNode(wp.crosspoint!.ilon, wp.crosspoint!.ilat);
            nmw.node1 = OsmNode(wp.node1!.ilon, wp.node1!.ilat);
            nmw.node2 = OsmNode(wp.node2!.ilon, wp.node2!.ilat);
            nmw.wpttype = MatchedWaypoint.waypointTypeDirect;

            if (wp.name != null) nmw.name = wp.name;
            waypoints.add(nmw);
            wp.name = '${wp.name}_add';
            waypoints.add(wp);
            if (wp.name!.startsWith('via')) {
              wp.wpttype = MatchedWaypoint.waypointTypeDirect;
              final emw = MatchedWaypoint();
              final onn2 = OsmNodeNamed(wp.crosspoint);
              onn2.name = '${wp.name}_2';
              emw.name = onn2.name;
              emw.waypoint = onn2;
              emw.crosspoint = OsmNode(
                nmw.crosspoint!.ilon,
                nmw.crosspoint!.ilat,
              );
              emw.node1 = OsmNode(nmw.node1!.ilon, nmw.node1!.ilat);
              emw.node2 = OsmNode(nmw.node2!.ilon, nmw.node2!.ilat);
              emw.wpttype = MatchedWaypoint.waypointTypeShaping;
              waypoints.add(emw);
            }
            wp.crosspoint = OsmNode(wp.waypoint!.ilon, wp.waypoint!.ilat);
          }
        } else {
          waypoints.add(wp);
        }
      }
      unmatchedWaypoints.clear();
      unmatchedWaypoints.addAll(waypoints);
    }
  }

  Future<OsmTrack?> _searchTrack(
    MatchedWaypoint startWp,
    MatchedWaypoint endWp,
    OsmTrack? nearbyTrack,
    OsmTrack? refTrack,
  ) async {
    // remove nogos with waypoints inside
    try {
      final calcBeeline = startWp.wpttype == MatchedWaypoint.waypointTypeDirect;

      if (!calcBeeline) {
        return await _searchRoutedTrack(startWp, endWp, nearbyTrack, refTrack);
      }

      // we want a beeline-segment
      var path = routingContext.createStartPath(
        OsmLink(null, startWp.crosspoint),
      );
      path = routingContext.createPath(
        path,
        OsmLink(startWp.crosspoint, endWp.crosspoint),
        null,
        false,
      );
      return _compileTrack(path, false);
    } finally {
      routingContext.restoreNogoList();
    }
  }

  Future<OsmTrack?> _searchRoutedTrack(
    MatchedWaypoint startWp,
    MatchedWaypoint endWp,
    OsmTrack? nearbyTrack,
    OsmTrack? refTrack,
  ) async {
    OsmTrack? track;
    final airDistanceCostFactors = <double>[
      routingContext.pass1coefficient,
      routingContext.pass2coefficient,
    ];
    var isDirty = false;
    ArgumentError? dirtyMessage;

    if (nearbyTrack != null) {
      airDistanceCostFactor = 0.0;
      try {
        track = await findTrackSegment(
          're-routing',
          startWp,
          endWp,
          nearbyTrack,
          refTrack,
          true,
        );
      } on ArgumentError catch (iae) {
        if (_terminated) rethrow;

        // fast partial recalcs: if that timed out, but we had a match,
        // build the concatenation from the partial and the nearby track
        if (_matchPath != null) {
          track = _mergeTrack(_matchPath!, nearbyTrack);
          isDirty = true;
          dirtyMessage = iae;
          _logInfo('using fast partial recalc');
        }
        if (_maxRunningTime > 0) {
          _maxRunningTime +=
              _currentTimeMillis() - _startTime; // reset timeout...
        }
      }
    }

    if (track == null) {
      for (var cfi = 0; cfi < airDistanceCostFactors.length; cfi++) {
        if (cfi > 0) {
          lastAirDistanceCostFactor = airDistanceCostFactors[cfi - 1];
        }
        airDistanceCostFactor = airDistanceCostFactors[cfi];

        if (airDistanceCostFactor < 0.0) {
          continue;
        }

        OsmTrack? t;
        try {
          t = await findTrackSegment(
            cfi == 0 ? 'pass0' : 'pass1',
            startWp,
            endWp,
            track,
            refTrack,
            false,
          );
          if (routingContext.ai != null) return t;
        } on ArgumentError {
          if (!_terminated && _matchPath != null) {
            // timeout, but eventually prepare a dirty ref track
            _logInfo('supplying dirty reference track after timeout');
            _foundRawTrack = _mergeTrack(_matchPath!, track!);
            _foundRawTrack!.endPoint = endWp;
            _foundRawTrack!.nogoChecksums = routingContext.getNogoChecksums();
            _foundRawTrack!.profileTimestamp = routingContext.profileTimestamp;
            _foundRawTrack!.isDirty = true;
          }
          rethrow;
        }

        if (t == null && track != null && _matchPath != null) {
          // ups, didn't find it, use a merge
          t = _mergeTrack(_matchPath!, track);
          _logInfo("using sloppy merge cause pass1 didn't reach destination");
        }
        if (t != null) {
          track = t;
        } else {
          throw ArgumentError('no track found at pass=$cfi');
        }
      }
    }
    if (track == null) throw ArgumentError('no track found');

    final wasClean = nearbyTrack != null && !nearbyTrack.isDirty;
    if (refTrack == null && !(wasClean && isDirty)) {
      // do not overwrite a clean with a dirty track
      _logInfo('supplying new reference track, dirty=$isDirty');
      track.endPoint = endWp;
      track.nogoChecksums = routingContext.getNogoChecksums();
      track.profileTimestamp = routingContext.profileTimestamp;
      track.isDirty = isDirty;
      _foundRawTrack = track;
    }

    if (!wasClean && isDirty) {
      throw dirtyMessage!;
    }

    // final run for verbose log info and detail nodes
    airDistanceCostFactor = 0.0;
    lastAirDistanceCostFactor = 0.0;
    _guideTrack = track;
    _startTime = _currentTimeMillis(); // reset timeout...
    try {
      final tt = await findTrackSegment(
        're-tracking',
        startWp,
        endWp,
        null,
        refTrack,
        false,
      );
      if (tt == null) throw ArgumentError('error re-tracking track');
      return tt;
    } finally {
      _guideTrack = null;
    }
  }

  void _resetCache(bool detailed) {
    if (_hasInfo() && nodesCache != null) {
      _logInfo('NodesCache status before reset=${nodesCache!.formatStatus()}');
    }
    final maxmem = routingContext.memoryclass * 1024 * 1024; // in MB

    nodesCache = NodesCache(
      segmentDir,
      routingContext.expctxWay!,
      routingContext.forceSecondaryData,
      maxmem,
      nodesCache,
      detailed,
      rawCache: rawCache,
    );
    _islandNodePairs.clearTempPairs();
  }

  /// `getStartPath(OsmNode n1, OsmNode n2, MatchedWaypoint mwp, OsmNodeNamed endPos, boolean sameSegmentSearch)`
  OsmPath? _getStartPathForWaypoint(
    OsmNode n1,
    OsmNode n2,
    MatchedWaypoint mwp,
    OsmNodeNamed? endPos,
    bool sameSegmentSearch,
  ) {
    if (endPos != null) {
      endPos.radius = 1.5;
    }
    final p = _getStartPath(
      n1,
      n2,
      OsmNodeNamed(mwp.crosspoint),
      endPos,
      sameSegmentSearch,
    );

    // special case: start+end on same segment
    if (p != null &&
        p.cost >= 0 &&
        sameSegmentSearch &&
        endPos != null &&
        endPos.radius < 1.5) {
      p.treedepth = 0; // hack: mark for the final-check
    }
    return p;
  }

  OsmPath? _getStartPath(
    OsmNode n1,
    OsmNode n2,
    OsmNodeNamed wp,
    OsmNodeNamed? endPos,
    bool sameSegmentSearch,
  ) {
    try {
      routingContext.setWaypoint(wp, false, sameSegmentSearch ? endPos : null);
      OsmPath? bestPath;
      OsmLink? bestLink;
      final startLink = OsmLink(null, n1);
      final startPath = routingContext.createStartPath(startLink);
      startLink.addLinkHolder(startPath, null);
      var minradius = 1e10;
      for (var link = n1.firstlink; link != null; link = link.getNext(n1)) {
        final nextNode = link.getTarget(n1);
        if (nextNode.isHollow()) continue; // border node?
        if (nextNode.firstlink == null) continue; // don't care about dead ends
        if (nextNode == n1) continue; // ?
        if (nextNode != n2) continue; // just that link

        wp.radius = 1.5;
        final testPath = routingContext.createPath(
          startPath,
          link,
          null,
          _guideTrack != null,
        );
        testPath.airdistance = endPos == null
            ? 0
            : nextNode.calcDistance(endPos);
        if (wp.radius < minradius) {
          bestPath = testPath;
          minradius = wp.radius;
          bestLink = link;
        }
      }
      if (bestLink != null) {
        bestLink.addLinkHolder(bestPath!, n1);
      }
      if (bestPath != null) bestPath.treedepth = 1;

      return bestPath;
    } finally {
      routingContext.unsetWaypoint();
    }
  }

  /// `findTrack(String operationName, MatchedWaypoint startWp, MatchedWaypoint endWp, OsmTrack costCuttingTrack, OsmTrack refTrack, boolean fastPartialRecalc)`
  Future<OsmTrack?> findTrackSegment(
    String operationName,
    MatchedWaypoint startWp,
    MatchedWaypoint? endWp,
    OsmTrack? costCuttingTrack,
    OsmTrack? refTrack,
    bool fastPartialRecalc,
  ) async {
    try {
      final wpts2 = <OsmNode>[];
      wpts2.add(startWp.waypoint!);
      if (endWp != null) wpts2.add(endWp.waypoint!);
      routingContext.cleanNogoList(wpts2);

      final detailed = _guideTrack != null;
      if (kProfile) Prof.segments++;
      _resetCache(detailed);
      nodesCache!.nodesMap.cleanupMode = detailed
          ? 0
          : (routingContext.considerTurnRestrictions ? 2 : 1);
      return await _findTrack(
        operationName,
        startWp,
        endWp,
        costCuttingTrack,
        refTrack,
        fastPartialRecalc,
      );
    } finally {
      routingContext.restoreNogoList();
      nodesCache!.clean(false); // clean only non-virgin caches
    }
  }

  Future<OsmTrack?> _findTrack(
    String operationName,
    MatchedWaypoint startWp,
    MatchedWaypoint? endWp,
    OsmTrack? costCuttingTrack,
    OsmTrack? refTrack,
    bool fastPartialRecalc,
  ) async {
    final verbose = _guideTrack != null;

    var maxTotalCost = _guideTrack != null
        ? _guideTrack!.cost + 5000
        : 1000000000;
    var firstMatchCost = 1000000000;

    _logInfo('findtrack with airDistanceCostFactor=$airDistanceCostFactor');
    if (costCuttingTrack != null) {
      _logInfo('costCuttingTrack.cost=${costCuttingTrack.cost}');
    }

    _matchPath = null;
    var nodesVisited = 0;

    final startNodeId1 = startWp.node1!.getIdFromPos();
    final startNodeId2 = startWp.node2!.getIdFromPos();
    final endNodeId1 = endWp == null ? -1 : endWp.node1!.getIdFromPos();
    final endNodeId2 = endWp == null ? -1 : endWp.node2!.getIdFromPos();
    OsmNode? end1;
    OsmNode? end2;
    OsmNodeNamed? endPos;

    var sameSegmentSearch = false;
    final nc = nodesCache!;
    final start1 = nc.getGraphNode(startWp.node1!);
    final start2 = nc.getGraphNode(startWp.node2!);
    if (endWp != null) {
      end1 = nc.getGraphNode(endWp.node1!);
      end2 = nc.getGraphNode(endWp.node2!);
      nc.nodesMap.endNode1 = end1;
      nc.nodesMap.endNode2 = end2;
      endPos = OsmNodeNamed(endWp.crosspoint);
      sameSegmentSearch =
          (start1 == end1 && start2 == end2) ||
          (start1 == end2 && start2 == end1);
    }
    if (!nc.obtainNonHollowNode(start1)) {
      return null;
    }
    nc.expandHollowLinkTargets(start1);
    if (!nc.obtainNonHollowNode(start2)) {
      return null;
    }
    nc.expandHollowLinkTargets(start2);

    routingContext.startDirectionValid =
        routingContext.forceUseStartDirection || fastPartialRecalc;
    routingContext.startDirectionValid &=
        routingContext.startDirection != null &&
        !routingContext.inverseDirection;
    if (routingContext.startDirectionValid) {
      _logInfo('using start direction ${routingContext.startDirection}');
    }

    final startPath1 = _getStartPathForWaypoint(
      start1,
      start2,
      startWp,
      endPos,
      sameSegmentSearch,
    );
    final startPath2 = _getStartPathForWaypoint(
      start2,
      start1,
      startWp,
      endPos,
      sameSegmentSearch,
    );

    // check for an INITIAL match with the cost-cutting-track
    if (costCuttingTrack != null) {
      final pe1 = costCuttingTrack.getLink(startNodeId1, startNodeId2);
      if (pe1 != null) {
        _logInfo('initialMatch pe1.cost=${pe1.cost}');
        var c = startPath1!.cost - pe1.cost;
        if (c < 0) c = 0;
        if (c < firstMatchCost) firstMatchCost = c;
      }

      final pe2 = costCuttingTrack.getLink(startNodeId2, startNodeId1);
      if (pe2 != null) {
        _logInfo('initialMatch pe2.cost=${pe2.cost}');
        var c = startPath2!.cost - pe2.cost;
        if (c < 0) c = 0;
        if (c < firstMatchCost) firstMatchCost = c;
      }

      if (firstMatchCost < 1000000000) {
        _logInfo('firstMatchCost from initial match=$firstMatchCost');
      }
    }

    if (startPath1 == null) return null;
    if (startPath2 == null) return null;

    _openSet.clear();
    _addToOpenset(startPath1);
    _addToOpenset(startPath2);
    final openBorderList = <OsmPath>[];
    var memoryPanicMode = false;
    var needNonPanicProcessing = false;

    for (;;) {
      if (_terminated) {
        throw ArgumentError(
          'operation killed by thread-priority-watchdog after ${(_currentTimeMillis() - _startTime) ~/ 1000} seconds',
        );
      }

      if (_maxRunningTime > 0) {
        final timeout = (_matchPath == null && fastPartialRecalc)
            ? _maxRunningTime ~/ 3
            : _maxRunningTime;
        if (_currentTimeMillis() - _startTime > timeout) {
          throw ArgumentError(
            '$operationName timeout after ${timeout ~/ 1000} seconds',
          );
        }
      }

      if (kProfile) Prof.expansions++;
      if (++_expansions % yieldInterval == 0) {
        final pl = progressListener;
        if (pl != null) pl(_linksProcessed, _openSet.getSize());
        final yh = yieldHook;
        if (yh != null) await yh();
      }

      {
        final path = _openSet.popLowestKeyValue();
        if (path == null) {
          if (openBorderList.isEmpty) {
            break;
          }
          for (final p in openBorderList) {
            _openSet.add(
              p.cost + d2i(p.airdistance * airDistanceCostFactor),
              p,
            );
          }
          openBorderList.clear();
          memoryPanicMode = false;
          needNonPanicProcessing = true;
          continue;
        }

        if (path.airdistance == -1) {
          continue;
        }

        if (_directWeaving && nc.hasHollowLinkTargets(path.getTargetNode())) {
          if (!memoryPanicMode) {
            if (!nc.nodesMap.isInMemoryBounds(_openSet.getSize(), false)) {
              final nodesBefore = nc.nodesMap.nodesCreated;
              final pathsBefore = _openSet.getSize();

              if (kProfile) {
                Prof.collect.start();
                Prof.collects++;
              }
              nc.nodesMap.collectOutreachers();
              if (kProfile) Prof.collect.stop();
              for (;;) {
                final p3 = _openSet.popLowestKeyValue();
                if (p3 == null) break;
                if (p3.airdistance != -1 &&
                    nc.nodesMap.canEscape(p3.getTargetNode())) {
                  openBorderList.add(p3);
                }
              }
              nc.nodesMap.clearTemp();
              for (final p in openBorderList) {
                _openSet.add(
                  p.cost + d2i(p.airdistance * airDistanceCostFactor),
                  p,
                );
              }
              openBorderList.clear();
              _logInfo(
                'collected, nodes/paths before=$nodesBefore/$pathsBefore after=${nc.nodesMap.nodesCreated}/${_openSet.getSize()} maxTotalCost=$maxTotalCost',
              );
              if (!nc.nodesMap.isInMemoryBounds(_openSet.getSize(), true)) {
                if (maxTotalCost < 1000000000 ||
                    needNonPanicProcessing ||
                    fastPartialRecalc) {
                  throw ArgumentError('memory limit reached');
                }
                memoryPanicMode = true;
                _logInfo(
                  '************************ memory limit reached, enabled memory panic mode *************************',
                );
              }
            }
          }
          if (memoryPanicMode) {
            openBorderList.add(path);
            continue;
          }
        }
        needNonPanicProcessing = false;

        if (fastPartialRecalc &&
            _matchPath != null &&
            path.cost > 30 * firstMatchCost &&
            !costCuttingTrack!.isDirty) {
          _logInfo(
            'early exit: firstMatchCost=$firstMatchCost path.cost=${path.cost}',
          );

          // use an early exit, unless there's a realistc chance to complete within the timeout
          if (path.cost > maxTotalCost ~/ 2 &&
              _currentTimeMillis() - _startTime < _maxRunningTime ~/ 3) {
            _logInfo(
              'early exit supressed, running for completion, resetting timeout',
            );
            _startTime = _currentTimeMillis();
            fastPartialRecalc = false;
          } else {
            throw ArgumentError('early exit for a close recalc');
          }
        }

        if (_nodeLimit > 0) {
          // check node-limit for target island search
          if (--_nodeLimit == 0) {
            return null;
          }
        }

        nodesVisited++;
        _linksProcessed++;

        final currentLink = path.getLink();
        final sourceNode = path.getSourceNode();
        final currentNode = path.getTargetNode();

        if (currentLink.isLinkUnused()) {
          continue;
        }

        final currentNodeId = currentNode.getIdFromPos();
        final sourceNodeId = sourceNode.getIdFromPos();

        if (!path.didEnterDestinationArea()) {
          _islandNodePairs.addTempPair(sourceNodeId, currentNodeId);
        }

        if (path.treedepth != 1) {
          if (path.treedepth == 0) {
            // hack: sameSegment Paths marked treedepth=0 to pass above check
            path.treedepth = 1;
          }

          if ((sourceNodeId == endNodeId1 && currentNodeId == endNodeId2) ||
              (sourceNodeId == endNodeId2 && currentNodeId == endNodeId1)) {
            // track found, compile
            _logInfo(
              'found track at cost ${path.cost} nodesVisited = $nodesVisited',
            );
            if (kProfile) Prof.compile.start();
            final t = _compileTrack(path, verbose);
            if (kProfile) Prof.compile.stop();
            t.showspeed = routingContext.showspeed;
            t.showSpeedProfile = routingContext.showSpeedProfile;
            return t;
          }

          // check for a match with the cost-cutting-track
          if (costCuttingTrack != null) {
            final pe = costCuttingTrack.getLink(sourceNodeId, currentNodeId);
            if (pe != null) {
              // remember first match cost for fast termination of partial recalcs
              var parentcost = path.originElement == null
                  ? 0
                  : path.originElement!.cost;

              // hitting start-element of costCuttingTrack?
              final c = path.cost - parentcost - pe.cost;
              if (c > 0) parentcost += c;

              if (parentcost < firstMatchCost) firstMatchCost = parentcost;

              final costEstimate =
                  path.cost +
                  path.elevationCorrection() +
                  (costCuttingTrack.cost - pe.cost);
              if (costEstimate <= maxTotalCost) {
                _matchPath = OsmPathElement.create(path);
              }
              if (costEstimate < maxTotalCost) {
                _logInfo('maxcost $maxTotalCost -> $costEstimate');
                maxTotalCost = costEstimate;
              }
            }
          }
        }

        final firstLinkHolder = currentLink.getFirstLinkHolder(sourceNode);
        for (
          OsmLinkHolder? linkHolder = firstLinkHolder;
          linkHolder != null;
          linkHolder = linkHolder.getNextForLink()
        ) {
          (linkHolder as OsmPath).airdistance =
              -1; // invalidate the entry in the open set;
        }

        if (path.treedepth > 1) {
          final isBidir = currentLink.isBidirectional();
          sourceNode.unlinkLink(currentLink);

          // if the counterlink is alive and does not yet have a path, remove it
          if (isBidir &&
              currentLink.getFirstLinkHolder(currentNode) == null &&
              !routingContext.considerTurnRestrictions) {
            currentNode.unlinkLink(currentLink);
          }
        }

        // recheck cutoff before doing expensive stuff
        const addDiff = 100;
        if (path.cost + path.airdistance > maxTotalCost + addDiff) {
          continue;
        }

        nc.nodesMap.currentMaxCost = maxTotalCost;
        nc.nodesMap.currentPathCost = path.cost;
        nc.nodesMap.destination = endPos;

        routingContext.firstPrePath = null;

        for (
          var link = currentNode.firstlink;
          link != null;
          link = link.getNext(currentNode)
        ) {
          final nextNode = link.getTarget(currentNode);

          if (!nc.obtainNonHollowNode(nextNode)) {
            continue; // border node?
          }
          if (nextNode.firstlink == null) {
            continue; // don't care about dead ends
          }
          if (nextNode == sourceNode) {
            continue; // border node?
          }

          final prePath = routingContext.createPrePath(path, link);
          if (prePath != null) {
            prePath.next = routingContext.firstPrePath;
            routingContext.firstPrePath = prePath;
          }
        }

        for (
          var link = currentNode.firstlink;
          link != null;
          link = link.getNext(currentNode)
        ) {
          final nextNode = link.getTarget(currentNode);

          if (!nc.obtainNonHollowNode(nextNode)) {
            continue; // border node?
          }
          if (nextNode.firstlink == null) {
            continue; // don't care about dead ends
          }
          if (nextNode == sourceNode) {
            continue; // border node?
          }

          if (_guideTrack != null) {
            final gidx = path.treedepth + 1;
            if (gidx >= _guideTrack!.nodes.length) {
              continue;
            }
            final guideNode =
                _guideTrack!.nodes[routingContext.inverseRouting
                    ? _guideTrack!.nodes.length - 1 - gidx
                    : gidx];
            final nextId = nextNode.getIdFromPos();
            if (nextId != guideNode.getIdFromPos()) {
              // not along the guide-track, discard, but register for voice-hint processing
              if (routingContext.turnInstructionMode > 0) {
                final detour = routingContext.createPath(
                  path,
                  link,
                  refTrack,
                  true,
                );
                if (detour.cost >= 0 &&
                    nextId != startNodeId1 &&
                    nextId != startNodeId2) {
                  _guideTrack!.registerDetourForId(
                    currentNode.getIdFromPos(),
                    OsmPathElement.create(detour),
                  );
                }
              }
              continue;
            }
          }

          OsmPath? bestPath;

          var isFinalLink = false;
          final targetNodeId = nextNode.getIdFromPos();
          if (currentNodeId == endNodeId1 || currentNodeId == endNodeId2) {
            if (targetNodeId == endNodeId1 || targetNodeId == endNodeId2) {
              isFinalLink = true;
            }
          }

          for (
            OsmLinkHolder? linkHolder = firstLinkHolder;
            linkHolder != null;
            linkHolder = linkHolder.getNextForLink()
          ) {
            final otherPath = linkHolder as OsmPath;
            try {
              if (isFinalLink) {
                endPos!.radius = 1.5; // 1.5 meters is the upper limit that will not change the unit-test result..
                routingContext.setWaypoint(endPos, true);
              }
              final testPath = routingContext.createPath(
                otherPath,
                link,
                refTrack,
                _guideTrack != null,
              );
              if (testPath.cost >= 0 &&
                  (bestPath == null || testPath.cost < bestPath.cost) &&
                  (testPath.sourceNode.getIdFromPos() !=
                      testPath.targetNode.getIdFromPos())) {
                bestPath = testPath;
              }
            } finally {
              if (isFinalLink) {
                routingContext.unsetWaypoint();
              }
            }
          }
          if (bestPath != null) {
            bestPath.airdistance = isFinalLink
                ? 0
                : nextNode.calcDistance(endPos!);

            final inRadius =
                boundary == null ||
                boundary!.isInBoundary(nextNode, bestPath.cost);

            if (inRadius &&
                (isFinalLink ||
                    bestPath.cost + bestPath.airdistance <=
                        (lastAirDistanceCostFactor != 0.0
                                ? maxTotalCost * lastAirDistanceCostFactor
                                : maxTotalCost) +
                            addDiff)) {
              // add only if this may beat an existing path for that link
              var dominator = link.getFirstLinkHolder(currentNode);
              while (dominator != null) {
                final dp = dominator as OsmPath;
                if (dp.airdistance != -1 && bestPath.definitlyWorseThan(dp)) {
                  break;
                }
                dominator = dominator.getNextForLink();
              }

              if (dominator == null) {
                bestPath.treedepth = path.treedepth + 1;
                link.addLinkHolder(bestPath, currentNode);
                _addToOpenset(bestPath);
              }
            }
          }
        }
      }
    }

    if (nodesVisited < _maxnodesIslandCheck &&
        _islandNodePairs.getFreezeCount() < 5) {
      throw RoutingIslandException();
    }

    return null;
  }

  void _addToOpenset(OsmPath path) {
    if (path.cost >= 0) {
      _openSet.add(
        path.cost + d2i(path.airdistance * airDistanceCostFactor),
        path,
      );
    }
  }

  OsmTrack _compileTrack(OsmPath path, bool verbose) {
    var element = OsmPathElement.create(path);

    // for final track, cut endnode
    if (_guideTrack != null && element.origin != null) {
      element = element.origin!;
    }

    final totalTime = element.getTime();
    final totalEnergy = element.getEnergy();

    final track = OsmTrack();
    track.cost = path.cost;
    track.energy = d2i(path.getTotalEnergy());

    var distance = 0;

    // R5: upstream inserts every element at index 0 (quadratic, and every
    // shifted element passes a covariant list-store check); the elements are
    // collected and reversed once instead, same order.
    final backwards = <OsmPathElement>[];
    OsmPathElement? e = element;
    while (e != null) {
      if (_guideTrack != null && e.message == null) {
        e.message = MessageData();
      }
      final nextElement = e.origin;
      // ignore double element
      if (nextElement != null && nextElement.positionEquals(e)) {
        e = nextElement;
        continue;
      }
      if (routingContext.inverseRouting) {
        e.setTime(f32(totalTime - e.getTime()));
        e.setEnergy(f32(totalEnergy - e.getEnergy()));
        track.nodes.add(e);
      } else {
        backwards.add(e);
      }

      if (nextElement != null) {
        distance += e.calcDistance(nextElement);
      }
      e = nextElement;
    }
    if (backwards.isNotEmpty) {
      track.nodes.addAll(backwards.reversed);
    }
    track.distance = distance;
    _logInfo('track-length = ${track.distance}');
    track.buildMap();

    // for final track..
    if (_guideTrack != null) {
      track.copyDetours(_guideTrack!);
    }
    return track;
  }

  OsmTrack _mergeTrack(OsmPathElement match, OsmTrack oldTrack) {
    _logInfo(
      '**************** merging match=${match.cost} with oldTrack=${oldTrack.cost}',
    );
    OsmPathElement? element = match;
    final track = OsmTrack();
    track.cost = oldTrack.cost;

    while (element != null) {
      track.addNode(element);
      element = element.origin;
    }
    var lastId = 0;
    final id1 = match.getIdFromPos();
    final id0 = match.origin == null ? 0 : match.origin!.getIdFromPos();
    var appending = false;
    for (final n in oldTrack.nodes) {
      if (appending) {
        track.nodes.add(n);
      }

      final id = n.getIdFromPos();
      if (id == id1 && lastId == id0) {
        appending = true;
      }
      lastId = id;
    }

    track.buildMap();
    return track;
  }

  int getPathPeak() {
    return _openSet.getPeakSize();
  }

  List<int> getOpenSet() {
    _extract ??= List<OsmPath?>.filled(500, null);

    if (_guideTrack != null) {
      final nodes = _guideTrack!.nodes;
      final res = List<int>.filled(nodes.length * 2, 0);
      var i = 0;
      for (final n in nodes) {
        res[i++] = n.getILon();
        res[i++] = n.getILat();
      }
      return res;
    }

    final size = _openSet.getExtract(_extract!);
    final res = List<int>.filled(size * 2, 0);
    for (var i = 0, j = 0; i < size; i++) {
      final p = _extract![i]!;
      _extract![i] = null;
      final n = p.getTargetNode();
      res[j++] = n.ilon;
      res[j++] = n.ilat;
    }
    return res;
  }

  bool isFinished() {
    return _finished;
  }

  int getLinksProcessed() {
    return _linksProcessed;
  }

  int getDistance() {
    return foundTrack.distance;
  }

  int getAscend() {
    return foundTrack.ascend;
  }

  int getPlainAscend() {
    return foundTrack.plainAscend;
  }

  String getTime() {
    return Formatter.getFormattedTime2(foundTrack.getTotalSeconds());
  }

  OsmTrack getFoundTrack() {
    return foundTrack;
  }

  String? getFoundInfo() {
    return outputMessage;
  }

  int getAlternativeIndex() {
    return _alternativeIndex;
  }

  OsmTrack? getFoundRawTrack() {
    return _foundRawTrack;
  }

  String? getErrorMessage() {
    return errorMessage;
  }

  void terminate() {
    _terminated = true;
  }

  bool isTerminated() {
    return _terminated;
  }

  String? getOutfile() {
    return _outfile;
  }
}

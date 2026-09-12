// Port of btools.mapaccess.NodesCache (BRouter v1.7.10).

import 'dart:io';

import '../codec/data_buffers.dart';
import '../codec/micro_cache.dart';
import '../codec/waypoint_matcher.dart';
import '../expressions/b_expression_context_way.dart';
import '../jvm.dart';
import 'matched_waypoint.dart';
import 'osm_file.dart';
import 'osm_link.dart';
import 'osm_node.dart';
import 'osm_node_pair_set.dart';
import 'osm_nodes_map.dart';
import 'physical_file.dart';
import 'waypoint_matcher_impl.dart';

/// Efficient cache or osmnodes
///
/// The `BExpressionContextWay` is, exactly like upstream, the
/// `TagValueValidator` of the decoders (`OsmFile.createMicroCache`), the
/// `IByteArrayUnifier` of the link descriptions (`OsmNode.parseNodeBody`) and
/// the source of `meta.lookupVersion` / `meta.lookupMinorVersion` for
/// `PhysicalFile`.
class NodesCache {
  NodesCache(
    Directory segmentDir,
    BExpressionContextWay ctxWay,
    bool forceSecondaryData,
    int maxmem,
    NodesCache? oldCache,
    bool detailed,
  ) : _maxmemtiles = maxmem ~/ 8,
      _segmentDir = segmentDir,
      _expCtxWay = ctxWay,
      _lookupVersion = ctxWay.meta!.lookupVersion,
      _lookupMinorVersion = ctxWay.meta!.lookupMinorVersion,
      _forceSecondaryData = forceSecondaryData,
      _detailed = detailed,
      _directWeaving = !disableDirectWeaving {
    nodesMap = OsmNodesMap();
    nodesMap.maxmem = (2 * maxmem) ~/ 3;

    ctxWay.setDecodeForbidden(detailed);

    firstFileAccessFailed = false;
    firstFileAccessName = null;

    if (!_segmentDir.existsSync()) {
      throw StateError(
        'segment directory ${segmentDir.absolute.path} does not exist',
      );
    }

    if (oldCache != null) {
      _fileCache = oldCache._fileCache;
      _dataBuffers = oldCache._dataBuffers;
      _secondarySegmentsDir = oldCache._secondarySegmentsDir;

      // re-use old, virgin caches (if same detail-mode)
      if (oldCache._detailed == detailed) {
        _fileRows = oldCache._fileRows;
        for (final fileRow in _fileRows) {
          if (fileRow == null) continue;
          for (final osmf in fileRow) {
            _cacheSum += osmf.setGhostState();
          }
        }
      } else {
        _fileRows = List<List<OsmFile>?>.filled(180, null);
      }
    } else {
      _fileCache = <String, PhysicalFile?>{};
      _fileRows = List<List<OsmFile>?>.filled(180, null);
      _dataBuffers = DataBuffers();
      // StorageConfigHelper.getSecondarySegmentDir(segmentDir) is not ported
      // (storageconfig.txt is an Android-app feature): no secondary directory.
      _secondarySegmentsDir = null;
    }
    _ghostSum = _cacheSum;
  }

  static const int retryRange = 250; // RETRY_RANGE

  final int _maxDynamicCatches = 20; // MAX_DYNAMIC_CATCHES, used with RoutingEngiine MAX_DYNAMIC_RANGE = 60000m

  /// `Boolean.getBoolean("disableDirectWeaving")`: read once per instance in
  /// the constructor, like the upstream field initialiser.
  static bool disableDirectWeaving = false;

  final Directory _segmentDir;
  Directory? _secondarySegmentsDir;

  late OsmNodesMap nodesMap;
  final BExpressionContextWay _expCtxWay;
  final int _lookupVersion;
  final int _lookupMinorVersion;
  final bool _forceSecondaryData;
  String? _currentFileName;

  late Map<String, PhysicalFile?> _fileCache;
  late DataBuffers _dataBuffers;

  late List<List<OsmFile>?> _fileRows;

  WaypointMatcher? waypointMatcher;

  /// `first_file_access_failed`.
  bool firstFileAccessFailed = false;

  /// `first_file_access_name`.
  String? firstFileAccessName;

  int _cacheSum = 0;
  int _maxmemtiles;
  final bool _detailed; // NOPMD used in constructor

  bool _garbageCollectionEnabled = false;
  bool _ghostCleaningDone = false;

  int _cacheSumClean = 0;
  int _ghostSum = 0;
  int _ghostWakeup = 0;

  final bool _directWeaving;

  String formatStatus() {
    return 'collecting=$_garbageCollectionEnabled noGhosts=$_ghostCleaningDone cacheSum=$_cacheSum cacheSumClean=$_cacheSumClean ghostSum=$_ghostSum ghostWakeup=$_ghostWakeup';
  }

  void clean(bool all) {
    for (final fileRow in _fileRows) {
      if (fileRow == null) continue;
      for (final osmf in fileRow) {
        osmf.clean(all);
      }
    }
  }

  // if the cache sum exceeded a threshold,
  // clean all ghosts and enable garbage collection
  void _checkEnableCacheCleaning() {
    if (_cacheSum < _maxmemtiles) {
      return;
    }

    for (var i = 0; i < _fileRows.length; i++) {
      final fileRow = _fileRows[i];
      if (fileRow == null) {
        continue;
      }
      for (final osmf in fileRow) {
        if (_garbageCollectionEnabled && !_ghostCleaningDone) {
          _cacheSum -= osmf.cleanGhosts();
        } else {
          _cacheSum -= osmf.collectAll();
        }
      }
    }

    if (_garbageCollectionEnabled) {
      _ghostCleaningDone = true;
      _maxmemtiles *= 2;
    } else {
      _cacheSumClean = _cacheSum;
      _garbageCollectionEnabled = true;
    }
  }

  int loadSegmentFor(int ilon, int ilat) {
    final mc = getSegmentFor(ilon, ilat);
    return mc == null ? 0 : mc.getSize();
  }

  MicroCache? getSegmentFor(int ilon, int ilat) {
    try {
      final lonDegree = ilon ~/ 1000000;
      final latDegree = ilat ~/ 1000000;
      OsmFile? osmf;
      final fileRow = _fileRows[latDegree];
      final ndegrees = fileRow == null ? 0 : fileRow.length;
      for (var i = 0; i < ndegrees; i++) {
        if (fileRow![i].lonDegree == lonDegree) {
          osmf = fileRow[i];
          break;
        }
      }
      if (osmf == null) {
        osmf = _fileForSegment(lonDegree, latDegree);
        final newFileRow = <OsmFile>[
          for (var i = 0; i < ndegrees; i++) fileRow![i],
          osmf,
        ];
        _fileRows[latDegree] = newFileRow;
      }
      _currentFileName = osmf.filename;

      if (!osmf.hasData()) {
        return null;
      }

      var segment = osmf.getMicroCache(ilon, ilat);
      // needed for a second chance
      if (segment == null ||
          (waypointMatcher != null &&
              (waypointMatcher as WaypointMatcherImpl).useDynamicRange)) {
        _checkEnableCacheCleaning();
        segment = osmf.createMicroCache(
          ilon,
          ilat,
          _dataBuffers,
          _expCtxWay,
          waypointMatcher,
          _directWeaving ? nodesMap : null,
        );

        _cacheSum += segment.getDataSize();
      } else if (segment.ghost) {
        segment.unGhost();
        _ghostWakeup += segment.getDataSize();
      }
      return segment;
    } on IOException catch (re) {
      throw StateError(re.message);
    } on Error {
      rethrow; // RuntimeException
    } catch (e) {
      throw StateError('error reading datafile $_currentFileName: $e');
    }
  }

  /// make sure the given node is non-hollow,
  /// which means it contains not just the id,
  /// but also the actual data
  ///
  /// Returns true if successfull, false if node is still hollow
  bool obtainNonHollowNode(OsmNode node) {
    if (!node.isHollow()) return true;

    final segment = getSegmentFor(node.ilon, node.ilat);
    if (segment == null) {
      return false;
    }
    if (!node.isHollow()) {
      return true; // direct weaving...
    }

    final id = node.getIdFromPos();
    if (segment.getAndClear(id)) {
      node.parseNodeBody(segment, nodesMap, _expCtxWay);
    }

    if (_garbageCollectionEnabled) {
      // garbage collection
      _cacheSum -= segment.collect(
        segment.getSize() >> 1,
      ); // threshold = 1/2 of size is deleted
    }

    return !node.isHollow();
  }

  /// make sure all link targets of the given node are non-hollow
  void expandHollowLinkTargets(OsmNode n) {
    for (OsmLink? link = n.firstlink; link != null; link = link.getNext(n)) {
      obtainNonHollowNode(link.getTarget(n));
    }
  }

  /// make sure all link targets of the given node are non-hollow
  bool hasHollowLinkTargets(OsmNode n) {
    for (OsmLink? link = n.firstlink; link != null; link = link.getNext(n)) {
      if (link.getTarget(n).isHollow()) {
        return true;
      }
    }
    return false;
  }

  /// get a node for the given id with all link-targets also non-hollow
  ///
  /// It is required that an instance of the start-node does not yet
  /// exist, not even a hollow instance, so getStartNode should only
  /// be called once right after resetting the cache
  ///
  /// Returns the fully expanded node for id, or null if it was not found
  OsmNode? getStartNode(int id) {
    // initialize the start-node
    final n = OsmNode.fromId(id);
    n.setHollow();
    nodesMap.put(n);
    if (!obtainNonHollowNode(n)) {
      return null;
    }
    expandHollowLinkTargets(n);
    return n;
  }

  OsmNode getGraphNode(OsmNode template) {
    final graphNode = OsmNode(template.ilon, template.ilat);
    graphNode.setHollow();
    final existing = nodesMap.put(graphNode);
    if (existing == null) {
      return graphNode;
    }
    nodesMap.put(existing);
    return existing;
  }

  bool matchWaypointsToNodes(
    List<MatchedWaypoint> unmatchedWaypoints,
    double maxDistance,
    OsmNodePairSet islandNodePairs,
  ) {
    waypointMatcher = WaypointMatcherImpl(
      unmatchedWaypoints,
      maxDistance,
      islandNodePairs,
    );
    for (final mwp in unmatchedWaypoints) {
      var cellsize = 12500;
      _preloadPosition(mwp.waypoint!, cellsize, 1, false);
      // get a second chance
      if (mwp.crosspoint == null || mwp.radius > retryRange) {
        cellsize = 1000000 ~/ 32;
        _preloadPosition(
          mwp.waypoint!,
          cellsize,
          maxDistance < 0 ? _maxDynamicCatches : 2,
          maxDistance < 0,
        );
      }
    }

    if (firstFileAccessFailed) {
      throw ArgumentError('datafile $firstFileAccessName not found');
    }
    final len = unmatchedWaypoints.length;
    for (var i = 0; i < len; i++) {
      final mwp = unmatchedWaypoints[i];
      if (mwp.crosspoint == null) {
        if (unmatchedWaypoints.length > 1 &&
            i == unmatchedWaypoints.length - 1 &&
            unmatchedWaypoints[i - 1].wpttype ==
                MatchedWaypoint.waypointTypeDirect) {
          mwp.crosspoint = OsmNode(mwp.waypoint!.ilon, mwp.waypoint!.ilat);
          mwp.wpttype = MatchedWaypoint.waypointTypeDirect;
        } else {
          // do not break here throw new IllegalArgumentException(mwp.name + "-position not mapped in existing datafile");
          return false;
        }
      }
      if (unmatchedWaypoints.length > 1 &&
          i == unmatchedWaypoints.length - 1 &&
          unmatchedWaypoints[i - 1].wpttype ==
              MatchedWaypoint.waypointTypeDirect) {
        mwp.crosspoint = OsmNode(mwp.waypoint!.ilon, mwp.waypoint!.ilat);
        mwp.wpttype = MatchedWaypoint.waypointTypeDirect;
      }
    }
    return true;
  }

  void _preloadPosition(OsmNode n, int d, int maxscale, bool bUseDynamicRange) {
    firstFileAccessFailed = false;
    firstFileAccessName = null;
    loadSegmentFor(n.ilon, n.ilat);
    if (firstFileAccessFailed) {
      throw ArgumentError('datafile $firstFileAccessName not found');
    }
    var scale = 1;
    while (scale < maxscale) {
      for (var idxLat = -scale; idxLat <= scale; idxLat++) {
        for (var idxLon = -scale; idxLon <= scale; idxLon++) {
          if (idxLon != 0 || idxLat != 0) {
            loadSegmentFor(n.ilon + d * idxLon, n.ilat + d * idxLat);
          }
        }
      }
      if (bUseDynamicRange && waypointMatcher!.hasMatch(n.ilon, n.ilat)) break;
      scale++;
    }
  }

  OsmFile _fileForSegment(int lonDegree, int latDegree) {
    final lonMod5 = rem(lonDegree, 5);
    final latMod5 = rem(latDegree, 5);

    final lon = lonDegree - 180 - lonMod5;
    final slon = lon < 0 ? 'W${-lon}' : 'E$lon';
    final lat = latDegree - 90 - latMod5;

    final slat = lat < 0 ? 'S${-lat}' : 'N$lat';
    final filenameBase = '${slon}_$slat';

    _currentFileName = '$filenameBase.rd5';

    PhysicalFile? ra;
    if (!_fileCache.containsKey(filenameBase)) {
      File? f;
      if (!_forceSecondaryData) {
        final primary = File('${_segmentDir.path}/$filenameBase.rd5');
        if (primary.existsSync()) {
          f = primary;
        }
      }
      if (f == null) {
        final secondaryDir = _secondarySegmentsDir;
        if (secondaryDir != null) {
          final secondary = File('${secondaryDir.path}/$filenameBase.rd5');
          if (secondary.existsSync()) {
            f = secondary;
          }
        }
      }
      if (f != null) {
        _currentFileName = f.uri.pathSegments.last;
        ra = PhysicalFile(f, _dataBuffers, _lookupVersion, _lookupMinorVersion);
      }
      _fileCache[filenameBase] = ra;
    }
    ra = _fileCache[filenameBase];
    final osmf = OsmFile(ra, lonDegree, latDegree, _dataBuffers);

    if (firstFileAccessName == null) {
      firstFileAccessName = _currentFileName;
      firstFileAccessFailed = osmf.filename == null;
    }

    return osmf;
  }

  void close() {
    for (final f in _fileCache.values) {
      try {
        f?.ra?.closeSync();
      } catch (_) {
        // ignore
      }
    }
  }

  int getElevationType(int ilon, int ilat) {
    final lonDegree = ilon ~/ 1000000;
    final latDegree = ilat ~/ 1000000;
    final fileRow = _fileRows[latDegree];
    final ndegrees = fileRow == null ? 0 : fileRow.length;
    for (var i = 0; i < ndegrees; i++) {
      if (fileRow![i].lonDegree == lonDegree) {
        final osmf = fileRow[i];
        return osmf.elevationType;
      }
    }
    return 3;
  }
}

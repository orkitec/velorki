// Port of btools.router.SearchBoundary (BRouter v1.7.10).
//
// static helper class for handling datafiles

import '../mapaccess/osm_node.dart';

final class SearchBoundary {
  late final int _minlon0;
  late final int _minlat0;
  late final int _maxlon0;
  late final int _maxlat0;

  late final int _minlon;
  late final int _minlat;
  late final int _maxlon;
  late final int _maxlat;
  final int _radius;
  late final OsmNode _p;

  int direction;

  /// [radius]: search radius in meters.
  SearchBoundary(OsmNode n, int radius, this.direction) : _radius = radius {
    _p = OsmNode(n.ilon, n.ilat);

    final lon = (n.ilon ~/ 5000000) * 5000000;
    final lat = (n.ilat ~/ 5000000) * 5000000;

    _minlon0 = lon - 5000000;
    _minlat0 = lat - 5000000;
    _maxlon0 = lon + 10000000;
    _maxlat0 = lat + 10000000;

    _minlon = lon - 1000000;
    _minlat = lat - 1000000;
    _maxlon = lon + 6000000;
    _maxlat = lat + 6000000;
  }

  static String getFileName(OsmNode n) {
    final lon = (n.ilon ~/ 5000000) * 5000000;
    final lat = (n.ilat ~/ 5000000) * 5000000;

    final dlon = lon ~/ 1000000 - 180;
    final dlat = lat ~/ 1000000 - 90;

    final slon = dlon < 0 ? 'W${-dlon}' : 'E$dlon';
    final slat = dlat < 0 ? 'S${-dlat}' : 'N$dlat';
    return '${slon}_$slat.trf';
  }

  bool isInBoundary(OsmNode n, int cost) {
    if (_radius > 0) {
      return n.calcDistance(_p) < _radius;
    }
    if (cost == 0) {
      return n.ilon > _minlon0 &&
          n.ilon < _maxlon0 &&
          n.ilat > _minlat0 &&
          n.ilat < _maxlat0;
    }
    return n.ilon > _minlon &&
        n.ilon < _maxlon &&
        n.ilat > _minlat &&
        n.ilat < _maxlat;
  }

  int getBoundaryDistance(OsmNode n) {
    switch (direction) {
      case 0:
        return n.calcDistance(OsmNode(n.ilon, _minlat));
      case 1:
        return n.calcDistance(OsmNode(_minlon, n.ilat));
      case 2:
        return n.calcDistance(OsmNode(n.ilon, _maxlat));
      case 3:
        return n.calcDistance(OsmNode(_maxlon, n.ilat));
      default:
        throw ArgumentError('undefined direction: $direction');
    }
  }
}

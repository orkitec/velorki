// Port of btools.mapaccess.OsmPos (BRouter v1.7.10).

/// Interface for a position (OsmNode or OsmPath)
abstract class OsmPos {
  int getILat();

  int getILon();

  int getSElev();

  double getElev();

  int calcDistance(OsmPos p);

  int getIdFromPos();
}

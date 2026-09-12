// Port of btools.mapaccess.OsmLinkHolder (BRouter v1.7.10).

/// Container for routig configs
abstract class OsmLinkHolder {
  void setNextForLink(OsmLinkHolder? holder);

  OsmLinkHolder? getNextForLink();
}

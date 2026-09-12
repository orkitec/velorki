// Port of btools.mapaccess.TurnRestriction (BRouter v1.7.10).

/// Container for a turn restriction
class TurnRestriction {
  bool isPositive = false;
  int exceptions = 0;

  int fromLon = 0;
  int fromLat = 0;

  int toLon = 0;
  int toLat = 0;

  TurnRestriction? next;

  bool exceptBikes() {
    return (exceptions & 1) != 0;
  }

  bool exceptMotorcars() {
    return (exceptions & 2) != 0;
  }

  static bool isTurnForbidden(
    TurnRestriction? first,
    int fromLon,
    int fromLat,
    int toLon,
    int toLat,
    bool bikeMode,
    bool carMode,
  ) {
    var hasAnyPositive = false;
    var hasPositive = false;
    var hasNegative = false;
    var tr = first;
    while (tr != null) {
      if ((tr.exceptBikes() && bikeMode) || (tr.exceptMotorcars() && carMode)) {
        tr = tr.next;
        continue;
      }
      if (tr.fromLon == fromLon && tr.fromLat == fromLat) {
        if (tr.isPositive) {
          hasAnyPositive = true;
        }
        if (tr.toLon == toLon && tr.toLat == toLat) {
          if (tr.isPositive) {
            hasPositive = true;
          } else {
            hasNegative = true;
          }
        }
      }
      tr = tr.next;
    }
    return !hasPositive && (hasAnyPositive || hasNegative);
  }

  @override
  String toString() {
    return 'pos=$isPositive fromLon=$fromLon fromLat=$fromLat toLon=$toLon toLat=$toLat';
  }
}

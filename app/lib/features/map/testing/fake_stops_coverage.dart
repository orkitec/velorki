import 'package:flutter/foundation.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../application/map_stops_controller.dart';

/// A [StopsCoverage] a test sets: everywhere by default, or where [covered]
/// says; [changed] stands in for a download finishing.
class FakeStopsCoverage extends ChangeNotifier implements StopsCoverage {
  /// Creates coverage that answers with [covered], everywhere when `null`.
  FakeStopsCoverage({this.covered});

  /// Whether a point is covered; every point when `null`.
  bool Function(LatLng point)? covered;

  @override
  bool covers(LatLng point) => covered?.call(point) ?? true;

  /// Sets what is covered and tells the listeners, as the gazetteer store
  /// does after a re-scan.
  void changed(bool Function(LatLng point)? covered) {
    this.covered = covered;
    notifyListeners();
  }
}

/// Smart loops for Velorki: candidate strategies, a weighted scorer and the
/// planner that turns "a nice 60 km loop from here past the lake" into three
/// real routes.
///
/// Pure algorithm, no model. Pure Dart, no Flutter dependency.
library;

export 'src/close_loop.dart';
export 'src/loop_planner.dart';
export 'src/loop_request.dart';
export 'src/scorer.dart';
export 'src/strategies.dart';
export 'src/version.dart';

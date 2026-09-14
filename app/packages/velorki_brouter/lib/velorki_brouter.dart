/// BRouter routing for Velorki: the [RoutingBackend] interface, an HTTP
/// backend for a self-hosted BRouter server, an on-device backend running the
/// `brouter_dart` port, the [CompositeRoutingBackend] that picks between them,
/// and the parsers that turn BRouter's GeoJSON and `messages` table into typed
/// results and surface statistics.
///
/// Pure Dart, no Flutter dependency (the on-device backend needs `dart:io`).
library;

export 'src/brouter_http_backend.dart';
export 'src/brouter_query.dart';
export 'src/composite_routing_backend.dart';
export 'src/local_routing_backend.dart';
export 'src/route_query.dart';
export 'src/route_result.dart';
export 'src/routing_backend.dart';
export 'src/routing_exception.dart';
export 'src/segment_message.dart';
export 'src/segments_manifest.dart';
export 'src/surface_stats.dart';
export 'src/tiles.dart';
export 'src/turn_hint.dart';
export 'src/version.dart';

/// BRouter routing for Velorki: the [RoutingBackend] interface, an HTTP
/// backend for a self-hosted BRouter server, and the parsers that turn its
/// GeoJSON and `messages` table into typed results and surface statistics.
///
/// Pure Dart, no Flutter dependency.
library;

export 'src/brouter_http_backend.dart';
export 'src/route_query.dart';
export 'src/route_result.dart';
export 'src/routing_backend.dart';
export 'src/routing_exception.dart';
export 'src/segment_message.dart';
export 'src/surface_stats.dart';
export 'src/version.dart';

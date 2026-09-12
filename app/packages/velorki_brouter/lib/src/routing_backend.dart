import 'route_query.dart';
import 'route_result.dart';
import 'routing_exception.dart';

/// Anything that can turn a [RouteQuery] into a [RouteResult].
///
/// The app talks only to this interface, so the HTTP backend, the future
/// on-device `brouter_dart` engine and the fakes in the tests are
/// interchangeable.
abstract class RoutingBackend {
  /// Computes a route.
  ///
  /// Throws [RoutingException] on every failure, including cancellation
  /// through [cancel].
  Future<RouteResult> route(RouteQuery q, {CancelToken? cancel});
}

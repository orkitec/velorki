// Port of btools.router.RoutingIslandException (BRouter v1.7.10).

/// Thrown by the search when too few nodes were visited (an island); the
/// caller freezes the temporary node pairs and retries. A `RuntimeException`
/// upstream, an `Error` here like the other runtime exceptions of the port.
class RoutingIslandException extends Error {}

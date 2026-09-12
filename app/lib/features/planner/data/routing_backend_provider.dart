import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

import '../../../app/app_config.dart';

part 'routing_backend_provider.g.dart';

/// The routing backend the planner talks to, or `null` when no BRouter URL is
/// configured.
///
/// `null` is a normal state, not an error: a fork can ship without a routing
/// server, and the planner then tells the user to set one in
/// Settings → Advanced. Override this provider in tests with a fake backend.
@Riverpod(keepAlive: true)
RoutingBackend? routingBackend(Ref ref) {
  final url = ref.watch(effectiveConfigProvider).brouterUrl;
  if (url.isEmpty) return null;
  final backend = BRouterHttpBackend(url);
  ref.onDispose(backend.close);
  return backend;
}

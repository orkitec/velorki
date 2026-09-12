import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:velorki_gpx/velorki_gpx.dart';

import '../../planner/domain/saved_route.dart';
import '../common/domain/integration_exception.dart';
import '../rwgps/data/rwgps_client.dart';
import '../rwgps/data/rwgps_providers.dart';
import '../rwgps/domain/rwgps_models.dart';

/// The GPX `<rte>` of [route], which is what a planned route exports as.
Uint8List routeGpxBytes(SavedRoute route, {String creator = 'Velorki'}) =>
    Uint8List.fromList(
      utf8.encode(
        GpxCodec.encodeRoute(
          points: route.geometry,
          name: route.name,
          creator: creator,
        ),
      ),
    );

/// Where a route ended up after it was sent.
class SentRoute {
  /// Creates a result.
  const SentRoute({required this.id, required this.url});

  /// The service's id for the created route.
  final String id;

  /// The page the rider can open.
  final String url;
}

/// Sends a saved route to a partner service.
///
/// Only Ride with GPS can receive one. **Strava's API can read routes but
/// cannot create them**, so there is no `sendToStrava` here: the route detail
/// screen exports a GPX and hands it to the share sheet instead, and says so.
class RouteSender {
  /// Creates a sender.
  RouteSender({required this.rwgps});

  /// The Ride with GPS client.
  final RwgpsClient rwgps;

  /// Uploads [route] to Ride with GPS as a route.
  Future<SentRoute> sendToRwgps(SavedRoute route) async {
    final points = route.geometry;
    if (points.isEmpty) {
      throw const IntegrationException(
        IntegrationFailure.rejected,
        'There is nothing to send: this route has no geometry.',
      );
    }
    final task = await rwgps.uploadRouteAndWait(
      gpxBytes: routeGpxBytes(route),
      name: route.name,
      description: route.description,
    );
    final item = task.firstItem;
    if (item == null) {
      throw IntegrationException(
        IntegrationFailure.rejected,
        task.errors.isEmpty
            ? 'Ride with GPS created nothing from the upload.'
            : 'Ride with GPS could not import the route: '
                  '${task.errors.map((e) => e.display).join('; ')}',
      );
    }
    return SentRoute(
      id: item.itemId,
      url: item.webUrl ?? rwgpsRouteUrl(item.itemId),
    );
  }
}

/// The sender over the app's clients.
final routeSenderProvider = Provider<RouteSender>(
  (ref) => RouteSender(rwgps: ref.watch(rwgpsClientProvider)),
);

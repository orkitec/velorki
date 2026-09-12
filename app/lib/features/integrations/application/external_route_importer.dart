import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/database.dart' show RouteSource;
import '../../import_export/data/import_repository.dart';
import '../../import_export/data/track_decoder.dart';
import '../../import_export/domain/imported_track.dart';
import '../../planner/domain/saved_route.dart';
import '../common/domain/connected_account.dart';
import '../common/domain/integration_exception.dart';

/// Turns a GPX downloaded from a partner service into a saved route.
///
/// The very same decoder a file import uses, so a Strava route and a Komoot
/// file take the same path into the library; only the `source` and the
/// external ids differ, and those are what the Strava rules key off.
class ExternalRouteImporter {
  /// Creates an importer over [_imports].
  ExternalRouteImporter(this._imports, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final ImportRepository _imports;
  final DateTime Function() _clock;

  /// The `routes.source` a route from [service] gets.
  static RouteSource sourceFor(IntegrationService service) => switch (service) {
    IntegrationService.strava => RouteSource.strava,
    IntegrationService.rwgps => RouteSource.rwgps,
  };

  /// The key the service's own route id is stored under in `external_ids`.
  static String externalIdKeyFor(IntegrationService service) =>
      '${service.id}_route_id';

  /// Decodes [gpx] and saves it as a route from [service].
  ///
  /// Throws [IntegrationException] when the file cannot be decoded: that is a
  /// problem with the service's export, not with anything the rider did.
  Future<SavedRoute> importRoute({
    required IntegrationService service,
    required Uint8List gpx,
    required String externalId,
    required String name,
  }) async {
    final track = _decode(service, gpx, name);
    return _imports.saveAsRoute(
      name: name,
      track: track,
      source: sourceFor(service),
      externalIds: <String, Object?>{externalIdKeyFor(service): externalId},
      externalFetchedAt: _clock(),
    );
  }

  ImportedTrack _decode(
    IntegrationService service,
    Uint8List gpx,
    String name,
  ) {
    try {
      return decodeTrack(gpx, fileName: '$name.gpx');
    } on ImportException catch (e) {
      throw IntegrationException(
        IntegrationFailure.serviceError,
        'The GPX ${service.id} returned could not be read '
        '(${e.failure.name}).',
        cause: e,
      );
    }
  }
}

/// The importer over the app database.
final externalRouteImporterProvider = Provider<ExternalRouteImporter>(
  (ref) => ExternalRouteImporter(ref.watch(importRepositoryProvider)),
);

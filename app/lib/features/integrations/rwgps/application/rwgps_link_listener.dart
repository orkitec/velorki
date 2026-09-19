import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:velorki_gpx/velorki_gpx.dart';

import '../../../import_export/data/incoming_file_service.dart';
import '../../../import_export/data/track_decoder.dart';
import '../../../sharing/data/share_service.dart';
import '../../common/data/connected_accounts_repository.dart';
import '../../common/domain/connected_account.dart';
import '../data/rwgps_providers.dart';

final Logger _log = Logger('RwgpsLinks');

/// The hosts a Ride with GPS route link comes with.
const Set<String> rwgpsLinkHosts = <String>{
  'ridewithgps.com',
  'www.ridewithgps.com',
};

final RegExp _routeIdPattern = RegExp(r'^\d{1,12}$');

/// The route id in a `https://ridewithgps.com/routes/<id>` link, with or
/// without `.gpx` and whatever follows, or `null` for any other link.
///
/// Only a plain number is taken: the id goes into a URL the app then fetches.
String? rwgpsRouteIdOf(Uri uri) {
  if (uri.scheme != 'https' || !rwgpsLinkHosts.contains(uri.host)) return null;
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.length < 2 || segments.first != 'routes') return null;
  var id = segments[1];
  if (id.endsWith('.gpx')) id = id.substring(0, id.length - '.gpx'.length);
  return _routeIdPattern.hasMatch(id) ? id : null;
}

/// The public GPX export of route [id]: a track at full resolution, which
/// Ride with GPS serves without a login for a public route and answers with
/// 401 for a private one.
Uri rwgpsPublicGpxUrl(String id) =>
    Uri.parse('https://ridewithgps.com/routes/$id.gpx?sub_format=track');

/// Fetches the GPX of route [id] through the connected account's API token.
/// Overridable, so the listener can be tested without a Ride with GPS.
final rwgpsRouteGpxProvider = Provider<Future<Uint8List> Function(String id)>(
  (ref) =>
      (id) => ref.read(rwgpsClientProvider).routeGpx(id),
);

/// Opens the Ride with GPS route [id] in the import preview.
///
/// The public export is tried first, because it needs nothing. A private
/// route answers with an error or with the login page, and then the connected
/// account fetches it through the API; without an account the import screen
/// says what is missing. Ride with GPS is what the rider tapped, so failing
/// silently is not an option here either.
Future<void> openRwgpsLink(ProviderContainer container, String id) async {
  final service = container.read(incomingFileServiceProvider);
  final label = 'ridewithgps.com/routes/$id';
  Uint8List? bytes;
  try {
    final fetched = await container.read(shareGpxFetcherProvider)(
      rwgpsPublicGpxUrl(id),
    );
    if (looksLikeGpx(fetched)) bytes = fetched;
  } on Object catch (e) {
    _log.info('the public export of route $id was refused: $e');
  }
  if (bytes == null) {
    final account = container.read(
      connectedAccountProvider(IntegrationService.rwgps),
    );
    if (account == null) {
      service.reject(
        ImportException(ImportFailure.accountNeeded, fileName: label),
      );
      return;
    }
    try {
      bytes = await container.read(rwgpsRouteGpxProvider)(id);
    } on Object catch (e, st) {
      _log.warning('route $id could not be fetched with the account', e, st);
      service.reject(
        ImportException(ImportFailure.linkUnreachable, fileName: label),
      );
      return;
    }
  }
  await service.addBytes(
    bytes,
    fileName: 'ridewithgps-$id.gpx',
    sourceHint: 'rwgps-link',
  );
}

/// Watches the deep-link stream for Ride with GPS route links and opens what
/// it finds. Called once from `bootstrap()`, next to the share-link listener.
void listenForRwgpsLinks(ProviderContainer container) {
  container.listen<AsyncValue<Uri>>(incomingDeepLinksProvider, (
    previous,
    next,
  ) {
    final uri = next.value;
    if (uri == null || uri == previous?.value) return;
    final id = rwgpsRouteIdOf(uri);
    if (id == null) return;
    _log.info('opening Ride with GPS route $id');
    unawaited(openRwgpsLink(container, id));
  }, fireImmediately: true);
}

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../../app/app_config.dart';
import '../../import_export/data/incoming_file_service.dart';
import '../data/share_service.dart';

final Logger _log = Logger('ShareLinks');

/// The host of a share deep link: `velorki://share/<id>`.
const String shareLinkHost = 'share';

/// The host the public share pages live on: `https://velorki.com/s/<id>`.
///
/// Only the bare host counts. `www.velorki.com` redirects to it, and the
/// App Links and Universal Links files are served for `velorki.com` alone, so
/// no other host can hand us a share id.
const String shareLinkWebHost = 'velorki.com';

/// What a share id looks like: ten base62 characters, as the relay mints them.
///
/// The id is interpolated into the URL the app then fetches, so it is checked
/// here and not only on the server: without this, any page could send
/// `velorki://share/..%2F..%2Fadmin` and make the app request a path of the
/// sender's choosing on the relay host.
final RegExp _shareIdPattern = RegExp(r'^[A-Za-z0-9]{10}$');

/// The share id in [uri], or `null` when it is not a share link.
///
/// Two shapes are accepted: the custom scheme the share page links to
/// (`velorki://share/7Kq2mZ0aTb`) and the public page's own URL
/// (`https://velorki.com/s/7Kq2mZ0aTb`, with or without `.gpx`), so a
/// universal link lands in the same place as the scheme.
String? shareIdOf(Uri uri) {
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  final String? raw;
  if (uri.host == shareLinkHost) {
    raw = segments.isEmpty ? null : segments.first;
  } else if (uri.host == shareLinkWebHost &&
      segments.length >= 2 &&
      segments.first == 's') {
    raw = segments[1];
  } else {
    raw = null;
  }
  if (raw == null || raw.isEmpty) return null;
  final id = raw.endsWith('.gpx')
      ? raw.substring(0, raw.length - '.gpx'.length)
      : raw;
  return _shareIdPattern.hasMatch(id) ? id : null;
}

/// Fetches the GPX behind share [id] and sends it into the import preview.
///
/// Nothing about a shared route is special once it is on the phone: it is a
/// GPX like any other, so it goes through the same preview and the same
/// decoder as a file opened from Files.
Future<void> openShareLink(ProviderContainer container, String id) async {
  final url = shareGpxUrl(container.read(effectiveConfigProvider).apiUrl, id);
  if (url == null) {
    _log.warning('no relay configured, cannot open the share link $id');
    return;
  }
  try {
    final bytes = await container.read(shareGpxFetcherProvider)(url);
    await container
        .read(incomingFileServiceProvider)
        .addBytes(bytes, fileName: '$id.gpx', sourceHint: 'share-link');
  } on Object catch (e, st) {
    // A link that is expired, mistyped or unreachable must not crash the app
    // it was opened with.
    _log.warning('the shared route $id could not be opened', e, st);
  }
}

/// Watches the deep-link stream for `velorki://share/<id>` and opens what it
/// finds.
///
/// Called once from `bootstrap()`, next to the import listener, so a cold
/// start through a share link is not lost.
void listenForShareLinks(ProviderContainer container) {
  container.listen<AsyncValue<Uri>>(incomingDeepLinksProvider, (
    previous,
    next,
  ) {
    final uri = next.value;
    if (uri == null || uri == previous?.value) return;
    final id = shareIdOf(uri);
    if (id == null) return;
    _log.info('opening the shared route $id');
    unawaited(openShareLink(container, id));
  }, fireImmediately: true);
}

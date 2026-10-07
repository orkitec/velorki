import 'dart:async';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';

import 'location_link.dart';

final Logger _log = Logger('ShortLinkResolver');

/// How long following a short link may take before the phone is taken to be
/// offline and the link left as it is.
const Duration shortLinkTimeout = Duration(seconds: 4);

/// How many redirects a short link is followed through.
const int _maxHops = 4;

/// [link] with the place its short link points to, when the phone is online
/// and the service answers; [link] itself otherwise.
///
/// A `maps.app.goo.gl`, `maps.apple/p/` or `osm.org/go/` link says nothing
/// by itself: the service answers it with a redirect to the full link, which
/// holds the place. One request per hop, no body read, the redirect target
/// read with [parseLocationLink]. Google may send its consent page first;
/// the real link is in its `continue` parameter. Whatever the text around
/// the short link said stays as the place's name.
Future<LocationLink> resolveShortLink(LocationLink link, Dio dio) async {
  var target = link.shortLink;
  if (link.position != null || target == null) return link;
  try {
    for (var hop = 0; hop < _maxHops && target != null; hop++) {
      final response = await dio
          .getUri<void>(
            target,
            options: Options(
              followRedirects: false,
              validateStatus: (_) => true,
              receiveTimeout: shortLinkTimeout,
              sendTimeout: shortLinkTimeout,
            ),
          )
          .timeout(shortLinkTimeout);
      final location = response.headers.value('location');
      if (location == null) break;
      var next = target.resolve(location);
      final onward = next.queryParameters['continue'];
      if (onward != null && next.host.startsWith('consent.')) {
        next = Uri.parse(onward);
      }
      final found = parseLocationLink(next.toString());
      final position = found?.position;
      if (position != null) {
        return LocationLink(
          source: found!.source,
          position: position,
          name: found.name ?? link.query,
        );
      }
      if (found != null && found.query != null) {
        return LocationLink(source: found.source, query: found.query);
      }
      target = next;
    }
  } on Object catch (error) {
    _log.info('short link not followed: $error');
  }
  return link;
}

import 'package:dio/dio.dart';

import '../../../core/http/user_agent.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:share_plus/share_plus.dart';
import 'package:velorki_api/velorki_api.dart';
import 'package:velorki_geo/velorki_geo.dart';
import 'package:velorki_gpx/velorki_gpx.dart';

import '../../integrations/common/data/relay_client_provider.dart';
import '../../planner/domain/route_poi.dart';

final Logger _log = Logger('ShareService');

/// A share link that could not be created.
class ShareException implements Exception {
  /// Creates the exception.
  const ShareException(this.message, {this.cause});

  /// What to tell the rider.
  final String message;

  /// The underlying error, for the log.
  final Object? cause;

  @override
  String toString() => 'ShareException: $message';
}

/// Turns a route or a ride into a link anyone can open.
///
/// This is the one feature that leaves data on our server: the GPX and a few
/// numbers, under a random id, for a year. Nothing identifies the rider — the
/// relay stores no app user id with the row — so the link itself is the only
/// key, and sharing it is the whole point.
class ShareService {
  /// Creates the service over [relay].
  const ShareService(this._relay);

  final RelayClient _relay;

  /// Stores [points] as a GPX and returns its public link.
  ///
  /// [kind] decides both the GPX shape and what the share page calls it: a
  /// route becomes a `<rte>`, a recorded ride a `<trk>` with its timestamps.
  Future<ShareLink> share({
    required String name,
    required List<TrackPoint> points,
    required ShareKind kind,
    required double distanceM,
    double? ascentM,
    Duration? duration,
    List<RoutePoi> pois = const <RoutePoi>[],
  }) async {
    if (points.isEmpty) {
      throw const ShareException('There is nothing to share.');
    }
    final gpx = kind == ShareKind.ride
        ? GpxCodec.encodeTrack(points: points, name: name)
        : GpxCodec.encodeRoute(
            points: points,
            name: name,
            waypoints: gpxWaypoints(pois),
          );
    try {
      return await _relay.createShare(
        name: name,
        gpx: gpx,
        kind: kind,
        summary: ShareSummary(
          distanceKm: distanceM / 1000,
          ascentM: ascentM,
          durationS: duration?.inSeconds,
        ),
      );
    } on RelayException catch (e) {
      throw ShareException(e.error.message, cause: e);
    }
  }
}

/// The share service, or `null` when this build has no relay.
final shareServiceProvider = Provider<ShareService?>((ref) {
  final relay = ref.watch(relayClientProvider);
  return relay == null ? null : ShareService(relay);
});

/// Fetches the GPX behind a share link.
typedef ShareGpxFetcher = Future<Uint8List> Function(Uri url);

/// Downloads the GPX of a share link, straight from the relay's public
/// endpoint: `GET /s/<id>.gpx` needs no authentication, which is what makes a
/// shared link openable by anyone.
final shareGpxFetcherProvider = Provider<ShareGpxFetcher>((ref) {
  final dio = velorkiDio();
  ref.onDispose(dio.close);
  return (url) async {
    final response = await dio.getUri<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    final data = response.data;
    if (data == null || data.isEmpty) {
      throw const ShareException('The shared file was empty.');
    }
    return Uint8List.fromList(data);
  };
});

/// The URL of the GPX behind the share [id], or `null` without a relay.
Uri? shareGpxUrl(String apiUrl, String id) {
  if (apiUrl.isEmpty || id.isEmpty) return null;
  final base = apiUrl.endsWith('/')
      ? apiUrl.substring(0, apiUrl.length - 1)
      : apiUrl;
  return Uri.tryParse('$base/s/$id.gpx');
}

/// Hands plain text to the system share sheet.
typedef TextSharer = Future<void> Function(String text, {String? subject});

/// Shares [text] through `share_plus`.
Future<void> shareTextWithSharePlus(String text, {String? subject}) async {
  await SharePlus.instance.share(ShareParams(text: text, subject: subject));
}

/// The text share sheet. Overridden in widget tests so no plugin is touched.
final textSharerProvider = Provider<TextSharer>(
  (ref) => shareTextWithSharePlus,
);

/// Puts [text] on the clipboard.
typedef ClipboardWriter = Future<void> Function(String text);

/// The clipboard. Overridden in widget tests.
final clipboardWriterProvider = Provider<ClipboardWriter>(
  (ref) => (text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } on Object catch (e) {
      _log.warning('could not write to the clipboard', e);
    }
  },
);

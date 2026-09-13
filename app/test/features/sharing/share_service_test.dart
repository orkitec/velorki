import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/integrations/common/data/relay_client_provider.dart';
import 'package:velorki/features/sharing/data/share_service.dart';
import 'package:velorki_api/velorki_api.dart';
import 'package:velorki_geo/velorki_geo.dart';
import 'package:velorki_gpx/velorki_gpx.dart';

/// One `POST /share` as it reached the relay.
class _ShareCall {
  _ShareCall({
    required this.name,
    required this.gpx,
    required this.summary,
    required this.kind,
  });

  final String name;
  final String gpx;
  final ShareSummary summary;
  final ShareKind kind;
}

/// A relay that records the share it was asked for instead of sending one.
class _FakeRelay extends RelayClient {
  _FakeRelay({this.link, this.failure}) : super('https://relay.test');

  /// What [createShare] answers.
  final ShareLink? link;

  /// Thrown instead of answering, when set.
  final RelayException? failure;

  /// Every share that was asked for, in order.
  final List<_ShareCall> calls = <_ShareCall>[];

  @override
  Future<ShareLink> createShare({
    required String name,
    required String gpx,
    required ShareSummary summary,
    ShareKind kind = ShareKind.route,
  }) async {
    if (failure != null) throw failure!;
    calls.add(_ShareCall(name: name, gpx: gpx, summary: summary, kind: kind));
    return link ?? const ShareLink(id: 'abc', url: 'https://velorki.app/s/abc');
  }
}

/// A ride: three fixes with timestamps and elevations.
final List<TrackPoint> _ride = <TrackPoint>[
  TrackPoint(
    const LatLng(48.1, 11.5),
    ele: 500,
    time: DateTime.utc(2026, 9, 12, 8),
  ),
  TrackPoint(
    const LatLng(48.2, 11.6),
    ele: 520,
    time: DateTime.utc(2026, 9, 12, 8, 30),
  ),
  TrackPoint(
    const LatLng(48.3, 11.7),
    ele: 480,
    time: DateTime.utc(2026, 9, 12, 9),
  ),
];

/// The same shape without timestamps, i.e. a planned route.
const List<TrackPoint> _route = <TrackPoint>[
  TrackPoint(LatLng(48.1, 11.5), ele: 500),
  TrackPoint(LatLng(48.2, 11.6), ele: 520),
];

/// A container with the relay overridden to [relay].
ProviderContainer _containerWith(RelayClient? relay) {
  final container = ProviderContainer(
    overrides: [relayClientProvider.overrideWithValue(relay)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a share that could not be created', () {
    test('reads as a sentence and keeps the cause for the log', () {
      const cause = FormatException('the relay said nothing');
      const failure = ShareException(
        'The share could not be made.',
        cause: cause,
      );

      expect(
        failure.toString(),
        'ShareException: The share could not be made.',
      );
      expect(failure.message, 'The share could not be made.');
      expect(failure.cause, same(cause));
    });

    test('a failure without a cause still reads as a sentence', () {
      expect(const ShareException('There is nothing to share.').cause, isNull);
    });
  });

  group('sharing a route', () {
    test('the GPX holds the route, its name and its points', () async {
      final relay = _FakeRelay();

      await ShareService(relay).share(
        name: 'Isar loop',
        points: _route,
        kind: ShareKind.route,
        distanceM: 42000,
        ascentM: 380,
      );

      final document = GpxCodec.decode(relay.calls.single.gpx);
      expect(document.routes, hasLength(1));
      expect(document.tracks, isEmpty);
      expect(document.routes.single.name, 'Isar loop');
      expect(document.name, 'Isar loop');
      expect(document.routes.single.points, hasLength(2));
      expect(document.routes.single.points.first.lat, 48.1);
      expect(document.routes.single.points.first.ele, 500);
    });

    test('the link the relay made is what the rider gets', () async {
      final relay = _FakeRelay(
        link: const ShareLink(
          id: '7Kq2mZ0aTb',
          url: 'https://velorki.app/s/7Kq2mZ0aTb',
          expiresAt: 1789214400,
        ),
      );

      final link = await ShareService(relay).share(
        name: 'Isar loop',
        points: _route,
        kind: ShareKind.route,
        distanceM: 42000,
      );

      expect(link.id, '7Kq2mZ0aTb');
      expect(link.url, 'https://velorki.app/s/7Kq2mZ0aTb');
      expect(link.gpxUrl, 'https://velorki.app/s/7Kq2mZ0aTb.gpx');
      expect(link.expiresAtUtc, DateTime.utc(2026, 9, 12, 12));
    });

    test(
      'a route is shared as a route even when its points have times',
      () async {
        final relay = _FakeRelay();

        await ShareService(relay).share(
          name: 'Isar loop',
          points: _ride,
          kind: ShareKind.route,
          distanceM: 42000,
        );

        expect(relay.calls.single.kind, ShareKind.route);
        expect(GpxCodec.decode(relay.calls.single.gpx).tracks, isEmpty);
      },
    );
  });

  group('sharing a ride', () {
    test(
      'the GPX holds a track with the timestamps that were recorded',
      () async {
        final relay = _FakeRelay();

        await ShareService(relay).share(
          name: 'Saturday',
          points: _ride,
          kind: ShareKind.ride,
          distanceM: 30000,
          duration: const Duration(minutes: 95),
        );

        final document = GpxCodec.decode(relay.calls.single.gpx);
        expect(document.routes, isEmpty);
        expect(document.tracks, hasLength(1));
        expect(document.tracks.single.name, 'Saturday');
        final points = document.tracks.single.segments.single;
        expect(points, hasLength(3));
        expect(points.first.time, DateTime.utc(2026, 9, 12, 8));
        expect(points.last.time, DateTime.utc(2026, 9, 12, 9));
      },
    );
  });

  group('the numbers stored beside the GPX', () {
    test('the distance is sent in kilometres, not metres', () async {
      final relay = _FakeRelay();

      await ShareService(relay).share(
        name: 'Isar loop',
        points: _route,
        kind: ShareKind.route,
        distanceM: 1234,
      );

      expect(relay.calls.single.summary.distanceKm, 1.234);
    });

    test(
      'climbing and duration are left out when they are not known',
      () async {
        final relay = _FakeRelay();

        await ShareService(relay).share(
          name: 'Isar loop',
          points: _route,
          kind: ShareKind.route,
          distanceM: 42000,
        );

        final summary = relay.calls.single.summary;
        expect(summary.ascentM, isNull);
        expect(summary.durationS, isNull);
        expect(summary.toJson().keys, <String>['distance_km']);
      },
    );

    test('a duration is sent in whole seconds', () async {
      final relay = _FakeRelay();

      await ShareService(relay).share(
        name: 'Saturday',
        points: _ride,
        kind: ShareKind.ride,
        distanceM: 30000,
        ascentM: 0,
        duration: const Duration(hours: 1, minutes: 35, milliseconds: 600),
      );

      expect(relay.calls.single.summary.durationS, 5700);
      expect(relay.calls.single.summary.ascentM, 0);
    });
  });

  group('a share that cannot be made', () {
    test('a single point is enough, an empty track is not', () async {
      final relay = _FakeRelay();
      final service = ShareService(relay);

      await service.share(
        name: 'here',
        points: const <TrackPoint>[TrackPoint(LatLng(48, 11))],
        kind: ShareKind.route,
        distanceM: 0,
      );
      expect(relay.calls, hasLength(1));

      await expectLater(
        service.share(
          name: 'nothing',
          points: const <TrackPoint>[],
          kind: ShareKind.ride,
          distanceM: 0,
        ),
        throwsA(
          isA<ShareException>().having(
            (e) => e.message,
            'message',
            'There is nothing to share.',
          ),
        ),
      );
      expect(relay.calls, hasLength(1));
    });

    test('what the relay said is what the rider is told', () async {
      final failure = const RelayException(
        RelayError(
          code: RelayErrorCode.unavailable,
          message: 'the server is down',
        ),
        statusCode: 503,
      );
      final relay = _FakeRelay(failure: failure);

      await expectLater(
        ShareService(relay).share(
          name: 'Isar loop',
          points: _route,
          kind: ShareKind.route,
          distanceM: 42000,
        ),
        throwsA(
          isA<ShareException>()
              .having((e) => e.message, 'message', 'the server is down')
              .having((e) => e.cause, 'cause', same(failure)),
        ),
      );
    });
  });

  group('the share service of a build', () {
    test('a build with a relay has one', () {
      final relay = _FakeRelay();
      final container = _containerWith(relay);

      expect(container.read(shareServiceProvider), isNotNull);
    });

    test('a build without a relay has none, which is not an error', () {
      final container = _containerWith(null);

      expect(container.read(shareServiceProvider), isNull);
    });
  });

  group('the GPX behind a share id', () {
    test('there is no URL without a relay or without an id', () {
      expect(shareGpxUrl('', 'abc'), isNull);
      expect(shareGpxUrl('https://relay.test', ''), isNull);
      expect(shareGpxUrl('', ''), isNull);
    });

    test('the id is appended to the relay, trailing slash or not', () {
      expect(
        shareGpxUrl('https://relay.test', '7Kq2mZ0aTb')?.toString(),
        'https://relay.test/s/7Kq2mZ0aTb.gpx',
      );
      expect(
        shareGpxUrl('https://relay.test/', '7Kq2mZ0aTb')?.toString(),
        'https://relay.test/s/7Kq2mZ0aTb.gpx',
      );
    });

    test('a relay behind a path prefix keeps the prefix', () {
      expect(
        shareGpxUrl('https://example.test/velorki', 'abc')?.toString(),
        'https://example.test/velorki/s/abc.gpx',
      );
    });
  });

  group('downloading the GPX behind a link', () {
    late _FakeHttpOverrides overrides;
    late HttpOverrides? previous;

    void serve(_FakeHttpResponse Function(Uri url) respond) {
      previous = HttpOverrides.current;
      overrides = _FakeHttpOverrides(respond);
      HttpOverrides.global = overrides;
      addTearDown(() => HttpOverrides.global = previous);
    }

    ShareGpxFetcher fetcher() {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      return container.read(shareGpxFetcherProvider);
    }

    test('the bytes of the file are handed back as they arrived', () async {
      final gpx = utf8.encode('<gpx version="1.1"/>');
      serve((_) => _FakeHttpResponse(gpx));

      final bytes = await fetcher()(Uri.parse('https://relay.test/s/abc.gpx'));

      expect(bytes, gpx);
      expect(
        overrides.requested.single.toString(),
        'https://relay.test/s/abc.gpx',
      );
    });

    test('an empty answer is reported rather than imported', () async {
      serve((_) => _FakeHttpResponse(const <int>[]));

      await expectLater(
        fetcher()(Uri.parse('https://relay.test/s/abc.gpx')),
        throwsA(
          isA<ShareException>().having(
            (e) => e.message,
            'message',
            'The shared file was empty.',
          ),
        ),
      );
    });

    test('a share that is gone is not swallowed', () async {
      serve((_) => _FakeHttpResponse(const <int>[], statusCode: 404));

      await expectLater(
        fetcher()(Uri.parse('https://relay.test/s/gone.gpx')),
        throwsA(anything),
      );
    });
  });

  group('handing a link to the system', () {
    test('the share sheet is the share_plus one unless a test replaces it', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(textSharerProvider), same(shareTextWithSharePlus));
    });

    test('the clipboard writer puts the link on the clipboard', () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(clipboardWriterProvider)(
        'https://velorki.app/s/abc',
      );

      final call = calls.singleWhere((c) => c.method == 'Clipboard.setData');
      expect(
        (call.arguments as Map<Object?, Object?>)['text'],
        'https://velorki.app/s/abc',
      );
    });

    test(
      'a clipboard that refuses is logged, not thrown at the rider',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              SystemChannels.platform,
              (call) async => throw PlatformException(code: 'no clipboard'),
            );
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null),
        );
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await expectLater(
          container.read(clipboardWriterProvider)('https://velorki.app/s/abc'),
          completes,
        );
      },
    );
  });

  group('the relay of a build', () {
    test('an empty API URL is a build without link sharing at all', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appConfigProvider.overrideWithValue(const AppConfig()),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(relayClientProvider), isNull);
      expect(container.read(shareServiceProvider), isNull);
    });
  });
}

/// Serves canned HTTP answers to the `dart:io` client dio builds itself.
class _FakeHttpOverrides extends HttpOverrides {
  _FakeHttpOverrides(this.respond);

  /// Answers one request.
  final _FakeHttpResponse Function(Uri url) respond;

  /// Every URL that was asked for, in order.
  final List<Uri> requested = <Uri>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _FakeHttpClient(respond, requested);
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this._respond, this._requested);

  final _FakeHttpResponse Function(Uri url) _respond;
  final List<Uri> _requested;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    _requested.add(url);
    return _FakeHttpClientRequest(method, url, _respond(url));
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpClientRequest implements HttpClientRequest {
  _FakeHttpClientRequest(this.method, this.uri, this._response);

  final _FakeHttpResponse _response;

  @override
  final String method;

  @override
  final Uri uri;

  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => _response;

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();

  @override
  Future<HttpClientResponse> get done async => _response;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpResponse extends StreamView<List<int>>
    implements HttpClientResponse {
  _FakeHttpResponse(List<int> bytes, {this.statusCode = 200})
    : contentLength = bytes.length,
      super(
        Stream<List<int>>.fromIterable(<List<int>>[Uint8List.fromList(bytes)]),
      );

  @override
  final int statusCode;

  @override
  final int contentLength;

  @override
  String get reasonPhrase => statusCode == 200 ? 'OK' : 'Not Found';

  @override
  bool get isRedirect => false;

  @override
  bool get persistentConnection => false;

  @override
  List<RedirectInfo> get redirects => const <RedirectInfo>[];

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpHeaders implements HttpHeaders {
  final Map<String, List<String>> _values = <String, List<String>>{};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      _values[name.toLowerCase()] = <String>['$value'];

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) =>
      _values.putIfAbsent(name.toLowerCase(), () => <String>[]).add('$value');

  @override
  void removeAll(String name) => _values.remove(name.toLowerCase());

  @override
  List<String>? operator [](String name) => _values[name.toLowerCase()];

  @override
  String? value(String name) => _values[name.toLowerCase()]?.first;

  @override
  void forEach(void Function(String name, List<String> values) action) =>
      _values.forEach(action);

  @override
  int contentLength = -1;

  @override
  bool chunkedTransferEncoding = false;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

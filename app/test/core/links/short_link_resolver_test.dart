import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/links/location_link.dart';
import 'package:velorki/core/links/short_link_resolver.dart';

/// Answers each request with the next of [hops]: a status and a location.
class _Redirects implements HttpClientAdapter {
  _Redirects(this.hops);

  final List<(int, String?)> hops;
  final List<Uri> requests = <Uri>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options.uri);
    final (status, location) = hops[requests.length - 1];
    return ResponseBody.fromString(
      '',
      status,
      headers: <String, List<String>>{
        if (location != null) 'location': <String>[location],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio _dio(HttpClientAdapter adapter) => Dio()..httpClientAdapter = adapter;

void main() {
  const google = 'https://maps.app.goo.gl/e36HiaDGvDjRm9Cy6?g_st=ic';

  test('a Google short link is followed to its place', () async {
    final redirects = _Redirects(<(int, String?)>[
      (302, 'https://maps.google.com/?q=40.7174711,-73.9483998&entry=gps'),
    ]);
    final link = parseLocationLink(google)!;
    expect(link.isUnresolvable, isTrue);

    final place = await resolveShortLink(link, _dio(redirects));
    expect(place.position!.lat, closeTo(40.7174711, 1e-7));
    expect(place.position!.lon, closeTo(-73.9483998, 1e-7));
    expect(redirects.requests, hasLength(1));
  });

  test('the text around the link stays as the name', () async {
    final redirects = _Redirects(<(int, String?)>[
      (302, 'https://maps.google.com/?q=52.5163,13.3777'),
    ]);
    final link = parseLocationLink('Brandenburger Tor\n$google')!;
    expect(link.query, 'Brandenburger Tor');

    final place = await resolveShortLink(link, _dio(redirects));
    expect(place.position, isNotNull);
    expect(place.name, 'Brandenburger Tor');
  });

  test("Google's consent page is seen through", () async {
    final redirects = _Redirects(<(int, String?)>[
      (
        302,
        'https://consent.google.com/m?continue='
            '${Uri.encodeComponent('https://maps.google.com/?q=48.8584,2.2945')}',
      ),
    ]);
    final place = await resolveShortLink(
      parseLocationLink(google)!,
      _dio(redirects),
    );
    expect(place.position!.lat, closeTo(48.8584, 1e-6));
  });

  test('offline, or no redirect, leaves the link as it was', () async {
    final failing = Dio()
      ..httpClientAdapter = _Redirects(<(int, String?)>[(200, null)]);
    final link = parseLocationLink(google)!;
    expect(await resolveShortLink(link, failing), same(link));

    final broken = Dio()..httpClientAdapter = _Throwing();
    expect(await resolveShortLink(link, broken), same(link));
  });

  test('a link with a place already is not fetched', () async {
    final redirects = _Redirects(<(int, String?)>[]);
    final link = parseLocationLink('https://maps.google.com/?q=1.5,2.5')!;
    expect(await resolveShortLink(link, _dio(redirects)), same(link));
    expect(redirects.requests, isEmpty);
  });
}

class _Throwing implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => throw DioException.connectionError(
    requestOptions: options,
    reason: 'offline',
  );

  @override
  void close({bool force = false}) {}
}

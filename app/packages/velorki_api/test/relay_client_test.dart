import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:velorki_api/velorki_api.dart';

/// A JSON response with the header the relay sends.
http.Response json(Object? body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

/// Captures the single request a test makes and answers it with [response].
class Captured {
  http.Request? request;

  /// The decoded JSON request body.
  Map<String, Object?> get body =>
      jsonDecode(request!.body) as Map<String, Object?>;

  MockClient answering(http.Response response) => MockClient((req) async {
    request = req;
    return response;
  });
}

void main() {
  const base = 'https://relay.velorki.app';

  const stravaBody = <String, Object?>{
    'token_type': 'Bearer',
    'expires_at': 1_789_000_000,
    'expires_in': 21600,
    'refresh_token': 'r3fr3sh',
    'access_token': 'acc3ss',
    'athlete': <String, Object?>{'id': 12345, 'username': 'velorki'},
  };

  group('base url joining', () {
    test('tolerates trailing slashes and a path prefix', () {
      for (final url in <String>[base, '$base/', '$base///', '  $base/  ']) {
        expect(
          RelayClient(
            url,
            client: MockClient((_) async => json(null)),
          ).uriFor('/share').toString(),
          '$base/share',
          reason: url,
        );
      }
      expect(
        RelayClient(
          '$base/v1/',
          client: MockClient((_) async => json(null)),
        ).uriFor('/share').toString(),
        '$base/v1/share',
      );
    });
  });

  group('exchangeStravaCode', () {
    test('sends the documented request and parses the response', () async {
      final captured = Captured();
      final client = RelayClient(
        '$base/',
        client: captured.answering(json(stravaBody)),
        clientId: 'android/1.4.0',
        appUserId: 'rc_user_42',
      );
      addTearDown(client.close);

      final tokens = await client.exchangeStravaCode(
        code: 'authcode',
        redirectUri: 'velorki://oauth/strava',
      );

      final request = captured.request!;
      expect(request.method, 'POST');
      expect(request.url.toString(), '$base/oauth/strava/token');
      expect(request.headers['X-Velorki-Client'], 'android/1.4.0');
      expect(
        request.headers['Content-Type'],
        'application/json; charset=utf-8',
      );
      expect(request.headers['Authorization'], 'Bearer rc_user_42');
      expect(request.headers['Accept'], 'application/json');
      expect(captured.body, <String, Object?>{
        'code': 'authcode',
        'redirect_uri': 'velorki://oauth/strava',
      });

      expect(tokens.accessToken, 'acc3ss');
      expect(tokens.refreshToken, 'r3fr3sh');
      expect(tokens.expiresAt, 1_789_000_000);
      expect(tokens.athlete!['id'], 12345);
    });

    test('defaults X-Velorki-Client to dart/<package version>', () async {
      final captured = Captured();
      final client = RelayClient(
        base,
        client: captured.answering(json(stravaBody)),
      );
      addTearDown(client.close);

      await client.exchangeStravaCode(code: 'c', redirectUri: 'r');
      expect(
        captured.request!.headers['X-Velorki-Client'],
        'dart/$packageVersion',
      );
    });

    test('omits Authorization when no app user id is configured', () async {
      final captured = Captured();
      final client = RelayClient(
        base,
        client: captured.answering(json(stravaBody)),
      );
      addTearDown(client.close);

      await client.exchangeStravaCode(code: 'c', redirectUri: 'r');
      expect(captured.request!.headers.containsKey('Authorization'), isFalse);
    });
  });

  group('refreshStrava', () {
    test('posts the refresh token to the refresh endpoint', () async {
      final captured = Captured();
      final client = RelayClient(
        base,
        client: captured.answering(
          json(<String, Object?>{...stravaBody, 'refresh_token': 'rotated'}),
        ),
        clientId: 'ios/1.4.0',
      );
      addTearDown(client.close);

      final tokens = await client.refreshStrava(refreshToken: 'r3fr3sh');

      expect(captured.request!.url.toString(), '$base/oauth/strava/refresh');
      expect(captured.request!.method, 'POST');
      expect(captured.request!.headers['X-Velorki-Client'], 'ios/1.4.0');
      expect(captured.body, <String, Object?>{'refresh_token': 'r3fr3sh'});
      expect(
        tokens.refreshToken,
        'rotated',
        reason: 'Strava rotates refresh tokens',
      );
    });
  });

  group('exchangeRwgpsCode', () {
    test('sends the code and parses a token without an expiry', () async {
      final captured = Captured();
      final client = RelayClient(
        base,
        client: captured.answering(
          json(const <String, Object?>{'access_token': 'rw-token'}),
        ),
        clientId: 'android/1.4.0',
      );
      addTearDown(client.close);

      final tokens = await client.exchangeRwgpsCode(
        code: 'rwcode',
        redirectUri: 'velorki://oauth/rwgps',
      );

      expect(captured.request!.url.toString(), '$base/oauth/rwgps/token');
      expect(captured.body, <String, Object?>{
        'code': 'rwcode',
        'redirect_uri': 'velorki://oauth/rwgps',
      });
      expect(tokens.accessToken, 'rw-token');
      expect(tokens.expiresAt, isNull);
      expect(tokens.refreshToken, isNull);
    });
  });

  group('createShare', () {
    const gpx = '<?xml version="1.0"?><gpx version="1.1"><trk/></gpx>';

    test('posts kind, name, gpx and summary and parses the link', () async {
      final captured = Captured();
      final client = RelayClient(
        base,
        client: captured.answering(
          json(const <String, Object?>{
            'id': 'aB3dE5',
            'url': '$base/s/aB3dE5',
          }, status: 201),
        ),
        clientId: 'ios/1.4.0',
        appUserId: 'rc_user_42',
      );
      addTearDown(client.close);

      final link = await client.createShare(
        name: 'Kaiserstuhl loop',
        gpx: gpx,
        summary: const ShareSummary(
          distanceKm: 62.4,
          ascentM: 980,
          durationS: 12600,
        ),
        kind: ShareKind.ride,
      );

      final request = captured.request!;
      expect(request.method, 'POST');
      expect(request.url.toString(), '$base/share');
      expect(request.headers['X-Velorki-Client'], 'ios/1.4.0');
      expect(request.headers['Authorization'], 'Bearer rc_user_42');
      expect(captured.body, <String, Object?>{
        'kind': 'ride',
        'name': 'Kaiserstuhl loop',
        'gpx': gpx,
        'summary': <String, Object?>{
          'distance_km': 62.4,
          'ascent_m': 980.0,
          'duration_s': 12600,
        },
      });

      expect(link.id, 'aB3dE5');
      expect(link.url, '$base/s/aB3dE5');
      expect(link.gpxUrl, '$base/s/aB3dE5.gpx');
      expect(link.expiresAt, isNull);
    });

    test('defaults kind to route and omits absent summary fields', () async {
      final captured = Captured();
      final client = RelayClient(
        base,
        client: captured.answering(
          json(const <String, Object?>{
            'id': 'x',
            'url': '$base/s/x',
            'expires_at': 1_789_000_000,
          }),
        ),
      );
      addTearDown(client.close);

      final link = await client.createShare(
        name: 'Plan',
        gpx: gpx,
        summary: const ShareSummary(distanceKm: 30),
      );

      expect(captured.body['kind'], 'route');
      expect(captured.body['summary'], <String, Object?>{'distance_km': 30.0});
      expect(link.expiresAt, 1_789_000_000);
      expect(link.expiresAtUtc, DateTime.utc(2026, 9, 10, 0, 26, 40));
    });

    test('a non-object success body throws RelayFormatException', () async {
      final client = RelayClient(
        base,
        client: MockClient((_) async => http.Response('[]', 201)),
      );
      addTearDown(client.close);

      expect(
        () => client.createShare(
          name: 'n',
          gpx: gpx,
          summary: const ShareSummary(distanceKm: 1),
        ),
        throwsA(isA<RelayFormatException>()),
      );
    });
  });

  test('close closes the injected client', () async {
    var closed = false;
    final inner = MockClient((_) async => json(stravaBody));
    final client = RelayClient(
      base,
      client: _ClosingClient(inner, () {
        closed = true;
      }),
    );
    client.close();
    expect(closed, isTrue);
  });
}

/// A pass-through client that reports when it was closed.
class _ClosingClient extends http.BaseClient {
  _ClosingClient(this._inner, this._onClose);

  final http.Client _inner;
  final void Function() _onClose;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request);

  @override
  void close() {
    _onClose();
    _inner.close();
  }
}

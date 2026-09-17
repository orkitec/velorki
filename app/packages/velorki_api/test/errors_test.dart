import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:velorki_api/velorki_api.dart';

/// Builds a client whose every request gets [response].
RelayClient clientReturning(http.Response response) => RelayClient(
  'https://relay.velorki.com',
  client: MockClient((_) async => response),
  clientId: 'test/0.0.1',
);

/// The uniform error body the relay sends.
http.Response errorBody(
  int status,
  String code,
  String message, {
  int? retryAfterS,
  Map<String, String> headers = const <String, String>{},
}) => http.Response(
  jsonEncode(<String, Object?>{
    'error': <String, Object?>{
      'code': code,
      'message': message,
      'retry_after_s': ?retryAfterS,
    },
  }),
  status,
  headers: <String, String>{
    'content-type': 'application/json; charset=utf-8',
    ...headers,
  },
);

/// Any call would do; the token exchange is the simplest.
Future<void> call(RelayClient client) =>
    client.exchangeStravaCode(code: 'c', redirectUri: 'r');

void main() {
  group('uniform error bodies map to RelayException', () {
    final cases = <int, String>{
      400: RelayErrorCode.invalidRequest,
      401: RelayErrorCode.notEntitled,
      403: RelayErrorCode.consentRequired,
      404: RelayErrorCode.notFound,
      429: RelayErrorCode.rateLimited,
      502: RelayErrorCode.upstreamError,
      503: RelayErrorCode.unavailable,
    };

    cases.forEach((status, code) {
      test('$status -> $code', () async {
        final client = clientReturning(errorBody(status, code, 'nope'));
        addTearDown(client.close);

        await expectLater(
          call(client),
          throwsA(
            isA<RelayException>()
                .having((e) => e.statusCode, 'statusCode', status)
                .having((e) => e.code, 'code', code)
                .having((e) => e.message, 'message', 'nope')
                .having((e) => e.retryAfterS, 'retryAfterS', isNull),
          ),
        );
      });
    });

    test('429 carries retry_after_s from the body', () async {
      final client = clientReturning(
        errorBody(
          429,
          RelayErrorCode.rateLimited,
          'Slow down.',
          retryAfterS: 900,
        ),
      );
      addTearDown(client.close);

      await expectLater(
        call(client),
        throwsA(
          isA<RelayException>()
              .having((e) => e.code, 'code', RelayErrorCode.rateLimited)
              .having((e) => e.retryAfterS, 'retryAfterS', 900)
              .having((e) => e.error.message, 'message', 'Slow down.'),
        ),
      );
    });

    test(
      'falls back to the Retry-After header when the body omits it',
      () async {
        final client = clientReturning(
          errorBody(
            429,
            RelayErrorCode.rateLimited,
            'Slow down.',
            headers: const <String, String>{'retry-after': '42'},
          ),
        );
        addTearDown(client.close);

        await expectLater(
          call(client),
          throwsA(
            isA<RelayException>().having(
              (e) => e.retryAfterS,
              'retryAfterS',
              42,
            ),
          ),
        );
      },
    );

    test('an unknown code is carried through verbatim', () async {
      final client = clientReturning(
        errorBody(418, 'teapot', 'Short and stout.'),
      );
      addTearDown(client.close);

      await expectLater(
        call(client),
        throwsA(
          isA<RelayException>()
              .having((e) => e.code, 'code', 'teapot')
              .having((e) => e.statusCode, 'statusCode', 418),
        ),
      );
    });
  });

  group('non-uniform failures are synthesised, never leaked', () {
    test('an HTML page from a proxy becomes upstream_error', () async {
      final client = clientReturning(
        http.Response(
          '<html><head><title>502 Bad Gateway</title></head>'
          '<body><center><h1>502 Bad Gateway</h1></center>'
          '<hr><center>nginx</center></body></html>',
          502,
          headers: const <String, String>{'content-type': 'text/html'},
        ),
      );
      addTearDown(client.close);

      await expectLater(
        call(client),
        throwsA(
          isA<RelayException>()
              .having((e) => e.code, 'code', RelayErrorCode.upstreamError)
              .having((e) => e.statusCode, 'statusCode', 502)
              .having((e) => e.message, 'message', contains('502')),
        ),
      );
    });

    test('a long HTML body is truncated in the message', () async {
      final client = clientReturning(
        http.Response('<p>${'x' * 5000}</p>', 500),
      );
      addTearDown(client.close);

      try {
        await call(client);
        fail('expected a RelayException');
      } on RelayException catch (e) {
        expect(e.code, RelayErrorCode.upstreamError);
        expect(e.message.length, lessThan(220));
        expect(e.message, endsWith('...'));
      }
    });

    test('an empty body still yields a coded error', () async {
      final client = clientReturning(http.Response('', 503));
      addTearDown(client.close);

      await expectLater(
        call(client),
        throwsA(
          isA<RelayException>()
              .having((e) => e.code, 'code', RelayErrorCode.unavailable)
              .having((e) => e.message, 'message', contains('empty body')),
        ),
      );
    });

    test(
      'valid JSON of the wrong shape is synthesised from the status',
      () async {
        final client = clientReturning(http.Response('{"detail":"nope"}', 400));
        addTearDown(client.close);

        await expectLater(
          call(client),
          throwsA(
            isA<RelayException>()
                .having((e) => e.code, 'code', RelayErrorCode.invalidRequest)
                .having((e) => e.message, 'message', contains('detail')),
          ),
        );
      },
    );

    test('an unmapped 4xx becomes invalid_request', () async {
      final client = clientReturning(http.Response('', 409));
      addTearDown(client.close);

      await expectLater(
        call(client),
        throwsA(
          isA<RelayException>().having(
            (e) => e.code,
            'code',
            RelayErrorCode.invalidRequest,
          ),
        ),
      );
    });
  });

  group('transport failures become RelayException', () {
    test('an http.ClientException becomes unavailable', () async {
      final client = RelayClient(
        'https://relay.velorki.com',
        client: MockClient((_) async {
          throw http.ClientException('Connection closed before full header');
        }),
      );
      addTearDown(client.close);

      await expectLater(
        call(client),
        throwsA(
          isA<RelayException>()
              .having((e) => e.code, 'code', RelayErrorCode.unavailable)
              .having((e) => e.statusCode, 'statusCode', isNull)
              .having(
                (e) => e.message,
                'message',
                contains('Connection closed before full header'),
              ),
        ),
      );
    });

    test('a SocketException-shaped failure becomes unavailable too', () async {
      // Stands in for dart:io's SocketException, which this package
      // deliberately does not import.
      final client = RelayClient(
        'https://relay.velorki.com',
        client: MockClient((_) async {
          throw const _SocketLike('No route to host');
        }),
      );
      addTearDown(client.close);

      await expectLater(
        call(client),
        throwsA(
          isA<RelayException>()
              .having((e) => e.code, 'code', RelayErrorCode.unavailable)
              .having(
                (e) => e.message,
                'message',
                contains('No route to host'),
              ),
        ),
      );
    });

    test('the exception message stays readable', () async {
      final client = RelayClient(
        'https://relay.velorki.com',
        client: MockClient((_) async => http.Response('', 503)),
      );
      addTearDown(client.close);

      try {
        await call(client);
        fail('expected a RelayException');
      } on RelayException catch (e) {
        expect(e.toString(), contains('HTTP 503'));
        expect(e.toString(), contains('unavailable'));
      }
    });
  });
}

/// A stand-in for `dart:io`'s `SocketException`.
class _SocketLike implements Exception {
  const _SocketLike(this.message);

  final String message;

  @override
  String toString() => 'SocketException: $message';
}

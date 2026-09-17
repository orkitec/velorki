import 'dart:convert';

import 'package:test/test.dart';
import 'package:velorki_api/velorki_api.dart';

/// A `propose_route` payload with every field present.
const Map<String, Object?> fullJson = <String, Object?>{
  'distance_km': 84.5,
  'loop': true,
  'start': <String, Object?>{'use_current': false, 'name': 'Freiburg'},
  'via': <String>['Schauinsland', 'Todtnau'],
  'surface': 'gravel',
  'hills': 'seek',
  'traffic_tolerance': 'low',
  'stops': <String>['cafe', 'viewpoint'],
  'profile_hint': 'gravel',
  'notes': 'Bring a jacket for the descent.',
  'confidence': 0.82,
};

/// The same payload with only the fields the relay's schema requires.
const Map<String, Object?> minimalJson = <String, Object?>{
  'distance_km': 40.0,
  'loop': false,
  'start': <String, Object?>{'use_current': true},
  'surface': 'paved',
  'hills': 'avoid',
  'traffic_tolerance': 'medium',
  'profile_hint': 'trekking',
};

void main() {
  group('RouteRequest', () {
    test('round trips with every field populated', () {
      final parsed = RouteRequest.fromJson(fullJson);
      expect(parsed.distanceKm, 84.5);
      expect(parsed.loop, isTrue);
      expect(
        parsed.start,
        const RouteStart(useCurrent: false, name: 'Freiburg'),
      );
      expect(parsed.via, <String>['Schauinsland', 'Todtnau']);
      expect(parsed.surface, SurfacePreference.gravel);
      expect(parsed.hills, HillPreference.seek);
      expect(parsed.trafficTolerance, TrafficTolerance.low);
      expect(parsed.stops, <StopKind>[StopKind.cafe, StopKind.viewpoint]);
      expect(parsed.profileHint, ProfileHint.gravel);
      expect(parsed.notes, 'Bring a jacket for the descent.');
      expect(parsed.confidence, 0.82);

      expect(parsed.toJson(), fullJson);
      expect(RouteRequest.fromJson(parsed.toJson()), parsed);
      // Through real JSON text, not just the map.
      expect(
        RouteRequest.fromJson(
          jsonDecode(jsonEncode(parsed.toJson())) as Map<String, Object?>,
        ),
        parsed,
      );
    });

    test('applies the relay defaults for absent optional fields', () {
      final parsed = RouteRequest.fromJson(minimalJson);
      expect(parsed.via, isEmpty);
      expect(parsed.stops, <StopKind>[StopKind.none]);
      expect(parsed.notes, isNull);
      expect(parsed.confidence, 0.5);

      // toJson writes the defaults out, so the result is a complete payload.
      expect(parsed.toJson(), <String, Object?>{
        ...minimalJson,
        'via': <String>[],
        'stops': <String>['none'],
        'confidence': 0.5,
      });
      expect(RouteRequest.fromJson(parsed.toJson()), parsed);
    });

    test('equality and hashCode look through the lists', () {
      final a = RouteRequest.fromJson(fullJson);
      final b = RouteRequest.fromJson(fullJson);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(b.copyWith(via: const <String>['Elsewhere'])));
      expect(a, isNot(b.copyWith(stops: const <StopKind>[StopKind.none])));
      expect(a, isNot(b.copyWith(distanceKm: 84.6)));
    });

    test('toString names the enum wire values', () {
      final text = RouteRequest.fromJson(fullJson).toString();
      expect(text, contains('surface: gravel'));
      expect(text, contains('[cafe, viewpoint]'));
    });

    test('a missing required field throws RelayFormatException', () {
      for (final key in minimalJson.keys) {
        final broken = Map<String, Object?>.from(minimalJson)..remove(key);
        expect(
          () => RouteRequest.fromJson(broken),
          throwsA(isA<RelayFormatException>()),
          reason: 'missing $key',
        );
      }
    });

    test('a field of the wrong type throws RelayFormatException', () {
      expect(
        () => RouteRequest.fromJson(<String, Object?>{
          ...minimalJson,
          'distance_km': '40',
        }),
        throwsA(isA<RelayFormatException>()),
      );
      expect(
        () => RouteRequest.fromJson(<String, Object?>{
          ...minimalJson,
          'loop': 'yes',
        }),
        throwsA(isA<RelayFormatException>()),
      );
      expect(
        () => RouteRequest.fromJson(<String, Object?>{
          ...minimalJson,
          'via': 'Todtnau',
        }),
        throwsA(isA<RelayFormatException>()),
      );
      expect(
        () => RouteRequest.fromJson(<String, Object?>{
          ...minimalJson,
          'stops': <Object?>[1],
        }),
        throwsA(isA<RelayFormatException>()),
      );
    });

    group('unknown enum values', () {
      // Policy: strict. An enum string this client does not know throws
      // RelayFormatException rather than silently becoming a default, because
      // the values steer a routing query and a wrong guess produces a route
      // the rider did not ask for.
      test('throw RelayFormatException naming the field and the value', () {
        expect(
          () => RouteRequest.fromJson(<String, Object?>{
            ...minimalJson,
            'surface': 'cobbles',
          }),
          throwsA(
            isA<RelayFormatException>().having(
              (e) => e.message,
              'message',
              allOf(contains('surface'), contains('cobbles')),
            ),
          ),
        );
      });

      test('apply to every enum field, including inside stops', () {
        const cases = <String, Object?>{
          'surface': 'cobbles',
          'hills': 'flat',
          'traffic_tolerance': 'none',
          'profile_hint': 'ebike',
          'stops': <String>['pub'],
        };
        cases.forEach((key, value) {
          expect(
            () => RouteRequest.fromJson(<String, Object?>{
              ...minimalJson,
              key: value,
            }),
            throwsA(isA<RelayFormatException>()),
            reason: key,
          );
        });
      });

      test('the enum parsers themselves are strict too', () {
        expect(SurfacePreference.fromJson('mixed'), SurfacePreference.mixed);
        expect(
          () => HillPreference.fromJson('Seek'),
          throwsA(isA<RelayFormatException>()),
        );
        expect(
          () => StopKind.fromJson(''),
          throwsA(isA<RelayFormatException>()),
        );
        expect(
          () => ShareKind.fromJson('track'),
          throwsA(isA<RelayFormatException>()),
        );
        expect(
          () => PlanUnits.fromJson('nautical'),
          throwsA(isA<RelayFormatException>()),
        );
      });
    });

    test('out-of-range and odd values are carried through unchanged', () {
      // Policy: the relay owns validation. The client preserves what it was
      // given so a round trip is lossless and a widened server limit does not
      // break an older client.
      final odd = RouteRequest.fromJson(<String, Object?>{
        ...minimalJson,
        'distance_km': 4000.0,
        'confidence': 1.9,
        'notes': 'x' * 400,
        'via': <String>['a', 'b', 'c', 'd', 'e', 'f'],
        'stops': <String>['none', 'none', 'cafe'],
      });
      expect(odd.distanceKm, 4000.0);
      expect(odd.confidence, 1.9);
      expect(odd.notes!.length, 400);
      expect(odd.via.length, 6);
      expect(odd.stops.length, 3);
      expect(RouteRequest.fromJson(odd.toJson()), odd);
    });

    test('accepts integer JSON numbers for double fields', () {
      final parsed = RouteRequest.fromJson(<String, Object?>{
        ...minimalJson,
        'distance_km': 40,
        'confidence': 1,
      });
      expect(parsed.distanceKm, 40.0);
      expect(parsed.confidence, 1.0);
    });

    test('negative and zero values are preserved, not clamped', () {
      final parsed = RouteRequest.fromJson(<String, Object?>{
        ...minimalJson,
        'distance_km': -5.0,
        'confidence': 0,
      });
      expect(parsed.distanceKm, -5.0);
      expect(parsed.confidence, 0.0);
    });
  });

  group('RouteStart', () {
    test('omits an absent name', () {
      const start = RouteStart(useCurrent: true);
      expect(start.toJson(), <String, Object?>{'use_current': true});
      expect(RouteStart.fromJson(start.toJson()), start);
    });

    test('rejects a missing use_current', () {
      expect(
        () => RouteStart.fromJson(const <String, Object?>{}),
        throwsA(isA<RelayFormatException>()),
      );
    });
  });

  group('token models', () {
    test('StravaTokens round trips including the athlete passthrough', () {
      const json = <String, Object?>{
        'token_type': 'Bearer',
        'expires_at': 1_789_000_000,
        'expires_in': 21600,
        'refresh_token': 'r3fr3sh',
        'access_token': 'acc3ss',
        'athlete': <String, Object?>{'id': 12345, 'username': 'velorki'},
      };
      final tokens = StravaTokens.fromJson(json);
      expect(tokens.accessToken, 'acc3ss');
      expect(tokens.refreshToken, 'r3fr3sh');
      expect(tokens.expiresAt, 1_789_000_000);
      expect(tokens.expiresIn, 21600);
      expect(tokens.athlete!['username'], 'velorki');
      expect(tokens.expiresAtUtc, DateTime.utc(2026, 9, 10, 0, 26, 40));
      expect(tokens.toJson(), json);
      expect(StravaTokens.fromJson(tokens.toJson()), tokens);
    });

    test('StravaTokens.isExpired respects the leeway', () {
      final soon = DateTime.now().toUtc().add(const Duration(minutes: 2));
      final tokens = StravaTokens(
        accessToken: 'a',
        refreshToken: 'r',
        expiresAt: soon.millisecondsSinceEpoch ~/ 1000,
      );
      expect(tokens.isExpired(), isTrue, reason: 'inside the 5 minute leeway');
      expect(tokens.isExpired(leeway: Duration.zero), isFalse);
    });

    test('StravaTokens requires the fields Strava always sends', () {
      expect(
        () => StravaTokens.fromJson(const <String, Object?>{
          'access_token': 'a',
          'expires_at': 1,
        }),
        throwsA(isA<RelayFormatException>()),
      );
      expect(
        () => StravaTokens.fromJson(const <String, Object?>{
          'access_token': 'a',
          'refresh_token': 'r',
        }),
        throwsA(isA<RelayFormatException>()),
      );
    });

    test('RwgpsTokens tolerate the absent refresh token and expiry', () {
      final tokens = RwgpsTokens.fromJson(const <String, Object?>{
        'access_token': 'rw',
      });
      expect(tokens.accessToken, 'rw');
      expect(tokens.refreshToken, isNull);
      expect(tokens.expiresAt, isNull);
      expect(tokens.expiresAtUtc, isNull);
      expect(tokens.tokenType, 'Bearer');
      expect(tokens.toJson(), <String, Object?>{
        'access_token': 'rw',
        'token_type': 'Bearer',
      });
      expect(RwgpsTokens.fromJson(tokens.toJson()), tokens);
    });
  });

  group('share models', () {
    test('ShareSummary omits absent fields', () {
      const summary = ShareSummary(distanceKm: 62.4);
      expect(summary.toJson(), <String, Object?>{'distance_km': 62.4});
      expect(ShareSummary.fromJson(summary.toJson()), summary);

      const full = ShareSummary(
        distanceKm: 62.4,
        ascentM: 980,
        durationS: 12600,
      );
      expect(ShareSummary.fromJson(full.toJson()), full);
    });

    test('ShareLink derives the gpx url and tolerates a missing expiry', () {
      final link = ShareLink.fromJson(const <String, Object?>{
        'id': 'aB3dE5',
        'url': 'https://relay.velorki.com/s/aB3dE5',
      });
      expect(link.gpxUrl, 'https://relay.velorki.com/s/aB3dE5.gpx');
      expect(link.expiresAt, isNull);
      expect(link.expiresAtUtc, isNull);
      expect(ShareLink.fromJson(link.toJson()), link);

      final expiring = ShareLink.fromJson(const <String, Object?>{
        'id': 'aB3dE5',
        'url': 'https://relay.velorki.com/s/aB3dE5',
        'expires_at': 1_789_000_000,
      });
      expect(expiring.expiresAtUtc, DateTime.utc(2026, 9, 10, 0, 26, 40));
      expect(expiring, isNot(link));
    });
  });

  group('plan request models', () {
    test('PlanContext and PlanStart round trip', () {
      const context = PlanContext(
        start: PlanStart(lat: 47.99, lon: 7.85),
        startLabel: 'Freiburg im Breisgau',
        today: 'Saturday',
      );
      expect(context.toJson(), <String, Object?>{
        'start': <String, Object?>{'lat': 47.99, 'lon': 7.85},
        'start_label': 'Freiburg im Breisgau',
        'today': 'Saturday',
      });
      expect(PlanContext.fromJson(context.toJson()), context);
      expect(
        PlanContext.fromJson(const <String, Object?>{}),
        const PlanContext(),
      );
    });

    test('RouteSummary round trips with and without the optional lists', () {
      const summary = RouteSummary(
        distanceKm: 62.4,
        ascentM: 980,
        surface: SurfaceMix(paved: 0.7, gravel: 0.3),
        waypoints: <String>['Freiburg', 'Kirchzarten'],
        highlights: <String>['Long descent'],
      );
      expect(RouteSummary.fromJson(summary.toJson()), summary);

      const bare = RouteSummary(distanceKm: 10, ascentM: 0);
      expect(bare.toJson(), <String, Object?>{
        'distance_km': 10.0,
        'ascent_m': 0.0,
        'surface': <String, Object?>{},
      });
      expect(RouteSummary.fromJson(bare.toJson()), bare);
    });

    test('PlanUsage maps the short wire keys', () {
      final usage = PlanUsage.fromJson(const <String, Object?>{
        'in': 1200,
        'out': 310,
      });
      expect(usage.inputTokens, 1200);
      expect(usage.outputTokens, 310);
      expect(usage.toJson(), <String, Object?>{'in': 1200, 'out': 310});
      expect(
        PlanUsage.fromJson(const <String, Object?>{}),
        const PlanUsage(inputTokens: 0, outputTokens: 0),
      );
    });
  });

  group('RelayError', () {
    test('round trips the uniform body', () {
      const error = RelayError(
        code: RelayErrorCode.rateLimited,
        message: 'Too many plans today.',
        retryAfterS: 900,
      );
      expect(error.toBody(), <String, Object?>{
        'error': <String, Object?>{
          'code': 'rate_limited',
          'message': 'Too many plans today.',
          'retry_after_s': 900,
        },
      });
      expect(RelayError.fromBody(error.toBody()), error);
      expect(error.toString(), contains('retry after 900s'));
    });

    test('accepts a bare inner object and a flattened string', () {
      expect(
        RelayError.fromBody(const <String, Object?>{
          'code': 'unavailable',
          'message': 'down',
        }),
        const RelayError(code: 'unavailable', message: 'down'),
      );
      expect(
        RelayError.fromBody(const <String, Object?>{'error': 'gateway down'}),
        const RelayError(
          code: RelayErrorCode.upstreamError,
          message: 'gateway down',
        ),
      );
    });

    test('rejects anything that is not an error body', () {
      expect(
        () => RelayError.fromBody('nope'),
        throwsA(isA<RelayFormatException>()),
      );
      expect(
        () => RelayError.fromBody(const <String, Object?>{'ok': true}),
        throwsA(isA<RelayFormatException>()),
      );
    });
  });
}

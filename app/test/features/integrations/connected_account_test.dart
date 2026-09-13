import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/integrations/common/domain/connected_account.dart';

/// A full account, every optional field set.
ConnectedAccount _full() => ConnectedAccount(
  service: IntegrationService.strava,
  accessToken: 'access',
  refreshToken: 'refresh',
  expiresAt: DateTime.utc(2026, 9, 12, 12),
  athleteId: '42',
  athleteName: 'Steffen Römer',
  scopes: const <String>['read', 'activity:write'],
);

void main() {
  group('naming a service', () {
    test('the id is the stable string storage and deep links use', () {
      expect(IntegrationService.strava.id, 'strava');
      expect(IntegrationService.rwgps.id, 'rwgps');
    });

    test('a known id maps back to its service', () {
      expect(IntegrationService.fromId('strava'), IntegrationService.strava);
      expect(IntegrationService.fromId('rwgps'), IntegrationService.rwgps);
    });

    test('an unknown or misspelled id maps to nothing', () {
      expect(IntegrationService.fromId('garmin'), isNull);
      expect(IntegrationService.fromId('Strava'), isNull);
      expect(IntegrationService.fromId(''), isNull);
    });
  });

  group('storing an account as JSON', () {
    test('every field survives the round trip', () {
      final read = ConnectedAccount.fromJson(_full().toJson());

      expect(read.service, IntegrationService.strava);
      expect(read.accessToken, 'access');
      expect(read.refreshToken, 'refresh');
      expect(read.expiresAt, DateTime.utc(2026, 9, 12, 12));
      expect(read.athleteId, '42');
      expect(read.athleteName, 'Steffen Römer');
      expect(read.scopes, <String>['read', 'activity:write']);
    });

    test('fields that are not set are left out of the document', () {
      const account = ConnectedAccount(
        service: IntegrationService.rwgps,
        accessToken: 'token',
      );

      expect(account.toJson(), <String, Object?>{
        'service': 'rwgps',
        'access_token': 'token',
      });

      final read = ConnectedAccount.fromJson(account.toJson());
      expect(read.refreshToken, isNull);
      expect(read.expiresAt, isNull);
      expect(read.athleteId, isNull);
      expect(read.athleteName, isNull);
      expect(read.scopes, isEmpty);
    });

    test('the expiry is written and read as whole Unix seconds', () {
      final account = ConnectedAccount(
        service: IntegrationService.strava,
        accessToken: 'access',
        expiresAt: DateTime.utc(
          2026,
          9,
          12,
          12,
        ).add(const Duration(milliseconds: 750)),
      );

      expect(account.toJson()['expires_at'], 1789214400);
      expect(
        ConnectedAccount.fromJson(account.toJson()).expiresAt,
        DateTime.utc(2026, 9, 12, 12),
      );
    });

    test('a local expiry is stored in UTC', () {
      final local = DateTime.utc(2026, 9, 12, 12).toLocal();
      final account = ConnectedAccount(
        service: IntegrationService.strava,
        accessToken: 'access',
        expiresAt: local,
      );

      expect(account.toJson()['expires_at'], 1789214400);
      expect(
        ConnectedAccount.fromJson(account.toJson()).expiresAt,
        DateTime.utc(2026, 9, 12, 12),
      );
    });

    test('an expiry that is not a whole number of seconds is ignored', () {
      final account = ConnectedAccount.fromJson(<String, Object?>{
        'service': 'strava',
        'access_token': 'access',
        'expires_at': 1789214400.5,
      });

      expect(account.expiresAt, isNull);
    });

    test('only the strings of a scopes list are kept', () {
      final account = ConnectedAccount.fromJson(<String, Object?>{
        'service': 'strava',
        'access_token': 'access',
        'scopes': <Object?>['read', 7, null, 'activity:write'],
      });

      expect(account.scopes, <String>['read', 'activity:write']);
    });

    test('a scopes field that is not a list leaves no scopes', () {
      final account = ConnectedAccount.fromJson(<String, Object?>{
        'service': 'strava',
        'access_token': 'access',
        'scopes': 'read,activity:write',
      });

      expect(account.scopes, isEmpty);
    });

    test('a document for an unknown service is not an account', () {
      expect(
        () => ConnectedAccount.fromJson(<String, Object?>{
          'service': 'garmin',
          'access_token': 'access',
        }),
        throwsFormatException,
      );
    });

    test('a document without a usable access token is not an account', () {
      expect(
        () => ConnectedAccount.fromJson(<String, Object?>{'service': 'strava'}),
        throwsFormatException,
      );
      expect(
        () => ConnectedAccount.fromJson(<String, Object?>{
          'service': 'strava',
          'access_token': '',
        }),
        throwsFormatException,
      );
      expect(
        () => ConnectedAccount.fromJson(<String, Object?>{
          'service': 'strava',
          'access_token': 12345,
        }),
        throwsFormatException,
      );
    });
  });

  group('decoding a secure storage entry', () {
    test('an encoded account is read back whole', () {
      final read = ConnectedAccount.decode(_full().encode());

      expect(read, _full());
      expect(read.scopes, <String>['read', 'activity:write']);
      expect(jsonDecode(_full().encode()), _full().toJson());
    });

    test('an entry that is not JSON is refused', () {
      expect(
        () => ConnectedAccount.decode('not json at all'),
        throwsA(anything),
      );
    });

    test('an entry that is JSON but not an object is refused', () {
      expect(() => ConnectedAccount.decode('[]'), throwsFormatException);
      expect(() => ConnectedAccount.decode('"strava"'), throwsFormatException);
    });
  });

  group('deciding whether a token must be refreshed', () {
    final now = DateTime.utc(2026, 9, 12, 12);

    ConnectedAccount account({DateTime? expiresAt, String? refreshToken}) =>
        ConnectedAccount(
          service: IntegrationService.strava,
          accessToken: 'access',
          refreshToken: refreshToken,
          expiresAt: expiresAt,
        );

    test('a token that has already expired is due', () {
      expect(
        account(
          expiresAt: now.subtract(const Duration(hours: 1)),
          refreshToken: 'refresh',
        ).needsRefresh(now: now),
        isTrue,
      );
    });

    test('a token expiring exactly at the leeway is due', () {
      expect(
        account(
          expiresAt: now.add(const Duration(seconds: 59)),
          refreshToken: 'refresh',
        ).needsRefresh(now: now),
        isTrue,
      );
      expect(
        account(
          expiresAt: now.add(const Duration(seconds: 61)),
          refreshToken: 'refresh',
        ).needsRefresh(now: now),
        isFalse,
      );
    });

    test('a longer leeway refreshes earlier', () {
      final soon = account(
        expiresAt: now.add(const Duration(minutes: 4)),
        refreshToken: 'refresh',
      );

      expect(soon.needsRefresh(now: now), isFalse);
      expect(
        soon.needsRefresh(now: now, leeway: const Duration(minutes: 5)),
        isTrue,
      );
    });

    test('a token without an expiry never needs refreshing', () {
      expect(account(refreshToken: 'refresh').needsRefresh(now: now), isFalse);
    });

    test('a local clock is compared in UTC', () {
      expect(
        account(
          expiresAt: now.add(const Duration(minutes: 10)),
          refreshToken: 'refresh',
        ).needsRefresh(now: now.toLocal()),
        isFalse,
      );
      expect(
        account(
          expiresAt: now.subtract(const Duration(minutes: 10)),
          refreshToken: 'refresh',
        ).needsRefresh(now: now.toLocal()),
        isTrue,
      );
    });

    test('without a clock the current time decides', () {
      expect(
        account(
          expiresAt: DateTime.utc(2000),
          refreshToken: 'refresh',
        ).needsRefresh(),
        isTrue,
      );
      expect(
        account(
          expiresAt: DateTime.utc(2100),
          refreshToken: 'refresh',
        ).needsRefresh(),
        isFalse,
      );
    });
  });

  group('scopes', () {
    test('a granted scope is reported, another one is not', () {
      expect(_full().hasScope('activity:write'), isTrue);
      expect(_full().hasScope('read'), isTrue);
      expect(_full().hasScope('activity:read_all'), isFalse);
    });

    test('an account without scopes has none', () {
      const account = ConnectedAccount(
        service: IntegrationService.rwgps,
        accessToken: 'token',
      );

      expect(account.hasScope('read'), isFalse);
    });
  });

  group('copying an account', () {
    test('the service stays, the given fields change', () {
      final refreshed = _full().copyWith(
        accessToken: 'newer',
        refreshToken: 'newer-refresh',
        expiresAt: DateTime.utc(2026, 9, 12, 18),
      );

      expect(refreshed.service, IntegrationService.strava);
      expect(refreshed.accessToken, 'newer');
      expect(refreshed.refreshToken, 'newer-refresh');
      expect(refreshed.expiresAt, DateTime.utc(2026, 9, 12, 18));
      expect(refreshed.athleteId, '42');
      expect(refreshed.athleteName, 'Steffen Römer');
      expect(refreshed.scopes, <String>['read', 'activity:write']);
    });

    test('copying nothing leaves an equal account', () {
      expect(_full().copyWith(), _full());
    });

    test('the athlete and the scopes can be filled in after connecting', () {
      const fresh = ConnectedAccount(
        service: IntegrationService.rwgps,
        accessToken: 'token',
      );

      final named = fresh.copyWith(
        athleteId: '7',
        athleteName: 'Rider',
        scopes: const <String>['read'],
      );

      expect(named.athleteId, '7');
      expect(named.athleteName, 'Rider');
      expect(named.scopes, <String>['read']);
      expect(named.accessToken, 'token');
    });
  });

  group('equality', () {
    test('two accounts holding the same token are the same account', () {
      expect(_full(), _full());
      expect(_full().hashCode, _full().hashCode);
      expect(<ConnectedAccount>{_full(), _full()}, hasLength(1));
    });

    test('a different service, token, expiry or athlete is a difference', () {
      expect(_full(), isNot(_full().copyWith(accessToken: 'other')));
      expect(_full(), isNot(_full().copyWith(refreshToken: 'other')));
      expect(_full(), isNot(_full().copyWith(expiresAt: DateTime.utc(2030))));
      expect(_full(), isNot(_full().copyWith(athleteId: '43')));
      expect(_full(), isNot(_full().copyWith(athleteName: 'Someone')));
      expect(
        _full(),
        isNot(
          const ConnectedAccount(
            service: IntegrationService.rwgps,
            accessToken: 'access',
            refreshToken: 'refresh',
          ),
        ),
      );
    });

    test('the granted scopes are not part of the identity', () {
      // Deliberate: a re-authorisation that only widens the scopes must not
      // look like a different account to the settings screen.
      expect(_full(), _full().copyWith(scopes: const <String>['read']));
      expect(
        _full().hashCode,
        _full().copyWith(scopes: const <String>['read']).hashCode,
      );
    });

    test('an account is not equal to something else entirely', () {
      expect(_full(), isNot(IntegrationService.strava));
    });
  });

  test('the description carries no secrets', () {
    final text = _full().toString();

    expect(text, contains('strava'));
    expect(text, contains('Steffen Römer'));
    expect(text, isNot(contains('access')));
    expect(text, isNot(contains('refresh')));
  });

  test('the description falls back to the athlete id without a name', () {
    const account = ConnectedAccount(
      service: IntegrationService.rwgps,
      accessToken: 'token',
      athleteId: '7',
    );

    expect(account.toString(), contains('athlete: 7'));
  });
}

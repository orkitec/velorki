import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/integrations/common/data/connected_accounts_repository.dart';
import 'package:velorki/features/integrations/common/domain/connected_account.dart';

import 'support/fakes.dart';

ConnectedAccount _strava({DateTime? expiresAt}) => ConnectedAccount(
  service: IntegrationService.strava,
  accessToken: 'access',
  refreshToken: 'refresh',
  expiresAt: expiresAt ?? DateTime.utc(2026, 9, 12, 12),
  athleteId: '42',
  athleteName: 'Steffen Römer',
  scopes: const <String>['read', 'activity:write'],
);

void main() {
  late InMemorySecureKeyValueStore store;
  late ConnectedAccountsRepository repository;

  setUp(() {
    store = InMemorySecureKeyValueStore();
    repository = ConnectedAccountsRepository(store);
  });

  test('an account round trips through secure storage', () async {
    await repository.save(_strava());

    expect(store.values.keys, contains('integrations.strava.account'));
    final read = await repository.read(IntegrationService.strava);
    expect(read, isNotNull);
    expect(read!.accessToken, 'access');
    expect(read.refreshToken, 'refresh');
    expect(read.expiresAt, DateTime.utc(2026, 9, 12, 12));
    expect(read.athleteId, '42');
    expect(read.athleteName, 'Steffen Römer');
    expect(read.scopes, <String>['read', 'activity:write']);
  });

  test('the two services are stored under separate keys', () async {
    await repository.save(_strava());
    await repository.save(
      const ConnectedAccount(
        service: IntegrationService.rwgps,
        accessToken: 'rwgps-token',
      ),
    );

    final all = await repository.readAll();
    expect(all.keys, hasLength(2));
    expect(all[IntegrationService.rwgps]!.accessToken, 'rwgps-token');

    await repository.remove(IntegrationService.strava);
    expect(await repository.read(IntegrationService.strava), isNull);
    expect(await repository.read(IntegrationService.rwgps), isNotNull);
  });

  test('an unreadable entry is discarded rather than thrown', () async {
    store.values['integrations.strava.account'] = 'not json at all';

    expect(await repository.read(IntegrationService.strava), isNull);
    expect(store.values, isEmpty);
  });

  test('an entry without an access token is discarded', () async {
    store.values['integrations.rwgps.account'] = '{"service":"rwgps"}';

    expect(await repository.read(IntegrationService.rwgps), isNull);
    expect(store.values, isEmpty);
  });

  test('the toString never leaks a token', () {
    expect(_strava().toString(), isNot(contains('access')));
  });

  group('needsRefresh', () {
    final now = DateTime.utc(2026, 9, 12, 12);

    test('is false well before expiry', () {
      expect(
        _strava(expiresAt: now.add(const Duration(minutes: 10)))
            .needsRefresh(now: now),
        isFalse,
      );
    });

    test('is true inside the 60 second leeway', () {
      expect(
        _strava(expiresAt: now.add(const Duration(seconds: 30)))
            .needsRefresh(now: now),
        isTrue,
      );
    });

    test('is false without a refresh token, whatever the expiry', () {
      const account = ConnectedAccount(
        service: IntegrationService.rwgps,
        accessToken: 'token',
      );
      expect(account.needsRefresh(now: now), isFalse);
    });
  });
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/sync/data/cloud_store.dart';
import 'package:velorki/features/sync/data/google_account.dart';

const _account = GoogleAccount(id: 'g-1', email: 'rider@example.com');

/// Tokens counted up, or what [next] says.
class _Tokens implements GoogleSignInService {
  int issued = 0;
  final List<String?> stale = <String?>[];

  /// Thrown or returned instead of a new token, while set.
  Object? next;

  @override
  Future<GoogleAccount> signIn() async => _account;

  @override
  Future<void> signOut() async {}

  @override
  Future<String?> accessToken(GoogleAccount account, {String? stale}) async {
    this.stale.add(stale);
    switch (next) {
      case final Exception e:
        throw e;
      case 'none':
        return null;
    }
    return 'token-${issued++}';
  }
}

void main() {
  group('the Drive token', () {
    late _Tokens tokens;
    late DateTime now;
    late GoogleAccount? account;
    late int lost;
    late GoogleDriveAuth auth;

    setUp(() {
      tokens = _Tokens();
      now = DateTime(2026, 10, 19, 12);
      account = _account;
      lost = 0;
      auth = GoogleDriveAuth(
        account: () => account,
        service: tokens,
        onLost: () async => lost++,
        clock: () => now,
      );
    });

    test('is kept for most of its hour', () async {
      expect(await auth.accessToken(), 'token-0');
      now = now.add(const Duration(minutes: 30));
      expect(await auth.accessToken(), 'token-0');
      now = now.add(const Duration(minutes: 20));
      expect(await auth.accessToken(), 'token-1');
    });

    test('refused by Drive, is replaced', () async {
      expect(await auth.accessToken(), 'token-0');
      expect(await auth.accessToken(stale: 'token-0'), 'token-1');
      expect(tokens.stale.last, 'token-0');
    });

    test('that only the rider can grant again loses the account', () async {
      tokens.next = 'none';
      expect(await auth.accessToken(), isNull);
      expect(lost, 1);
    });

    test('not to be had now is a transient failure', () async {
      tokens.next = Exception('offline');
      await expectLater(
        auth.accessToken(),
        throwsA(
          isA<CloudStoreException>().having(
            (e) => e.failure,
            'failure',
            CloudStoreFailure.transient,
          ),
        ),
      );
      expect(lost, 0);
    });

    test('signed out, there is none and no account', () async {
      account = null;
      expect(auth.accountId, isNull);
      expect(await auth.accessToken(), isNull);
      expect(tokens.stale, isEmpty);
    });
  });

  test('the account signed in outlives a restart, and is forgotten on '
      'sign-out', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    ProviderContainer launch() {
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          googleSignInServiceProvider.overrideWithValue(_Tokens()),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    final first = launch();
    expect(first.read(googleAccountControllerProvider), isNull);
    await first.read(googleAccountControllerProvider.notifier).signIn();
    expect(launch().read(googleAccountControllerProvider), _account);

    await first.read(googleAccountControllerProvider.notifier).signOut();
    expect(first.read(googleAccountControllerProvider), isNull);
    expect(launch().read(googleAccountControllerProvider), isNull);
  });
}

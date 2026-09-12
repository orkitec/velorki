import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/core/plus/app_user_id.dart';

Future<ProviderContainer> _container(Map<String, Object> initial) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a fresh install gets an anonymous id and keeps it', () async {
    final container = await _container(<String, Object>{});

    final first = container.read(appUserIdProvider);
    expect(isAnonymousAppUserId(first), isTrue);
    expect(first, startsWith('anon-'));
    expect(container.read(appUserIdProvider), first);

    // It reached shared_preferences, so the next launch reuses it.
    await Future<void>.delayed(Duration.zero);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(appUserIdPrefsKey), first);
  });

  test('an existing id is reused verbatim', () async {
    final container = await _container(<String, Object>{
      appUserIdPrefsKey: 'anon-already-here',
    });

    expect(container.read(appUserIdProvider), 'anon-already-here');
  });

  test('two generated ids differ', () {
    expect(generateAnonymousAppUserId(), isNot(generateAnonymousAppUserId()));
  });

  test('a RevenueCat id is not treated as anonymous', () {
    expect(isAnonymousAppUserId(r'$RCAnonymousID:abc'), isFalse);
  });
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/recording/data/follow_mode.dart';

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
  test('nothing stored means north stays up', () async {
    final container = await _container(const <String, Object>{});

    expect(container.read(followModeProvider), FollowMode.northUp);
  });

  test('a stored mode comes back', () async {
    final container = await _container(const {'recording.follow': 'headingUp'});

    expect(container.read(followModeProvider), FollowMode.headingUp);
  });

  test('an unknown stored name falls back to north up', () async {
    final container = await _container(const {'recording.follow': 'sideways'});

    expect(container.read(followModeProvider), FollowMode.northUp);
  });

  test('choosing heading up persists it and rebuilds', () async {
    final container = await _container(const <String, Object>{});

    await container
        .read(followModeProvider.notifier)
        .select(FollowMode.headingUp);

    expect(container.read(followModeProvider), FollowMode.headingUp);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('recording.follow'), 'headingUp');
  });

  test(
    'choosing north up again forgets the key rather than storing it',
    () async {
      final container = await _container(const {
        'recording.follow': 'headingUp',
      });

      await container
          .read(followModeProvider.notifier)
          .select(FollowMode.northUp);

      expect(container.read(followModeProvider), FollowMode.northUp);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('recording.follow'), isNull);
    },
  );
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/search/data/osm_details.dart';
import 'package:velorki/features/search/data/osm_details_cache.dart';

/// Tags answered by the test, or [error].
class _FakeSource implements OsmDetailsSource {
  Map<String, String> answer = const <String, String>{};
  Object? error;
  final List<String> asked = <String>[];

  @override
  Future<Map<String, String>> tags(String type, int id) async {
    asked.add('$type/$id');
    final e = error;
    if (e != null) throw e;
    return answer;
  }
}

void main() {
  late DateTime now;
  late _FakeSource source;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    now = DateTime(2026, 10, 5, 10);
    source = _FakeSource();
  });

  /// A fresh container over the device's preferences, as after a restart.
  Future<ProviderContainer> container() async {
    SharedPreferences.resetStatic();
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        osmDetailsSourceProvider.overrideWithValue(source),
        osmDetailsCacheProvider.overrideWithValue(
          OsmDetailsCache(prefs, now: () => now),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test(
    'fetched details are there after a restart, without the network',
    () async {
      source.answer = const {
        'name': 'Café Wolf',
        'amenity': 'cafe',
        'opening_hours': 'Mo-Fr 08:00-18:00',
      };
      final first = await container();
      final repo = first.read(osmDetailsRepositoryProvider);
      expect(repo.cached('node', 1), isNull);
      expect((await repo.fetch('node', 1)).openingHours, 'Mo-Fr 08:00-18:00');
      expect(source.asked, ['node/1']);

      final second = await container();
      final again = second.read(osmDetailsRepositoryProvider).cached('node', 1);
      expect(again?.openingHours, 'Mo-Fr 08:00-18:00');
      expect(source.asked, hasLength(1));
      // Only the tags the card reads are kept.
      final cache = second.read(osmDetailsCacheProvider);
      expect(cache.lookup('node', 1), {'opening_hours': 'Mo-Fr 08:00-18:00'});
      expect(cache.lookup('way', 1), isNull);
    },
  );

  test('not found is kept as nothing to show; a failure is not kept', () async {
    final c = await container();
    final repo = c.read(osmDetailsRepositoryProvider);
    expect((await repo.fetch('node', 2)).isEmpty, isTrue);
    expect(repo.cached('node', 2)?.isEmpty, isTrue);

    source.error = const OsmDetailsException('offline');
    await expectLater(
      repo.fetch('node', 3),
      throwsA(isA<OsmDetailsException>()),
    );
    expect(repo.cached('node', 3), isNull);
  });

  test('details older than seven days are fetched again', () async {
    source.answer = const {'phone': '+1'};
    final c = await container();
    final repo = c.read(osmDetailsRepositoryProvider);
    await repo.fetch('node', 1);
    now = now.add(const Duration(days: 7));
    expect(repo.cached('node', 1)?.phone, '+1');
    now = now.add(const Duration(minutes: 1));
    expect(repo.cached('node', 1), isNull);

    source.answer = const {'phone': '+2'};
    expect((await repo.fetch('node', 1)).phone, '+2');
    expect(repo.cached('node', 1)?.phone, '+2');
    expect(source.asked, hasLength(2));
  });

  test('the oldest places go once the cache is full', () async {
    final c = await container();
    final cache = c.read(osmDetailsCacheProvider);
    for (var id = 0; id < OsmDetailsCache.capacity + 2; id++) {
      await cache.store('node', id, const {'phone': '+1'});
      now = now.add(const Duration(seconds: 1));
    }
    expect(cache.lookup('node', 0), isNull);
    expect(cache.lookup('node', 1), isNull);
    expect(cache.lookup('node', 2), isNotNull);
    expect(cache.lookup('node', OsmDetailsCache.capacity + 1), isNotNull);

    final reloaded = (await container()).read(osmDetailsCacheProvider);
    expect(reloaded.lookup('node', 1), isNull);
    expect(reloaded.lookup('node', 2), isNotNull);
  });

  test('a garbled store reads as empty', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'search.osm_details': '{not json',
    });
    final c = await container();
    final cache = c.read(osmDetailsCacheProvider);
    expect(cache.lookup('node', 1), isNull);
    await cache.store('node', 1, const {'phone': '+1'});
    expect(cache.lookup('node', 1), {'phone': '+1'});
  });
}

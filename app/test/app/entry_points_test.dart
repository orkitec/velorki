// The two entry points, and the rule that keeps them from drifting apart.
//
// `main.dart` and `main_fdroid.dart` must differ in exactly one thing: the
// list of services `startVelorki` is given. Everything else — the container,
// the listeners, the first frame — lives in `startup.dart` and is shared, so
// a feature added to the startup reaches both builds by itself.
//
// The second half of the file is the contract the F-Droid build rests on:
// nothing reachable from `main_fdroid.dart` may import a closed-source
// plugin, because that build's pubspec does not list them. Dart compiles only
// what the entry point reaches, so this is checked by walking the import
// graph rather than by building. See docs/FDROID.md.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The pub packages `tool/fdroid_strip.sh` removes from `pubspec.yaml`.
const List<String> _proprietaryPackages = [
  'purchases_flutter',
  'google_sign_in',
  'google_sign_in_android',
  'google_sign_in_ios',
  'google_sign_in_web',
  'google_sign_in_platform_interface',
  'googleapis',
  'in_app_update',
  'in_app_review',
  'watch_connectivity',
  'live_activities',
];

String _read(String path) => File(path).readAsStringSync();

/// Every `import`, `export` and `part` target in [source], both sides of a
/// conditional one, as written.
Iterable<String> _referencedUris(String source) sync* {
  final directive = RegExp(
    r'^\s*(?:import|export|part)\s+(.*?);',
    multiLine: true,
    dotAll: true,
  );
  final uri = RegExp(r"""['"]([^'"]+)['"]""");
  for (final match in directive.allMatches(source)) {
    for (final found in uri.allMatches(match.group(1)!)) {
      yield found.group(1)!;
    }
  }
}

/// The lib/ files reachable from [entry], by import, export and part.
Set<String> _reachable(String entry) {
  final seen = <String>{};
  final queue = <String>[p.normalize(entry)];
  while (queue.isNotEmpty) {
    final path = queue.removeLast();
    if (!seen.add(path)) continue;
    if (!File(path).existsSync()) continue;
    for (final uri in _referencedUris(_read(path))) {
      final String next;
      if (uri.startsWith('package:velorki/')) {
        next = p.join('lib', uri.substring('package:velorki/'.length));
      } else if (uri.startsWith('dart:') || uri.startsWith('package:')) {
        continue;
      } else {
        next = p.join(p.dirname(path), uri);
      }
      queue.add(p.normalize(next));
    }
  }
  return seen;
}

/// The packages in [_proprietaryPackages] that [source] imports.
Iterable<String> _proprietaryImports(String source) =>
    _referencedUris(source)
        .where((uri) => uri.startsWith('package:'))
        .map((uri) => uri.substring('package:'.length).split('/').first)
        .where(_proprietaryPackages.contains);

void main() {
  group('the two entry points', () {
    final fdroid = _read('lib/main_fdroid.dart');
    final bootstrap = _read('lib/app/bootstrap.dart');
    final main = _read('lib/main.dart');

    test('both reach the app through the one shared startup', () {
      expect(bootstrap, contains('startVelorki('));
      expect(fdroid, contains('startVelorki('));
      expect(main, contains('bootstrap()'));
    });

    test('neither entry point starts the app itself', () {
      // A copy of the startup in main_fdroid.dart is exactly the drift this
      // guards against: it would stop getting everything added to
      // startup.dart, silently, for the one build nobody runs daily.
      for (final entry in {
        'lib/main.dart': main,
        'lib/main_fdroid.dart': fdroid,
        'lib/app/bootstrap.dart': bootstrap,
      }.entries) {
        expect(
          entry.value,
          isNot(contains('ProviderContainer')),
          reason: '${entry.key} must leave the container to startup.dart',
        );
        expect(
          entry.value,
          isNot(contains('runApp')),
          reason: '${entry.key} must leave runApp to startup.dart',
        );
      }
    });

    test('only the shared startup and the browser\'s start call runApp', () {
      final callers = <String>[];
      for (final file in Directory('lib').listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        if (_read(file.path).contains('runApp(')) callers.add(file.path);
      }
      expect(callers..sort(), [
        p.join('lib', 'app', 'startup.dart'),
        p.join('lib', 'app', 'web', 'bootstrap_web.dart'),
      ]);
    });

    test('the F-Droid entry point adds no proprietary service, and takes the '
        'Plus offer away', () {
      expect(fdroid, contains('googleServicesAvailable = false'));
      expect(fdroid, contains('startVelorki('));
      expect(
        fdroid,
        contains('plusOfferedProvider.overrideWithValue(false)'),
        reason: 'every Plus entry point hangs off that one override',
      );
      expect(
        fdroid,
        isNot(contains('proprietaryServiceOverrides')),
        reason: 'installing them would defeat the whole flavour',
      );
    });

    test('the ordinary entry point adds all of them', () {
      expect(bootstrap, contains('proprietaryServiceOverrides()'));
      expect(bootstrap, isNot(contains('googleServicesAvailable')));
    });
  });

  group(
    'nothing the F-Droid build compiles touches a closed-source plugin',
    () {
      test('no file reachable from main_fdroid.dart imports one', () {
        final offenders = <String, List<String>>{};
        for (final path in _reachable('lib/main_fdroid.dart')) {
          if (!File(path).existsSync()) continue;
          final found = _proprietaryImports(_read(path)).toList();
          if (found.isNotEmpty) offenders[path] = found;
        }
        expect(
          offenders,
          isEmpty,
          reason:
              'the F-Droid build drops these packages from pubspec.yaml, so an '
              'import of one from the main_fdroid.dart graph stops that build '
              'compiling. Put the implementation behind a provider override in '
              'lib/app/proprietary_services.dart instead; see docs/FDROID.md.',
        );
      });

      test('the walk really does reach the app, so the check above means '
          'something', () {
        final reachable = _reachable('lib/main_fdroid.dart');
        expect(reachable, contains(p.join('lib', 'app', 'startup.dart')));
        expect(reachable, contains(p.join('lib', 'app', 'app.dart')));
        expect(
          reachable,
          contains(
            p.join(
              'lib',
              'features',
              'planner',
              'presentation',
              'planner_map_host.dart',
            ),
          ),
        );
        expect(reachable.length, greaterThan(300));
      });

      test('and the ordinary build does reach them, in exactly the files that '
          'are allowed to', () {
        final allowed = {
          p.join(
            'lib',
            'features',
            'recording',
            'data',
            'plugin_live_activity.dart',
          ),
          p.join(
            'lib',
            'features',
            'sensors',
            'data',
            'plugin_watch_gateway.dart',
          ),
          p.join(
            'lib',
            'features',
            'store_prompts',
            'data',
            'play_store_services.dart',
          ),
          p.join(
            'lib',
            'features',
            'subscription',
            'data',
            'revenuecat_subscription_service.dart',
          ),
          p.join('lib', 'features', 'sync', 'data', 'drive_cloud_store.dart'),
          p.join('lib', 'features', 'sync', 'data', 'google_cloud.dart'),
          p.join(
            'lib',
            'features',
            'sync',
            'data',
            'google_web_sign_in_web.dart',
          ),
        };
        final importers = <String>{};
        for (final file in Directory('lib').listSync(recursive: true)) {
          if (file is! File || !file.path.endsWith('.dart')) continue;
          if (_proprietaryImports(_read(file.path)).isNotEmpty) {
            importers.add(p.normalize(file.path));
          }
        }
        expect(importers, allowed);
      });
    },
  );
}

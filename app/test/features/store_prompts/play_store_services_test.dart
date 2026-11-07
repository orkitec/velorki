// The store SDKs the F-Droid build leaves out: which source each build picks
// for the update notice, and the two plugin-backed paths behind the
// overrides, over mocked platform channels.
//
// The free side of the same pair — the no-op rating request and the App Store
// lookup every build keeps — is pinned in test/app/proprietary_services_test.dart
// and test/features/store_prompts/app_store_update_source_test.dart.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:velorki/features/store_prompts/data/play_store_services.dart';
import 'package:velorki/features/store_prompts/data/store_services.dart';

const MethodChannel _review = MethodChannel('dev.britannio.in_app_review');
const MethodChannel _update = MethodChannel('de.ffuf.in_app_update/methods');

/// Answers [channel] with [answers] and records what was asked.
List<String> _mock(MethodChannel channel, Map<String, Object?> answers) {
  final calls = <String>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        final answer = answers[call.method];
        if (answer is PlatformException) throw answer;
        return answer;
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  return calls;
}

/// What Play's `checkForUpdate` hands back, with [overrides] applied.
Map<String, Object?> _playAnswer([Map<String, Object?> overrides = const {}]) =>
    {
      'updateAvailability': 2, // updateAvailable
      'immediateAllowed': true,
      'flexibleAllowed': true,
      'availableVersionCode': 42,
      'installStatus': 0, // unknown
      'packageName': 'com.orkitec.velorki',
      'clientVersionStalenessDays': 3,
      'updatePriority': 0,
      ...overrides,
    };

PackageInfo _installed() => PackageInfo(
  appName: 'Velorki',
  packageName: 'com.orkitec.velorki',
  version: '1.2.2',
  buildNumber: '22',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('which source a build looks for updates in', () {
    test('a build with no store SDK: the App Store on iOS, nowhere else', () {
      expect(
        updateSourceWithoutStoreSdk(platform: TargetPlatform.iOS, debug: false),
        isA<AppStoreUpdateSource>(),
      );
      for (final platform in [
        TargetPlatform.android,
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.fuchsia,
      ]) {
        expect(
          updateSourceWithoutStoreSdk(platform: platform, debug: false),
          isNull,
          reason: 'no store SDK, so nothing on $platform',
        );
      }
    });

    test('a build with Google Play: Play on Android, the App Store on iOS', () {
      expect(
        updateSourceWithPlay(platform: TargetPlatform.android, debug: false),
        isA<PlayUpdateSource>(),
      );
      expect(
        updateSourceWithPlay(platform: TargetPlatform.iOS, debug: false),
        isA<AppStoreUpdateSource>(),
      );
      expect(
        updateSourceWithPlay(platform: TargetPlatform.macOS, debug: false),
        isNull,
      );
    });

    test(
      'neither in a browser or a debug build, whose version no store has',
      () {
        for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
          expect(
            updateSourceWithPlay(platform: platform, web: true, debug: false),
            isNull,
          );
          expect(updateSourceWithPlay(platform: platform, debug: true), isNull);
          expect(
            updateSourceWithoutStoreSdk(platform: platform, debug: true),
            isNull,
          );
        }
      },
    );
  });

  group('the system rating dialog', () {
    test('asks the platform whether it can show one, then shows it', () async {
      final calls = _mock(_review, {
        'isAvailable': true,
        'requestReview': null,
      });
      await requestSystemReview();
      expect(calls, ['isAvailable', 'requestReview']);
    });

    test('and asks for nothing where the platform has none', () async {
      final calls = _mock(_review, {'isAvailable': false});
      await requestSystemReview();
      expect(calls, ['isAvailable']);
    });
  });

  group('Google Play as the update source', () {
    test('offers the version code Play names, on Play\'s own page', () async {
      _mock(_update, {'checkForUpdate': _playAnswer()});
      final update = await PlayUpdateSource().check(_installed());
      expect(
        update,
        isA<UpdateAvailable>()
            .having((u) => u.version, 'version', 'code 42')
            .having((u) => u.storeUrl, 'storeUrl', playStorePageUrl)
            .having((u) => u.inApp, 'inApp', isTrue),
      );
    });

    test('says so when Play has already downloaded one', () async {
      _mock(_update, {
        'checkForUpdate': _playAnswer({'installStatus': 11}),
      });
      expect(
        await PlayUpdateSource().check(_installed()),
        isA<UpdateDownloaded>(),
      );
    });

    test('offers nothing when Play has nothing newer', () async {
      _mock(_update, {
        'checkForUpdate': _playAnswer({'updateAvailability': 1}),
      });
      expect(await PlayUpdateSource().check(_installed()), isNull);
    });

    test('a download the rider declined is not a failure', () async {
      _mock(_update, {
        'startFlexibleUpdate': PlatformException(code: 'USER_DENIED_UPDATE'),
      });
      expect(await PlayUpdateSource().download(), isFalse);
    });

    test('nor is one Play could not do', () async {
      _mock(_update, {
        'startFlexibleUpdate': PlatformException(code: 'IN_APP_UPDATE_FAILED'),
      });
      expect(await PlayUpdateSource().download(), isFalse);
    });

    test('a download that worked can then be installed', () async {
      final calls = _mock(_update, {
        'startFlexibleUpdate': null,
        'completeFlexibleUpdate': null,
      });
      expect(await PlayUpdateSource().download(), isTrue);
      await PlayUpdateSource().install();
      expect(calls, ['startFlexibleUpdate', 'completeFlexibleUpdate']);
    });
  });
}

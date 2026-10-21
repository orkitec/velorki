import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/platform_features.dart';
import 'package:velorki/core/links/link_opener.dart';
import 'package:velorki/features/recording/data/recording_recovery.dart';
import 'package:velorki/features/recording/data/recording_service.dart';
import 'package:velorki/features/recording/domain/recording_snapshot.dart';
import 'package:velorki/features/recording/domain/recording_state.dart';
import 'package:velorki/features/settings/data/package_info_provider.dart';
import 'package:velorki/features/store_prompts/application/calm_moment.dart';
import 'package:velorki/features/store_prompts/application/update_notices.dart';
import 'package:velorki/features/store_prompts/data/store_services.dart';
import 'package:velorki/features/store_prompts/presentation/store_update_dialog.dart';

import '../recording/support/fakes.dart';

final DateTime _launch = DateTime.utc(2026, 10, 20, 9);

/// A store that says what the test tells it to.
class _FakeSource implements StoreUpdateSource {
  StoreUpdate? answer;
  bool downloads = true;
  int checks = 0;
  int downloadsStarted = 0;
  int installs = 0;

  @override
  Future<StoreUpdate?> check(PackageInfo installed) async {
    checks++;
    return answer;
  }

  @override
  Future<bool> download() async {
    downloadsStarted++;
    return downloads;
  }

  @override
  Future<void> install() async => installs++;
}

class _Harness {
  _Harness(this.container, this.source, this.service, this.clock);

  final ProviderContainer container;
  final _FakeSource source;
  final FakeRecordingService service;
  final List<DateTime> clock;

  /// Every dialog shown, `true` for the restart one.
  final List<bool> prompts = <bool>[];

  /// What the rider answers in the dialog.
  bool accept = false;

  final List<Uri> opened = <Uri>[];

  void Function()? _stop;

  static Future<_Harness> create({
    StoreUpdate? answer,
    PlatformFeatures features = PlatformFeatures.device,
    String packageName = 'com.orkitec.velorki',
    RecoveryResult recovery = const NoRecovery(),
    Map<String, Object> stored = const <String, Object>{},
  }) async {
    SharedPreferences.setMockInitialValues(stored);
    final prefs = await SharedPreferences.getInstance();
    final source = _FakeSource()..answer = answer;
    final service = FakeRecordingService();
    final clock = <DateTime>[_launch];
    late final _Harness harness;
    final container = ProviderContainer(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        platformFeaturesProvider.overrideWithValue(features),
        recordingServiceProvider.overrideWithValue(service),
        recordingRecoveryProvider.overrideWith((ref) async => recovery),
        packageInfoProvider.overrideWith(
          (ref) async => PackageInfo(
            appName: 'Velorki',
            packageName: packageName,
            version: '1.1.0',
            buildNumber: '11',
          ),
        ),
        storeUpdateSourceProvider.overrideWithValue(source),
        storePromptClockProvider.overrideWithValue(() => clock.last),
        updatePromptProvider.overrideWithValue(({
          required bool downloaded,
        }) async {
          harness.prompts.add(downloaded);
          return harness.accept;
        }),
        linkOpenerProvider.overrideWithValue((url) async {
          harness.opened.add(url);
          return true;
        }),
      ],
    );
    harness = _Harness(container, source, service, clock);
    return harness;
  }

  void start(FakeAsync async) {
    _stop = startUpdateNotices(container);
    async.elapse(updateCheckDelay + calmSettle * 2);
  }

  void dispose() {
    _stop?.call();
    container.dispose();
  }
}

const _newer = UpdateAvailable(version: '1.2.0', storeUrl: appStorePageUrl);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a newer version in the store brings the dialog up after launch, and '
      'Update opens the store page', () async {
    final h = await _Harness.create(answer: _newer)
      ..accept = true;
    fakeAsync((async) {
      h.start(async);
      expect(h.prompts, <bool>[false]);
      expect(h.opened, <Uri>[Uri.parse(appStorePageUrl)]);
    });
    h.dispose();
  });

  test('Later leaves the store closed', () async {
    final h = await _Harness.create(answer: _newer);
    fakeAsync((async) {
      h.start(async);
      expect(h.prompts, <bool>[false]);
      expect(h.opened, isEmpty);
    });
    h.dispose();
  });

  test('nothing newer, nothing shown', () async {
    final h = await _Harness.create();
    fakeAsync((async) {
      h.start(async);
      expect(h.source.checks, 1);
      expect(h.prompts, isEmpty);
    });
    h.dispose();
  });

  test('once per store version', () async {
    final h = await _Harness.create(
      answer: _newer,
      stored: <String, Object>{
        'store_prompts.update_version': '1.2.0',
        'store_prompts.update_at': _launch
            .subtract(const Duration(days: 30))
            .millisecondsSinceEpoch,
      },
    );
    fakeAsync((async) {
      h.start(async);
      expect(h.source.checks, 1);
      expect(h.prompts, isEmpty);
    });
    h.dispose();
  });

  test('not more often than every three days', () async {
    final shown = _launch.subtract(const Duration(days: 2));
    final stored = <String, Object>{
      'store_prompts.update_version': '1.1.5',
      'store_prompts.update_at': shown.millisecondsSinceEpoch,
    };
    final soon = await _Harness.create(answer: _newer, stored: stored);
    fakeAsync((async) {
      soon.start(async);
      expect(soon.prompts, isEmpty);
    });
    soon.dispose();

    final later = await _Harness.create(answer: _newer, stored: stored);
    later.clock.add(shown.add(updateNoticeInterval));
    fakeAsync((async) {
      later.start(async);
      expect(later.prompts, <bool>[false]);
    });
    later.dispose();
  });

  test('never while a ride records: it waits for the ride to end', () async {
    final h = await _Harness.create(answer: _newer);
    fakeAsync((async) {
      h.container.read(rideCalmProvider);
      h.service.emit(
        RecordingSnapshot(
          rideId: 'ride-1',
          status: RecordingStatus.active,
          startedAt: _launch,
        ),
      );
      async.flushMicrotasks();
      h.start(async);
      async.elapse(const Duration(hours: 1));
      expect(h.source.checks, 1);
      expect(h.prompts, isEmpty);
      h.service.emit(
        RecordingSnapshot(
          rideId: 'ride-1',
          status: RecordingStatus.idle,
          startedAt: _launch,
        ),
      );
      async.flushMicrotasks();
      async.elapse(calmSettle * 2);
      expect(h.prompts, <bool>[false]);
    });
    h.dispose();
  });

  test('a ride left unfinished at launch keeps the notice away', () async {
    final h = await _Harness.create(
      answer: _newer,
      recovery: ReattachRecording(
        RecordingState(
          rideId: 'ride-1',
          startedAt: _launch,
          status: RecordingStatus.active,
        ),
      ),
    );
    fakeAsync((async) {
      h.start(async);
      expect(h.source.checks, 0);
      expect(h.prompts, isEmpty);
    });
    h.dispose();
  });

  test('nothing in a browser or in the .dev test build', () async {
    final web = await _Harness.create(
      answer: _newer,
      features: PlatformFeatures.browser,
    );
    fakeAsync((async) {
      web.start(async);
      expect(web.source.checks, 0);
    });
    web.dispose();

    final dev = await _Harness.create(
      answer: _newer,
      packageName: 'com.orkitec.velorki.dev',
    );
    fakeAsync((async) {
      dev.start(async);
      expect(dev.source.checks, 0);
    });
    dev.dispose();
  });

  test('Google Play updates in place: its own sheet, then the restart '
      'dialog', () async {
    final h =
        await _Harness.create(
            answer: const UpdateAvailable(
              version: 'code 12',
              storeUrl: playStorePageUrl,
              inApp: true,
            ),
          )
          ..accept = true;
    fakeAsync((async) {
      h.start(async);
      expect(h.source.downloadsStarted, 1);
      expect(h.prompts, <bool>[true]);
      expect(h.source.installs, 1);
      expect(h.opened, isEmpty);
    });
    h.dispose();
  });

  test('a declined Play download asks nothing more', () async {
    final h = await _Harness.create(
      answer: const UpdateAvailable(
        version: 'code 12',
        storeUrl: playStorePageUrl,
        inApp: true,
      ),
    );
    h.source.downloads = false;
    fakeAsync((async) {
      h.start(async);
      expect(h.source.downloadsStarted, 1);
      expect(h.prompts, isEmpty);
    });
    h.dispose();
  });

  test('an update Play downloaded earlier offers the restart, and Later '
      'leaves it', () async {
    final h = await _Harness.create(answer: const UpdateDownloaded());
    fakeAsync((async) {
      h.start(async);
      expect(h.prompts, <bool>[true]);
      expect(h.source.installs, 0);
    });
    h.dispose();
  });

  test('isNewerVersion compares part by part', () {
    expect(isNewerVersion('1.10.0', than: '1.9.2'), isTrue);
    expect(isNewerVersion('1.2', than: '1.2.0'), isFalse);
    expect(isNewerVersion('1.2.1', than: '1.2'), isTrue);
    expect(isNewerVersion('1.1.0+12', than: '1.1.0'), isFalse);
    expect(isNewerVersion('1.0.9', than: '1.1.0'), isFalse);
  });
}

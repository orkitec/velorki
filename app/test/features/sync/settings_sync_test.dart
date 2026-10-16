import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/features/sync/application/settings_sync.dart';

import 'support/fake_cloud.dart';

void main() {
  late FakeCloudSyncBridge bridge;
  late int applied;

  setUp(() {
    bridge = FakeCloudSyncBridge(FakeCloud(Directory.systemTemp));
    applied = 0;
  });

  Future<(SettingsSync, SharedPreferences)> device(
    Map<String, Object> values,
  ) async {
    SharedPreferences.setMockInitialValues(values);
    final prefs = await SharedPreferences.getInstance();
    return (
      SettingsSync(prefs: prefs, bridge: bridge, onApplied: () => applied++),
      prefs,
    );
  }

  test('a first start takes what iCloud has and sends what it lacks', () async {
    bridge.settings.addAll({
      'appearance.accent': 'ocean',
      'units.system': 'imperial',
    });
    final (sync, prefs) = await device({
      'appearance.accent': 'volt',
      'navigation.leadSeconds': 12,
      'map.camera.lat': 32.6,
    });

    await sync.start();

    expect(prefs.getString('appearance.accent'), 'ocean');
    expect(prefs.getString('units.system'), 'imperial');
    expect(bridge.settings['navigation.leadSeconds'], 12);
    expect(bridge.settings.containsKey('map.camera.lat'), isFalse);
    expect(applied, 1);
  });

  test('later, a change here goes out and one from iCloud comes in', () async {
    final (sync, prefs) = await device({'appearance.mode': 'dark'});
    await sync.start();
    expect(bridge.settings['appearance.mode'], 'dark');

    await prefs.setBool('navigation.voice', false);
    await sync.localChanged();
    expect(bridge.settings['navigation.voice'], false);

    await sync.remoteChanged({'appearance.mode': 'light', 'other.key': 1});
    expect(prefs.getString('appearance.mode'), 'light');
    expect(prefs.containsKey('other.key'), isFalse);
    expect(applied, 1);
  });

  test('a setting put back to its default is removed everywhere', () async {
    final (sync, prefs) = await device({'appearance.bar': 'tinted'});
    await sync.start();
    await prefs.remove('appearance.bar');
    await sync.localChanged();
    expect(bridge.settings.containsKey('appearance.bar'), isFalse);

    await prefs.setString('appearance.bar', 'tinted');
    await sync.localChanged();
    await sync.remoteChanged({'appearance.bar': null});
    expect(prefs.containsKey('appearance.bar'), isFalse);
  });

  test('a restart sends only what changed here meanwhile', () async {
    final (sync, prefs) = await device({'appearance.accent': 'volt'});
    await sync.start();
    // Changed elsewhere while this device was away, and here too.
    bridge.settings['appearance.accent'] = 'ocean';
    await prefs.setString('units.system', 'imperial');
    bridge.settingWrites.clear();

    await sync.start();

    expect(prefs.getString('appearance.accent'), 'ocean');
    expect(bridge.settingWrites, [
      {'units.system': 'imperial'},
    ]);
  });

  test('nothing is sent when nothing changed', () async {
    final (sync, _) = await device({'appearance.accent': 'volt'});
    await sync.start();
    bridge.settingWrites.clear();
    await sync.localChanged();
    await sync.start();
    expect(bridge.settingWrites, isEmpty);
  });

  test('device settings are not among those synced', () {
    for (final key in syncedSettingKeys) {
      expect(key, isNot(startsWith('map.camera')));
      expect(key, isNot(startsWith('sensors.')));
      expect(key, isNot(equals('navigation.voiceId')));
      expect(key, isNot(equals('language.locale')));
    }
  });
}

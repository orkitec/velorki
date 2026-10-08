// Text that lives outside Flutter's own strings must follow the app's
// languages: the iOS InfoPlist.strings (permission prompts), the watch
// app's string catalogue, and Android's per-app language list. A language is
// "an app language" when lib/l10n/app_<lang>.arb exists.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _arbName = RegExp(r'^app_([A-Za-z_]+)\.arb$');

List<String> _languages() {
  final langs = <String>[
    for (final f in Directory('lib/l10n').listSync().whereType<File>())
      if (_arbName.firstMatch(f.uri.pathSegments.last) case final m?)
        m.group(1)!,
  ]..sort();
  return langs;
}

/// Keys of a `.strings` file: `"key" = "value";`, comments skipped.
Set<String> _stringsKeys(String path) {
  final text = File(path)
      .readAsStringSync()
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
      .replaceAll(RegExp(r'//[^\n]*'), '');
  final keys = <String>{};
  final entry = RegExp(
    r'''(?:"((?:[^"\\]|\\.)*)"|([A-Za-z0-9_.$-]+))\s*=\s*"(?:[^"\\]|\\.)*"\s*;''',
  );
  for (final m in entry.allMatches(text)) {
    keys.add(m.group(1) ?? m.group(2)!);
  }
  return keys;
}

/// Top-level `<key>` names of a plist whose value is a `<string>`.
Set<String> _plistStringKeys(String path) => {
  for (final m in RegExp(
    r'<key>([^<]+)</key>\s*<string>',
  ).allMatches(File(path).readAsStringSync()))
    m.group(1)!,
};

bool _isUserVisible(String key) =>
    RegExp(r'^NS\w+UsageDescription$').hasMatch(key);

Set<String> _androidNames(String path) => {
  for (final m in RegExp(
    r'<string\s+([^>]*)>',
  ).allMatches(File(path).readAsStringSync()))
    if (!m.group(1)!.contains('translatable="false"'))
      RegExp(r'name="([^"]+)"').firstMatch(m.group(1)!)!.group(1)!,
};

void main() {
  final langs = _languages();

  test('the app has languages to check', () {
    expect(langs, containsAll(['en', 'de']));
  });

  group('iOS Runner', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final pbx = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    final enKeys = _stringsKeys('ios/Runner/en.lproj/InfoPlist.strings');
    final plistKeys = _plistStringKeys('ios/Runner/Info.plist');

    test('every key of en.lproj is a string key of Info.plist', () {
      expect(plistKeys.containsAll(enKeys), isTrue, reason: '$enKeys');
    });

    test('every user-visible Info.plist string is in en.lproj', () {
      final visible = plistKeys.where(_isUserVisible).toSet();
      expect(visible, isNotEmpty);
      expect(
        enKeys.containsAll(visible),
        isTrue,
        reason: '$visible vs $enKeys',
      );
    });

    final localizations = RegExp(
      r'<key>CFBundleLocalizations</key>\s*<array>(.*?)</array>',
      dotAll: true,
    ).firstMatch(plist);
    final listed = {
      for (final m in RegExp(
        r'<string>([^<]+)</string>',
      ).allMatches(localizations?.group(1) ?? ''))
        m.group(1)!,
    };
    final regions = {
      for (final m in RegExp(
        r'knownRegions = \((.*?)\);',
        dotAll: true,
      ).allMatches(pbx))
        ...m
            .group(1)!
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty),
    };
    final group = RegExp(
      r'/\* InfoPlist\.strings \*/ = \{\s*isa = PBXVariantGroup;\s*children = \((.*?)\);',
      dotAll: true,
    ).firstMatch(pbx);

    for (final lang in langs) {
      test('$lang: InfoPlist.strings, CFBundleLocalizations, project', () {
        expect(
          _stringsKeys('ios/Runner/$lang.lproj/InfoPlist.strings'),
          enKeys,
          reason: 'ios/Runner/$lang.lproj/InfoPlist.strings keys',
        );
        expect(listed, contains(lang), reason: 'CFBundleLocalizations');
        expect(regions, contains(lang), reason: 'knownRegions');
        expect(group, isNotNull, reason: 'InfoPlist.strings variant group');
        final ref = RegExp(
          '(\\w{24}) /\\* $lang \\*/ = \\{isa = PBXFileReference;[^}]*'
          'path = $lang\\.lproj/InfoPlist\\.strings;',
        ).firstMatch(pbx);
        expect(ref, isNotNull, reason: 'file reference for $lang');
        final id = ref!.group(1)!;
        expect(group!.group(1), contains(id), reason: 'in the variant group');
      });
    }

    test('the group is in the Runner group and Resources phase', () {
      final id = RegExp(
        r'(\w{24}) /\* InfoPlist\.strings \*/ = \{\s*isa = PBXVariantGroup',
      ).firstMatch(pbx)!.group(1)!;
      final build = RegExp(
        '(\\w{24}) /\\* InfoPlist\\.strings in Resources \\*/ = '
        '\\{isa = PBXBuildFile; fileRef = $id',
      ).firstMatch(pbx);
      expect(build, isNotNull, reason: 'build file for the group');
      expect(
        RegExp(
          '\\t\\t\\t\\t${build!.group(1)} /\\* InfoPlist\\.strings in Resources \\*/,',
        ).hasMatch(pbx),
        isTrue,
        reason: 'in a Resources phase',
      );
      expect(
        RegExp('\\t\\t\\t\\t$id /\\* InfoPlist\\.strings \\*/,').hasMatch(pbx),
        isTrue,
      );
    });
  });

  group('iOS extensions', () {
    // The share extension and the live activity show only the app name (a
    // brand); the watch app localizes its permission prompts in a catalogue.
    for (final target in [
      'VelorkiShare',
      'VelorkiLiveActivity',
      'VelorkiWatch',
    ]) {
      test('$target: user-visible Info.plist strings are localized', () {
        final visible = _plistStringKeys('ios/$target/Info.plist')
            .where(_isUserVisible)
            .toSet();
        if (visible.isEmpty) return;
        final catalogue = jsonDecode(
          File('ios/$target/InfoPlist.xcstrings').readAsStringSync(),
        ) as Map<String, dynamic>;
        final strings = catalogue['strings'] as Map<String, dynamic>;
        expect(strings.keys.toSet(), visible);
        for (final lang in langs) {
          if (lang == catalogue['sourceLanguage']) continue;
          for (final e in strings.entries) {
            final loc = (e.value as Map)['localizations'] as Map?;
            final value = (loc?[lang] as Map?)?['stringUnit']?['value'];
            expect(value, isA<String>(), reason: '${e.key} in $lang');
            expect((value as String).trim(), isNotEmpty);
          }
        }
      });
    }

    test('the watch catalogue has every language for its strings', () {
      final catalogue = jsonDecode(
        File('ios/VelorkiWatch/Localizable.xcstrings').readAsStringSync(),
      ) as Map<String, dynamic>;
      final strings = catalogue['strings'] as Map<String, dynamic>;
      for (final lang in langs) {
        if (lang == catalogue['sourceLanguage']) continue;
        for (final e in strings.entries) {
          final loc = (e.value as Map)['localizations'] as Map?;
          expect(loc?.containsKey(lang), isTrue, reason: '${e.key} in $lang');
        }
      }
    });
  });

  group('Android', () {
    const res = 'android/app/src/main/res';
    final base = File('$res/values/strings.xml');

    test('values-<lang>/strings.xml match values/strings.xml', () {
      if (!base.existsSync()) return;
      final names = _androidNames(base.path);
      for (final lang in langs.where((l) => l != 'en')) {
        final f = File('$res/values-$lang/strings.xml');
        expect(f.existsSync(), isTrue, reason: '$lang strings.xml');
        expect(_androidNames(f.path), names, reason: lang);
      }
    });

    test('locales_config lists every app language', () {
      final f = File('$res/xml/locales_config.xml');
      expect(f.existsSync(), isTrue);
      final listed = {
        for (final m in RegExp(
          r'<locale\s+android:name="([^"]+)"',
        ).allMatches(f.readAsStringSync()))
          m.group(1)!,
      };
      expect(listed, langs.toSet());
      expect(
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
        contains('android:localeConfig="@xml/locales_config"'),
      );
    });
  });
}

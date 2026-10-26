import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every entry has a name and a notice, each name once', () {
    for (final web in <bool>[false, true]) {
      final entries = velorkiLicenseEntries(web: web);
      expect(entries, isNotEmpty);
      for (final entry in entries) {
        expect(entry.package.trim(), isNotEmpty);
        expect(entry.text.trim(), isNotEmpty, reason: entry.package);
      }
      final names = entries.map((e) => e.package).toList();
      expect(names.toSet(), hasLength(names.length));
    }
  });

  test('MapLibre Native is credited on the phone, not on the web', () {
    List<String> names({required bool web}) =>
        velorkiLicenseEntries(web: web).map((e) => e.package).toList();
    expect(names(web: false), contains('MapLibre Native'));
    expect(names(web: true), isNot(contains('MapLibre Native')));
  });

  test('the registered entries reach the licence page', () async {
    registerVelorkiLicenses();
    final packages = <String>{
      await for (final entry in LicenseRegistry.licenses) ...entry.packages,
    };
    for (final entry in velorkiLicenseEntries(web: kIsWeb)) {
      expect(packages, contains(entry.package));
    }
  });
}

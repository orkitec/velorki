import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:upgrader/upgrader.dart' show ITunesSearchAPI;
import 'package:velorki/features/store_prompts/data/store_services.dart';

final PackageInfo _installed = PackageInfo(
  appName: 'Velorki',
  packageName: 'com.orkitec.velorki',
  version: '1.1.0',
  buildNumber: '11',
);

/// The source over a lookup that answers [results], recording the URLs.
AppStoreUpdateSource _source(
  List<Map<String, Object>> results,
  List<Uri> asked, {
  String os = 'Version 18.1 (Build 22B83)',
}) {
  final api = ITunesSearchAPI()
    ..client = MockClient((request) async {
      asked.add(request.url);
      return http.Response(
        jsonEncode({'resultCount': results.length, 'results': results}),
        200,
      );
    });
  return AppStoreUpdateSource(api: api, osVersion: os);
}

const _listing = 'https://apps.apple.com/de/app/velorki/id6816790504';

void main() {
  test('a newer App Store version is an update, with its page', () async {
    final asked = <Uri>[];
    final update = await _source(<Map<String, Object>>[
      {
        'version': '1.2.0',
        'trackViewUrl': _listing,
        'minimumOsVersion': '15.0',
      },
    ], asked).check(_installed);
    expect(update, isA<UpdateAvailable>());
    final available = update! as UpdateAvailable;
    expect(available.version, '1.2.0');
    expect(available.storeUrl, _listing);
    expect(available.inApp, isFalse);
    // Only the App Store's own lookup, by the bundle id.
    expect(asked.single.host, 'itunes.apple.com');
    expect(asked.single.path, '/lookup');
    expect(asked.single.queryParameters['bundleId'], 'com.orkitec.velorki');
  });

  test('the same or an older version is nothing', () async {
    for (final version in <String>['1.1.0', '1.0.4']) {
      final update = await _source(<Map<String, Object>>[
        {'version': version, 'trackViewUrl': _listing},
      ], <Uri>[]).check(_installed);
      expect(update, isNull, reason: version);
    }
  });

  test('a version this iOS cannot run is nothing', () async {
    final update = await _source(
      <Map<String, Object>>[
        {
          'version': '1.2.0',
          'trackViewUrl': _listing,
          'minimumOsVersion': '17.0',
        },
      ],
      <Uri>[],
      os: 'Version 16.7.10 (Build 20H350)',
    ).check(_installed);
    expect(update, isNull);
  });

  test('an app the store does not list is nothing', () async {
    final update = await _source(
      <Map<String, Object>>[],
      <Uri>[],
    ).check(_installed);
    expect(update, isNull);
  });
}

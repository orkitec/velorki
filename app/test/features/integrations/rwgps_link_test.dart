import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/features/import_export/data/incoming_file_service.dart';
import 'package:velorki/features/import_export/data/track_decoder.dart';
import 'package:velorki/features/import_export/domain/imported_track.dart';
import 'package:velorki/features/integrations/common/data/connected_accounts_repository.dart';
import 'package:velorki/features/integrations/common/domain/connected_account.dart';
import 'package:velorki/features/integrations/rwgps/application/rwgps_link_listener.dart';
import 'package:velorki/features/sharing/data/share_service.dart';

import 'package:velorki/app/app_config.dart';

import '../import_export/support/fixtures.dart';
import '../import_export/support/silent_sources.dart';

void main() {
  group('rwgpsRouteIdOf', () {
    test('reads the id of a route link, with or without .gpx or a tail', () {
      expect(
        rwgpsRouteIdOf(Uri.parse('https://ridewithgps.com/routes/56868123')),
        '56868123',
      );
      expect(
        rwgpsRouteIdOf(
          Uri.parse('https://www.ridewithgps.com/routes/56868123.gpx'),
        ),
        '56868123',
      );
      expect(
        rwgpsRouteIdOf(
          Uri.parse('https://ridewithgps.com/routes/56868123/edit?x=1'),
        ),
        '56868123',
      );
    });

    test("every other link is somebody else's business", () {
      for (final link in <String>[
        'https://ridewithgps.com/trips/1',
        'https://ridewithgps.com/routes/',
        'https://ridewithgps.com/routes/abc',
        'https://ridewithgps.com/routes/..%2Fadmin',
        'http://ridewithgps.com/routes/56868123',
        'https://velorki.com/s/7Kq2mZ0aTb',
        'velorki://share/7Kq2mZ0aTb',
      ]) {
        expect(rwgpsRouteIdOf(Uri.parse(link)), isNull, reason: link);
      }
    });
  });

  group('opening a Ride with GPS link', () {
    late IncomingFileService service;
    late List<ImportCandidate> candidates;
    late List<ImportException> rejections;

    Future<ProviderContainer> containerWith({
      required Future<Uint8List> Function(Uri url) publicFetch,
      ConnectedAccount? account,
      Future<Uint8List> Function(String id)? withAccount,
    }) async {
      service = IncomingFileService(SilentSources());
      addTearDown(service.dispose);
      candidates = <ImportCandidate>[];
      rejections = <ImportException>[];
      service.imports.listen(candidates.add);
      service.rejections.listen(rejections.add);
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          incomingFileServiceProvider.overrideWithValue(service),
          shareGpxFetcherProvider.overrideWithValue(publicFetch),
          connectedAccountProvider(IntegrationService.rwgps)
              .overrideWithValue(account),
          if (withAccount != null)
            rwgpsRouteGpxProvider.overrideWithValue(withAccount),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('a public route comes through the public export', () async {
      final fetched = <Uri>[];
      final container = await containerWith(
        publicFetch: (url) async {
          fetched.add(url);
          return fixtureBytes('ridewithgps.gpx');
        },
      );

      await openRwgpsLink(container, '56868123');
      await Future<void>.delayed(Duration.zero);

      expect(
        fetched.single.toString(),
        'https://ridewithgps.com/routes/56868123.gpx?sub_format=track',
      );
      expect(candidates.single.fileName, 'ridewithgps-56868123.gpx');
      expect(candidates.single.sourceHint, 'rwgps-link');
      expect(rejections, isEmpty);
    });

    test('a private route without an account says what is missing', () async {
      final container = await containerWith(
        publicFetch: (url) async => throw Exception('401'),
      );

      await openRwgpsLink(container, '56868123');
      await Future<void>.delayed(Duration.zero);

      expect(candidates, isEmpty);
      expect(rejections.single.failure, ImportFailure.accountNeeded);
      expect(rejections.single.fileName, 'ridewithgps.com/routes/56868123');
    });

    test('the login page served as the export counts as private', () async {
      final container = await containerWith(
        publicFetch: (url) async =>
            Uint8List.fromList('<!DOCTYPE html><html></html>'.codeUnits),
      );

      await openRwgpsLink(container, '56868123');
      await Future<void>.delayed(Duration.zero);

      expect(rejections.single.failure, ImportFailure.accountNeeded);
    });

    test('a private route with an account comes through the API', () async {
      final asked = <String>[];
      final container = await containerWith(
        publicFetch: (url) async => throw Exception('401'),
        account: const ConnectedAccount(
          service: IntegrationService.rwgps,
          accessToken: 't',
        ),
        withAccount: (id) async {
          asked.add(id);
          return fixtureBytes('komoot.gpx');
        },
      );

      await openRwgpsLink(container, '56868123');
      await Future<void>.delayed(Duration.zero);

      expect(asked, <String>['56868123']);
      expect(candidates.single.fileName, 'ridewithgps-56868123.gpx');
    });

    test('an account that cannot fetch it either is reported', () async {
      final container = await containerWith(
        publicFetch: (url) async => throw Exception('401'),
        account: const ConnectedAccount(
          service: IntegrationService.rwgps,
          accessToken: 't',
        ),
        withAccount: (id) async => throw Exception('403'),
      );

      await openRwgpsLink(container, '56868123');
      await Future<void>.delayed(Duration.zero);

      expect(rejections.single.failure, ImportFailure.linkUnreachable);
    });
  });
}

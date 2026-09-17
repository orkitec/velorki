import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/core/plus/plus_gate.dart';
import 'package:velorki/features/import_export/data/incoming_file_service.dart';
import 'package:velorki/features/import_export/domain/imported_track.dart';
import 'package:velorki/features/integrations/common/data/relay_client_provider.dart';
import 'package:velorki/features/sharing/application/share_link_listener.dart';
import 'package:velorki/features/sharing/data/share_service.dart';
import 'package:velorki/features/sharing/presentation/share_link_button.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';
import 'package:velorki_api/velorki_api.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../import_export/support/fixtures.dart';
import '../integrations/support/fakes.dart';

const List<TrackPoint> _points = <TrackPoint>[
  TrackPoint(LatLng(48, 11), ele: 500),
  TrackPoint(LatLng(48.1, 11.1), ele: 520),
];

void main() {
  group('shareIdOf', () {
    test('reads the id of a velorki://share link', () {
      expect(shareIdOf(Uri.parse('velorki://share/7Kq2mZ0aTb')), '7Kq2mZ0aTb');
    });

    test('reads the id of the public page URL, with or without .gpx', () {
      expect(
        shareIdOf(Uri.parse('https://velorki.com/s/7Kq2mZ0aTb')),
        '7Kq2mZ0aTb',
      );
      expect(
        shareIdOf(Uri.parse('https://velorki.com/s/7Kq2mZ0aTb.gpx')),
        '7Kq2mZ0aTb',
      );
    });

    test('every other link is somebody else\'s business', () {
      expect(shareIdOf(Uri.parse('velorki://oauth/strava?code=1')), isNull);
      expect(shareIdOf(Uri.parse('velorki://share/')), isNull);
      expect(shareIdOf(Uri.parse('https://velorki.com/')), isNull);
    });
  });

  group('shareGpxUrl', () {
    test('joins the relay URL, trailing slash or not', () {
      expect(
        shareGpxUrl('https://relay.test', 'abc')?.toString(),
        'https://relay.test/s/abc.gpx',
      );
      expect(
        shareGpxUrl('https://relay.test/', 'abc')?.toString(),
        'https://relay.test/s/abc.gpx',
      );
    });

    test('a build without a relay has no share URL', () {
      expect(shareGpxUrl('', 'abc'), isNull);
    });
  });

  group('ShareService', () {
    test('a route is stored as a GPX route with its numbers', () async {
      final relay = FakeRelayClient(
        shareLink: const ShareLink(id: 'abc', url: 'https://velorki.com/s/abc'),
      );

      final link = await ShareService(relay).share(
        name: 'Isar loop',
        points: _points,
        kind: ShareKind.route,
        distanceM: 42000,
        ascentM: 380,
      );

      expect(link.url, 'https://velorki.com/s/abc');
      final call = relay.shareCalls.single;
      expect(call.kind, ShareKind.route);
      expect(call.name, 'Isar loop');
      expect(call.gpx, contains('<rte>'));
      expect(call.summary.distanceKm, 42);
      expect(call.summary.ascentM, 380);
    });

    test('a ride is stored as a GPX track with its duration', () async {
      final relay = FakeRelayClient();

      await ShareService(relay).share(
        name: 'Saturday',
        points: _points,
        kind: ShareKind.ride,
        distanceM: 30000,
        duration: const Duration(minutes: 95),
      );

      final call = relay.shareCalls.single;
      expect(call.kind, ShareKind.ride);
      expect(call.gpx, contains('<trk>'));
      expect(call.summary.durationS, 5700);
    });

    test('a relay failure becomes a ShareException', () async {
      final relay = FakeRelayClient(
        failure: const RelayException(
          RelayError(
            code: RelayErrorCode.rateLimited,
            message: 'too many shares today',
          ),
          statusCode: 429,
        ),
      );

      await expectLater(
        ShareService(relay).share(
          name: 'Isar loop',
          points: _points,
          kind: ShareKind.route,
          distanceM: 42000,
        ),
        throwsA(
          isA<ShareException>().having(
            (e) => e.message,
            'message',
            'too many shares today',
          ),
        ),
      );
    });

    test('an empty track is refused before the relay is asked', () async {
      final relay = FakeRelayClient();
      await expectLater(
        ShareService(relay).share(
          name: 'nothing',
          points: const <TrackPoint>[],
          kind: ShareKind.route,
          distanceM: 0,
        ),
        throwsA(isA<ShareException>()),
      );
      expect(relay.shareCalls, isEmpty);
    });
  });

  group('opening a share link', () {
    test('fetches the GPX and sends it into the import preview', () async {
      final gpx = fixtureBytes('komoot.gpx');
      final fetched = <Uri>[];
      final sources = _SilentSources();
      final service = IncomingFileService(sources);
      addTearDown(service.dispose);

      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appConfigProvider.overrideWithValue(
            const AppConfig(apiUrl: 'https://relay.test'),
          ),
          incomingFileServiceProvider.overrideWithValue(service),
          shareGpxFetcherProvider.overrideWithValue((url) async {
            fetched.add(url);
            return gpx;
          }),
        ],
      );
      addTearDown(container.dispose);

      final candidates = <ImportCandidate>[];
      final subscription = service.imports.listen(candidates.add);
      addTearDown(subscription.cancel);

      await openShareLink(container, '7Kq2mZ0aTb');
      await Future<void>.delayed(Duration.zero);

      expect(fetched.single.toString(), 'https://relay.test/s/7Kq2mZ0aTb.gpx');
      expect(candidates.single.fileName, '7Kq2mZ0aTb.gpx');
      expect(candidates.single.sourceHint, 'share-link');
    });

    test('a link that cannot be fetched is dropped, not thrown', () async {
      final sources = _SilentSources();
      final service = IncomingFileService(sources);
      addTearDown(service.dispose);
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appConfigProvider.overrideWithValue(
            const AppConfig(apiUrl: 'https://relay.test'),
          ),
          incomingFileServiceProvider.overrideWithValue(service),
          shareGpxFetcherProvider.overrideWithValue(
            (url) async => throw const ShareException('404'),
          ),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(openShareLink(container, 'gone'), completes);
    });

    test('without a relay there is nothing to fetch', () async {
      var asked = false;
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appConfigProvider.overrideWithValue(const AppConfig()),
          shareGpxFetcherProvider.overrideWithValue((url) async {
            asked = true;
            return Uint8List(0);
          }),
        ],
      );
      addTearDown(container.dispose);

      await openShareLink(container, 'abc');

      expect(asked, isFalse);
    });
  });

  group('ShareLinkButton', () {
    Future<ProviderContainer> pump(
      WidgetTester tester, {
      required FakeRelayClient relay,
      bool entitled = true,
      bool withRelay = true,
    }) async {
      await tester.binding.setSurfaceSize(const Size(1000, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          relayClientProvider.overrideWithValue(withRelay ? relay : null),
          clipboardWriterProvider.overrideWithValue((text) async {}),
          textSharerProvider.overrideWithValue((text, {subject}) async {}),
        ],
      );
      addTearDown(container.dispose);
      container.read(plusEntitledProvider.notifier).value = entitled;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildLightTheme(),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: ShareLinkButton(
                name: 'Isar loop',
                points: _points,
                kind: ShareKind.route,
                distanceM: 42000,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('creates the link and shows it', (tester) async {
      final relay = FakeRelayClient(
        shareLink: const ShareLink(id: 'abc', url: 'https://velorki.com/s/abc'),
      );
      await pump(tester, relay: relay);

      await tester.tap(find.text('Share link'));
      await tester.pumpAndSettle();

      expect(find.text('https://velorki.com/s/abc'), findsOneWidget);
      expect(relay.shareCalls, hasLength(1));

      await tester.tap(find.text('Copy link'));
      await tester.pumpAndSettle();
      expect(find.text('Link copied.'), findsOneWidget);
    });

    testWidgets('without Velorki Plus it offers the paywall instead', (
      tester,
    ) async {
      final relay = FakeRelayClient();
      await pump(tester, relay: relay, entitled: false);

      await tester.tap(find.text('Share link'));
      await tester.pumpAndSettle();

      expect(
        find.text('Link sharing is part of Velorki Plus.'),
        findsOneWidget,
      );
      expect(find.text('See Velorki Plus'), findsOneWidget);
      expect(relay.shareCalls, isEmpty);
    });

    testWidgets('a build without a relay hides the button', (tester) async {
      await pump(tester, relay: FakeRelayClient(), withRelay: false);
      expect(find.text('Share link'), findsNothing);
    });

    testWidgets('a failure is reported', (tester) async {
      final relay = FakeRelayClient(
        failure: const RelayException(
          RelayError(
            code: RelayErrorCode.unavailable,
            message: 'the server is down',
          ),
          statusCode: 503,
        ),
      );
      await pump(tester, relay: relay);

      await tester.tap(find.text('Share link'));
      await tester.pumpAndSettle();

      expect(find.textContaining('the server is down'), findsOneWidget);
    });
  });
}

/// An [IncomingSources] that never delivers anything by itself, so a test can
/// drive [IncomingFileService.addBytes] alone.
class _SilentSources implements IncomingSources {
  @override
  Future<List<Never>> initialSharedMedia() async => const [];

  @override
  Stream<List<Never>> sharedMediaStream() => const Stream.empty();

  @override
  Future<Uri?> initialLink() async => null;

  @override
  Stream<Uri> linkStream() => const Stream.empty();

  @override
  Stream<String> openedFilePaths() => const Stream.empty();

  @override
  Future<Uint8List?> readFile(String path) async => null;

  @override
  Future<Uint8List?> readContentUri(Uri uri) async => null;
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/app/platform_features.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/map/data/offline_regions_repository.dart';
import 'package:velorki/features/map/presentation/stops_download_chip.dart';
import 'package:velorki/features/map/testing/testing.dart';
import 'package:velorki/features/offline/application/area_download_activity.dart';
import 'package:velorki/features/offline/presentation/download_visible_area.dart';
import 'package:velorki/features/routing_tiles/data/brouter_assets.dart';
import 'package:velorki/features/routing_tiles/data/brouter_storage.dart';
import 'package:velorki/features/routing_tiles/data/segments_manifest_service.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';
import '../map/support/offline_fakes.dart';
import '../routing_tiles/support/fake_segments.dart';

final Uint8List _body = Uint8List.fromList(utf8.encode('rd5'));

/// Stands in for a map screen: it owns the map and starts the download the
/// way the planner does, and hands the chip what the download is doing.
class _Host extends ConsumerStatefulWidget {
  const _Host(this.map);

  final MapController map;

  @override
  ConsumerState<_Host> createState() => _HostState();
}

class _HostState extends ConsumerState<_Host> {
  @override
  Widget build(BuildContext context) {
    final activity = ref.watch(areaDownloadActivityProvider);
    return Scaffold(
      body: Center(
        child: StopsDownloadChip(
          onDownload: () =>
              unawaited(downloadVisibleArea(context, ref, widget.map)),
          downloading: activity != null,
          progress: activity?.fraction,
          onClose: () {},
          onCancel: () => unawaited(cancelVisibleAreaDownload(context, ref)),
        ),
      ),
    );
  }
}

class _Harness {
  _Harness()
    : db = VelorkiDatabase.memory(),
      storage = BrouterStorage(tempDir('velorki-chip')),
      adapter = FakeSegmentsAdapter((options) {
        if (options.uri.path.endsWith('manifest.json')) {
          return FakeSegmentsResponse.json(<String, Object?>{
            'formatVersion': '11.2',
            'tiles': <Object?>[
              <String, Object?>{
                'tile': 'E10_N45',
                'bytes': _body.length,
                'updatedAt': '2026-09-12T01:03:00Z',
              },
            ],
          });
        }
        return FakeSegmentsResponse.bytes(_body);
      }) {
    storage.segments.createSync(recursive: true);
    storage.profiles.createSync(recursive: true);
  }

  final VelorkiDatabase db;
  final BrouterStorage storage;
  final FakeSegmentsAdapter adapter;
  final FakeOfflineMapApi api = FakeOfflineMapApi();

  List<Override> get overrides => <Override>[
    velorkiDatabaseProvider.overrideWithValue(db),
    appConfigProvider.overrideWithValue(
      const AppConfig(segmentsUrl: 'https://mirror.test/segments4'),
    ),
    brouterStorageProvider.overrideWith((ref) async => storage),
    brouterProfilesProvider.overrideWith((ref) async => storage.profiles),
    segmentsDioProvider.overrideWithValue(segmentsDioWith(adapter)),
    offlineMapApiProvider.overrideWithValue(api),
  ];
}

FakeMapController _map() => FakeMapController()
  ..visibleBounds = const BoundingBox(
    south: 46.0,
    west: 10.5,
    north: 47.0,
    east: 11.5,
  );

/// A chip over a map whose routing tile is on the device already, so that
/// what is left to download is the map pack, which the test can hold open.
Future<_Harness> _pump(WidgetTester tester, MapController map) async {
  final h = _Harness();
  addTearDown(h.db.close);
  File('${h.storage.segments.path}/E10_N45.rd5').writeAsStringSync('rd5');
  await h.db.routingTilesDao.markReady(
    'E10_N45',
    bytes: 3,
    updatedAt: DateTime.utc(2026, 9, 12, 1, 3),
    formatVersion: '11.2',
  );
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        platformFeaturesProvider.overrideWithValue(PlatformFeatures.device),
        ...h.overrides,
      ],
      child: testApp(home: _Host(map)),
    ),
  );
  await tester.pumpAndSettle();
  return h;
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

Future<void> _untilTrue(WidgetTester tester, bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!done() && DateTime.now().isBefore(deadline)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Pumps, with real time for the manifest to come, until [finder] is there.
/// Not `pumpAndSettle`: the chip's spinner never settles.
Future<void> _until(WidgetTester tester, Finder finder) =>
    _untilTrue(tester, () => finder.evaluate().isNotEmpty);

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.text(l10n.mapStopsDownload));
  await _until(tester, find.text(l10n.commonCancel));
}

Future<void> _startDownload(WidgetTester tester) async {
  await _openDialog(tester);
  await tester.tap(find.text(l10n.offlineDialogDownload).last);
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('the chip downloads the visible area in place and shows it', (
    tester,
  ) async {
    final release = Completer<void>();
    final map = _map();
    final h = await _pump(tester, map);
    h.api.duringDownload = () => release.future;

    expect(find.text(l10n.mapStopsDownload), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    await _startDownload(tester);
    await _untilTrue(tester, () => h.api.downloads.isNotEmpty);

    // The map pack for the visible bounds, started without a screen change.
    expect(h.api.downloads, hasLength(1));
    expect(h.api.downloads.single.bounds, map.visibleBounds);
    expect(find.text(l10n.mapOfflineDownloading), findsOneWidget);
    expect(find.text(l10n.mapStopsDownload), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // While it downloads the button at the end stops it, after asking.
    expect(find.byTooltip(l10n.routingTilesCancelDownload), findsOneWidget);

    // A second tap while it runs opens nothing and starts nothing.
    await tester.tap(find.text(l10n.mapOfflineDownloading));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text(l10n.commonCancel), findsNothing);
    expect(h.api.downloads, hasLength(1));

    release.complete();
    await _until(tester, find.text(l10n.mapStopsDownload));
    await tester.pumpAndSettle();
    expect(find.text(l10n.mapStopsDownload), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(h.api.downloads, hasLength(1));
    await _unmount(tester);
  });

  testWidgets('cancelling the dialog leaves the chip as it was', (
    tester,
  ) async {
    final h = await _pump(tester, _map());

    await _openDialog(tester);
    await tester.tap(find.text(l10n.commonCancel));
    await tester.pumpAndSettle();

    expect(h.api.downloads, isEmpty);
    expect(find.text(l10n.mapStopsDownload), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('a failed download says so in a snackbar', (tester) async {
    final h = await _pump(tester, _map());
    h.api.failWith = StateError('no space');

    await _startDownload(tester);
    await _until(tester, find.byType(SnackBar));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining(l10n.offlineMapFailed('')), findsOneWidget);
    expect(find.text(l10n.mapStopsDownload), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('with no area on screen the chip says why instead of starting', (
    tester,
  ) async {
    final map = FakeMapController();
    final h = await _pump(tester, map);

    await tester.tap(find.text(l10n.mapStopsDownload));
    await tester.pumpAndSettle();

    expect(find.text(l10n.offlineNeedsMap), findsOneWidget);
    expect(find.text(l10n.commonCancel), findsNothing);
    expect(h.api.downloads, isEmpty);
    await _unmount(tester);
  });

  testWidgets('the button at the end stops the download after asking, and '
      'the chip offers the area again', (tester) async {
    final map = _map();
    final h = await _pump(tester, map);
    h.api.duringDownload = () => Completer<void>().future;

    await _startDownload(tester);
    await _untilTrue(tester, () => h.api.downloads.isNotEmpty);
    expect(find.text(l10n.mapOfflineDownloading), findsOneWidget);

    // Asked first: keeping it changes nothing.
    await tester.tap(find.byTooltip(l10n.routingTilesCancelDownload));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(l10n.offlineCancelTitle), findsOneWidget);
    await tester.tap(find.text(l10n.offlineCancelKeep));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(l10n.mapOfflineDownloading), findsOneWidget);

    await tester.tap(find.byTooltip(l10n.routingTilesCancelDownload));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(l10n.routingTilesCancelDownload),
      ),
    );
    await _until(tester, find.text(l10n.mapStopsDownload));
    await tester.pumpAndSettle();

    expect(find.text(l10n.mapStopsDownload), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(h.api.live, isEmpty);
    await _unmount(tester);
  });
}

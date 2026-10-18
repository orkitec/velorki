import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/core/db/tables/routes.dart';
import 'package:velorki/features/navigation/application/route_turn_generator.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/planner/domain/saved_route.dart';
import 'package:velorki/features/recording/application/recording_controller.dart';
import 'package:velorki/features/recording/domain/follow_choice.dart';
import 'package:velorki/features/recording/presentation/recording_screen.dart';
import 'package:velorki/features/routing_tiles/data/brouter_assets.dart';
import 'package:velorki/features/routing_tiles/data/brouter_storage.dart';
import 'package:velorki/features/routing_tiles/data/segments_manifest_service.dart';
import 'package:velorki/features/routing_tiles/presentation/routing_tiles_screen.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

import '../../support/app.dart';
import '../recording/support/pump.dart';
import '../routing_tiles/support/fake_segments.dart';
import 'support/fake_turns.dart';

const TileName _tile = TileName(10, 45);

/// The record tab, following [route]; the turns are made by [backend] over
/// a coverage that is missing whatever [missing] says.
class _Setup {
  _Setup() : harness = RecordingHarness();

  final RecordingHarness harness;
  final TrackFollowingBackend backend = TrackFollowingBackend();
  List<TileName> missing = const <TileName>[];
  late SavedRoute route;

  RouteRepository get routes => RouteRepository(
    harness.planner.db.routesDao,
    clock: () => DateTime.utc(2026, 10, 12, 10),
  );

  List<Override> get overrides => [
    routeTurnGeneratorProvider.overrideWith(
      (ref) => RouteTurnGenerator(
        service: () => fakeTurnService(backend, missing: () => missing),
        routes: ref.watch(routeRepositoryProvider),
      ),
    ),
  ];

  Future<void> pump(
    WidgetTester tester, {
    bool withTurns = false,
    List<Override> extra = const <Override>[],
  }) async {
    route = await routes.saveImportedRoute(
      name: 'Plain track',
      points: leggedTrack(),
      source: RouteSource.importedGpx,
      turns: withTurns
          ? const <TurnHint>[TurnHint(pointIndex: 30, kind: TurnKind.right)]
          : const <TurnHint>[],
    );
    await pumpRecordingScreen(
      tester,
      const RecordingScreen(),
      harness: harness,
      extraOverrides: [...overrides, ...extra],
    );
    await tester.pump();
    ProviderScope.containerOf(tester.element(find.byType(RecordingScreen)))
        .read(recordingControllerProvider.notifier)
        .choose(FollowSaved(route.id));
    await tester.pumpAndSettle();
  }

  Future<SavedRoute> saved() async => (await routes.routeById(route.id))!;
}

/// What the tiles screen needs to show the tiles a route is missing.
List<Override> _tilesScreen(BrouterStorage storage) => <Override>[
  appConfigProvider.overrideWithValue(
    const AppConfig(segmentsUrl: 'https://mirror.test/segments4'),
  ),
  brouterStorageProvider.overrideWith((ref) async => storage),
  brouterProfilesProvider.overrideWith((ref) async => storage.profiles),
  segmentsDioProvider.overrideWithValue(
    segmentsDioWith(
      FakeSegmentsAdapter(
        (_) => FakeSegmentsResponse.json(<String, Object?>{
          'formatVersion': '11.2',
          'tiles': <Object?>[
            <String, Object?>{
              'tile': 'E10_N45',
              'bytes': 131072000,
              'updatedAt': '2026-09-12T01:03:00Z',
            },
          ],
        }),
      ),
    ),
  ),
];

void main() {
  testWidgets('a route with turns starts at once', (tester) async {
    final s = _Setup();
    await s.pump(tester, withTurns: true);

    await tester.tap(find.text(l10n.recordingStart));
    await tester.pumpAndSettle();

    expect(find.text(l10n.turnsMissingTitle), findsNothing);
    expect(s.harness.service.calls, ['start(${s.route.id})']);
    await unmountApp(tester);
  });

  testWidgets('without turns the rider is asked; "Ride without" starts the '
      'ride and makes none', (tester) async {
    final s = _Setup();
    await s.pump(tester);

    await tester.tap(find.text(l10n.recordingStart));
    await tester.pumpAndSettle();

    expect(find.text(l10n.turnsMissingTitle), findsOneWidget);
    expect(find.text(l10n.turnsMissingBody), findsOneWidget);
    await tester.tap(find.text(l10n.turnsMissingRideWithout));
    await tester.pumpAndSettle();

    expect(s.harness.service.calls, ['start(${s.route.id})']);
    expect(s.backend.queries, isEmpty);
    expect((await s.saved()).turns, isEmpty);
    await unmountApp(tester);
  });

  testWidgets('"Create" makes the turns from the map, then starts the ride', (
    tester,
  ) async {
    final s = _Setup();
    await s.pump(tester);

    await tester.tap(find.text(l10n.recordingStart));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.turnsMissingCreate));
    await tester.pumpAndSettle();

    expect(s.backend.queries, isNotEmpty);
    final saved = await s.saved();
    expect(saved.turnsGenerated, isTrue);
    expect(saved.turns.first.pointIndex, 30);
    expect(s.harness.service.calls, ['start(${s.route.id})']);
    await unmountApp(tester);
  });

  testWidgets('backing out of the question starts nothing', (tester) async {
    final s = _Setup();
    await s.pump(tester);

    await tester.tap(find.text(l10n.recordingStart));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(find.text(l10n.turnsMissingTitle), findsNothing);
    expect(s.harness.service.calls, isEmpty);
    await unmountApp(tester);
  });

  group('without the region on the phone', () {
    late BrouterStorage storage;

    setUp(() {
      storage = BrouterStorage(tempDir('velorki-turns-tiles'))
        ..segments.createSync(recursive: true)
        ..profiles.createSync(recursive: true);
    });

    testWidgets('"Create" offers the download first and carries on once the '
        'tiles are there', (tester) async {
      final s = _Setup()..missing = const <TileName>[_tile];
      await s.pump(tester, extra: _tilesScreen(storage));

      await tester.tap(find.text(l10n.recordingStart));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.turnsMissingCreate));
      await tester.pumpAndSettle();

      expect(find.byType(RoutingTilesScreen), findsOneWidget);
      expect(find.text('E10_N45'), findsOneWidget);
      expect(s.harness.service.calls, isEmpty);

      // Downloaded, and back.
      s.missing = const <TileName>[];
      await _back(tester);
      await tester.pumpAndSettle();

      expect((await s.saved()).turnsGenerated, isTrue);
      expect(s.harness.service.calls, ['start(${s.route.id})']);
      await unmountApp(tester);
    });

    testWidgets('back without the download, the rider is told and may still '
        'ride without', (tester) async {
      final s = _Setup()..missing = const <TileName>[_tile];
      await s.pump(tester, extra: _tilesScreen(storage));

      await tester.tap(find.text(l10n.recordingStart));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.turnsMissingCreate));
      await tester.pumpAndSettle();
      await _back(tester);
      await tester.pumpAndSettle();

      expect(find.text(l10n.turnsCreateNoRegion), findsOneWidget);
      expect(s.backend.queries, isEmpty);
      await tester.tap(find.text(l10n.turnsMissingRideWithout));
      await tester.pumpAndSettle();

      expect(s.harness.service.calls, ['start(${s.route.id})']);
      expect((await s.saved()).turnsGenerated, isFalse);
      await unmountApp(tester);
    });
  });

  testWidgets('when the map cannot follow the route, the rider is told and '
      'may cancel', (tester) async {
    final s = _Setup();
    await s.pump(tester);
    s.backend.failAt.add(s.route.geometry.first.pos);

    await tester.tap(find.text(l10n.recordingStart));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.turnsMissingCreate));
    await tester.pumpAndSettle();

    expect(find.text(l10n.turnsCreateFailed), findsOneWidget);
    await tester.tap(find.text(l10n.commonCancel));
    await tester.pumpAndSettle();

    expect(s.harness.service.calls, isEmpty);
    await unmountApp(tester);
  });
}

/// Back from the tiles screen, as the back arrow does in any language.
Future<void> _back(WidgetTester tester) async {
  Navigator.of(tester.element(find.byType(RoutingTilesScreen))).pop();
  await tester.pump();
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart'
    show CupertinoActivityIndicator, CupertinoSliverRefreshControl;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/features/library/data/library_section.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/planner/domain/routing_options.dart';
import 'package:velorki/features/planner/domain/waypoint.dart';
import 'package:velorki/features/recording/data/ride_repository.dart';
import 'package:velorki/features/sync/application/cloud_sync_controller.dart';
import 'package:velorki/features/sync/data/cloud_sync_bridge.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';
import '../../support/format.dart';
import '../planner/support/fakes.dart' show syntheticRoute;
import '../recording/support/pump.dart';
import '../sync/support/fake_cloud.dart';

const List<Waypoint> _waypoints = [
  Waypoint(pos: LatLng(48.0, 11.0), kind: WaypointKind.start),
  Waypoint(pos: LatLng(48.04, 11.04), kind: WaypointKind.end),
];

List<TrackPoint> _track() => <TrackPoint>[
  for (var i = 0; i < 60; i++)
    TrackPoint(
      LatLng(48 + i * 0.0002, 11),
      ele: 500 + (i < 30 ? i * 2.0 : (60 - i) * 2.0),
      time: DateTime.utc(2026, 9, 12, 10, 0, i),
    ),
];

Future<void> _seedRoute(RecordingHarness h) =>
    RouteRepository(
      h.planner.db.routesDao,
      clock: () => DateTime.utc(2026, 9, 12, 10),
    ).savePlannedRoute(
      name: 'Isar loop',
      route: syntheticRoute(),
      waypoints: _waypoints,
      options: const RoutingOptions(),
    );

Future<void> _seedRide(RecordingHarness h) =>
    RideRepository(h.planner.db.ridesDao).finalizeRide(
      rideId: 'ride-1',
      name: 'Morning loop',
      points: _track(),
      startedAt: DateTime.utc(2026, 9, 12, 10),
      endedAt: DateTime.utc(2026, 9, 12, 10, 0, 59),
    );

void main() {
  group('pull to refresh', _pullRefreshTests);
  testWidgets('the library offers both sections and starts on routes', (
    tester,
  ) async {
    final h = RecordingHarness();
    await _seedRoute(h);
    await _seedRide(h);
    await pumpRecordingApp(tester, initialLocation: libraryRoute, harness: h);
    await tester.pumpAndSettle();

    final switcher = find.byType(SegmentedButton<LibrarySection>);
    expect(switcher, findsOneWidget);
    expect(
      find.descendant(of: switcher, matching: find.text(l10n.libraryRoutes)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: switcher, matching: find.text(l10n.libraryRides)),
      findsOneWidget,
    );

    // Nothing stored yet, so the routes half shows and the rides stay away.
    expect(find.text('Isar loop'), findsOneWidget);
    expect(find.text('Morning loop'), findsNothing);
    await unmountApp(tester);
  });

  testWidgets('the routes section keeps its list, import buttons and menu', (
    tester,
  ) async {
    final h = RecordingHarness();
    await _seedRoute(h);
    await pumpRecordingApp(tester, initialLocation: libraryRoute, harness: h);
    await tester.pumpAndSettle();

    expect(find.text('Isar loop'), findsOneWidget);
    expect(
      find.text(
        l10n.libraryRouteSubtitle(
          testDate(DateTime.utc(2026, 9, 12, 10).toLocal()),
          testDistance(10000),
          testHeight(120),
        ),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.more_vert), findsOneWidget);

    // The file import stays in the app bar next to the new switch. Its
    // sibling, the import-from-service menu, hides itself when no API URL is
    // configured, which is the case in tests.
    expect(find.byIcon(Icons.file_open_outlined), findsOneWidget);

    await tester.tap(find.text('Isar loop'));
    await tester.pumpAndSettle();
    // The card's title now, with the list gone.
    expect(find.text('Isar loop'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('switching to rides lists every ride and remembers the choice', (
    tester,
  ) async {
    final h = RecordingHarness();
    await _seedRoute(h);
    await _seedRide(h);
    await pumpRecordingApp(tester, initialLocation: libraryRoute, harness: h);
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.libraryRides));
    await tester.pumpAndSettle();

    expect(find.text('Morning loop'), findsOneWidget);
    expect(find.text(l10n.libraryRidesCount(1).toUpperCase()), findsOneWidget);
    expect(find.text('Isar loop'), findsNothing);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('library.section'), 'rides');

    // And back again, which forgets the choice rather than storing the
    // default.
    await tester.tap(find.text(l10n.libraryRoutes));
    await tester.pumpAndSettle();

    expect(find.text('Isar loop'), findsOneWidget);
    expect(find.text('Morning loop'), findsNothing);
    expect(prefs.getString('library.section'), isNull);
    await unmountApp(tester);
  });

  testWidgets('the stored choice is restored on the next start', (
    tester,
  ) async {
    final h = RecordingHarness();
    await _seedRoute(h);
    await _seedRide(h);
    await pumpRecordingApp(
      tester,
      initialLocation: libraryRoute,
      harness: h,
      preferences: const {'library.section': 'rides'},
    );
    await tester.pumpAndSettle();

    expect(find.text('Morning loop'), findsOneWidget);
    expect(find.text('Isar loop'), findsNothing);
    await unmountApp(tester);
  });

  testWidgets('an empty rides section says so', (tester) async {
    await pumpRecordingApp(
      tester,
      initialLocation: libraryRoute,
      preferences: const {'library.section': 'rides'},
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.recordingNoRides), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('tapping a ride opens its detail screen', (tester) async {
    final h = RecordingHarness();
    await _seedRide(h);
    await pumpRecordingApp(
      tester,
      initialLocation: libraryRoute,
      harness: h,
      preferences: const {'library.section': 'rides'},
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Morning loop'));
    await tester.pumpAndSettle();

    expect(find.text(l10n.statDistance.toUpperCase()), findsOneWidget);
    // Twice: the stat tile, and the column of the splits table.
    expect(find.text(l10n.statMovingTime.toUpperCase()), findsWidgets);
    expect(find.text(l10n.rideDetailExportGpx), findsWidgets);
    await unmountApp(tester);
  });
}

void _pullRefreshTests() {
  late Directory dir;
  late _GatedBridge bridge;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('library_pull');
    bridge = _GatedBridge(FakeCloud(dir));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> pump(
    WidgetTester tester, {
    required bool syncOn,
    int moreRoutes = 30,
  }) async {
    final h = RecordingHarness();
    await _seedRoute(h);
    for (var i = 0; i < moreRoutes; i++) {
      await RouteRepository(
        h.planner.db.routesDao,
        clock: () => DateTime.utc(2026, 9, 11, 10, i),
      ).savePlannedRoute(
        name: 'Route $i',
        route: syntheticRoute(),
        waypoints: _waypoints,
        options: const RoutingOptions(),
      );
    }
    await pumpRecordingApp(
      tester,
      initialLocation: libraryRoute,
      harness: h,
      extraOverrides: [
        cloudSyncBridgeProvider.overrideWithValue(bridge),
        cloudSyncOutboxProvider.overrideWith((ref) async => dir),
        cloudSyncEnabledProvider.overrideWith(() => _Enabled(syncOn)),
      ],
    );
    ProviderScope.containerOf(
      tester.element(find.byType(SegmentedButton<LibrarySection>)),
    ).listen(cloudSyncControllerProvider, (_, _) {});
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await unmountApp(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// Pulls the list down from its first row, lets go and lets the list
  /// come to rest, which with a fetch under way is held open.
  Future<void> pull(WidgetTester tester) async {
    final g = await tester.startGesture(
      tester.getCenter(find.text('Isar loop')),
    );
    for (var i = 0; i < 20; i++) {
      await g.moveBy(const Offset(0, 40));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pullHoldsUntilFetched(WidgetTester tester) async {
    final before = bridge.fetchRequests;
    final segments = find.byType(SegmentedButton<LibrarySection>);
    final switchRect = tester.getRect(segments);
    final rowTop = tester.getTopLeft(find.text('Isar loop')).dy;
    // Idle it paints nothing, so the finder has to look offstage too.
    expect(
      find.byType(CupertinoSliverRefreshControl, skipOffstage: false),
      findsOneWidget,
    );
    expect(find.byType(CupertinoActivityIndicator), findsNothing);

    bridge.gate = Completer<void>();
    await pull(tester);
    expect(bridge.fetchRequests, before + 1);
    // Held open while the fetch runs: the spinner in the space opened
    // between the switch and the first row, the switch where it was.
    final spinner = find.byType(CupertinoActivityIndicator);
    expect(spinner, findsOneWidget);
    expect(tester.getRect(segments), switchRect);
    expect(
      tester.getRect(spinner).top,
      greaterThanOrEqualTo(switchRect.bottom),
    );
    final heldTop = tester.getTopLeft(find.text('Isar loop')).dy;
    expect(heldTop, greaterThan(rowTop + 40));
    expect(tester.getRect(spinner).bottom, lessThanOrEqualTo(heldTop));

    // Still held a while later.
    await tester.pump(const Duration(seconds: 2));
    expect(tester.getTopLeft(find.text('Isar loop')).dy, heldTop);

    bridge.gate!.complete();
    bridge.gate = null;
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    expect(tester.getTopLeft(find.text('Isar loop')).dy, rowTop);
    expect(tester.getRect(segments), switchRect);
  }

  testWidgets('pulling the list holds it open until iCloud has answered', (
    tester,
  ) async {
    await pump(tester, syncOn: true);
    await pullHoldsUntilFetched(tester);
    await finish(tester);
  });

  testWidgets('a list that fits can be pulled too', (tester) async {
    await pump(tester, syncOn: true, moreRoutes: 1);
    await pullHoldsUntilFetched(tester);
    await finish(tester);
  });

  testWidgets('with sync off the list has no pull', (tester) async {
    await pump(tester, syncOn: false);
    expect(
      find.byType(CupertinoSliverRefreshControl, skipOffstage: false),
      findsNothing,
    );
    expect(find.byType(RefreshIndicator), findsNothing);
    await unmountApp(tester);
  });
}

/// A device's engine whose [fetchNow] waits for [gate], when there is one.
class _GatedBridge extends FakeCloudSyncBridge {
  _GatedBridge(super.cloud);

  Completer<void>? gate;

  @override
  Future<void> fetchNow() async {
    final wait = gate?.future;
    final fetched = super.fetchNow();
    if (wait != null) await wait;
    await fetched;
  }
}

class _Enabled extends CloudSyncEnabled {
  _Enabled(this.value);

  final bool value;

  @override
  bool build() => value;
}

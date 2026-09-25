import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/core/geo/ride_stats.dart';
import 'package:velorki_geo/velorki_geo.dart';
import 'package:velorki/features/import_export/application/incoming_import_listener.dart';
import 'package:velorki/features/import_export/data/incoming_file_service.dart';
import 'package:velorki/features/recording/application/recovery_on_launch.dart';
import 'package:velorki/features/recording/data/recording_journal.dart';
import 'package:velorki/features/recording/data/recording_recovery.dart';
import 'package:velorki/features/recording/domain/recording_snapshot.dart';
import 'package:velorki/features/recording/domain/recording_state.dart';
import 'package:velorki/features/recording/presentation/save_ride_sheet.dart';
import 'package:velorki/features/shared/application/active_tab.dart';

import '../../support/app.dart';
import '../import_export/support/fixtures.dart';
import 'support/pump.dart';

final RecordingState _state = RecordingState(
  rideId: 'ride-1',
  startedAt: DateTime.utc(2026, 9, 12, 10),
  status: RecordingStatus.active,
);

final InterruptedRecording _interrupted = InterruptedRecording(
  state: _state,
  stats: const RideStats(distanceM: 12345, movingTime: Duration(minutes: 42)),
);

/// Files opened with the app, pushed from a test.
class _Sources implements IncomingSources {
  _Sources(this.files);

  final Map<String, Uint8List> files;
  final StreamController<String> opened = StreamController<String>.broadcast();

  @override
  Future<List<SharedMediaFile>> initialSharedMedia() async => const [];

  @override
  Stream<List<SharedMediaFile>> sharedMediaStream() =>
      const Stream<List<SharedMediaFile>>.empty();

  @override
  Future<Uri?> initialLink() async => null;

  @override
  Stream<Uri> linkStream() => const Stream<Uri>.empty();

  @override
  Stream<String> openedFilePaths() => opened.stream;

  @override
  Future<Uint8List?> readFile(String path) async => files[path];

  @override
  Future<Uint8List?> readContentUri(Uri uri) async => null;
}

/// The app launched on [from], with [recovery] waiting, the way `bootstrap()`
/// launches it: the launch check is listened to before the first frame.
Future<(RecordingHarness, ProviderContainer)> _launch(
  WidgetTester tester, {
  required RecoveryResult recovery,
  String from = plannerRoute,
  _Sources? sources,
  bool reattaches = false,
  RecordingHarness? harness,
}) async {
  final h = harness ?? RecordingHarness(recovery: recovery);
  h.service.reattaches = reattaches;
  await tester.binding.setSurfaceSize(const Size(1000, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(h.planner.db.close);
  addTearDown(h.service.dispose);
  addTearDown(h.cleanUp);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final router = createRouter(initialLocation: from);
  final container = ProviderContainer(
    overrides: [
      ...h.overrides(prefs, tab: from),
      routerProvider.overrideWithValue(router),
      if (sources != null)
        incomingFileServiceProvider.overrideWithValue(
          IncomingFileService(sources),
        ),
    ],
  );
  addTearDown(container.dispose);
  showRecoveryOnLaunch(container);
  if (sources != null) listenForIncomingImports(container);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: testRouterApp(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return (h, container);
}

void main() {
  for (final from in [plannerRoute, libraryRoute, settingsRoute]) {
    testWidgets('an interrupted ride brings Record up with the question, '
        'launched on $from', (tester) async {
      final (_, container) = await _launch(
        tester,
        recovery: _interrupted,
        from: from,
      );

      expect(container.read(activeTabProvider), recordingRoute);
      expect(
        GoRouter.of(tester.element(find.byType(Scaffold).first))
            .state
            .matchedLocation,
        recordingRoute,
      );
      expect(find.text(l10n.recordingRecoveryTitle), findsOneWidget);
      await unmountApp(tester);
    });
  }

  testWidgets('Resume carries on, and the question is not asked again', (
    tester,
  ) async {
    final (h, _) = await _launch(tester, recovery: _interrupted);
    await tester.tap(find.widgetWithText(FilledButton, l10n.recordingResume));
    await tester.pumpAndSettle();
    expect(h.service.calls, contains('resumeInterrupted(ride-1)'));

    // Away and back: once per launch.
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(libraryRoute);
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(recordingRoute);
    await tester.pumpAndSettle();
    expect(find.text(l10n.recordingRecoveryTitle), findsNothing);
    await unmountApp(tester);
  });

  testWidgets('Finish goes to the save sheet', (tester) async {
    final (h, _) = await _launch(tester, recovery: _interrupted);
    await tester.runAsync(
      () => RecordingStore(h.directory).writeJournal('ride-1', <TrackPoint>[
        TrackPoint(
          const LatLng(32.6669, -16.9241),
          time: DateTime.utc(2026, 9, 12, 10),
        ),
        TrackPoint(
          const LatLng(32.6687, -16.9241),
          time: DateTime.utc(2026, 9, 12, 10, 30),
        ),
      ]),
    );
    await tester.tap(find.text(l10n.recordingFinish));
    // Reading the journal is real work, in real time.
    for (var i = 0; i < 50; i++) {
      await settleAsync(tester);
      if (find.byType(SaveRideSheet).evaluate().isNotEmpty) break;
    }
    expect(find.byType(SaveRideSheet), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('Discard throws it away', (tester) async {
    final (h, _) = await _launch(tester, recovery: _interrupted);
    await tester.tap(find.text(l10n.recordingRecoveryDiscard));
    await tester.pumpAndSettle();
    expect(h.service.calls, contains('discardInterrupted(ride-1)'));
    await unmountApp(tester);
  });

  testWidgets('a ride still running opens on Record, with no question', (
    tester,
  ) async {
    final (h, container) = await _launch(
      tester,
      recovery: ReattachRecording(_state),
      reattaches: true,
    );
    expect(container.read(activeTabProvider), recordingRoute);
    expect(find.text(l10n.recordingRecoveryTitle), findsNothing);
    expect(h.service.calls, contains('reattach'));
    await unmountApp(tester);
  });

  testWidgets('a ride that stopped between the check and the reattach, '
      'with nothing left to ask about, does not hold a file back', (
    tester,
  ) async {
    final h = RecordingHarness(recovery: ReattachRecording(_state))
      ..recheck = const NoRecovery();
    final (_, container) = await _launch(
      tester,
      recovery: h.recovery,
      harness: h,
    );
    await tester.pumpAndSettle();
    expect(h.service.calls, contains('reattach'));
    expect(container.read(recoverySettledProvider), isTrue);
    await waitForRecovery(container);
    await unmountApp(tester);
  });

  testWidgets('nothing to recover leaves the start tab alone', (tester) async {
    final (_, container) = await _launch(
      tester,
      recovery: const NoRecovery(),
      from: libraryRoute,
    );
    expect(container.read(activeTabProvider), libraryRoute);
    expect(find.text(l10n.recordingRecoveryTitle), findsNothing);
    await unmountApp(tester);
  });

  testWidgets('a file that opened the app waits for the answer, then opens', (
    tester,
  ) async {
    final sources = _Sources({'/tmp/tour.gpx': fixtureBytes('route.gpx')});
    addTearDown(sources.opened.close);
    await _launch(tester, recovery: _interrupted, sources: sources);
    sources.opened.add('/tmp/tour.gpx');
    await tester.pumpAndSettle();

    expect(find.text(l10n.recordingRecoveryTitle), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Import'), findsNothing);

    await tester.tap(find.text(l10n.recordingRecoveryDiscard));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Import'), findsOneWidget);
    await unmountApp(tester);
  });
}

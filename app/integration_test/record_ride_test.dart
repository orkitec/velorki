// A whole ride on the device: start, record a track, pause, resume, finish,
// and find the ride again on its detail screen and in the list.
//
//   flutter test integration_test/record_ride_test.dart -d emulator-5554 \
//     --dart-define=VELORKI_BROUTER_URL= \
//     --dart-define=VELORKI_SEGMENTS_URL=http://10.0.2.2:8000 \
//     --dart-define=VELORKI_API_URL=
//
// The recorder is the app's own MainIsolateRecordingService instead of the
// Android default. That is not a shortcut around the recording code — it is
// the same RecordingEngine, the same journal, the same RideRepository, and it
// is what actually runs on iOS. What it does not do is start a
// flutter_foreground_task service, and that is the part a test runner cannot
// have: the foreground service records in a *second Dart isolate* that
// hardcodes `GeolocatorPositionSource`, so no position source the test
// installs would ever reach it, and the snapshots would come back over a
// platform port the test cannot drive. Starting it would also raise the
// POST_NOTIFICATIONS prompt and the battery-optimisation settings page, which
// are system UI outside the Flutter tree. The three gateways behind those
// dialogs are faked for the same reason.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:velorki/core/permissions/location_permission.dart';
import 'package:velorki/features/map/data/position_provider.dart';
import 'package:velorki/features/recording/application/recording_controller.dart';
import 'package:velorki/features/recording/data/recording_gateways.dart';
import 'package:velorki/features/recording/data/recording_recovery.dart';
import 'package:velorki/features/recording/data/recording_service.dart';
import 'package:velorki/features/recording/data/ride_repository.dart';
import 'package:velorki/features/recording/presentation/ride_detail_screen.dart';
import 'package:velorki/features/recording/presentation/save_ride_sheet.dart';
import 'package:velorki/features/shared/presentation/stat_tile.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/fakes.dart';
import 'support/harness.dart';
import 'support/region.dart';

/// How many fixes the scripted ride emits.
const int _points = 30;

/// Metres between two fixes.
const double _stepM = 10;

/// Seconds between two fixes, so the speed is 5 m/s.
const int _stepS = 2;

/// One degree of latitude, in metres.
const double _degreeM = 111194.9266;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('records a ride, pauses, resumes and finishes it', (
    tester,
  ) async {
    // bootstrap() memoises the launch recovery check; a leftover journal from
    // an earlier run would otherwise open the "Unfinished ride" dialog.
    RecordingRecovery.overrideWith(
      Future<RecoveryResult>.value(const NoRecovery()),
    );
    addTearDown(RecordingRecovery.reset);

    final positions = ScriptedPositionSource(region.start);
    addTearDown(positions.close);
    final wake = RecordingScreenWake();

    final container = await pumpApp(
      tester,
      overrides: [
        positionSourceProvider.overrideWithValue(positions),
        locationPermissionGatewayProvider.overrideWithValue(
          const GrantedLocationPermission(),
        ),
        notificationPermissionProvider.overrideWithValue(
          const GrantedNotificationPermission(),
        ),
        batteryOptimizationProvider.overrideWithValue(
          const ExemptBatteryOptimization(),
        ),
        screenWakeProvider.overrideWithValue(wake),
        recordingRecoveryProvider.overrideWith(
          (ref) async => const NoRecovery(),
        ),
        recordingServiceProvider.overrideWith((ref) {
          final service = MainIsolateRecordingService(
            store: ref.watch(recordingStoreProvider),
            rides: ref.watch(rideRepositoryProvider),
            positions: positions,
            // Keeps the engine off geolocator's AndroidSettings, which want
            // the foreground-service notification this run does not have.
            platform: TargetPlatform.linux,
          );
          ref.onDispose(service.dispose);
          return service;
        }),
      ],
    );

    final rides = container.listen(ridesProvider, (_, _) {});
    addTearDown(rides.close);
    // The ride this test finishes is found by being the one that was not here
    // before, so "before" has to be the real contents of the database and not
    // the empty list a stream that has yet to emit reads as. Every earlier ride
    // is scripted from the same fake clock as this one, so a newest-first sort
    // would not tell them apart either: this is the only handle there is.
    await waitUntil(
      tester,
      () => rides.read().hasValue,
      describe: 'the rides already in the database',
      onTimeout: () => '${rides.read()}',
    );
    final before = {for (final ride in rides.read().requireValue) ride.id};
    debugPrint('VELORKI_RIDE ${before.length} ride(s) before this one');

    await tapAndPump(tester, find.text('Record'));
    await waitForWidget(
      tester,
      find.widgetWithText(FilledButton, 'Start ride'),
    );

    // ---------------------------------------------------------------- start
    await tapAndPump(tester, find.widgetWithText(FilledButton, 'Start ride'));
    await waitUntil(
      tester,
      () => positions.isListenedTo,
      describe: 'the recorder to subscribe to the GPS',
      onTimeout: () =>
          'controller=${container.read(recordingControllerProvider)}',
    );
    await waitForWidget(tester, find.text('RECORDING'));

    await _ride(tester, positions, from: 0, to: 20);
    await waitUntil(
      tester,
      () =>
          (container.read(recordingControllerProvider).snapshot?.distanceM ??
              0) >
          0,
      describe: 'the distance to start counting',
      onTimeout: () =>
          '${container.read(recordingControllerProvider).snapshot}',
    );
    final movingDistance = container
        .read(recordingControllerProvider)
        .snapshot!
        .distanceM;
    debugPrint('VELORKI_RIDE after 20 fixes: ${movingDistance.round()}m');
    expect(movingDistance, greaterThan(0));

    // ---------------------------------------------------------------- pause
    // The live controls are round icon buttons; their tooltips name them.
    await tapAndPump(tester, find.byTooltip('Pause'));
    await waitUntil(
      tester,
      () => container.read(recordingControllerProvider).isPaused,
      describe: 'the recording to pause',
      onTimeout: () =>
          '${container.read(recordingControllerProvider).snapshot}',
    );
    expect(find.text('PAUSED'), findsOneWidget);
    await screenshot(tester, 'recording-paused');

    // --------------------------------------------------------------- resume
    await tapAndPump(tester, find.byTooltip('Resume'));
    await waitUntil(
      tester,
      () => !container.read(recordingControllerProvider).isPaused,
      describe: 'the recording to resume',
      onTimeout: () =>
          '${container.read(recordingControllerProvider).snapshot}',
    );
    expect(find.text('RECORDING'), findsOneWidget);

    await _ride(tester, positions, from: 20, to: _points);
    // Every fix, not just the first after the pause: the recorder works in
    // its own isolate and the last one can land after the distance grew.
    await waitUntil(
      tester,
      () =>
          (container.read(recordingControllerProvider).snapshot?.pointCount ??
              0) >=
          _points,
      describe: 'every fix to be recorded after resuming',
      onTimeout: () =>
          '${container.read(recordingControllerProvider).snapshot}',
    );
    final total = container
        .read(recordingControllerProvider)
        .snapshot!
        .distanceM;
    debugPrint('VELORKI_RIDE after $_points fixes: ${total.round()}m');

    // --------------------------------------------------------------- finish
    await tapAndPump(
      tester,
      find.byTooltip('Finish'),
      settle: const Duration(seconds: 2),
    );
    // The save sheet: the ride is only written once it has a name.
    await waitForWidget(tester, find.byType(SaveRideSheet));
    final suggested = tester
        .widget<TextField>(
          find.descendant(
            of: find.byType(SaveRideSheet),
            matching: find.byType(TextField),
          ),
        )
        .controller!
        .text;
    debugPrint('VELORKI_RIDE suggested name: $suggested');
    expect(suggested, isNotEmpty);
    await screenshot(tester, 'save-ride');
    await tapAndPump(
      tester,
      find.widgetWithText(FilledButton, 'Save'),
      settle: const Duration(seconds: 2),
    );
    await waitUntil(
      tester,
      () => (rides.read().value ?? const []).any(
        (ride) => !before.contains(ride.id),
      ),
      describe: 'the finished ride in the database',
      onTimeout: () => '${rides.read()}',
    );
    final ride = rides.read().value!.firstWhere(
      (ride) => !before.contains(ride.id),
    );
    debugPrint(
      'VELORKI_RIDE saved ${ride.name}: ${ride.stats.distanceM.round()}m '
      '${ride.stats.pointCount} points, pauses=${ride.pauses.length}',
    );
    expect(ride.stats.distanceM, closeTo(total, 1));
    expect(ride.stats.pointCount, greaterThan(1));
    expect(ride.pauses, isNotEmpty, reason: 'the pause has to be recorded');

    // Finishing goes straight to the ride's detail screen.
    await waitForWidget(tester, find.widgetWithText(AppBar, ride.name));
    await waitForWidget(tester, find.byType(RideStatsGrid));
    final distance = tester.widget<StatTile>(
      find.ancestor(of: find.text('DISTANCE'), matching: find.byType(StatTile)),
    );
    debugPrint('VELORKI_RIDE detail DISTANCE=${distance.value}');
    expect(distance.label, 'Distance');
    expect(distance.value, isNotEmpty);
    await screenshot(tester, 'ride-detail');

    // ----------------------------------------------------------- in the list
    // The Library is the rides list; the record tab has none.
    await tapAndPump(tester, find.text('Library'));
    // The Library opens on its routes; the rides are the second segment.
    await tapAndPump(tester, find.text('Rides'));
    // The row is found by the id in its Dismissible key, not by its name: a
    // ride with no name of its own is named after the time of day and the
    // place, so every ride this suite records in one run is called the same
    // thing, and dragUntilVisible insists on exactly one match.
    final row = find.byKey(ValueKey('ride-${ride.id}'));
    await waitForWidget(tester, row);
    expect(
      find.descendant(of: row, matching: find.text(ride.name)),
      findsOneWidget,
    );
    expect(wake.enabled, isFalse, reason: 'the wake lock is released');

    await unmountApp(tester);
  });
}

/// Emits the fixes `[from, to)` of the scripted track, pumping between them.
Future<void> _ride(
  WidgetTester tester,
  ScriptedPositionSource positions, {
  required int from,
  required int to,
}) async {
  for (var i = from; i < to; i++) {
    positions.emit(
      fix(
        LatLng(region.start.lat + i * _stepM / _degreeM, region.start.lon),
        seconds: i * _stepS,
        ele: 10 + (i % 5) * 2.0,
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));
  }
  await pumpFor(tester, const Duration(milliseconds: 600));
}

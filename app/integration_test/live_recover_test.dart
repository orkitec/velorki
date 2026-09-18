// A ride interrupted by a kill, picked up again on the simulator's own GPS:
// the journal and the state file are on disk as the recorder leaves them, the
// app launches, offers to resume, and the ride goes on from the real fixes.
// Skipped off iOS.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:velorki/core/permissions/location_permission.dart';
import 'package:velorki/features/recording/application/recording_controller.dart';
import 'package:velorki/features/recording/data/recording_gateways.dart';
import 'package:velorki/features/recording/data/recording_journal.dart';
import 'package:velorki/features/recording/data/recording_recovery.dart';
import 'package:velorki/features/recording/domain/recording_snapshot.dart';
import 'package:velorki/features/recording/domain/recording_state.dart';
import 'package:velorki/features/recording/presentation/save_ride_sheet.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/fakes.dart';
import 'support/harness.dart';
import 'support/region.dart';

const String _rideId = 'itest-interrupted';
const int _points = 12;
const double _stepM = 10;
const double _degreeM = 111194.9266;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('resumes an interrupted ride on the simulator GPS', (
    tester,
  ) async {
    if (!Platform.isIOS) {
      markTestSkipped('needs the iOS simulator and tool/sim_ride.py');
      return;
    }

    // What a killed recorder leaves behind: the state file saying a ride is
    // active, and a journal with the fixes so far.
    final store = await RecordingStore.open();
    await store.ensureDirectory();
    final startedAt = DateTime.now().toUtc().subtract(
      const Duration(minutes: 10),
    );
    await store.writeState(
      RecordingState(
        rideId: _rideId,
        startedAt: startedAt,
        status: RecordingStatus.active,
      ),
    );
    await store.writeJournal(_rideId, <TrackPoint>[
      for (var i = 0; i < _points; i++)
        TrackPoint(
          LatLng(region.start.lat + i * _stepM / _degreeM, region.start.lon),
          time: startedAt.add(Duration(seconds: 2 * i)),
          speedMps: 5,
          accuracyM: 5,
        ),
    ]);
    final seededM = (_points - 1) * _stepM;
    addTearDown(() async {
      await store.clearState();
      final journal = store.journalFile(_rideId);
      if (await journal.exists()) await journal.delete();
    });

    // The launch check is memoised for the process; an earlier file in the
    // combined run has already answered it, so ask again.
    RecordingRecovery.reset();
    addTearDown(RecordingRecovery.reset);

    final container = await pumpApp(
      tester,
      overrides: [
        locationPermissionGatewayProvider.overrideWithValue(
          const GrantedLocationPermission(),
        ),
        notificationPermissionProvider.overrideWithValue(
          const GrantedNotificationPermission(),
        ),
        batteryOptimizationProvider.overrideWithValue(
          const ExemptBatteryOptimization(),
        ),
        screenWakeProvider.overrideWithValue(RecordingScreenWake()),
      ],
    );

    await tapAndPump(tester, find.text('Record'));
    await waitForWidget(tester, find.text('Unfinished ride'));
    await tapAndPump(tester, find.text('Resume'));
    await waitForWidget(tester, find.text('RECORDING'));

    final recording = container.listen(recordingControllerProvider, (_, _) {});
    addTearDown(recording.close);
    expect(
      recording.read().snapshot?.distanceM ?? 0,
      greaterThanOrEqualTo(seededM - 1),
      reason: 'the journal is folded back in',
    );
    await waitUntil(
      tester,
      () => (recording.read().snapshot?.distanceM ?? 0) > seededM + 50,
      describe: 'the resumed ride to go on from the simulator GPS',
      timeout: const Duration(seconds: 120),
      onTimeout: () => '${recording.read().snapshot}',
    );

    await tapAndPump(tester, find.byTooltip('Finish'));
    await waitForWidget(tester, find.byType(SaveRideSheet));
    await tapAndPump(tester, find.widgetWithText(FilledButton, 'Save'));
    await waitUntil(
      tester,
      () => !recording.read().isRecording,
      describe: 'the ride to finish',
    );
    await unmountApp(tester);
  });
}

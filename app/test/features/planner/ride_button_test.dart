import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/core/permissions/location_permission.dart';
import 'package:velorki/features/planner/presentation/planner_screen.dart';
import 'package:velorki/features/recording/application/recording_controller.dart';
import 'package:velorki/features/recording/domain/follow_choice.dart';
import 'package:velorki/features/recording/domain/recording_snapshot.dart';
import 'package:velorki/features/shared/application/active_tab.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../support/app.dart';
import '../recording/support/pump.dart';
import 'support/pump.dart' show pumpScreen;

const LatLng _a = LatLng(48.0, 11.0);
const LatLng _b = LatLng(48.2, 11.2);

Future<void> _plotRoute(WidgetTester tester, PlannerHarness h) async {
  h.map.onTap!(_a);
  h.map.onTap!(_b);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

Finder _rideButton() => find.widgetWithText(FilledButton, l10n.plannerRide);

Finder _saveButton() => find.widgetWithText(OutlinedButton, l10n.plannerSave);

RecordingSnapshot _running() => RecordingSnapshot(
  rideId: 'ride-1',
  status: RecordingStatus.active,
  startedAt: DateTime.utc(2026, 9, 12, 10),
  autoPaused: false,
  distanceM: 1200,
  elapsed: const Duration(minutes: 4),
  moving: const Duration(minutes: 4),
  speedMps: 5,
  avgSpeedMps: 5,
  ascentM: 10,
  descentM: 10,
  lastPosition: _a,
  accuracyM: 4,
  pointCount: 10,
  newPoints: const <LatLng>[_a, _b],
);

void main() {
  testWidgets('the Plan sheet offers Save and Ride, both off without a route', (
    tester,
  ) async {
    await pumpScreen(tester, const PlannerScreen());

    expect(_saveButton(), findsOneWidget);
    expect(_rideButton(), findsOneWidget);
    expect(tester.widget<OutlinedButton>(_saveButton()).onPressed, isNull);
    expect(tester.widget<FilledButton>(_rideButton()).onPressed, isNull);
    // Side by side, one height, sharing the width.
    final save = tester.getRect(_saveButton());
    final ride = tester.getRect(_rideButton());
    expect(save.top, ride.top);
    expect(save.height, ride.height);
    expect(save.right, lessThan(ride.left));
  });

  testWidgets('with a route Ride is on, and tapping it starts the ride on the '
      'Record tab, following the plan', (tester) async {
    final h = await pumpRecordingApp(tester, initialLocation: plannerRoute);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PlannerScreen)),
    );
    // Something else picked before: Ride must override it.
    container
        .read(recordingControllerProvider.notifier)
        .choose(FollowChoice.none);
    await _plotRoute(tester, h.planner);
    expect(tester.widget<FilledButton>(_rideButton()).onPressed, isNotNull);

    await tester.tap(_rideButton());
    await tester.pumpAndSettle();

    expect(container.read(activeTabProvider), recordingRoute);
    expect(
      container.read(recordingControllerProvider).follow,
      FollowChoice.plan,
    );
    // The normal flow ran (permission granted by the fakes) and started.
    expect(h.service.calls, <String>['start(null)']);
    await unmountApp(tester);
  });

  testWidgets('a refused location permission leaves the rider on the Record '
      'tab, as if Start had been tapped there', (tester) async {
    final h = await pumpRecordingApp(
      tester,
      initialLocation: plannerRoute,
      harness: RecordingHarness(
        location: LocationPermissionStatus.deniedForever,
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PlannerScreen)),
    );
    await _plotRoute(tester, h.planner);

    await tester.tap(_rideButton());
    await tester.pumpAndSettle();

    expect(container.read(activeTabProvider), recordingRoute);
    expect(h.service.calls, isEmpty);
    expect(find.text(l10n.recordingLocationDenied), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('with a ride already running Ride starts no second one', (
    tester,
  ) async {
    final h = await pumpRecordingApp(tester, initialLocation: plannerRoute);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PlannerScreen)),
    );
    await _plotRoute(tester, h.planner);
    await emitSnapshot(tester, h, _running());

    await tester.tap(_rideButton());
    await tester.pumpAndSettle();

    expect(container.read(activeTabProvider), recordingRoute);
    expect(h.service.calls, isEmpty);
    await unmountApp(tester);
  });
}

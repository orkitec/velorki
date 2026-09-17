import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/core/files/track_exporter.dart';
import 'package:velorki/core/permissions/location_permission.dart';
import 'package:velorki/features/map/data/compass_heading.dart';
import 'package:velorki/features/map/testing/fake_compass_source.dart';
import 'package:velorki/features/recording/data/recording_gateways.dart';
import 'package:velorki/features/recording/data/recording_journal.dart';
import 'package:velorki/features/recording/data/recording_recovery.dart';
import 'package:velorki/features/recording/data/recording_service.dart';
import 'package:velorki/features/recording/domain/recording_snapshot.dart';

import '../../../support/app.dart';
import '../../planner/support/fakes.dart' show TestMapController;
import '../../planner/support/pump.dart';
import 'fakes.dart';

export '../../planner/support/pump.dart'
    show PlannerHarness, imperialUnits, unmountApp;

/// Everything a recording widget test needs on top of [PlannerHarness]: a
/// recorder that records calls instead of driving the GPS, and permissions
/// that answer without a platform channel.
class RecordingHarness {
  /// Wires the fakes together.
  RecordingHarness({
    this.recovery = const NoRecovery(),
    LocationPermissionStatus location = LocationPermissionStatus.granted,
    bool notificationsGranted = true,
    bool batteryIgnored = true,
    PlannerHarness? planner,
  }) : planner = planner ?? PlannerHarness(),
       permission = FakeLocationPermissionGateway(status: location),
       notifications = FakeNotificationPermission(
         granted: notificationsGranted,
       ),
       battery = FakeBatteryOptimization(ignored: batteryIgnored);

  /// The database, the map and the preferences.
  final PlannerHarness planner;

  /// The recorder the screens drive.
  final FakeRecordingService service = FakeRecordingService();

  /// The exporter the ride detail screen hands files to.
  final FakeTrackExporter exporter = FakeTrackExporter();

  /// The keep-screen-on gateway.
  final FakeScreenWake screenWake = FakeScreenWake();

  /// The screen-dimming gateway the battery saver drives.
  final FakeScreenDimmer dimmer = FakeScreenDimmer();

  /// The location permission.
  final FakeLocationPermissionGateway permission;

  /// The notification permission.
  final FakeNotificationPermission notifications;

  /// The battery-optimisation exemption.
  final FakeBatteryOptimization battery;

  /// Where the phone points, for the standstill heading. Silent until a test
  /// points it somewhere, so no magnetometer is ever asked for.
  final FakeCompassSource compass = FakeCompassSource();

  /// What the launch check found.
  final RecoveryResult recovery;

  /// A throw-away journal directory, so nothing reaches path_provider.
  final Directory directory = Directory.systemTemp.createTempSync(
    'velorki_recording_ui',
  );

  /// The map the screens draw on.
  TestMapController get map => planner.map;

  /// The overrides to hand to a [ProviderScope].
  List<Override> overrides(SharedPreferences prefs) => <Override>[
    ...planner.overrides(prefs),
    recordingServiceProvider.overrideWithValue(service),
    recordingStoreProvider.overrideWithValue(
      Future<RecordingStore>.value(RecordingStore(directory)),
    ),
    recordingRecoveryProvider.overrideWith((ref) async => recovery),
    locationPermissionGatewayProvider.overrideWithValue(permission),
    notificationPermissionProvider.overrideWithValue(notifications),
    batteryOptimizationProvider.overrideWithValue(battery),
    screenWakeProvider.overrideWithValue(screenWake),
    screenDimmerProvider.overrideWithValue(dimmer),
    trackExporterProvider.overrideWithValue(exporter),
    compassSourceProvider.overrideWithValue(compass),
  ];

  /// Removes the throw-away journal directory.
  void cleanUp() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }
}

/// Lets real file system work finish, which [WidgetTester.pumpAndSettle] does
/// not: it only drives the frame scheduler, not the event loop.
Future<void> settleAsync(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump();
}

/// Pushes [snapshot] through the fake recorder and lets the UI catch up.
///
/// Two frames: the stream event reaches the controller in a microtask after
/// the first one.
Future<void> emitSnapshot(
  WidgetTester tester,
  RecordingHarness harness,
  RecordingSnapshot snapshot,
) async {
  harness.service.emit(snapshot);
  await tester.pump();
  await tester.pump();
}

Future<SharedPreferences> _prefs(Map<String, Object> initial) async {
  SharedPreferences.setMockInitialValues(initial);
  return SharedPreferences.getInstance();
}

/// Pumps [child] inside a localised [MaterialApp] with the recording fakes.
Future<RecordingHarness> pumpRecordingScreen(
  WidgetTester tester,
  Widget child, {
  RecordingHarness? harness,
  Map<String, Object> preferences = const <String, Object>{},
  List<Override> extraOverrides = const <Override>[],
  Size surfaceSize = const Size(1000, 2000),
}) async {
  final h = harness ?? RecordingHarness();
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(h.planner.db.close);
  addTearDown(h.service.dispose);
  addTearDown(h.cleanUp);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [...h.overrides(await _prefs(preferences)), ...extraOverrides],
      child: testApp(home: child),
    ),
  );
  await tester.pump();
  expectNoClippedText(tester);
  return h;
}

/// Pumps the whole app shell at [initialLocation], for the tests that navigate
/// from the record tab to a ride.
Future<RecordingHarness> pumpRecordingApp(
  WidgetTester tester, {
  String initialLocation = recordingRoute,
  RecordingHarness? harness,
  Map<String, Object> preferences = const <String, Object>{},
  Size surfaceSize = const Size(1000, 2000),
}) async {
  final h = harness ?? RecordingHarness();
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(h.planner.db.close);
  addTearDown(h.service.dispose);
  addTearDown(h.cleanUp);

  await tester.pumpWidget(
    ProviderScope(
      overrides: h.overrides(await _prefs(preferences)),
      child: testRouterApp(
        routerConfig: createRouter(initialLocation: initialLocation),
      ),
    ),
  );
  await tester.pump();
  expectNoClippedText(tester);
  return h;
}

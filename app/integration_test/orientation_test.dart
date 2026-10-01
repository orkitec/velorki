// Turning the phone: the tab bar becomes a rail and the sheets side panels,
// and back, with a ride running through it.
//
// Flutter's own DeviceOrientation.landscapeLeft is not the same physical turn
// on iOS and Android, so nothing here expects the rail on a given side: only
// that it stands on the side the platform says the bottom edge went to.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/app/shell_layout.dart';
import 'package:velorki/core/permissions/location_permission.dart';
import 'package:velorki/features/map/data/position_provider.dart';
import 'package:velorki/features/map/presentation/shared_map_host.dart';
import 'package:velorki/features/recording/application/recording_controller.dart';
import 'package:velorki/features/recording/data/recording_gateways.dart';
import 'package:velorki/features/recording/data/recording_recovery.dart';
import 'package:velorki/features/recording/data/recording_service.dart';
import 'package:velorki/features/recording/data/ride_repository.dart';
import 'package:velorki/features/recording/presentation/live_figures_view.dart';
import 'package:velorki/features/shared/presentation/adaptive_docking_sheet.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/fakes.dart';
import 'support/harness.dart';
import 'support/region.dart';

const double _degreeM = 111194.9266;

/// Turns the screen and waits until the app is laid out for it.
Future<void> _turn(
  WidgetTester tester,
  DeviceOrientation orientation, {
  required bool sideways,
}) async {
  await SystemChrome.setPreferredOrientations([orientation]);
  await waitUntil(tester, () {
    final size = tester.view.physicalSize;
    return (size.width > size.height) == sideways;
  }, describe: 'the screen to turn to $orientation');
  await pumpFor(tester, const Duration(seconds: 2));
  debugPrint('VELORKI_ORIENT $orientation');
}

/// Where the rail is, and where the platform says the bottom edge went.
void _expectRailOnBottomSide(WidgetTester tester, ProviderContainer app) {
  final rail = tester.getRect(find.byType(FloatingNavigationBar));
  final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
  final side = app.read(railSideProvider);
  if (side == RailSide.left) {
    expect(rail.center.dx, lessThan(width / 2));
  } else {
    expect(rail.center.dx, greaterThan(width / 2));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // The suite runs in one process on iOS: whatever this file does to the
  // screen is undone for the files after it.
  tearDown(() => SystemChrome.setPreferredOrientations(const []));

  testWidgets('turned sideways the app has a rail and side panels, a ride '
      'runs through turning back and forth, and the map stays one map', (
    tester,
  ) async {
    RecordingRecovery.overrideWith(
      Future<RecoveryResult>.value(const NoRecovery()),
    );
    addTearDown(RecordingRecovery.reset);

    final positions = ScriptedPositionSource(region.start);
    addTearDown(positions.close);

    final app = await pumpApp(
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
        screenWakeProvider.overrideWithValue(RecordingScreenWake()),
        recordingRecoveryProvider.overrideWith(
          (ref) async => const NoRecovery(),
        ),
        recordingServiceProvider.overrideWith((ref) {
          final service = MainIsolateRecordingService(
            store: ref.watch(recordingStoreProvider),
            rides: ref.watch(rideRepositoryProvider),
            positions: positions,
            platform: TargetPlatform.linux,
          );
          ref.onDispose(service.dispose);
          return service;
        }),
      ],
    );
    final map = tester.element(find.byType(SharedMapHost));

    // ------------------------------------------------------------- sideways
    await _turn(tester, DeviceOrientation.landscapeLeft, sideways: true);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(SidePanel), findsOneWidget);
    _expectRailOnBottomSide(tester, app);

    // The other way round: the rail crosses over with the bottom edge.
    await _turn(tester, DeviceOrientation.landscapeRight, sideways: true);
    _expectRailOnBottomSide(tester, app);

    // ------------------------------------------------------ a ride sideways
    await tapAndPump(
      tester,
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Record'),
      ),
    );
    await waitForWidget(
      tester,
      find.widgetWithText(FilledButton, 'Start ride'),
    );
    await tapAndPump(tester, find.widgetWithText(FilledButton, 'Start ride'));
    await waitUntil(
      tester,
      () => positions.isListenedTo,
      describe: 'the recorder to subscribe to the GPS',
    );
    for (var i = 0; i < 10; i++) {
      positions.emit(
        fix(
          LatLng(region.start.lat + i * 10 / _degreeM, region.start.lon),
          seconds: i * 2,
        ),
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
    await waitUntil(
      tester,
      () =>
          (app.read(recordingControllerProvider).snapshot?.distanceM ?? 0) > 0,
      describe: 'the distance to start counting',
    );
    await pumpFor(tester, const Duration(seconds: 1));
    // The ride's figures stand in the rail's place.
    expect(find.byType(NavigationRail), findsNothing);
    final figures = tester.widget<FiguresBar>(find.byType(FiguresBar));
    expect(figures.railSide, app.read(railSideProvider));
    debugPrint('VELORKI_ORIENT riding sideways');
    await pumpFor(tester, const Duration(seconds: 3));

    // ---------------------------------------------------- upright and back
    await _turn(tester, DeviceOrientation.portraitUp, sideways: false);
    expect(find.byType(SidePanel), findsNothing);
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    expect(app.read(recordingControllerProvider).isRecording, isTrue);

    await _turn(tester, DeviceOrientation.landscapeLeft, sideways: true);
    expect(find.byType(SidePanel), findsOneWidget);
    expect(app.read(recordingControllerProvider).isRecording, isTrue);
    // The one map all along: a map widget that was rebuilt would show black.
    expect(tester.element(find.byType(SharedMapHost)), same(map));

    // --------------------------------------------------------------- finish
    await app
        .read(recordingControllerProvider.notifier)
        .stop(rideName: 'Turned');
    await pumpFor(tester, const Duration(seconds: 1));
    await _turn(tester, DeviceOrientation.portraitUp, sideways: false);
    expect(find.byType(NavigationBar), findsOneWidget);

    await unmountApp(tester);
  });
}

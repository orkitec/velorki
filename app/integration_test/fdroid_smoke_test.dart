// The Google-free flavour on a device: everything the F-Droid build promises,
// in one flow.
//
// The point is not the Dart, which the unit suite already pins
// (test/app/proprietary_services_test.dart). The point is the *artifact*: in
// CI this file is built after `tool/fdroid_strip.sh` has taken the six
// closed-source plugins out of pubspec.yaml and patched geolocator and
// maplibre, and it is run on an AOSP system image with no Google Play
// Services on it at all. Everything here is something that could only break
// there — a plugin whose Android half is gone, a location client that was
// compiled away, a store SDK that is not there to answer.
//
//   bash tool/fdroid_strip.sh            # modifies the pub cache
//   bash tool/itest_mirror.sh            # the rd5 + .gaz on :8000
//   adb emu geo fix -16.92 32.65
//   flutter test integration_test/fdroid_smoke_test.dart -d emulator-5554 \
//     --dart-define=VELORKI_SEGMENTS_URL=http://10.0.2.2:8000 \
//     --dart-define=VELORKI_BROUTER_URL= --dart-define=VELORKI_API_URL=
//
// `tool/itest_fdroid.sh` is that, as the workflow runs it. The file is in the
// ordinary sweep too (and in all_tests.dart): there it runs on a google_apis
// emulator against an unstripped build, where it still proves the provider
// defaults and the on-device routing, just not the stripping. Off Android it
// skips itself — the flavour is an Android build.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:integration_test/integration_test.dart';
import 'package:velorki/app/build_flavour.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/core/plus/plus_gate.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';
import 'package:velorki/core/permissions/location_permission.dart';
import 'package:velorki/features/map/data/position_provider.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/presentation/planner_screen.dart';
import 'package:velorki/features/recording/application/recording_controller.dart';
import 'package:velorki/features/recording/data/recording_gateways.dart';
import 'package:velorki/features/recording/data/recording_recovery.dart';
import 'package:velorki/features/recording/data/recording_service.dart';
import 'package:velorki/features/recording/data/ride_repository.dart';
import 'package:velorki/features/recording/data/live_activity.dart';
import 'package:velorki/features/recording/data/recording_positions.dart';
import 'package:velorki/features/routing_tiles/application/tile_download_controller.dart';
import 'package:velorki/features/routing_tiles/data/routing_tiles_repository.dart';
import 'package:velorki/features/routing_tiles/data/segments_manifest_service.dart';
import 'package:velorki/features/sensors/data/watch_gateway.dart';
import 'package:velorki/features/store_prompts/data/store_services.dart';
import 'package:velorki/features/subscription/application/offered_plus_features.dart';
import 'package:velorki/features/subscription/data/subscription_service.dart';
import 'package:velorki/features/sync/data/google_account.dart';
import 'package:velorki/features/sync/data/google_drive_sync.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

import 'support/fakes.dart';
import 'support/harness.dart';
import 'support/region.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the Google-free build starts, finds the rider, sells nothing '
      'and routes on the device', (tester) async {
    if (!Platform.isAndroid) {
      markTestSkipped('the F-Droid flavour is an Android build');
      return;
    }
    // What `lib/main_fdroid.dart` does before the first frame, and the only
    // thing that entry point does differently besides installing no services.
    googleServicesAvailable = false;
    addTearDown(() => googleServicesAvailable = true);

    // ---- the app starts --------------------------------------------------
    // No proprietary overrides: `pumpApp` installs none, which is exactly the
    // container main_fdroid.dart builds.
    final container = await pumpApp(
      tester,
      overrides: [
        // The other half of what main_fdroid.dart installs: no Plus on offer.
        plusOfferedProvider.overrideWithValue(false),
        // Every system dialog a ride would raise is nothing a test can tap;
        // the position behind them is the real one.
        locationPermissionGatewayProvider.overrideWithValue(
          const GrantedLocationPermission(),
        ),
        notificationPermissionProvider.overrideWithValue(
          const GrantedNotificationPermission(),
        ),
        batteryOptimizationProvider.overrideWithValue(
          const ExemptBatteryOptimization(),
        ),
        recordingRecoveryProvider.overrideWith(
          (ref) async => const NoRecovery(),
        ),
        // See the ride below: the same engine, off the foreground service.
        recordingServiceProvider.overrideWith((ref) {
          final service = MainIsolateRecordingService(
            store: ref.watch(recordingStoreProvider),
            rides: ref.watch(rideRepositoryProvider),
            positions: ref.watch(positionSourceProvider),
            platform: TargetPlatform.linux,
          );
          ref.onDispose(service.dispose);
          return service;
        }),
      ],
    );
    expect(find.byType(MaterialApp), findsOneWidget);

    // ---- nothing closed-source answers -----------------------------------
    // Each of these is a plugin that is not in the APK at all. Reading the
    // provider on a stripped build would throw if anything still reached for
    // one.
    expect(
      container.read(subscriptionServiceProvider),
      isA<NoopSubscriptionService>(),
    );
    expect(container.read(googleSignInServiceProvider), isNull);
    expect(container.read(googleDriveStoreProvider), isNull);
    expect(container.read(watchGatewayProvider), isNull);
    expect(container.read(rideLiveActivityProvider), isA<NoRideLiveActivity>());
    expect(container.read(storeUpdateSourceProvider), isNull);
    await expectLater(container.read(reviewRequestProvider)(), completes);

    // ---- a fix through the Android LocationManager ------------------------
    // The stripped geolocator has no FusedLocationClient compiled into it and
    // the image has no Play Services to provide one, so a fix arriving here
    // can only have come from the platform's own LocationManager. The
    // recording profile says so outright as well.
    expect(
      (recordingLocationSettings(
        platform: TargetPlatform.android,
      ) as geo.AndroidSettings).forceLocationManager,
      isTrue,
    );
    // Asked again and again rather than watched: `tool/grant_location.sh`
    // grants the OS permission as soon as `flutter test` has installed the
    // app, which can be a moment after the first frame, and a stream opened
    // before that would have failed for good. Each poll is a fresh request.
    const source = GeolocatorPositionSource(web: false);
    geo.Position? fix;
    unawaited(() async {
      while (fix == null) {
        fix = await source.current(timeLimit: const Duration(seconds: 5));
        if (fix == null) await Future<void>.delayed(const Duration(seconds: 2));
      }
    }());
    await waitUntil(
      tester,
      () => fix != null,
      describe: 'a position from the platform',
      timeout: const Duration(seconds: 120),
      onTimeout: () =>
          'is the emulator at a simulated position, and was the location '
          'permission granted (tool/grant_location.sh)?',
    );
    debugPrint('VELORKI_FDROID fix ${fix!.latitude},${fix!.longitude}');
    expect(fix!.latitude, closeTo(region.start.lat, 1));
    expect(fix!.longitude, closeTo(region.start.lon, 1));

    // ---- no Plus entry point anywhere ------------------------------------
    // Not a paywall that says no: nothing at all. Nobody can buy Plus in this
    // build, so a row or a button for it is a dead end, and a dead end naming
    // a paid add-on is what a store reads as an advertisement for one.
    final l10n = AppLocalizations.of(
      tester.element(find.byType(PlannerScreen)),
    );
    expect(container.read(offeredPlusFeaturesProvider), isEmpty);
    expect(find.text(l10n.assistantAction), findsNothing);
    expect(find.text(l10n.loopAction), findsOneWidget, reason: 'the free ones');
    container.read(routerProvider).go(settingsRoute);
    await pumpFor(tester, const Duration(seconds: 2));
    expect(find.text(l10n.plusTitle), findsNothing);
    expect(find.text(l10n.settingsAi), findsNothing);
    expect(find.text(l10n.settingsMapsData), findsOneWidget);
    container.read(routerProvider).go(plannerRoute);
    await pumpFor(tester, const Duration(seconds: 2));

    // ---- a region downloads and a route is computed on the device ---------
    final tile = TileName.parse(region.tile);
    final repository = await container.read(
      routingTilesRepositoryProvider.future,
    );
    if (!repository.readyTiles().contains(tile)) {
      final manifest = await container.read(
        segmentsManifestSourceProvider.future,
      );
      final entry = manifest.byTile[tile];
      expect(entry, isNotNull, reason: 'mirror manifest lacks $tile');
      await container.read(tileDownloadQueueProvider.notifier).enqueue([
        entry!,
      ]);
      await waitUntil(
        tester,
        () => repository.readyTiles().contains(tile),
        describe: 'the $tile tile to download',
        timeout: const Duration(minutes: 3),
      );
    }
    // Let the routing backend rebuild with the new tile.
    await pumpFor(tester, const Duration(seconds: 2));

    final planner = container.read(plannerControllerProvider.notifier);
    planner
      ..addWaypoint(region.start)
      ..addWaypoint(region.end);
    await waitUntil(
      tester,
      () {
        final state = container.read(plannerControllerProvider);
        if (state.route.hasError) fail('routing failed: ${state.route.error}');
        return state.result != null && !state.isRouting;
      },
      describe: 'a route off the on-device engine',
      timeout: const Duration(seconds: 90),
      onTimeout: () => '${container.read(plannerControllerProvider)}',
    );

    final state = container.read(plannerControllerProvider);
    expect(state.routingSource, RoutingSource.local);
    expect(state.result!.lengthM, greaterThan(1000));
    debugPrint(
      'VELORKI_FDROID routed ${state.result!.lengthM.round()}m on the device',
    );

    // ---- a ride, recorded off the platform's own GPS ---------------------
    // No position source is faked: the fixes come from geolocator through
    // the patched Android LocationManager, fed by tool/emu_ride.py, which
    // tool/itest.sh starts for this file alone. That path is the point of
    // this test, so a ride that records nothing here is a ride that would
    // record nothing on the rider's phone.
    //
    // What is replaced is the *service*, for the reason record_ride_test.dart
    // gives: the Android foreground service records in a second isolate and
    // would raise the notification and battery-optimisation dialogs, which
    // are system UI no test can tap. MainIsolateRecordingService runs the
    // same engine, the same journal and the same repository over the same
    // real position source. `platform: linux` only keeps the engine off
    // geolocator's AndroidSettings, which want that notification; the fixes
    // still come through geolocator_android, which after the strip has no
    // fused client compiled into it at all.
    container.read(routerProvider).go(recordingRoute);
    await pumpFor(tester, const Duration(seconds: 2));

    final recorder = container.read(recordingControllerProvider.notifier);
    await recorder.start(notificationTitle: 'Velorki');
    await waitUntil(
      tester,
      () => container.read(recordingControllerProvider).isRecording,
      describe: 'the recorder to start',
      timeout: const Duration(seconds: 30),
    );
    // tool/itest.sh sets the emulator moving when it reads this line, and
    // not before: a fix a second while the slow emulator routes held the
    // route past its timeout.
    debugPrint('VELORKI_EMU_RIDE go');
    await waitUntil(
      tester,
      () =>
          (container.read(recordingControllerProvider).snapshot?.distanceM ??
              0) >
          200,
      describe: 'the rider to cover 200 m',
      timeout: const Duration(minutes: 3),
      onTimeout: () =>
          'is tool/emu_ride.py riding? '
          '${container.read(recordingControllerProvider).snapshot}',
    );
    final ridden = container
        .read(recordingControllerProvider)
        .snapshot!
        .distanceM;
    debugPrint('VELORKI_FDROID rode ${ridden.round()}m on the platform GPS');

    final ride = await recorder.stop(rideName: 'F-Droid smoke');
    expect(container.read(recordingControllerProvider).isRecording, isFalse);
    // Saved, not just measured: the ride has to survive into the library.
    expect(ride, isNotNull);
    expect(ride!.stats.distanceM, closeTo(ridden, 50));
    // A few hundred metres at 18 km/h, not a jump across the island: a fix
    // that teleports would show up as kilometres here.
    expect(ridden, greaterThan(200));
    expect(ridden, lessThan(5000));

    await unmountApp(tester);
  });
}

// The App Store screenshots: six screens of the real app on Madeira, in one
// language, in each app theme asked for.
//
//   tool/store_screenshots.sh            # the whole pipeline; see there
//
// Not part of the suite: tool/itest.sh and all_tests.dart only take the files
// directly under integration_test/, and this one clears the library of the
// device it runs on, so it refuses to run without
// --dart-define=VELORKI_STORE_SHOTS=true, which only the driver passes.
//
// The pictures are taken from outside (see shutter.dart): the map is a
// platform view, and the status bar belongs to the simulator. Everything the
// screens show is computed on the device from the oracle tile: the planned
// route and its variants, the saved routes, the ride (laid along a route with
// demoRide) and the navigation, which follows a scripted rider along a route
// planned the same way, so the turn banner is the navigator's own.
//
// Map taps never reach the native map view from a test, so waypoints go in
// through the planner; the plan shot loads a saved route because only a whole
// route appearing at once makes the planner fit the camera to it.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/core/permissions/location_permission.dart';
import 'package:velorki/features/import_export/application/incoming_import_listener.dart';
import 'package:velorki/features/import_export/data/incoming_file_service.dart';
import 'package:velorki/features/map/data/position_provider.dart';
import 'package:velorki/features/navigation/data/navigation_settings.dart';
import 'package:velorki/features/navigation/data/turn_speaker.dart';
import 'package:velorki/features/navigation/domain/navigation_progress.dart';
import 'package:velorki/features/navigation/presentation/turn_banner.dart';
import 'package:velorki/features/navigation/testing/fake_turn_speaker.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/shared/presentation/stat_tile.dart';
import 'package:velorki/features/planner/domain/saved_route.dart';
import 'package:velorki/features/recording/application/recording_controller.dart';
import 'package:velorki/features/recording/data/recording_gateways.dart';
import 'package:velorki/features/recording/data/recording_recovery.dart';
import 'package:velorki/features/recording/data/ride_repository.dart';
import 'package:velorki/features/recording/presentation/live_figures_view.dart';
import 'package:velorki/features/recording/presentation/recording_screen.dart';
import 'package:velorki/features/recording/presentation/ride_charts.dart';
import 'package:velorki/features/settings/data/appearance_controller.dart';
import 'package:velorki/features/settings/data/language_controller.dart';
import 'package:velorki/features/settings/data/units.dart';
import 'package:velorki/features/shared/presentation/docking_sheet.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';
import 'package:velorki_gpx/velorki_gpx.dart';

import '../support/fakes.dart';
import '../support/harness.dart';
import '../support/tiles.dart';
import 'demo_data.dart';
import 'shutter.dart';

const bool _enabled = bool.fromEnvironment('VELORKI_STORE_SHOTS');
const String _locale = String.fromEnvironment(
  'VELORKI_STORE_LOCALE',
  defaultValue: 'en',
);
const String _themes = String.fromEnvironment(
  'VELORKI_STORE_THEMES',
  defaultValue: 'light,dark',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final l10n = lookupAppLocalizations(Locale(_locale));
  final rideName = rideNames[_locale] ?? rideNames['en']!;

  for (final theme in _themes.split(',').map((t) => t.trim())) {
    final mode = ThemeMode.values.byName(theme);

    testWidgets('store screenshots, $_locale, $theme', (tester) async {
      if (!_enabled) {
        markTestSkipped('only tool/store_screenshots.sh runs this');
        return;
      }
      // The banner a debug build puts in the corner has no place in a store.
      WidgetsApp.debugAllowBannerOverride = false;
      addTearDown(() => WidgetsApp.debugAllowBannerOverride = true);
      RecordingRecovery.overrideWith(
        Future<RecoveryResult>.value(const NoRecovery()),
      );
      addTearDown(RecordingRecovery.reset);

      final positions = ScriptedPositionSource(funchal);
      addTearDown(positions.close);
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
          screenWakeProvider.overrideWithValue(RecordingScreenWake()),
          turnSpeakerProvider.overrideWithValue(FakeTurnSpeaker()),
          recordingRecoveryProvider.overrideWith(
            (ref) async => const NoRecovery(),
          ),
        ],
      );
      listenForIncomingImports(container);
      await ensureRegionTile(tester, container);

      // The device keeps its preferences between runs; set every one the
      // pictures depend on.
      await container
          .read(languageSettingProvider.notifier)
          .select(Locale(_locale));
      final appearance = container.read(appearanceSettingProvider.notifier);
      await appearance.setMode(mode);
      await appearance.setAccent(AccentPreset.volt);
      await appearance.setMapLook(MapLook.auto);
      await container
          .read(unitSystemProvider.notifier)
          .select(UnitSystem.metric);
      final navigation = container.read(navigationSettingsProvider.notifier);
      await navigation.setTurns(true);
      await navigation.setVoice(false);
      await navigation.setRerouteMode(RerouteMode.guideBack);
      await pumpFor(tester, const Duration(seconds: 2));

      final shot = '$theme/$_locale';
      final featured = await _seedLibrary(tester, container);
      final planner = container.read(plannerControllerProvider.notifier);

      // ---------------------------------------------------------- 01 plan
      planner
        ..clear()
        ..loadSavedRoute(featured);
      // The first shot of a run waits for the map style and its tiles.
      await takeStoreShot(
        tester,
        '$shot/01-plan',
        hold: const Duration(seconds: 10),
      );

      // -------------------------------------------------------- 02 choice
      // The label sits under the button, outside what takes the tap.
      await tapAndPump(
        tester,
        find.descendant(
          of: find.ancestor(
            of: find.text(l10n.plannerVariants),
            matching: find.byType(LabeledIconButton),
          ),
          matching: find.byType(InkWell),
        ),
      );
      await waitUntil(
        tester,
        () {
          final state = container.read(plannerControllerProvider);
          return state.alternatives.length > 1 && !state.loadingAlternatives;
        },
        describe: 'the variants',
        timeout: const Duration(seconds: 120),
        onTimeout: () {
          final state = container.read(plannerControllerProvider);
          return '${state.alternatives.length} variants, '
              'loading ${state.loadingAlternatives}, error ${state.error}';
        },
      );
      await tapAndPump(tester, find.text(l10n.plannerAlternativeIndex(1)));
      await takeStoreShot(tester, '$shot/02-choice');

      // -------------------------------------------------------- 06 import
      final rideRoute = await _plan(tester, container, rideWaypoints);
      planner.clear();
      final gpx = GpxCodec.encodeTrack(
        points: demoRide(rideRoute),
        name: rideName,
        type: 'cycling',
      );
      await container
          .read(incomingFileServiceProvider)
          .addBytes(
            Uint8List.fromList(utf8.encode(gpx)),
            fileName: '$rideName.gpx',
            sourceHint: 'picker',
          );
      await pumpFor(tester, const Duration(milliseconds: 500));
      await waitForWidget(tester, find.text(l10n.importKindRide));
      await tapAndPump(tester, find.text(l10n.importKindRide));
      await takeStoreShot(tester, '$shot/06-import');

      // ---------------------------------------------------------- 04 ride
      await tapAndPump(tester, find.text(l10n.commonSave).last);
      await waitForWidget(
        tester,
        find.byType(RideElevationChart),
        timeout: const Duration(seconds: 30),
      );
      _clearSnackBars(tester);
      await dragSheetUp(tester);
      await Scrollable.ensureVisible(
        tester.element(find.byType(RideElevationChart)),
      );
      await takeStoreShot(tester, '$shot/04-ride');

      // ------------------------------------------------------- 05 library
      await tapAndPump(tester, find.text(l10n.tabLibrary));
      await tapAndPump(tester, find.text(l10n.tabLibrary));
      await tapAndPump(tester, find.text(l10n.libraryRoutes));
      await waitForWidget(tester, find.text(featuredRoute.name));
      _clearSnackBars(tester);
      await takeStoreShot(tester, '$shot/05-library');

      // ------------------------------------------------------ 03 navigate
      await tapAndPump(tester, find.text(l10n.tabPlan));
      final route = await _plan(tester, container, navigationWaypoints);
      await tapAndPump(tester, find.text(l10n.tabRecord));
      final sheet = find
          .descendant(
            of: find.byType(DraggableScrollableSheet),
            matching: find.byType(Scrollable),
          )
          .first;
      final start = find.widgetWithText(FilledButton, l10n.recordingStart);
      await tester.dragUntilVisible(start, sheet, const Offset(0, 220));
      await tapAndPump(tester, start);
      await waitUntil(
        tester,
        () => positions.isListenedTo,
        describe: 'the recorder to subscribe to the GPS',
      );
      final ride = ScriptedRide(
        source: positions,
        line: route.positions,
        stepM: 15,
        speedMps: 6,
      );
      // Ridden in steps with a tick between them, because navigation only
      // sees the position of the recorder's last snapshot; stopped where the
      // next turn is close enough to read as one.
      var shown = false;
      for (var target = 60.0; target < ride.totalM - 100; target += 30) {
        await ride.rideTo(tester, target);
        await pumpFor(tester, const Duration(milliseconds: 1200));
        final progress = _progress(tester);
        final next = progress?.distanceToNextM;
        if (progress?.next != null &&
            target > 250 &&
            next != null &&
            next > 40 &&
            next < 160) {
          shown = true;
          break;
        }
      }
      expect(shown, isTrue, reason: 'a turn has to come up on the way');
      // Folded down, the live sheet docks into the figures bar.
      await tester.dragFrom(
        tester.getCenter(
          find
              .descendant(
                of: find.byType(RecordingScreen),
                matching: find.byType(SheetHandle),
              )
              .first,
        ),
        const Offset(0, 700),
      );
      await pumpFor(tester, const Duration(seconds: 1));
      await waitForWidget(tester, find.byType(FiguresBar));
      await takeStoreShot(tester, '$shot/03-navigate');

      final recording = container.read(recordingControllerProvider.notifier);
      final halted = await recording.halt();
      if (halted != null) await recording.discardInterrupted(halted);
      await pumpFor(tester, const Duration(seconds: 1));
      planner.clear();
      await unmountApp(tester);
    });
  }
}

/// Empties the library and fills it with the demo routes, the featured one
/// last so it heads the list. Hands back the featured route as saved.
///
/// Every run of the pipeline starts here, so the pictures never show what an
/// earlier run, or anything else on this simulator, left behind.
Future<SavedRoute> _seedLibrary(
  WidgetTester tester,
  ProviderContainer container,
) async {
  final routes = container.read(routeRepositoryProvider);
  final rides = container.read(rideRepositoryProvider);
  for (final route in await routes.watchRoutes().first) {
    await routes.delete(route.id);
  }
  for (final ride in await rides.watchRides().first) {
    await rides.delete(ride.id);
  }
  late SavedRoute featured;
  for (final demo in [...libraryRoutes, featuredRoute]) {
    await _plan(tester, container, demo.waypoints);
    final state = container.read(plannerControllerProvider);
    featured = await routes.savePlannedRoute(
      name: demo.name,
      route: state.result!,
      waypoints: state.waypoints,
      options: state.options,
    );
  }
  container.read(plannerControllerProvider.notifier).clear();
  await pumpFor(tester, const Duration(milliseconds: 500));
  return featured;
}

/// Plans [waypoints] on the device and waits for the route.
Future<RouteResult> _plan(
  WidgetTester tester,
  ProviderContainer container,
  List<LatLng> waypoints,
) async {
  final planner = container.read(plannerControllerProvider.notifier)..clear();
  for (final point in waypoints) {
    planner.addWaypoint(point);
  }
  await pumpFor(tester, const Duration(milliseconds: 400));
  await waitUntil(
    tester,
    () {
      final state = container.read(plannerControllerProvider);
      if (state.route.hasError) fail('routing failed: ${state.route.error}');
      return state.result != null && !state.isRouting;
    },
    describe: 'a route through $waypoints',
    timeout: const Duration(seconds: 90),
    onTimeout: () => '${container.read(plannerControllerProvider).route}',
  );
  return container.read(plannerControllerProvider).result!;
}

/// The progress the turn banner on screen was built from.
NavigationProgress? _progress(WidgetTester tester) {
  final banner = find.byType(TurnBanner).evaluate();
  if (banner.isEmpty) return null;
  return (banner.first.widget as TurnBanner).progress;
}

/// Takes every confirmation off the screen: "added to your rides" and the
/// like would otherwise sit over the bottom of the picture.
void _clearSnackBars(WidgetTester tester) {
  for (final messenger in tester.stateList<ScaffoldMessengerState>(
    find.byType(ScaffoldMessenger),
  )) {
    messenger.clearSnackBars();
  }
}

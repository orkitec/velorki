// The App Store screenshots: every screen the slides use, from the real app
// on Madeira, in one language, in each app theme asked for.
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
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/core/permissions/location_permission.dart';
import 'package:velorki/features/import_export/application/incoming_import_listener.dart';
import 'package:velorki/features/import_export/data/incoming_file_service.dart';
import 'package:velorki/features/map/data/position_provider.dart';
import 'package:velorki/features/map/presentation/map_controls.dart';
import 'package:velorki/features/map/presentation/shared_map_host.dart';
import 'package:velorki/features/planner/presentation/planner_screen.dart';
import 'package:velorki/features/planner/presentation/profile_chip_row.dart';
import 'package:velorki/features/map/data/offline_regions_repository.dart';
import 'package:velorki/features/recording/application/ride_notification_updater.dart';
import 'package:velorki/features/recording/data/follow_mode.dart';
import 'package:velorki/features/smart_loop/application/smart_loop_controller.dart';
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
import 'package:velorki/features/recording/data/recording_service.dart';
import 'package:velorki/features/recording/data/ride_repository.dart';
import 'package:velorki/features/recording/presentation/live_figures_view.dart';
import 'package:velorki/features/recording/presentation/recording_screen.dart';
import 'package:velorki/features/recording/presentation/ride_charts.dart';
import 'package:velorki/features/settings/data/appearance_controller.dart';
import 'package:velorki/features/settings/data/language_controller.dart';
import 'package:velorki/features/settings/data/units.dart';
import 'package:velorki/features/shared/presentation/docking_sheet.dart';
import 'package:velorki/features/sensors/domain/sensor_snapshot.dart';
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

/// How long the loop on the loop shot is: a morning's ride from Funchal.
const double _loopKm = 25;

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
      // The recorder's clock and the heart rate follow the scripted ride, so
      // an hour of riding fits in a minute of test and every figure on the
      // live card, the Live Activity and the watch agrees with the others.
      final ride = _RideClock();
      // The loop sheet opens at the distance last asked for.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('loop.distance_km', _loopKm);
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
          recordingServiceProvider.overrideWith((ref) {
            final service = MainIsolateRecordingService(
              store: ref.watch(recordingStoreProvider),
              rides: ref.watch(rideRepositoryProvider),
              positions: positions,
              clock: ride.now,
              sensors: ride.sensors,
            );
            ref.onDispose(service.dispose);
            return service;
          }),
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
      await _seedOfflineMap(tester, container);
      final planner = container.read(plannerControllerProvider.notifier);

      // ------------------------------------------------------------ plan
      planner
        ..clear()
        ..loadSavedRoute(featured);
      await _frameRoute(tester, container, featured.geometry);
      // The first shot of a run waits for the map style and its tiles.
      await takeStoreShot(
        tester,
        '$shot/plan',
        hold: const Duration(seconds: 10),
      );
      // The same plan in another accent, for the half of the theme slide
      // that shows the accent can be chosen.
      if (mode == ThemeMode.dark) {
        await appearance.setAccent(AccentPreset.ember);
        await takeStoreShot(tester, '$shot/plan-accent');
        await appearance.setAccent(AccentPreset.volt);
        await pumpFor(tester, const Duration(seconds: 2));
      }

      // -------------------------------------------------------- variants
      await tapAndPump(tester, _action(l10n.plannerVariants));
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
      // Tapping scrolled the sheet's content; the chips belong at its top.
      _scrollSheetToTop(tester);
      await takeStoreShot(tester, '$shot/variants');

      // ------------------------------------------------------------ loop
      // From the rider's position, at the distance seeded before the start.
      planner.clear();
      await pumpFor(tester, const Duration(milliseconds: 500));
      await tapAndPump(tester, _action(l10n.loopAction));
      // The sheet's title says the same as the button.
      await tapAndPump(
        tester,
        find.ancestor(
          of: find.text(l10n.loopMake),
          matching: find.byWidgetPredicate((w) => w is FilledButton),
        ),
      );
      await waitUntil(
        tester,
        () {
          final loop = container.read(smartLoopControllerProvider);
          if (loop.error != null) fail('loop search: ${loop.error}');
          return !loop.running && loop.hasSearched;
        },
        describe: 'the loop search',
        timeout: const Duration(minutes: 3),
        onTimeout: () => '${container.read(smartLoopControllerProvider)}',
      );
      expect(container.read(smartLoopControllerProvider).foundNothing, isFalse);
      await takeStoreShot(tester, '$shot/loop');
      await tapAndPump(
        tester,
        find.ancestor(
          of: find.text(l10n.loopDone),
          matching: find.byWidgetPredicate((w) => w is FilledButton),
        ),
      );
      planner.clear();

      // ---------------------------------------------------------- import
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
      await takeStoreShot(tester, '$shot/import');

      // ------------------------------------------------------------ ride
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
      await takeStoreShot(tester, '$shot/ride');

      // --------------------------------------------------------- library
      await tapAndPump(tester, find.text(l10n.tabLibrary));
      await tapAndPump(tester, find.text(l10n.tabLibrary));
      await tapAndPump(tester, find.text(l10n.libraryRoutes));
      await waitForWidget(tester, find.text(featuredRoute.name));
      _clearSnackBars(tester);
      await takeStoreShot(tester, '$shot/library');

      // --------------------------------------------------------- offline
      // The planner with a route on the map downloaded for offline use, and
      // the status bar with no signal at all.
      await tapAndPump(tester, find.text(l10n.tabPlan));
      final saved = await container
          .read(routeRepositoryProvider)
          .watchRoutes()
          .first;
      final coast = saved.firstWhere((r) => r.name == libraryRoutes.first.name);
      planner
        ..clear()
        ..loadSavedRoute(coast);
      await _frameRoute(tester, container, coast.geometry);
      await takeStoreShot(tester, '$shot/offline', offline: true);
      planner.clear();

      // ------------------------------------------------ live and navigation
      // The featured route, ridden the way the demo ride is: most of it fast
      // forward, then a fix a second until a turn comes up about 20 km in.
      final route = await _plan(tester, container, featuredRoute.waypoints);
      await container
          .read(followModeProvider.notifier)
          .select(FollowMode.headingUp);
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
      final rider = _Rider(positions, ride, demoRide(route));
      await rider.rideTo(tester, 18000);
      // Navigation only sees the recorder's last snapshot, so the banner is
      // read after every fix once they come a second apart.
      Future<void> rideOn(int fixes) async {
        for (var i = 0; i < fixes && !rider.done; i++) {
          await rider.step(tester, const Duration(seconds: 1));
        }
      }

      var shown = false;
      while (!rider.done && rider.alongM < 21500) {
        await rideOn(1);
        final progress = _progress(tester);
        final next = progress?.distanceToNextM;
        if (progress?.next != null &&
            next != null &&
            next > 110 &&
            next < 250) {
          shown = true;
          break;
        }
      }
      expect(shown, isTrue, reason: 'a turn has to come up on the way');
      // Held still, the speed would drop to nothing: the rider rides on
      // through every pause.
      await rideOn(1);
      await takeStoreShot(tester, '$shot/live', hold: Duration.zero);
      // What the Live Activity and the watch show right now, for the slides
      // that draw them: the same snapshot the live card was built from.
      await sendStoreData(
        tester,
        '$shot/activity',
        rideActivityData(
          l10n,
          UnitSystem.metric,
          container.read(recordingControllerProvider).snapshot!,
          _progress(tester),
        ),
      );
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
      await rideOn(2);
      await waitForWidget(tester, find.byType(FiguresBar));
      await takeStoreShot(tester, '$shot/navigation', hold: Duration.zero);

      final recording = container.read(recordingControllerProvider.notifier);
      final halted = await recording.halt();
      if (halted != null) await recording.discardInterrupted(halted);
      await container
          .read(followModeProvider.notifier)
          .select(FollowMode.northUp);
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

/// The button of a planner action by its label, which sits under the button,
/// outside what takes the tap.
Finder _action(String label) => find.descendant(
  of: find.ancestor(
    of: find.text(label),
    matching: find.byType(LabeledIconButton),
  ),
  matching: find.byType(InkWell),
);

/// Downloads the map around Funchal for offline use, once per simulator, so
/// the offline screen has a region to show next to the routing tile.
Future<void> _seedOfflineMap(
  WidgetTester tester,
  ProviderContainer container,
) async {
  final regions = container.read(offlineRegionsRepositoryProvider);
  if ((await regions.regions()).isNotEmpty) return;
  final download = container
      .read(offlineDownloadControllerProvider.notifier)
      .download(
        OfflineRegionSpec(
          name: 'Funchal',
          bounds: const BoundingBox(
            south: 32.63,
            west: -16.96,
            north: 32.69,
            east: -16.86,
          ),
          styleUrl: container.read(offlineStyleUrlProvider),
        ),
      );
  var done = false;
  unawaited(download.whenComplete(() => done = true));
  await waitUntil(
    tester,
    () => done,
    describe: 'the offline map around Funchal',
    timeout: const Duration(minutes: 5),
  );
}

/// Fits [line] between the planner's chrome with room to spare: the planner
/// fits a loaded route to the edge of what is visible, which leaves the
/// place names beside its end markers cut off by the screen's edge.
Future<void> _frameRoute(
  WidgetTester tester,
  ProviderContainer container,
  List<TrackPoint> line,
) async {
  // The planner's own fit goes first; this one lands after it.
  await pumpFor(tester, const Duration(seconds: 2));
  final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  final chips = tester.getRect(find.byType(ProfileChipRow).first);
  final controls = tester.getRect(find.byType(MapControls).first);
  final sheet = tester.getRect(
    find
        .descendant(
          of: find.byType(PlannerScreen),
          matching: find.byType(SheetHandle),
        )
        .first,
  );
  await container
      .read(sharedMapControllerProvider)
      ?.fitBounds(
        BoundingBox.fromPoints([for (final point in line) point.pos]),
        // A town's name is drawn centred on it, so an end marker in a town
        // needs half a name's width of room on either side.
        padding: EdgeInsets.fromLTRB(
          88,
          chips.bottom + 24,
          screen.width - controls.left + 72,
          screen.height - sheet.top + 24,
        ),
      );
}

/// Scrolls every list in the planner's sheet back to its top.
void _scrollSheetToTop(WidgetTester tester) {
  final lists = find.descendant(
    of: find.descendant(
      of: find.byType(PlannerScreen),
      matching: find.byType(DraggableScrollableSheet),
    ),
    matching: find.byType(Scrollable),
  );
  for (final state in tester.stateList<ScrollableState>(lists)) {
    if (state.position.axis == Axis.vertical && state.position.pixels > 0) {
      state.position.jumpTo(0);
    }
  }
}

/// The recorder's clock and heart-rate sensor during the scripted ride: the
/// time is that of the last fix, the heart rate the one the demo ride has
/// there.
class _RideClock {
  /// Where the clock stands before the first fix; [fix] counts from here.
  static final DateTime start = DateTime.utc(2026, 9, 12, 10);

  DateTime _now = start;
  int? _heartRate;

  DateTime now() => _now;

  SensorSnapshot sensors() => SensorSnapshot(
    heartRateBpm: _heartRate,
    heartRateAt: _heartRate == null ? null : _now,
  );
}

/// Rides [points] (a demo ride: positions, heights, times and heart rates)
/// through [source], moving [clock] along with every fix.
class _Rider {
  _Rider(this.source, this.clock, this.points);

  final ScriptedPositionSource source;
  final _RideClock clock;
  final List<TrackPoint> points;
  int _next = 0;
  double alongM = 0;

  bool get done => _next >= points.length;

  /// Rides on to [metres] along the ride, a frame between fixes.
  Future<void> rideTo(WidgetTester tester, double metres) async {
    while (!done && alongM < metres) {
      await step(tester, const Duration(milliseconds: 30));
    }
  }

  /// Pushes the next fix and pumps [pump].
  Future<void> step(WidgetTester tester, Duration pump) async {
    final point = points[_next];
    final previous = _next == 0 ? null : points[_next - 1];
    final seconds = point.time!.difference(points.first.time!).inSeconds;
    var speed = 0.0;
    var heading = 0.0;
    if (previous != null) {
      final metres = haversineMeters(previous.pos, point.pos);
      final took = point.time!.difference(previous.time!).inMilliseconds;
      speed = took <= 0 ? 0 : metres / took * 1000;
      heading = bearingDegrees(previous.pos, point.pos);
      alongM += metres;
    }
    clock
      .._now = _RideClock.start.add(Duration(seconds: seconds))
      .._heartRate = point.heartRateBpm;
    source.emit(
      fix(
        point.pos,
        seconds: seconds,
        speed: speed,
        ele: point.ele ?? 0,
        heading: heading,
      ),
    );
    _next++;
    await tester.pump(pump);
  }
}

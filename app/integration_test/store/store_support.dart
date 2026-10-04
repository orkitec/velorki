/// What the store screenshot and preview tests share: the app booted with
/// the doubles and the settings the pictures depend on, the demo library,
/// planning, and the scripted rider.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/core/permissions/location_permission.dart';
import 'package:velorki/core/plus/plus_gate.dart';
import 'package:velorki/features/assistant/data/ai_consent_controller.dart';
import 'package:velorki/features/assistant/data/place_geocoder.dart';
import 'package:velorki/features/assistant/domain/ai_consent.dart';
import 'package:velorki/features/assistant/domain/intent_resolver.dart';
import 'package:velorki/features/integrations/common/data/relay_client_provider.dart';
import 'package:velorki/features/import_export/application/incoming_import_listener.dart';
import 'package:velorki/features/map/data/position_provider.dart';
import 'package:velorki/features/map/presentation/map_controls.dart';
import 'package:velorki/features/map/presentation/shared_map_host.dart';
import 'package:velorki/features/planner/presentation/planner_screen.dart';
import 'package:velorki/features/planner/presentation/profile_chip_row.dart';
import 'package:velorki/features/map/data/offline_regions_repository.dart';
import 'package:velorki/features/recording/data/follow_mode.dart';
import 'package:velorki/features/navigation/data/navigation_settings.dart';
import 'package:velorki/features/navigation/data/turn_speaker.dart';
import 'package:velorki/features/navigation/domain/navigation_progress.dart';
import 'package:velorki/features/navigation/presentation/turn_banner.dart';
import 'package:velorki/features/navigation/testing/fake_turn_speaker.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/shared/presentation/stat_tile.dart';
import 'package:velorki/features/subscription/application/offered_plus_features.dart';
import 'package:velorki/features/subscription/data/subscription_service.dart';
import 'package:velorki/features/planner/domain/saved_route.dart';
import 'package:velorki/features/recording/data/recording_gateways.dart';
import 'package:velorki/features/recording/data/recording_recovery.dart';
import 'package:velorki/features/recording/data/recording_service.dart';
import 'package:velorki/features/recording/data/ride_repository.dart';
import 'package:velorki/features/settings/data/appearance_controller.dart';
import 'package:velorki/features/settings/data/language_controller.dart';
import 'package:velorki/features/settings/data/units.dart';
import 'package:velorki/features/shared/presentation/docking_sheet.dart';
import 'package:velorki/features/search/data/gazetteer_store.dart';
import 'package:velorki/features/search/domain/search_result.dart';
import 'package:velorki/features/sensors/domain/sensor_snapshot.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

// No Flutter in it: the relay the widget suite mocks, shared with the device.
import '../../test/features/subscription/support/fake_subscription_service.dart';
import '../../test/support/mock_relay.dart';
import '../support/fakes.dart';
import '../support/harness.dart';
import '../support/tiles.dart';
import 'demo_data.dart';

/// The loop distance the loop sheet opens at: a morning's ride from Funchal.
const double storeLoopKm = 25;

/// The app as a test left it for the pictures.
class StoreSession {
  StoreSession(this.container, this.positions, this.clock, this.relay);

  /// The app's providers.
  final ProviderContainer container;

  /// Where the rider is; the recorder listens to it.
  final ScriptedPositionSource positions;

  /// The recorder's clock and heart rate.
  final RideClock clock;

  /// The relay the app talks to: mocked in the test process, so the AI
  /// answers the same on every run and nothing leaves the device.
  final MockRelay relay;
}

/// Boots the app for the store pictures in [locale] and [mode], with the
/// rider at [origin]: every permission granted, the store's offering, the voice silent, the
/// recorder on [RideClock], the region's tile on the device, and every
/// setting the pictures depend on set, because the device keeps them
/// between runs.
Future<StoreSession> startStoreApp(
  WidgetTester tester, {
  required String locale,
  required ThemeMode mode,
  required LatLng origin,
}) async {
  // The banner a debug build puts in the corner has no place in a store.
  WidgetsApp.debugAllowBannerOverride = false;
  addTearDown(() => WidgetsApp.debugAllowBannerOverride = true);
  RecordingRecovery.overrideWith(
    Future<RecoveryResult>.value(const NoRecovery()),
  );
  addTearDown(RecordingRecovery.reset);

  final positions = ScriptedPositionSource(origin);
  addTearDown(positions.close);
  // The recorder's clock and the heart rate follow the scripted ride, so an
  // hour of riding fits in a minute of test and every figure on the live
  // card, the Live Activity and the watch agrees with the others.
  final ride = RideClock();
  final relay = MockRelay();
  // The loop sheet opens at the distance last asked for.
  final prefs = await SharedPreferences.getInstance();
  await prefs.setDouble('loop.distance_km', storeLoopKm);
  // The planner opens on the bike last chosen; the pictures want the default.
  await prefs.remove('planner.profile');
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
      recordingRecoveryProvider.overrideWith((ref) async => const NoRecovery()),
      relayClientProvider.overrideWith((ref) {
        final client = relay.client();
        ref.onDispose(client.close);
        return client;
      }),
      // Place names resolve off the region's gazetteer on the device.
      // The paywall sells what the stores sell, at their prices, and lists
      // every feature a release build delivers (this one has no partner
      // client ids).
      subscriptionServiceProvider.overrideWithValue(
        FakeSubscriptionService(offering: plusOffering(locale)),
      ),
      offeredPlusFeaturesProvider.overrideWithValue([
        for (final feature in PlusFeature.values)
          if (gatedFeatures.contains(feature)) feature,
      ]),
      intentResolverProvider.overrideWith(
        (ref) => IntentResolver(
          geocoder: _GazetteerGeocoder(
            () => ref.read(gazetteerStoreProvider.future),
          ),
        ),
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

  await container.read(languageSettingProvider.notifier).select(Locale(locale));
  final appearance = container.read(appearanceSettingProvider.notifier);
  await appearance.setMode(mode);
  await appearance.setAccent(AccentPreset.volt);
  await appearance.setMapLook(MapLook.auto);
  await container.read(unitSystemProvider.notifier).select(UnitSystem.metric);
  final navigation = container.read(navigationSettingsProvider.notifier);
  await navigation.setTurns(true);
  await navigation.setVoice(false);
  await navigation.setRerouteMode(RerouteMode.guideBack);
  await container.read(followModeProvider.notifier).select(FollowMode.northUp);
  await pumpFor(tester, const Duration(seconds: 2));
  return StoreSession(container, positions, ride, relay);
}

/// Opens the assistant to the rider: Velorki Plus held, consent given, and
/// the gazetteer that came with the region's tile read.
Future<void> grantAssistant(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await (await container.read(gazetteerStoreProvider.future)).refresh();
  container.read(plusEntitledProvider.notifier).value = true;
  await container
      .read(aiConsentControllerProvider.notifier)
      .set(AiConsent.textOnly);
  await pumpFor(tester, const Duration(milliseconds: 300));
}

/// Names resolved by the region's offline gazetteer.
class _GazetteerGeocoder implements PlaceGeocoder {
  _GazetteerGeocoder(this.store);
  final Future<GazetteerStore> Function() store;

  @override
  Future<List<SearchResult>> lookup(
    String query, {
    LatLng? bias,
    int limit = 5,
  }) async => (await store()).search(query, near: bias, limit: limit);
}

/// Empties the library and fills it with the demo routes, the featured one
/// last so it heads the list. Hands back the featured route as saved.
///
/// Every run of the pipeline starts here, so the pictures never show what an
/// earlier run, or anything else on this simulator, left behind.
Future<SavedRoute> seedLibrary(
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
    await planRoute(tester, container, demo.waypoints);
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
Future<RouteResult> planRoute(
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
NavigationProgress? bannerProgress(WidgetTester tester) {
  final banner = find.byType(TurnBanner).evaluate();
  if (banner.isEmpty) return null;
  return (banner.first.widget as TurnBanner).progress;
}

/// Takes every confirmation off the screen: "added to your rides" and the
/// like would otherwise sit over the bottom of the picture.
void clearSnackBars(WidgetTester tester) {
  for (final messenger in tester.stateList<ScaffoldMessengerState>(
    find.byType(ScaffoldMessenger),
  )) {
    messenger.clearSnackBars();
  }
}

/// The button of a planner action by its label, which sits under the button,
/// outside what takes the tap.
Finder plannerAction(String label) => find.descendant(
  of: find.ancestor(
    of: find.text(label),
    matching: find.byType(LabeledIconButton),
  ),
  matching: find.byType(InkWell),
);

/// Downloads the map around Funchal for offline use, once per simulator, so
/// the offline screen has a region to show next to the routing tile.
Future<void> seedOfflineMap(
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
///
/// [handle] is the handle of the card the route has to stay above, the
/// planner's by default.
Future<void> frameRoute(
  WidgetTester tester,
  ProviderContainer container,
  List<TrackPoint> line, {
  Finder? handle,
}) async {
  // The planner's own fit goes first; this one lands after it.
  await pumpFor(tester, const Duration(seconds: 2));
  final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  final chips = tester.getRect(find.byType(ProfileChipRow).first);
  final controls = tester.getRect(find.byType(MapControls).first);
  final sheet = tester.getRect(
    handle ??
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
void scrollSheetToTop(WidgetTester tester) {
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
class RideClock {
  /// Creates the clock at [start].
  RideClock();

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
class Rider {
  /// Creates a rider of [points] through [source], moving [clock].
  Rider(this.source, this.clock, this.points);

  final ScriptedPositionSource source;
  final RideClock clock;
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
      .._now = RideClock.start.add(Duration(seconds: seconds))
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

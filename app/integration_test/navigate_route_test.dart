// Turn-by-turn on the device: plan a route, ride it with the turn directions
// on and the voice off, and watch the banner count the turns down, change
// instruction at each of them, say the ride has arrived, and notice a rider
// who has left the route.
//
//   flutter test integration_test/navigate_route_test.dart -d emulator-5554 \
//     --dart-define=VELORKI_BROUTER_URL= \
//     --dart-define=VELORKI_SEGMENTS_URL=http://10.0.2.2:8000 \
//     --dart-define=VELORKI_API_URL= \
//     --dart-define=VELORKI_ITEST_REGION=madeira
//
// The route is planned twice on purpose. The region's own pair of points is
// tens of kilometres apart, which is more than a scripted ride can cover in a
// test; the first plan is only there to find a point about [_rideM] metres
// along it, and the second plan — start to that point — is the one the ride
// follows. Both come off the on-device engine, so the turn hints the banner
// shows are the ones a rider would really get.
//
// Like record_ride_test, the recorder is the app's own
// MainIsolateRecordingService: the Android foreground service records in a
// second isolate that hardcodes the real GPS, so no scripted position would
// ever reach it. The speaker is a fake as well, and the assertion at the end
// is that it was never asked to say anything — with the voice switch off,
// flutter_tts must not be touched at all.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:velorki/core/permissions/location_permission.dart';
import 'package:velorki/features/map/data/position_provider.dart';
import 'package:velorki/features/navigation/application/navigation_controller.dart';
import 'package:velorki/features/navigation/data/navigation_settings.dart';
import 'package:velorki/features/navigation/data/turn_speaker.dart';
import 'package:velorki/features/navigation/domain/navigation_progress.dart';
import 'package:velorki/features/navigation/presentation/navigation_toggles.dart';
import 'package:velorki/features/navigation/presentation/turn_banner.dart';
import 'package:velorki/features/navigation/presentation/turn_phrases.dart';
import 'package:velorki/features/navigation/testing/fake_turn_speaker.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/recording/application/recording_controller.dart';
import 'package:velorki/features/recording/data/recording_gateways.dart';
import 'package:velorki/features/recording/data/recording_recovery.dart';
import 'package:velorki/features/recording/data/recording_service.dart';
import 'package:velorki/features/recording/data/ride_repository.dart';
import 'package:velorki/features/settings/data/units.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/fakes.dart';
import 'support/harness.dart';
import 'support/region.dart';
import 'support/tiles.dart';

/// How long the ride should be, in metres. Long enough for a handful of turns
/// in either region, short enough to ride at [ScriptedRide.stepM] steps well
/// inside the file's time budget.
const double _rideM = 1800;

/// How far past a turn the rider has to be before the navigator calls it
/// taken, plus a little; see `_passedMarginM` in turn_navigator.dart.
const double _pastTurnM = 40;

/// How far off the route the stray fixes go. Over the navigator's 50 m stray
/// threshold by enough that no GPS jitter could explain it.
const double _strayM = 150;

/// How long one tick of the recorder takes, plus a frame or two: the engine
/// publishes a snapshot once a second, and navigation only ever sees the
/// position that was in the last one.
const Duration _tick = Duration(milliseconds: 1200);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('guides a scripted ride along a planned route', (tester) async {
    // bootstrap() memoises the launch recovery check; a leftover journal from
    // an earlier run would otherwise open the "Unfinished ride" dialog.
    RecordingRecovery.overrideWith(
      Future<RecoveryResult>.value(const NoRecovery()),
    );
    addTearDown(RecordingRecovery.reset);

    final positions = ScriptedPositionSource(region.start);
    addTearDown(positions.close);
    final speaker = FakeTurnSpeaker();

    final container = await pumpApp(
      tester,
      // The banner and everything asserted here are Flutter-side; maplibre
      // only slows the run down.
      realMap: false,
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
        turnSpeakerProvider.overrideWithValue(speaker),
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
    await ensureRegionTile(tester, container);

    // The emulator keeps its preferences between runs, and this very test
    // switches the voice off; start from the defaults either way.
    final settings = container.read(navigationSettingsProvider.notifier);
    await settings.setTurns(true);
    await settings.setVoice(true);
    await settings.setReroute(true);

    // ------------------------------------------------------------- the route
    final planner = container.read(plannerControllerProvider.notifier);
    planner
      ..addWaypoint(region.start)
      ..addWaypoint(region.end);
    final far = await _routed(tester, container, describe: "the region's ends");
    planner.moveWaypoint(1, _pointAlong(far.positions, _rideM));
    final route = await _routed(
      tester,
      container,
      describe: 'the ride to $_rideM m',
    );
    final line = route.positions;
    final turns = route.turns.where(_isAnnounced).toList(growable: false);
    debugPrint(
      'VELORKI_NAV route ${route.lengthM.round()}m ${line.length} points, '
      '${turns.length} announced turns',
    );
    expect(
      turns.length,
      greaterThanOrEqualTo(2),
      reason: 'the ride needs turns to be guided through',
    );

    // ----------------------------------------------------- turns on, voice off
    await tapAndPump(tester, find.text('Record'));
    // The navigation switches sit below the fold of the idle sheet, under the
    // two recording ones.
    final sheet = find
        .descendant(
          of: find.byType(DraggableScrollableSheet),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.dragUntilVisible(
      find.byType(NavigationToggles),
      sheet,
      const Offset(0, -220),
    );
    await waitForWidget(tester, find.byType(NavigationToggles));
    final l10n = AppLocalizations.of(
      tester.element(find.byType(NavigationToggles)),
    );
    await tapAndPump(
      tester,
      find.widgetWithText(SwitchListTile, l10n.settingsVoiceDirections),
    );
    await waitUntil(
      tester,
      () => !container.read(navigationSettingsProvider).voice,
      describe: 'the voice switch to go off',
      onTimeout: () => '${container.read(navigationSettingsProvider)}',
    );
    final chosen = container.read(navigationSettingsProvider);
    expect(chosen.turns, isTrue, reason: 'the turn directions stay on');
    expect(chosen.reroute, isTrue, reason: 're-routing stays on');

    // -------------------------------------------------------------- the ride
    // The start button is back above the fold, and the sheet's list has
    // thrown it away while the switches were on screen.
    await tester.dragUntilVisible(
      find.widgetWithText(FilledButton, 'Start ride'),
      sheet,
      const Offset(0, 220),
    );
    await tapAndPump(tester, find.widgetWithText(FilledButton, 'Start ride'));
    await waitUntil(
      tester,
      () => positions.isListenedTo,
      describe: 'the recorder to subscribe to the GPS',
      onTimeout: () =>
          '${container.read(recordingControllerProvider).snapshot}',
    );

    final ride = ScriptedRide(source: positions, line: line);
    await ride.rideTo(tester, ride.stepM);
    await waitUntil(
      tester,
      () => _progress(tester)?.next != null,
      describe: 'the turn banner to show the first turn',
      onTimeout: () => '${container.read(navigationControllerProvider)}',
    );

    // The banner in the tree was built from this progress, so the texts it
    // rendered are exactly the ones these two lines ask for. Nothing is
    // pumped in between, so nothing can move underneath them.
    final units = container.read(unitSystemProvider);
    var showing = _progress(tester)!;
    final firstTurn = showing.next!;
    final firstLabel = turnLabel(firstTurn, l10n);
    debugPrint(
      'VELORKI_NAV first banner: $firstLabel in '
      '${showing.distanceToNextM.round()}m',
    );
    expect(
      find.text(distanceLabel(showing.distanceToNextM, l10n, units)),
      findsOneWidget,
      reason: 'the banner shows how far the turn is',
    );
    expect(find.text(firstLabel), findsOneWidget);

    // ------------------------------------------- past the first turn, and on
    // Ridden in stages rather than in one go: navigation only sees the
    // position of the last snapshot, so the ride has to stop for a tick now
    // and then for the banner to follow it at all.
    String? secondLabel;
    for (
      var target = _cumulativeTo(line, firstTurn.pointIndex) + _pastTurnM;
      target < ride.totalM;
      target += 60
    ) {
      await ride.rideTo(tester, target);
      await pumpFor(tester, _tick);
      final next = _progress(tester)?.next;
      if (next != null &&
          next.pointIndex > firstTurn.pointIndex &&
          turnLabel(next, l10n) != firstLabel) {
        secondLabel = turnLabel(next, l10n);
        break;
      }
    }
    expect(
      secondLabel,
      isNotNull,
      reason: 'the instruction has to change once the first turn is behind',
    );
    showing = _progress(tester)!;
    debugPrint(
      'VELORKI_NAV after the first turn: $secondLabel in '
      '${showing.distanceToNextM.round()}m, ${showing.alongM.round()}m along',
    );
    expect(
      showing.alongM,
      greaterThan(_cumulativeTo(line, firstTurn.pointIndex)),
    );
    expect(find.text(secondLabel!), findsOneWidget);
    expect(find.text(firstLabel), findsNothing);
    expect(
      find.text(distanceLabel(showing.distanceToNextM, l10n, units)),
      findsOneWidget,
    );
    await screenshot(tester, 'navigation-turn-banner');

    // ------------------------------------------------------------- the end
    await ride.rideTo(tester, ride.totalM);
    await waitUntil(
      tester,
      () => _progress(tester)?.arrived ?? false,
      describe: 'the banner to say the ride has arrived',
      timeout: const Duration(seconds: 20),
      onTimeout: () => '${container.read(navigationControllerProvider)}',
    );
    expect(find.text(l10n.navArrived), findsOneWidget);
    await screenshot(tester, 'navigation-arrived');

    // --------------------------------------------------------- off the route
    // Every state the controller passes through, because some of them do not
    // last a frame: the re-route answer comes back in well under a tenth of a
    // second on the device, so "off route" can be gone before it is ever
    // drawn.
    final passed = <NavigationProgress?>[];
    final watch = container.listen(
      navigationControllerProvider,
      (_, next) => passed.add(next),
    );
    addTearDown(watch.close);

    // Walked out rather than teleported: a jump of 150 m in one fix implies a
    // speed the recorder throws away as impossible, and it takes three stray
    // fixes in a row before the navigator calls the rider off route anyway.
    for (var offset = 25.0; offset <= _strayM; offset += 25) {
      await ride.strayTo(tester, offset);
      await pumpFor(tester, _tick);
    }
    await waitUntil(
      tester,
      () =>
          container.read(detourRouteProvider) != null ||
          passed.any((p) => p?.rerouting ?? false),
      describe: 'a way back onto the route to be asked for',
      timeout: const Duration(seconds: 20),
      onTimeout: () => '${container.read(navigationControllerProvider)}',
    );
    final detour = container.read(detourRouteProvider);
    debugPrint(
      'VELORKI_NAV off route: ${passed.where((p) => p?.offRoute ?? false).length}'
      ' of ${passed.length} states off route, '
      'detour=${detour?.line.length ?? 0} points',
    );
    expect(
      passed.any((p) => p?.offRoute ?? false),
      isTrue,
      reason: 'a fix $_strayM m off the route has to count as off route',
    );
    expect(
      detour != null || passed.any((p) => p?.rerouting ?? false),
      isTrue,
      reason: 'leaving the route has to ask the router for a way back',
    );

    // The detour starts where the rider strayed to, so following it would put
    // them back on a route. Carrying on away from it is what leaves the
    // banner on "off route" long enough to read: the next re-route is a good
    // twenty seconds off, and until then there is nothing else to show.
    var offRouteShown = false;
    for (
      var offset = _strayM + 50;
      offset <= 400 && !offRouteShown;
      offset += 50
    ) {
      await ride.strayTo(tester, offset);
      await pumpFor(tester, _tick);
      final progress = _progress(tester);
      if (progress == null || !(progress.offRoute || progress.rerouting)) {
        continue;
      }
      // Nothing is pumped between reading the progress and this, so the
      // banner in the tree is still the one that progress built.
      expect(
        find.text(progress.rerouting ? l10n.navRerouting : l10n.navOffRoute),
        findsOneWidget,
      );
      offRouteShown = true;
      await screenshot(tester, 'navigation-off-route');
    }
    expect(
      offRouteShown,
      isTrue,
      reason: 'the banner has to tell the rider they left the route',
    );

    // ------------------------------------------------------------- the voice
    expect(
      speaker.spoken,
      isEmpty,
      reason: 'the voice was switched off, so nothing may be said',
    );
    expect(speaker.selections, isEmpty);

    // Leaves the device without a running recording for the next test.
    await tapAndPump(
      tester,
      find.byTooltip('Finish'),
      settle: const Duration(seconds: 2),
    );
    await waitUntil(
      tester,
      () => !container.read(recordingControllerProvider).isRecording,
      describe: 'the ride to finish',
      onTimeout: () => '${container.read(recordingControllerProvider)}',
    );
    await unmountApp(tester);
  });
}

/// Turn kinds the navigator tells the rider about; see `_announced` in
/// turn_navigator.dart.
bool _isAnnounced(TurnHint hint) =>
    hint.kind != TurnKind.straight &&
    hint.kind != TurnKind.beeline &&
    hint.kind != TurnKind.offRoad;

/// The progress the [TurnBanner] on screen was built from, or `null` while
/// there is no banner.
NavigationProgress? _progress(WidgetTester tester) {
  final banner = find.byType(TurnBanner).evaluate();
  if (banner.isEmpty) return null;
  return (banner.first.widget as TurnBanner).progress;
}

/// Waits for the planner to finish the route it is computing and hands it back.
Future<RouteResult> _routed(
  WidgetTester tester,
  ProviderContainer container, {
  required String describe,
}) async {
  await pumpFor(tester, const Duration(milliseconds: 400));
  await waitUntil(
    tester,
    () {
      final state = container.read(plannerControllerProvider);
      if (state.route.hasError) fail('routing failed: ${state.route.error}');
      return state.result != null && !state.isRouting;
    },
    describe: 'the on-device router to answer for $describe',
    timeout: const Duration(seconds: 90),
    onTimeout: () => '${container.read(plannerControllerProvider).route}',
  );
  return container.read(plannerControllerProvider).result!;
}

/// Distance from the start of [line] to its point [index].
double _cumulativeTo(List<LatLng> line, int index) {
  var metres = 0.0;
  for (var i = 1; i <= index && i < line.length; i++) {
    metres += haversineMeters(line[i - 1], line[i]);
  }
  return metres;
}

/// The point [metres] along [line], or its last point when it is shorter.
LatLng _pointAlong(List<LatLng> line, double metres) {
  var covered = 0.0;
  for (var i = 1; i < line.length; i++) {
    covered += haversineMeters(line[i - 1], line[i]);
    if (covered >= metres) return line[i];
  }
  return line.last;
}

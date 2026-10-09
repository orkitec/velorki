// The App Store screenshots: every screen the slides use, from the real app
// on Madeira (the cycle map in New York), in one language, in each app theme
// asked for.
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
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/core/plus/plus_gate.dart';
import 'package:velorki/features/assistant/application/assistant_controller.dart';
import 'package:velorki/features/assistant/presentation/assistant_sheet.dart';
import 'package:velorki/features/import_export/data/incoming_file_service.dart';
import 'package:velorki/features/map/data/map_preferences.dart';
import 'package:velorki/features/map/domain/cycle_map.dart';
import 'package:velorki/features/map/presentation/layers_sheet.dart';
import 'package:velorki/features/recording/application/ride_notification_updater.dart';
import 'package:velorki/features/recording/data/follow_mode.dart';
import 'package:velorki/features/smart_loop/application/smart_loop_controller.dart';
import 'package:velorki/features/planner/application/planner_controller.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/planner/domain/route_profile.dart';
import 'package:velorki/features/recording/application/recording_controller.dart';
import 'package:velorki/features/recording/presentation/live_figures_view.dart';
import 'package:velorki/features/recording/presentation/recording_screen.dart';
import 'package:velorki/features/recording/presentation/ride_charts.dart';
import 'package:velorki/features/search/data/gazetteer_store.dart';
import 'package:velorki/features/settings/data/appearance_controller.dart';
import 'package:velorki/features/settings/data/units.dart';
import 'package:velorki/features/shared/presentation/docking_sheet.dart';
import 'package:velorki/features/subscription/presentation/paywall_screen.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';
import 'package:velorki_gpx/velorki_gpx.dart';

import '../../test/support/mock_relay.dart';
import '../support/fakes.dart';
import '../support/harness.dart';
import '../support/tiles.dart';
import 'demo_data.dart';
import 'shutter.dart';
import 'store_support.dart';

const bool _enabled = bool.fromEnvironment('VELORKI_STORE_SHOTS');
const String _locale = String.fromEnvironment(
  'VELORKI_STORE_LOCALE',
  defaultValue: 'en',
);
const String _themes = String.fromEnvironment(
  'VELORKI_STORE_THEMES',
  defaultValue: 'light,dark',
);

/// The last screen to take, for a run that only needs the first few; the
/// screens come in the order of the sections below. Empty takes them all.
const String _until = String.fromEnvironment('VELORKI_STORE_UNTIL');

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
      final session = await startStoreApp(
        tester,
        locale: _locale,
        mode: mode,
        // The rider stands at the plan's start for the first shots, under
        // its marker, and moves to [funchal] before the loop; a position
        // dot of its own would sit on the town's name.
        origin: featuredRoute.waypoints.first,
      );
      final container = session.container;
      final positions = session.positions;
      final ride = session.clock;
      final appearance = container.read(appearanceSettingProvider.notifier);

      final shot = '$theme/$_locale';
      final featured = await seedLibrary(tester, container);
      await seedOfflineMap(tester, container);
      final planner = container.read(plannerControllerProvider.notifier);
      Future<bool> stopAfter(String screen) async {
        if (_until != screen) return false;
        planner.clear();
        await unmountApp(tester);
        return true;
      }

      // ------------------------------------------------------- cycle map
      // The offline cycle map and the stops, drawn on the device from New
      // York's routing tile and gazetteer (Funchal has too few bike lanes to
      // show them), with the parts and the kinds of stop the app starts
      // with; then the Layers sheet that switches them.
      await ensureRegionTile(tester, container, name: cycleMapTile);
      await (await container.read(gazetteerStoreProvider.future)).refresh();
      final cycleMap = container.read(cycleMapPreferencesProvider.notifier);
      for (final part in CycleMapPart.values) {
        await cycleMap.setPart(
          part,
          shown: defaultCycleMapParts.contains(part),
        );
      }
      final stops = container.read(mapStopsPreferencesProvider.notifier);
      for (final kind in {
        ...container.read(mapStopsPreferencesProvider).kinds,
        ...defaultStopKinds,
      }) {
        await stops.setKind(kind, shown: defaultStopKinds.contains(kind));
      }
      await cycleMap.setShown(true);
      await stops.setShown(true);
      planner.clear();
      await frameArea(tester, container, chelsea, chelseaZoom);
      // The first shot of a run waits for the map style and its tiles.
      await takeStoreShot(
        tester,
        '$shot/cyclemap',
        hold: const Duration(seconds: 20),
      );

      if (await stopAfter('cyclemap')) return;

      await tapAndPump(tester, find.byTooltip(l10n.mapLayers));
      await waitForWidget(tester, find.byType(LayersSheet));
      await takeStoreShot(tester, '$shot/layers');
      Navigator.of(tester.element(find.byType(LayersSheet))).pop();
      await cycleMap.setShown(false);
      await stops.setShown(false);
      await pumpFor(tester, const Duration(seconds: 1));

      if (await stopAfter('layers')) return;

      // ------------------------------------------------------------ plan
      planner
        ..clear()
        ..loadSavedRoute(featured);
      await frameRoute(tester, container, featured.geometry);
      // The first shot over Madeira waits for its tiles.
      await takeStoreShot(
        tester,
        '$shot/plan',
        hold: const Duration(seconds: 10),
      );

      if (await stopAfter('plan')) return;

      // -------------------------------------------------------- variants
      await tapAndPump(tester, plannerAction(l10n.plannerVariants));
      await waitUntil(
        tester,
        () {
          final state = container.read(plannerControllerProvider);
          return state.alternatives.length > 1 && !state.loadingAlternatives;
        },
        describe: 'the variants',
        timeout: const Duration(minutes: 5),
        onTimeout: () {
          final state = container.read(plannerControllerProvider);
          return '${state.alternatives.length} variants, '
              'loading ${state.loadingAlternatives}, error ${state.error}';
        },
      );
      await tapAndPump(tester, find.text(l10n.plannerAlternativeIndex(1)));
      // Tapping scrolled the sheet's content; the chips belong at its top.
      scrollSheetToTop(tester);
      await takeStoreShot(tester, '$shot/variants');

      if (await stopAfter('variants')) return;

      // ------------------------------------------------------------ loop
      // From the rider's position, at the distance seeded before the start.
      positions.emit(fix(funchal, seconds: 0, speed: 0));
      planner.clear();
      await pumpFor(tester, const Duration(milliseconds: 500));
      await tapAndPump(tester, plannerAction(l10n.loopAction));
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
        timeout: const Duration(minutes: 5),
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

      if (await stopAfter('loop')) return;

      // -------------------------------------------------------------- ai
      // The AI card, asked for a loop from the rider's position: the relay is
      // the in-process mock (see startStoreApp), its answer fixed in
      // demo_data, and the loop planned on the device through the place it
      // names. Opened again on the loop, the card shows what was asked and
      // what came back, the loop on the map above it.
      await grantAssistant(tester, container);
      session.relay.reply(
        RelayReply.stream([
          SseFrame.routeRequest(assistantAnswer),
          SseFrame.done(),
        ], gap: const Duration(milliseconds: 300)),
      );
      Finder inCard(Finder f) =>
          find.descendant(of: find.byType(AssistantSheet), matching: f);
      Future<void> openCard() async {
        await tapAndPump(tester, plannerAction(l10n.assistantAction));
        await waitForWidget(tester, find.byType(AssistantSheet));
        await pumpFor(tester, const Duration(milliseconds: 600));
      }

      await openCard();
      await tester.enterText(
        inCard(find.byType(TextField)),
        assistantPrompts[_locale] ?? assistantPrompts['en']!,
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await pumpFor(tester, const Duration(milliseconds: 600));
      await tapAndPump(
        tester,
        inCard(find.widgetWithText(FilledButton, l10n.assistantSend)),
      );
      await waitUntil(
        tester,
        () => find.byType(AssistantSheet).evaluate().isEmpty,
        describe: 'the AI card to make way for the loop',
        onTimeout: () => '${container.read(assistantControllerProvider)}',
      );
      await waitUntil(
        tester,
        () {
          final state = container.read(plannerControllerProvider);
          return state.result != null && !state.isRouting;
        },
        describe: 'the loop the assistant asked for',
        timeout: const Duration(minutes: 5),
        onTimeout: () => '${container.read(plannerControllerProvider).route}',
      );
      final aiLoop = container.read(plannerControllerProvider).result!;
      debugPrint('VELORKI_STORE ai loop ${aiLoop.lengthM.round()} m');
      await openCard();
      await tapAndPump(tester, inCard(find.text(l10n.assistantModeNew)));
      // At rest the answer is under the bar: the card is pulled up just far
      // enough, and its content scrolled to the end, for the request, Ask and
      // the answer to show together, the loop on the map above them.
      final card = tester
          .widget<DraggableScrollableSheet>(
            inCard(find.byType(DraggableScrollableSheet)),
          )
          .controller!;
      final content = inCard(
        find.descendant(
          of: find.byType(Scrollbar),
          matching: find.byType(Scrollable),
        ),
      ).first;
      for (var i = 0; i < 4; i++) {
        final scroll = tester.state<ScrollableState>(content).position;
        scroll.jumpTo(scroll.maxScrollExtent);
        await pumpFor(tester, const Duration(milliseconds: 300));
        final short =
            tester.getRect(content).top -
            tester.getRect(inCard(find.byType(TextField))).top +
            12;
        if (short <= 1) break;
        card.jumpTo(card.size + card.pixelsToSize(short));
        await pumpFor(tester, const Duration(milliseconds: 300));
      }
      final cardHandle = find.descendant(
        of: find.byKey(assistantSheetSurfaceKey),
        matching: find.byType(SheetHandle),
      );
      await frameRoute(tester, container, aiLoop.geometry, handle: cardHandle);
      await takeStoreShot(tester, '$shot/ai');
      for (var i = 0; i < 3 && cardHandle.evaluate().isNotEmpty; i++) {
        await tester.fling(
          cardHandle,
          const Offset(0, 600),
          2000,
          warnIfMissed: false,
        );
        await pumpFor(tester, const Duration(milliseconds: 800));
      }
      // The rest is planned on the default bike, as before the AI chose one.
      planner
        ..clear()
        ..setProfile(RouteProfile.trekking);

      if (await stopAfter('ai')) return;

      // ---------------------------------------------------------- paywall
      // Velorki Plus to someone without it, at the stores' prices (see
      // plusOffering): the top of the page, then its end, with the plans,
      // Subscribe and the terms.
      // First as a subscriber sees it, for the website's Plus section: the
      // same page with the active banner where the prices are, which the
      // site never quotes.
      container.read(plusEntitledProvider.notifier).value = true;
      unawaited(container.read(routerProvider).push(paywallRoute));
      await waitForWidget(tester, find.byType(PaywallScreen));
      await pumpFor(tester, const Duration(seconds: 1));
      await takeStoreShot(tester, '$shot/paywall-active');
      container.read(routerProvider).pop();
      await pumpFor(tester, const Duration(seconds: 1));
      container.read(plusEntitledProvider.notifier).value = false;
      unawaited(container.read(routerProvider).push(paywallRoute));
      await waitForWidget(tester, find.byType(PaywallScreen));
      await pumpFor(tester, const Duration(seconds: 1));
      await takeStoreShot(tester, '$shot/paywall-top');
      final paywall = find
          .descendant(
            of: find.byType(PaywallScreen),
            matching: find.byType(Scrollable),
          )
          .first;
      // A lazy list knows its end only once it has built it.
      for (var i = 0; i < 3; i++) {
        final scroll = tester.state<ScrollableState>(paywall).position;
        scroll.jumpTo(scroll.maxScrollExtent);
        await pumpFor(tester, const Duration(milliseconds: 300));
      }
      await takeStoreShot(tester, '$shot/paywall-bottom');
      container.read(routerProvider).pop();
      await pumpFor(tester, const Duration(seconds: 1));

      if (await stopAfter('paywall')) return;

      // ---------------------------------------------------------- import
      final rideRoute = await planRoute(tester, container, rideWaypoints);
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
      // The preview's own map loads its marker images after the route
      // shows; on a loaded emulator that takes a while longer.
      await takeStoreShot(
        tester,
        '$shot/import',
        hold: const Duration(seconds: 20),
      );

      if (await stopAfter('import')) return;

      // ------------------------------------------------------------ ride
      await tapAndPump(tester, find.text(l10n.commonSave).last);
      await waitForWidget(
        tester,
        find.byType(RideElevationChart),
        timeout: const Duration(seconds: 30),
      );
      clearSnackBars(tester);
      await dragSheetUp(tester);
      await Scrollable.ensureVisible(
        tester.element(find.byType(RideElevationChart)),
      );
      await takeStoreShot(tester, '$shot/ride');

      if (await stopAfter('ride')) return;

      // --------------------------------------------------------- library
      await tapAndPump(tester, find.text(l10n.tabLibrary));
      await tapAndPump(tester, find.text(l10n.tabLibrary));
      await tapAndPump(tester, find.text(l10n.libraryRoutes));
      await waitForWidget(tester, find.text(featuredRoute.name));
      clearSnackBars(tester);
      await takeStoreShot(tester, '$shot/library');

      if (await stopAfter('library')) return;

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
      await frameRoute(tester, container, coast.geometry);
      await takeStoreShot(tester, '$shot/offline', offline: true);
      // The same in another accent, for the dark half of the slide that
      // shows the themes with it.
      if (mode == ThemeMode.dark) {
        await appearance.setAccent(AccentPreset.ember);
        await takeStoreShot(tester, '$shot/offline-accent', offline: true);
        await appearance.setAccent(AccentPreset.volt);
        await pumpFor(tester, const Duration(seconds: 2));
      }
      planner.clear();

      if (await stopAfter('offline')) return;

      // ------------------------------------------------ live and navigation
      // Funchal to Santa Cruz by Camacha, ridden the way the demo ride is: most of it fast
      // forward, then a fix a second until a turn comes up about 20 km in.
      final route = await planRoute(tester, container, liveRideWaypoints);
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
      final rider = Rider(positions, ride, demoRide(route));
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
        final progress = bannerProgress(tester);
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
      // that draw them: the same snapshot the live card was built from. The
      // Play set has neither.
      if (Platform.isIOS) {
        await sendStoreData(
          tester,
          '$shot/activity',
          rideActivityData(
            l10n,
            UnitSystem.metric,
            container.read(recordingControllerProvider).snapshot!,
            bannerProgress(tester),
          ),
        );
      }
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

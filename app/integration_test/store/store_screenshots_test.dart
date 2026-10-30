// The App Store screenshots: every screen the slides use, from the real app
// on Madeira (the cycle map in New York), in every language and app theme
// asked for, in one run.
//
// Each screen is set up once, in the first language and theme, and then
// shot in every theme and language by switching them in the app's own
// settings, which rebuilds the screen in place: open sheets, scroll positions
// and the map stay. Only what the app does not translate itself is redone per
// language (the AI prompt the rider typed, the paywall's prices, the imported
// ride's name, a sheet scrolled to a button). So the routing, the loop search
// and the ride are done once, not once per language and theme.
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
import 'package:velorki/features/map/application/map_drawn.dart';
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
import 'package:velorki/features/recording/data/ride_repository.dart';
import 'package:velorki/features/settings/data/appearance_controller.dart';
import 'package:velorki/features/settings/data/language_controller.dart';
import 'package:velorki/features/settings/data/units.dart';
import 'package:velorki/features/shared/presentation/docking_sheet.dart';
import 'package:velorki/features/subscription/application/subscription_controller.dart';
import 'package:velorki/features/subscription/presentation/paywall_screen.dart';
import 'package:velorki/features/weather/application/route_overlay.dart';
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
const String _locales = String.fromEnvironment(
  'VELORKI_STORE_LOCALES',
  defaultValue: 'en',
);
const String _themes = String.fromEnvironment(
  'VELORKI_STORE_THEMES',
  defaultValue: 'light,dark',
);

/// The last screen to take, for a run that only needs the first few; the
/// screens come in the order of the sections below. Empty takes them all.
const String _until = String.fromEnvironment('VELORKI_STORE_UNTIL');

/// The pictures the slides use, as `screen:theme` pairs (tool/store_need.py);
/// empty takes every screen in every theme.
const String _need = String.fromEnvironment('VELORKI_STORE_NEED');

/// Whether [screen] is wanted in any theme: a screen nobody wants is not
/// even set up, where nothing after it depends on it.
bool _any(String screen) =>
    _need.isEmpty || _need.split(',').any((p) => p.startsWith('$screen:'));

/// Whether [screen] is wanted in [mode].
bool _wanted(String screen, ThemeMode mode) =>
    _need.isEmpty || _need.split(',').contains('$screen:${mode.name}');

/// Takes every picture after a change of language twice, the second
/// [_lateHold] later as `<screen>-late`, to check that settleFrames and waitForMapDrawn waited
/// long enough: the pairs should not differ.
const bool _lateCheck = bool.fromEnvironment('VELORKI_STORE_LATE_CHECK');
const Duration _lateHold = Duration(seconds: 4);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final locales = [
    for (final l in _locales.split(','))
      if (l.trim().isNotEmpty) l.trim(),
  ];
  final themes = [
    for (final t in _themes.split(','))
      if (t.trim().isNotEmpty) ThemeMode.values.byName(t.trim()),
  ];
  // The screens are set up in the first language, so its texts find their
  // buttons; every shot puts it back when it is done.
  final base = locales.first;
  final l10n = lookupAppLocalizations(Locale(base));

  testWidgets('store screenshots, ${locales.join(',')}, $_themes', (
    tester,
  ) async {
    if (!_enabled) {
      markTestSkipped('only tool/store_screenshots.sh runs this');
      return;
    }
    final session = await startStoreApp(
      tester,
      locale: base,
      mode: themes.first,
      // The rider stands at the plan's start for the first shots, under
      // its marker, and moves to [funchal] before the loop; a position
      // dot of its own would sit on the town's name.
      origin: featuredRoute.waypoints.first,
    );
    final container = session.container;
    final positions = session.positions;
    final ride = session.clock;
    final appearance = container.read(appearanceSettingProvider.notifier);
    final language = container.read(languageSettingProvider.notifier);

    /// Shoots [screen] as it stands in every theme (those [only] allows)
    /// and every language of [inLocales], all of [locales] by default,
    /// starting in the theme it finds and leaving the last one, then puts
    /// the first language back.
    ///
    /// Nothing waits a fixed time. The first picture in each theme waits
    /// for the map to have drawn what changed since the last
    /// [markMapChange] (the screen's set-up, the switch of theme), at most
    /// [hold]; [mapChanges] false says the set-up left the map as it was (a
    /// sheet over it); [mapShown] false that no map is on screen at all (a
    /// page over it), which then never draws; [weather] that the map shows
    /// the weather, whose frames must be back after a change of theme, and
    /// [cycleMap] the same of the cycle map, and [route] that a route line
    /// has to be on the map first. Every
    /// picture waits for Flutter to have
    /// drawn everything: a change of language only redraws its texts.
    /// [relocalize] puts right what the app does not translate itself,
    /// before each picture.
    Future<void> shoot(
      String screen, {
      Duration? hold,
      bool offline = false,
      bool mapChanges = true,
      bool mapShown = true,
      bool weather = false,
      bool cycleMap = false,
      bool route = false,
      bool Function(ThemeMode mode)? only,
      List<String>? inLocales,
      Future<void> Function(ThemeMode mode, String locale)? relocalize,
    }) async {
      final these = inLocales ?? locales;
      // On the emulator the map is drawn in software: a change of theme
      // reloads its style, which takes 15 to 20 s to draw, and the map's
      // idle ends the wait long before this anywhere it can.
      final cap = Platform.isAndroid
          ? const Duration(seconds: 30)
          : hold ?? const Duration(seconds: 4);
      // The theme the last screen left first: one change of theme a
      // screen, not two.
      final current = container.read(appearanceSettingProvider).mode;
      final order = [
        if (themes.contains(current)) current,
        for (final mode in themes)
          if (mode != current) mode,
      ];
      for (final mode in order) {
        if (only != null && !only(mode)) continue;
        if (!_wanted(screen, mode)) continue;
        final switched = container.read(appearanceSettingProvider).mode != mode;
        final styles = MapDrawn.styles.value;
        final frames = MapDrawn.weatherFrames.value;
        final cycles = MapDrawn.cycleMaps.value;
        if (switched) markMapChange();
        await appearance.setMode(mode);
        if (switched && mapShown) {
          // A change of theme swaps the map's style: an idle before the new
          // one has loaded is the old style's, and a picture then caught the
          // map half drawn.
          await waitUntil(
            tester,
            () => MapDrawn.styles.value > styles,
            describe: 'the map style for ${mode.name}',
            timeout: const Duration(seconds: 60),
          );
          // The weather's frames go back on the new style once loaded.
          if (weather) {
            await waitUntil(
              tester,
              () => MapDrawn.weatherFrames.value > frames,
              describe: 'the weather drawn again in ${mode.name}',
              timeout: const Duration(seconds: 60),
            );
          }
          if (cycleMap) {
            await waitUntil(
              tester,
              () => MapDrawn.cycleMaps.value > cycles,
              describe: 'the cycle map drawn again in ${mode.name}',
              timeout: const Duration(seconds: 60),
            );
          }
          markMapChange();
        }
        var first = true;
        for (final locale in these) {
          await language.select(Locale(locale));
          if (relocalize != null) {
            // Laid out in the new language first: the fixes measure it.
            await settleFrames(tester);
            await relocalize(mode, locale);
          }
          if (first && route) {
            // An owner draws its markers first and its route after them;
            // the map can go idle in between.
            await waitUntil(
              tester,
              () => MapDrawn.routeLines > 0,
              describe: 'the route on the map for $screen',
              timeout: const Duration(seconds: 60),
            );
          }
          if (first && mapShown && (mapChanges || switched)) {
            await waitForMapDrawn(tester, cap: cap, label: screen);
          }
          await settleFrames(tester, margin: true, label: screen);
          await takeStoreShot(
            tester,
            '${mode.name}/$locale/$screen',
            hold: Duration.zero,
            offline: offline,
          );
          if (_lateCheck) {
            await takeStoreShot(
              tester,
              '${mode.name}/$locale/$screen-late',
              hold: _lateHold,
              offline: offline,
            );
          }
          first = false;
        }
      }
      await language.select(Locale(these.first));
      await settleFrames(tester);
      // What the next screen's set-up changes on the map comes after this.
      markMapChange();
    }

    bool dark(ThemeMode mode) => mode == ThemeMode.dark;
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
      await cycleMap.setPart(part, shown: defaultCycleMapParts.contains(part));
    }
    final stops = container.read(mapStopsPreferencesProvider.notifier);
    for (final kind in {
      ...container.read(mapStopsPreferencesProvider).kinds,
      ...defaultStopKinds,
    }) {
      await stops.setKind(kind, shown: defaultStopKinds.contains(kind));
    }
    final cyclesBefore = MapDrawn.cycleMaps.value;
    await cycleMap.setShown(true);
    // The stops read best on a plain route line.
    await container.read(routeColouringOnProvider.notifier).set(on: false);
    await stops.setShown(true);
    planner.clear();
    await frameArea(tester, container, chelsea, chelseaZoom);
    // The first shot of a run waits for the map style and its tiles.
    // The cycle map is drawn once its data is built from the tile, which
    // can be after the map has gone idle.
    await waitUntil(
      tester,
      () => MapDrawn.cycleMaps.value > cyclesBefore,
      describe: 'the cycle map drawn',
      // Built from the tile in the background: over 90 s once on a CI
      // tablet emulator, whose larger map needs more of it.
      timeout: const Duration(minutes: 3),
    );
    markMapChange();
    await shoot('cyclemap', hold: const Duration(seconds: 20), cycleMap: true);

    if (await stopAfter('cyclemap')) return;

    await tapAndPump(tester, find.byTooltip(l10n.mapLayers));
    await waitForWidget(tester, find.byType(LayersSheet));
    await shoot('layers', mapChanges: false, cycleMap: true);
    Navigator.of(tester.element(find.byType(LayersSheet))).pop();
    await cycleMap.setShown(false);
    await stops.setShown(false);
    await settleFrames(tester);

    if (await stopAfter('layers')) return;

    // ------------------------------------------------------------ plan
    planner
      ..clear()
      ..loadSavedRoute(featured);
    await frameRoute(tester, container, featured.geometry);
    // The first shot over Madeira waits for its tiles.
    await shoot('plan', route: true, hold: const Duration(seconds: 10));

    if (await stopAfter('plan')) return;

    if (_any('variants')) {
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
      await shoot(
        'variants',
        route: true,
        relocalize: (_, _) async => scrollSheetToTop(tester),
      );
    }
    if (await stopAfter('variants')) return;

    // --------------------------------------------------------- weather
    // The featured route coloured by the rain on the way, under the map's
    // rain, for a ride leaving four hours from now.
    final colouringOn = container.read(routeColouringOnProvider);
    final restoreWeather = await showRouteRain(
      tester,
      container,
      featured,
      offsetMinutes: 240,
      save: l10n.plannerSave,
    );
    await shoot(
      'weather',
      route: true,
      weather: true,
      hold: const Duration(seconds: 8),
      // The time control and the colours' key under the Save button, in
      // each language's own heights.
      relocalize: (_, locale) async {
        scrollPlannerSheetTo(
          tester,
          lookupAppLocalizations(Locale(locale)).plannerSave,
        );
      },
    );
    await restoreWeather();

    if (await stopAfter('weather')) return;

    // ----------------------------------------------------------- stops
    // The stops beside a route, drawn from the region's gazetteer, with
    // the status bar showing no signal at all; in the dark, in another
    // accent, for the other half of the slide that shows the themes too.
    final stopsRoute =
        (await container.read(routeRepositoryProvider).watchRoutes().first)
            .firstWhere((r) => r.name == stopsRouteName);
    // The stops read best on a plain route line.
    await container.read(routeColouringOnProvider.notifier).set(on: false);
    await stops.setShown(true);
    planner
      ..clear()
      ..loadSavedRoute(stopsRoute);
    await frameRoute(tester, container, stopsRoute.geometry);
    await shoot(
      'stops',
      route: true,
      offline: true,
      hold: const Duration(seconds: 8),
    );
    if (themes.any(dark)) {
      markMapChange();
      await appearance.setAccent(AccentPreset.ember);
      await shoot('stops-accent', route: true, offline: true, only: dark);
      markMapChange();
      await appearance.setAccent(AccentPreset.volt);
      await waitForMapDrawn(tester, cap: const Duration(seconds: 4));
    }
    await stops.setShown(false);
    await container
        .read(routeColouringOnProvider.notifier)
        .set(on: colouringOn);
    planner.clear();

    if (await stopAfter('stops')) return;

    // ------------------------------------------------------------ loop
    // From the rider's position, at the distance seeded before the start.
    positions.emit(fix(funchal, seconds: 0, speed: 0));
    planner.clear();
    await settleFrames(tester);
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
    await shoot('loop', route: true);
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
      await settleFrames(tester);
    }

    await openCard();
    await tester.enterText(
      inCard(find.byType(TextField)),
      assistantPrompts[base] ?? assistantPrompts['en']!,
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await settleFrames(tester);
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
    final cardHandle = find.descendant(
      of: find.byKey(assistantSheetSurfaceKey),
      matching: find.byType(SheetHandle),
    );
    Future<void> fitCard() async {
      for (var i = 0; i < 4; i++) {
        final scroll = tester.state<ScrollableState>(content).position;
        scroll.jumpTo(scroll.maxScrollExtent);
        await settleFrames(tester);
        final short =
            tester.getRect(content).top -
            tester.getRect(inCard(find.byType(TextField))).top +
            12;
        if (short <= 1) break;
        card.jumpTo(card.size + card.pixelsToSize(short));
        await settleFrames(tester);
      }
      await frameRoute(tester, container, aiLoop.geometry, handle: cardHandle);
    }

    await fitCard();
    // The rider's request in each language, the card fitted to it again.
    await shoot(
      'ai',
      route: true,
      relocalize: (_, locale) async {
        // Into the field's controller: with an answer on the card, typing
        // through the test's keyboard never reaches it.
        final field = tester
            .widget<TextField>(inCard(find.byType(TextField)))
            .controller!;
        final prompt = assistantPrompts[locale] ?? assistantPrompts['en']!;
        // Fitted to this prompt already: fitted again, the map would not
        // move, and the picture would wait for a redraw that never comes.
        if (field.text == prompt) return;
        field.text = prompt;
        await settleFrames(tester);
        await fitCard();
      },
    );
    for (var i = 0; i < 3 && cardHandle.evaluate().isNotEmpty; i++) {
      await tester.fling(
        cardHandle,
        const Offset(0, 600),
        2000,
        warnIfMissed: false,
      );
      await settleFrames(tester);
    }
    // The rest is planned on the default bike, as before the AI chose one.
    planner
      ..clear()
      ..setProfile(RouteProfile.trekking);

    if (await stopAfter('ai')) return;

    if (_any('paywall-active') ||
        _any('paywall-top') ||
        _any('paywall-bottom')) {
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
      await settleFrames(tester);
      await shoot('paywall-active', mapShown: false);
      container.read(routerProvider).pop();
      await settleFrames(tester);
      container.read(plusEntitledProvider.notifier).value = false;
      unawaited(container.read(routerProvider).push(paywallRoute));
      await waitForWidget(tester, find.byType(PaywallScreen));
      await settleFrames(tester);
      // The prices in each language's currency and format: the store asked
      // again for its offering.
      Future<void> price(String locale) async {
        session.subscriptions.offering = plusOffering(locale);
        container.invalidate(plusOfferingProvider);
        await waitUntil(
          tester,
          // The fake hands back the very offering it was given.
          () => identical(
            container.read(plusOfferingProvider).value,
            session.subscriptions.offering,
          ),
          describe: 'the offering in $locale',
        );
        await settleFrames(tester);
      }

      await shoot(
        'paywall-top',
        mapShown: false,
        relocalize: (_, locale) => price(locale),
      );
      final paywall = find
          .descendant(
            of: find.byType(PaywallScreen),
            matching: find.byType(Scrollable),
          )
          .first;
      Future<void> toEnd() async {
        // A lazy list knows its end only once it has built it.
        for (var i = 0; i < 3; i++) {
          final scroll = tester.state<ScrollableState>(paywall).position;
          scroll.jumpTo(scroll.maxScrollExtent);
          await settleFrames(tester);
        }
      }

      await shoot(
        'paywall-bottom',
        mapShown: false,
        relocalize: (_, locale) async {
          await price(locale);
          await toEnd();
        },
      );
      await price(base);
      container.read(routerProvider).pop();
      await settleFrames(tester);
    }
    // The rest is shot without Velorki Plus, as after the paywall.
    container.read(plusEntitledProvider.notifier).value = false;
    if (await stopAfter('paywall')) return;

    // ---------------------------------------------------- import, ride
    // A GPX of the demo ride, named in the language it is shown in, so
    // imported and saved once per language: the preview, then the saved
    // ride's charts. Each ride goes again before the next is imported.
    final rideRoute = await planRoute(tester, container, rideWaypoints);
    planner.clear();
    final rideTrack = demoRide(rideRoute);
    final rides = container.read(rideRepositoryProvider);
    for (final locale in locales) {
      final local = lookupAppLocalizations(Locale(locale));
      final rideName = rideNames[locale] ?? rideNames['en']!;
      await language.select(Locale(locale));
      await tapAndPump(tester, find.text(local.tabPlan));
      final gpx = GpxCodec.encodeTrack(
        points: rideTrack,
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
      await waitForWidget(tester, find.text(local.importKindRide));
      await tapAndPump(tester, find.text(local.importKindRide));
      // The preview's own map loads its marker images after the route
      // shows; on a loaded emulator that takes a while longer.
      await shoot(
        'import',
        route: true,
        hold: const Duration(seconds: 20),
        inLocales: [locale],
      );
      if (await stopAfter('import')) return;

      await tapAndPump(tester, find.text(local.commonSave).last);
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
      await shoot('ride', inLocales: [locale]);
      // Back to the library's start, and the ride deleted.
      await tapAndPump(tester, find.text(local.tabLibrary));
      await tapAndPump(tester, find.text(local.tabLibrary));
      for (final saved in await rides.watchRides().first) {
        await rides.delete(saved.id);
      }
      await settleFrames(tester);
    }
    await language.select(Locale(base));
    await settleFrames(tester);

    if (await stopAfter('ride')) return;

    if (_any('library')) {
      // --------------------------------------------------------- library
      await tapAndPump(tester, find.text(l10n.tabLibrary));
      await tapAndPump(tester, find.text(l10n.tabLibrary));
      await tapAndPump(tester, find.text(l10n.libraryRoutes));
      await waitForWidget(tester, find.text(featuredRoute.name));
      clearSnackBars(tester);
      await shoot('library');
    }
    if (await stopAfter('library')) return;

    if (_any('offline')) {
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
      await shoot('offline', route: true, offline: true);
      // The same in another accent, for the dark half of the slide that
      // shows the themes with it.
      if (themes.any(dark)) {
        markMapChange();
        await appearance.setAccent(AccentPreset.ember);
        await shoot('offline-accent', route: true, offline: true, only: dark);
        markMapChange();
        await appearance.setAccent(AccentPreset.volt);
        await waitForMapDrawn(tester, cap: const Duration(seconds: 4));
      }
      planner.clear();
    }
    if (await stopAfter('offline')) return;

    // The ride is only for the live and navigation pictures.
    if (_any('live') || _any('navigation')) {
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
      await rideOn(1);
      // From here the rider stands still while every theme and language is
      // shot: the recorder's clock moves only with the fixes, so the figures
      // and the banner hold as they are.
      await shoot('live', route: true);
      // What the Live Activity and the watch show right now, for the slides
      // that draw them: the same snapshot the live card was built from, in
      // every language the store has and both themes, shot or not (the ride
      // is the same in every run, and so are its figures), so the watch can
      // be shot for all of them from one run. The Play set has neither.
      if (Platform.isIOS) {
        for (final mode in themes) {
          for (final locale in rideNames.keys) {
            await sendStoreData(
              tester,
              '${mode.name}/$locale/activity',
              rideActivityData(
                lookupAppLocalizations(Locale(locale)),
                UnitSystem.metric,
                container.read(recordingControllerProvider).snapshot!,
                bannerProgress(tester),
              ),
            );
          }
        }
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
      await shoot('navigation', route: true);

      final recording = container.read(recordingControllerProvider.notifier);
      final halted = await recording.halt();
      if (halted != null) await recording.discardInterrupted(halted);
    }
    await container
        .read(followModeProvider.notifier)
        .select(FollowMode.northUp);
    await settleFrames(tester);
    planner.clear();
    await unmountApp(tester);
  });
}

/// The bits every feature test in this directory needs: booting the real app
/// into a container the test controls, waiting without `pumpAndSettle`, and an
/// optional screenshot.
///
/// `pumpAndSettle` can never be used here. The map is a platform view with its
/// own render loop and the route line animates, so the frame scheduler never
/// goes idle and `pumpAndSettle` times out even when the app is perfectly
/// healthy. Everything in this file therefore pumps fixed steps and polls a
/// predicate instead.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/features/map/presentation/map_view.dart';
import 'package:velorki/features/planner/presentation/planner_map_host.dart';
import 'package:velorki/features/settings/data/units.dart';

/// How long a step of the pump loop is. Short enough that a tap is picked up
/// quickly, long enough that a few hundred of them cover a minute.
const Duration pumpStep = Duration(milliseconds: 100);

/// Boots the real [VelorkiApp] on the device and hands back its container.
///
/// [overrides] are appended to the two the app itself always needs, so a test
/// can replace the GPS, the geocoder or the recorder without repeating the
/// boilerplate. Pass `realMap: false` to keep the placeholder map: the tests
/// that only assert on state run a good deal faster without maplibre, but the
/// ones that care about the style reload need the real thing.
Future<ProviderContainer> pumpApp(
  WidgetTester tester, {
  List<Override> overrides = const <Override>[],
  bool realMap = true,
  Duration warmUp = const Duration(seconds: 3),
}) async {
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      // The emulator says en-US, which would open the app in miles; these
      // flows are written in metric.
      localeCountryProvider.overrideWithValue(null),
      if (realMap)
        mapViewBuilderProvider.overrideWithValue(
          (onReady) => MapView(onControllerReady: onReady),
        ),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);

  tolerateOverflow();
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const VelorkiApp()),
  );
  await pumpFor(tester, warmUp);
  return container;
}

/// Every framework error [tolerateOverflow] swallowed in this test, newest
/// last, so a test can assert on exactly what it let through.
final List<FlutterErrorDetails> toleratedErrors = <FlutterErrorDetails>[];

/// Demotes `RenderFlex overflowed by N pixels` to a log line for this test.
///
/// Tearing the app down at the end of a test relayouts the shell at sizes it
/// never sees in use, and the navigation bar overflows by a couple of dozen
/// pixels on the way out. `flutter_test` turns any framework error into a test
/// failure, so without this every feature test here ends red for a frame that
/// no rider will ever look at. Only overflow errors are demoted, and every one
/// of them is kept in [toleratedErrors] so nothing is silent.
///
/// This can never be widened to swallow an *uncaught async* error, however
/// tempting that looks: the test binding routes those through
/// `FlutterError.onError` and then asserts that the handler recorded them, so
/// returning without reporting trips
/// "A test overrode FlutterError.onError ... but had unexpected additional
/// errors that it could not handle" instead of passing. Overflow errors do not
/// come that way; an unawaited future that rejects does.
///
/// The handler is deliberately *not* restored at the end of the test: the app
/// keeps unwinding after the body returns, and an overflow raised then would
/// otherwise fail a test that has already passed. Each `testWidgets` installs
/// the binding's own handler again, so nothing leaks into the next one.
void tolerateOverflow() {
  final previous = FlutterError.onError;
  toleratedErrors.clear();
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed by')) {
      toleratedErrors.add(details);
      debugPrint('VELORKI_ITEST tolerated a render overflow');
      return;
    }
    previous?.call(details);
  };
  addTearDown(() {
    if (toleratedErrors.isNotEmpty) {
      debugPrint('VELORKI_ITEST tolerated ${toleratedErrors.length} error(s)');
    }
  });
}

/// Takes the app back off the screen before the test ends.
///
/// Leaving the real map mounted through teardown means maplibre's platform
/// view is disposed while the binding is already shutting down, which surfaces
/// as "Looking up a deactivated widget's ancestor is unsafe" instead of a
/// clean finish.
Future<void> unmountApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 50));
}

/// Pumps frames for [duration] without ever asking the tree to settle.
Future<void> pumpFor(WidgetTester tester, Duration duration) async {
  final steps = (duration.inMilliseconds / pumpStep.inMilliseconds).ceil();
  for (var i = 0; i < steps; i++) {
    await tester.pump(pumpStep);
  }
}

/// Pumps until [predicate] holds, or fails the test after [timeout].
///
/// [describe] names what was being waited for, and [onTimeout] may add what
/// the state looked like when the wait ran out — both end up in the failure,
/// which is the only forensics a device run leaves behind.
Future<void> waitUntil(
  WidgetTester tester,
  bool Function() predicate, {
  required String describe,
  Duration timeout = const Duration(seconds: 30),
  String Function()? onTimeout,
}) async {
  final clock = Stopwatch()..start();
  while (clock.elapsed < timeout) {
    if (predicate()) {
      debugPrint(
        'VELORKI_ITEST waited ${clock.elapsedMilliseconds}ms '
        'for $describe',
      );
      return;
    }
    await tester.pump(pumpStep);
  }
  final detail = onTimeout == null ? '' : '\n  state: ${onTimeout()}';
  fail('timed out after ${timeout.inSeconds}s waiting for $describe$detail');
}

/// [waitUntil] for a finder, which is the common case for UI assertions.
Future<void> waitForWidget(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) => waitUntil(
  tester,
  () => finder.evaluate().isNotEmpty,
  describe: 'widget $finder',
  timeout: timeout,
);

/// Taps [finder] after waiting for it to appear, then pumps a few frames so
/// the reaction is in the tree before the caller asserts on it.
Future<void> tapAndPump(
  WidgetTester tester,
  Finder finder, {
  Duration settle = const Duration(milliseconds: 600),
  Duration timeout = const Duration(seconds: 20),
}) async {
  await waitForWidget(tester, finder, timeout: timeout);
  try {
    await tester.ensureVisible(finder.first);
    await tester.pump();
  } on Object {
    // No scrollable around it, or it is already on screen.
  }
  await tester.tap(finder.first, warnIfMissed: false);
  await pumpFor(tester, settle);
}

/// Takes a screenshot when the binding can, and says so when it cannot.
///
/// Screenshots need `convertFlutterSurfaceToImage()`, which only works while
/// no platform view is being composited on some devices, and needs a driver on
/// others. None of the assertions depend on one, so a failure here is logged
/// and swallowed rather than failing a feature test.
Future<void> screenshot(WidgetTester tester, String name) async {
  final binding = IntegrationTestWidgetsFlutterBinding.instance;
  try {
    // convertFlutterSurfaceToImage asserts if it is called twice, and the
    // surface stays converted for the rest of the test.
    if (!_surfaceConverted) {
      await binding.convertFlutterSurfaceToImage();
      _surfaceConverted = true;
      addTearDown(() => _surfaceConverted = false);
    }
    await tester.pump();
    await binding.takeScreenshot(name);
    debugPrint('VELORKI_ITEST screenshot $name');
  } on Object catch (error) {
    debugPrint('VELORKI_ITEST screenshot $name unavailable: $error');
  }
}

bool _surfaceConverted = false;

/// Drags the planner's bottom sheet to its full height.
///
/// The sheet is a [DraggableScrollableSheet] that opens at 42 % of the screen,
/// so the routing chip, the elevation profile and the surface bar start below
/// the fold. A finder still sees them — the sheet's ListView has only a
/// handful of explicit children — but a tap would miss, and a screenshot would
/// not show them.
Future<void> dragSheetUp(WidgetTester tester) async {
  if (find.byType(DraggableScrollableSheet).evaluate().isEmpty) return;
  // Dragging the sheet widget itself would start the gesture at its centre,
  // which is over the map; the grab has to land inside the sheet's own area.
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  await tester.dragFrom(
    Offset(size.width / 2, size.height * 0.78),
    Offset(0, -size.height * 0.45),
  );
  await pumpFor(tester, const Duration(milliseconds: 900));
}

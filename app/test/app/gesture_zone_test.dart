import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/app/shell_layout.dart';
import 'package:velorki/features/map/presentation/shared_map_host.dart';
import 'package:velorki/features/recording/presentation/recording_screen.dart';
import 'package:velorki/features/shared/application/nav_bar_docking.dart';
import 'package:velorki/features/shared/presentation/docking_sheet.dart';
import 'package:velorki/features/shared/presentation/gesture_zone_guard.dart';

import '../features/recording/support/pump.dart';
import '../support/app.dart';

const Size _upright = Size(402, 874);
const Size _sideways = Size(874, 402);

/// The phone's shape: [bottom] the home indicator's inset (iOS) or the
/// navigation bar's (Android), [gestures] the system's bottom gesture inset.
Future<void> _screen(
  WidgetTester tester,
  Size size, {
  required double bottom,
  double gestures = 0,
}) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = size * 3;
  final sideways = size.width > size.height;
  tester.view.viewPadding = FakeViewPadding(
    left: sideways ? 62 * 3 : 0,
    right: sideways ? 62 * 3 : 0,
    top: sideways ? 0 : 62 * 3,
    bottom: bottom * 3,
  );
  tester.view.padding = tester.view.viewPadding;
  tester.view.systemGestureInsets = FakeViewPadding(bottom: gestures * 3);
  await tester.pumpAndSettle();
}

void _railOnLeft(WidgetTester tester) {
  const channel = MethodChannel(ScreenSideChannel.channelName);
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    channel,
    (call) async => call.method == 'side' ? RailSide.left.name : null,
  );
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
}

Rect _sheet(WidgetTester tester) =>
    tester.getRect(find.byType(DockingSheetShell));

/// Where the sheet's top is and how far its content is scrolled.
(double, double) _sheetState(WidgetTester tester) {
  final content = tester.state<ScrollableState>(
    find
        .descendant(
          of: find.byType(SheetContentScroll),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  return (_sheet(tester).top, content.position.pixels);
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(SharedMapHost)));

/// The phones the shell guards a zone on, by platform: the zone, and the
/// insets that make it.
final _phones = <TargetPlatform, ({double bottom, double gestures})>{
  // A Face ID iPhone: the home indicator's inset upright.
  TargetPlatform.iOS: (bottom: 34, gestures: 0),
  // Android with gesture navigation: the gesture inset is the zone.
  TargetPlatform.android: (bottom: 24, gestures: 32),
};

void main() {
  setUp(() => debugShellLayoutOverride = null);
  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view
      ..resetPhysicalSize()
      ..resetDevicePixelRatio()
      ..resetViewPadding()
      ..resetPadding()
      ..resetSystemGestureInsets();
  });

  group('the zone', () {
    const iPhone = MediaQueryData(
      viewPadding: EdgeInsets.only(bottom: 34),
      systemGestureInsets: EdgeInsets.zero,
    );
    test('on iOS is the home indicator, none with a home button', () {
      expect(systemGestureZoneHeight(iPhone, TargetPlatform.iOS), 34);
      expect(
        systemGestureZoneHeight(const MediaQueryData(), TargetPlatform.iOS),
        0,
      );
    });
    test('on Android is the gesture inset, none with three buttons', () {
      const gestures = MediaQueryData(
        viewPadding: EdgeInsets.only(bottom: 24),
        systemGestureInsets: EdgeInsets.only(bottom: 32),
      );
      expect(systemGestureZoneHeight(gestures, TargetPlatform.android), 32);
      const buttons = MediaQueryData(viewPadding: EdgeInsets.only(bottom: 48));
      expect(systemGestureZoneHeight(buttons, TargetPlatform.android), 0);
    });
  });

  for (final MapEntry(key: platform, value: phone) in _phones.entries) {
    final zone = platform == TargetPlatform.iOS ? phone.bottom : phone.gestures;

    testWidgets(
      'upright on ${platform.name}: a drag from the bottom edge '
      'leaves the sheet, one from just above reaches it, the bar still taps',
      (tester) async {
        await _screen(
          tester,
          _upright,
          bottom: phone.bottom,
          gestures: phone.gestures,
        );
        await pumpRecordingApp(
          tester,
          initialLocation: plannerRoute,
          surfaceSize: _upright,
          expectTextFits: false,
        );
        await tester.pumpAndSettle();
        final rest = _sheetState(tester);
        // Under the bar, where the sheet reaches to the screen's edge.
        final x = _upright.width / 2;

        await tester.dragFrom(
          Offset(x, _upright.height - 10),
          const Offset(0, -600),
        );
        await tester.pumpAndSettle();
        expect(_sheetState(tester), rest);

        // Just above, the drag is the sheet's: here its content scrolls,
        // since the test font is wider than the app's; on a phone where the
        // content fits, the sheet itself moves.
        await tester.dragFrom(
          Offset(x, _upright.height - zone - 2),
          const Offset(0, -600),
        );
        await tester.pumpAndSettle();
        expect(_sheetState(tester), isNot(rest));

        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(l10n.tabRecord),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(RecordingScreen), findsOneWidget);
        await unmountApp(tester);
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  testWidgets('sideways on iOS: a drag towards the rail from the bottom edge '
      'leaves the sheet, one from just above docks it, the rail still taps', (
    tester,
  ) async {
    _railOnLeft(tester);
    await _screen(tester, _sideways, bottom: 21);
    await pumpRecordingApp(
      tester,
      initialLocation: plannerRoute,
      surfaceSize: _sideways,
      expectTextFits: false,
    );
    await tester.pumpAndSettle();
    final container = _container(tester);
    final rest = _sheet(tester);
    expect(rest.bottom, greaterThan(_sideways.height - 10));
    final x = rest.center.dx;
    final towardsRail = Offset(-_sideways.width, 0);

    await tester.dragFrom(Offset(x, _sideways.height - 10), towardsRail);
    await tester.pumpAndSettle();
    expect(container.read(navBarDockingProvider), isEmpty);
    expect(_sheet(tester), rest);

    // Upwards from the edge, the way the home gesture goes, neither.
    await tester.dragFrom(
      Offset(x, _sideways.height - 10),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(_sheet(tester), rest);

    await tester.dragFrom(Offset(x, _sideways.height - 23), towardsRail);
    await tester.pumpAndSettle();
    expect(container.read(navBarDockingProvider), {plannerRoute});

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text(l10n.tabRecord),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(RecordingScreen), findsOneWidget);
    await unmountApp(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/app/shell_layout.dart';
import 'package:velorki/features/shared/application/nav_bar_docking.dart';
import 'package:velorki/features/shared/presentation/docking_sheet.dart';

import 'package:velorki/features/recording/domain/recording_snapshot.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../features/recording/support/pump.dart';

/// A turn of the phone: where the rail ends up, `null` upright.
typedef _Way = RailSide?;

String _name(_Way way) => way == null ? 'upright' : 'rail ${way.name}';

/// A phone upright, in points, with the safe areas it has each way up.
class _Phone {
  const _Phone(this.name, this.upright, this.island, this.top);

  final String name;
  final Size upright;
  final double island;
  final double top;

  Size size(_Way way) => way == null ? upright : upright.flipped;
}

const _phones = <_Phone>[
  _Phone('iPhone 17 Pro', Size(402, 874), 62, 62),
  _Phone('iPhone 13 Pro', Size(390, 844), 47, 47),
];

/// The keyboard's height each way up, about what iOS gives it.
const double _uprightKeyboard = 336;
const double _sidewaysKeyboard = 209;

/// Puts the test view the way [way] says, as the phone reports it while it
/// turns: the size goes there over a few frames, the safe areas follow, and
/// the platform names the rail's side.
Future<void> _turn(
  WidgetTester tester,
  _Phone phone,
  _Way way, {
  bool keyboard = false,
  bool announce = true,
  bool steps = true,
  bool keyboardBounces = false,
}) async {
  final size = phone.size(way);
  final sideways = way != null;
  const channel = MethodChannel(ScreenSideChannel.channelName);
  final messenger = tester.binding.defaultBinaryMessenger;
  if (way != null) {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'side' ? way.name : null,
    );
  }
  tester.view.devicePixelRatio = 3;
  final from = tester.view.physicalSize / 3;
  if (keyboardBounces) {
    // iOS puts the keyboard away for the turn and brings it back after.
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump(const Duration(milliseconds: 16));
  }
  if (steps && from != size) {
    for (var t = 0.05; t < 0.999; t += 0.05) {
      final mid = Size.lerp(from, size, t)!;
      await tester.binding.setSurfaceSize(mid);
      tester.view.physicalSize = mid * 3;
      await tester.pump(const Duration(milliseconds: 16));
    }
  }
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size * 3;
  if (steps) await tester.pump(const Duration(milliseconds: 16));
  tester.view.viewPadding = FakeViewPadding(
    left: sideways ? phone.island * 3 : 0,
    right: sideways ? phone.island * 3 : 0,
    top: sideways ? 0 : phone.top * 3,
    bottom: 21 * 3,
  );
  tester.view.padding = tester.view.viewPadding;
  tester.view.viewInsets = FakeViewPadding(
    bottom: !keyboard
        ? 0
        : (sideways ? _sidewaysKeyboard : _uprightKeyboard) * 3,
  );
  // A turn by half a circle keeps the size: only the platform says the
  // rail's side changed.
  if (way != null && announce) {
    await messenger.handlePlatformMessage(
      ScreenSideChannel.channelName,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('sideChanged', way.name),
      ),
      (_) {},
    );
  }
  await tester.pumpAndSettle();
}

/// Where the rider left the sheet.
enum _State { rest, docked, open }

DraggableScrollableSheet _sheetWidget(WidgetTester tester) => tester
    .widget<DraggableScrollableSheet>(find.byType(DraggableScrollableSheet));

double _extent(WidgetTester tester) => _sheetWidget(tester).controller!.size;

/// The extent the sheet has in [state] this way up.
double _expected(WidgetTester tester, _State state) {
  final sheet = _sheetWidget(tester);
  return switch (state) {
    _State.rest => sheet.snapSizes?.first ?? sheet.initialChildSize,
    _State.docked => sheet.minChildSize,
    _State.open => sheet.maxChildSize,
  };
}

/// Whether the sheet's own shell shows it docked.
bool _shellDocked(WidgetTester tester) =>
    tester.widget<DockingSheetShell>(find.byType(DockingSheetShell)).docked >=
    sheetDockedThreshold;

/// What the bar shows: docked or not, `null` while it is hidden.
bool? _barDocked(WidgetTester tester) {
  final bars = find.byType(FloatingNavigationBar);
  if (bars.evaluate().isEmpty) return null;
  return tester.widget<FloatingNavigationBar>(bars).docked;
}

bool _flagDocked(WidgetTester tester, String route) =>
    ProviderScope.containerOf(tester.element(find.byType(HomeShell)))
        .read(navBarDockingProvider)
        .contains(route);

/// The sheet is where [state] puts it this way up, and stays there; the bar
/// is docked exactly when the sheet is.
Future<void> _expectState(
  WidgetTester tester,
  _State state,
  String what, {
  String route = plannerRoute,
  bool reportsDocked = true,
}) async {
  final expected = _expected(tester, state);
  expect(
    _extent(tester),
    closeTo(expected, 0.003),
    reason: '$what: the sheet is ${state.name}',
  );
  // No stepping: the sheet stays put.
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
  await tester.pumpAndSettle();
  expect(
    _extent(tester),
    closeTo(expected, 0.003),
    reason: '$what: the sheet stays ${state.name}',
  );
  if (reportsDocked) _expectDockedMatches(tester, what, route: route);
  expect(
    _shellDocked(tester),
    state == _State.docked,
    reason: '$what: the shell looks ${state.name}',
  );
}

/// The bar's look and the docking flag say what the sheet shows.
void _expectDockedMatches(
  WidgetTester tester,
  String what, {
  String route = plannerRoute,
}) {
  final docked = _shellDocked(tester);
  expect(
    _flagDocked(tester, route),
    docked,
    reason: '$what: the flag says docked exactly when the sheet is',
  );
  final bar = _barDocked(tester);
  if (bar != null) {
    expect(bar, docked, reason: '$what: the bar is docked when the sheet is');
  }
}

/// Pulls the sheet by its handle [dp] away from the bar or rail.
Future<void> _pull(WidgetTester tester, _Way way, double dp) async {
  final offset = switch (way) {
    null => Offset(0, -dp),
    RailSide.left => Offset(dp, 0),
    RailSide.right => Offset(-dp, 0),
  };
  await tester.dragFrom(tester.getCenter(find.byType(SheetHandle)), offset);
  await tester.pumpAndSettle();
}

/// Leaves the sheet in [state], moved by the rider's hand.
Future<void> _leave(WidgetTester tester, _Way way, _State state) async {
  switch (state) {
    case _State.rest:
      // A small pull that snaps back: the sheet has been dragged.
      await _pull(tester, way, 30);
    case _State.docked:
      await _pull(tester, way, -1000);
    case _State.open:
      await _pull(tester, way, 1000);
  }
}

/// Moves the sheet by hand to about [target], where it snaps.
Future<void> _pullTo(
  WidgetTester tester,
  _Phone phone,
  _Way way,
  double target,
) async {
  final size = phone.size(way);
  final length = way == null ? size.height : size.width;
  await _pull(tester, way, (target - _extent(tester)) * length);
}

Future<void> _open(WidgetTester tester, _Phone phone, _Way way) async {
  await _turn(tester, phone, way, steps: false, announce: way != null);
  await pumpRecordingApp(
    tester,
    initialLocation: plannerRoute,
    surfaceSize: phone.size(way),
    expectTextFits: false,
  );
  await tester.pumpAndSettle();
}

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
      ..resetViewInsets();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(ScreenSideChannel.channelName),
          null,
        );
  });

  const journeys = <List<_Way>>[
    [null, RailSide.left, null],
    [null, RailSide.right, null],
    [RailSide.left, RailSide.right],
    [RailSide.right, RailSide.left],
  ];

  for (final phone in _phones) {
    group(phone.name, () {
      for (final journey in journeys) {
        final name = journey.map(_name).join(' → ');
        for (final state in _State.values) {
          testWidgets('Plan: a sheet ${state.name} stays ${state.name} '
              'through $name', (tester) async {
            await _open(tester, phone, journey.first);
            await _leave(tester, journey.first, state);
            await _expectState(tester, state, 'before the turn');
            for (final way in journey.skip(1)) {
              await _turn(tester, phone, way);
              await _expectState(tester, state, 'at ${_name(way)}');
            }
            // Again, to be sure nothing grows turn by turn.
            for (final way in journey.skip(1)) {
              await _turn(tester, phone, way);
              await _expectState(tester, state, 'again at ${_name(way)}');
            }
            await unmountApp(tester);
          });
        }
        for (final via in [_State.open, _State.docked]) {
          testWidgets('Plan: a sheet pulled ${via.name} by hand and back to '
              'rest stays at rest through $name', (tester) async {
            await _open(tester, phone, journey.first);
            await _leave(tester, journey.first, via);
            await _pullTo(
              tester,
              phone,
              journey.first,
              _expected(tester, _State.rest),
            );
            await _expectState(tester, _State.rest, 'before the turn');
            for (var round = 0; round < 3; round++) {
              for (final way in journey.skip(1)) {
                await _turn(tester, phone, way);
                await _expectState(
                  tester,
                  _State.rest,
                  'round $round at ${_name(way)}',
                );
              }
            }
            await unmountApp(tester);
          });
        }
        testWidgets('Plan: a sheet left at rest by the search stays at rest '
            'through $name', (tester) async {
          await _open(tester, phone, journey.first);
          await tester.enterText(find.byType(TextField), 'munich');
          await tester.pumpAndSettle();
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
          await _expectState(tester, _State.rest, 'before the turn');
          for (final way in journey.skip(1)) {
            await _turn(tester, phone, way);
            await _expectState(tester, _State.rest, 'at ${_name(way)}');
          }
          await unmountApp(tester);
        });
      }

      const turns = <(_Way, _Way)>[
        (null, RailSide.left),
        (null, RailSide.right),
        (RailSide.left, null),
        (RailSide.right, null),
        (RailSide.left, RailSide.right),
        (RailSide.right, RailSide.left),
      ];
      for (final (from, to) in turns) {
        for (final bounce in [false, true]) {
          testWidgets('Plan: searching, turned from ${_name(from)} to '
              '${_name(to)}${bounce ? ', the keyboard going and coming' : ''}, '
              'the bar and the sheet agree, and the sheet rests once the '
              'keyboard goes', (tester) async {
            await _open(tester, phone, from);
            await tester.enterText(find.byType(TextField), 'munich');
            await _turn(tester, phone, from, keyboard: true, announce: false);
            await tester.pump(const Duration(milliseconds: 400));
            await tester.pumpAndSettle();
            _expectDockedMatches(tester, 'searching ${_name(from)}');

            await _turn(
              tester,
              phone,
              to,
              keyboard: true,
              keyboardBounces: bounce,
            );
            _expectDockedMatches(tester, 'searching, turned ${_name(to)}');

            // The keyboard goes, the field keeps its focus.
            await _turn(tester, phone, to, announce: false);
            await _expectState(tester, _State.rest, 'keyboard away');

            FocusManager.instance.primaryFocus?.unfocus();
            await tester.pumpAndSettle();
            await _expectState(tester, _State.rest, 'search left');
            await unmountApp(tester);
          });
        }
      }
    });
  }

  for (final (route, label) in [
    (recordingRoute, 'Record'),
    (libraryRoute, 'Library'),
  ]) {
    for (final journey in journeys) {
      final name = journey.map(_name).join(' → ');
      for (final state in [_State.rest, _State.docked]) {
        testWidgets('$label: a sheet ${state.name} stays ${state.name} '
            'through $name', (tester) async {
          final phone = _phones.first;
          await _turn(
            tester,
            phone,
            journey.first,
            steps: false,
            announce: journey.first != null,
          );
          await pumpRecordingApp(
            tester,
            initialLocation: route,
            surfaceSize: phone.size(journey.first),
            expectTextFits: false,
          );
          await tester.pumpAndSettle();
          await _leave(tester, journey.first, state);
          await _expectState(tester, state, 'before the turn', route: route);
          for (final way in journey.skip(1)) {
            await _turn(tester, phone, way);
            await _expectState(tester, state, 'at ${_name(way)}', route: route);
          }
          await unmountApp(tester);
        });
      }
    }
  }

  for (final journey in journeys) {
    final name = journey.map(_name).join(' → ');
    for (final state in _State.values) {
      testWidgets('Record during a ride: a sheet ${state.name} stays '
          '${state.name} through $name', (tester) async {
        final phone = _phones.first;
        await _turn(
          tester,
          phone,
          journey.first,
          steps: false,
          announce: journey.first != null,
        );
        final h = await pumpRecordingApp(
          tester,
          surfaceSize: phone.size(journey.first),
          expectTextFits: false,
        );
        await tester.pump();
        await emitSnapshot(tester, h, _ride());
        await tester.pumpAndSettle();
        await _leave(tester, journey.first, state);
        // The ride's sheet docks into the figures bar, not the navigation
        // bar, and tells the bar nothing.
        await _expectState(
          tester,
          state,
          'before the turn',
          reportsDocked: false,
        );
        for (final way in journey.skip(1)) {
          await _turn(tester, phone, way);
          await _expectState(
            tester,
            state,
            'at ${_name(way)}',
            reportsDocked: false,
          );
        }
        await unmountApp(tester);
      });
    }
  }
}

RecordingSnapshot _ride() => RecordingSnapshot(
  rideId: 'ride-1',
  status: RecordingStatus.active,
  startedAt: DateTime.utc(2026, 9, 12, 10),
  autoPaused: false,
  distanceM: 12345,
  elapsed: const Duration(minutes: 42, seconds: 7),
  moving: const Duration(minutes: 40),
  speedMps: 6,
  avgSpeedMps: 5,
  ascentM: 210,
  descentM: 190,
  lastPosition: const LatLng(48.1, 11.2),
  accuracyM: 4,
  pointCount: 120,
  newPoints: const [LatLng(48.0, 11.0), LatLng(48.1, 11.2)],
);

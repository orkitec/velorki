import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/router.dart';
import 'package:velorki/app/shell_layout.dart';
import 'package:velorki/features/search/presentation/search_field.dart';
import 'package:velorki/features/shared/presentation/adaptive_docking_sheet.dart';
import 'package:velorki/features/shared/presentation/docking_sheet.dart';

import '../features/recording/support/pump.dart';

/// The phone upright and sideways, in points, as an iPhone 17 Pro has it.
const Size _upright = Size(402, 874);
const Size _sideways = Size(874, 402);

/// The keyboard's height each way up, about what iOS gives it with the
/// suggestions bar.
const double _uprightKeyboard = 336;
const double _sidewaysKeyboard = 209;

/// A turn of the phone: where the rail ends up, `null` upright.
typedef _Way = RailSide?;

String _name(_Way way) => way == null ? 'upright' : 'rail ${way.name}';

/// Puts the test view the way [way] says, with the safe areas an iPhone has
/// that way up, the keyboard up when [keyboard], and tells the app which
/// side the phone's bottom edge went to.
Future<void> _turn(
  WidgetTester tester,
  _Way way, {
  bool keyboard = true,
  bool announce = true,
}) async {
  final size = way == null ? _upright : _sideways;
  final sideways = way != null;
  const channel = MethodChannel(ScreenSideChannel.channelName);
  final messenger = tester.binding.defaultBinaryMessenger;
  // Upright the side does not matter; the last one stays what the
  // platform reports, as it does on a phone.
  if (way != null) {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'side' ? way.name : null,
    );
  }
  await tester.binding.setSurfaceSize(size);
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = size * 3;
  tester.view.viewPadding = FakeViewPadding(
    left: sideways ? 62 * 3 : 0,
    right: sideways ? 62 * 3 : 0,
    top: sideways ? 0 : 62 * 3,
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

/// The result list as it shows: the card under the field.
Finder get _list => find
    .descendant(
      of: find.byType(CompositedTransformFollower),
      matching: find.byType(Material),
    )
    .first;

/// The planner's sheet as it shows, turned or not.
Rect _sheet(WidgetTester tester) =>
    tester.getRect(find.byType(DockingSheetShell));

void _expectRect(Rect actual, Rect expected, String what) {
  for (final (a, e) in [
    (actual.left, expected.left),
    (actual.top, expected.top),
    (actual.right, expected.right),
    (actual.bottom, expected.bottom),
  ]) {
    expect(a, closeTo(e, 1), reason: '$what: $actual, not $expected');
  }
}

String _fieldText(WidgetTester tester) => tester
    .widget<TextField>(
      find.descendant(
        of: find.byType(SearchField),
        matching: find.byType(TextField),
      ),
    )
    .controller!
    .text;

/// The list is open, under the field, on the screen and above the keyboard,
/// and sideways as wide as upright.
void _expectListUnderField(
  WidgetTester tester,
  _Way way, {
  bool keyboardUp = true,
}) {
  final size = way == null ? _upright : _sideways;
  final keyboard = !keyboardUp
      ? 0
      : way == null
      ? _uprightKeyboard
      : _sidewaysKeyboard;
  expect(_fieldText(tester), 'munich');
  expect(find.text('Munich'), findsOneWidget, reason: 'the list is open');
  final field = tester.getRect(find.byType(SearchField));
  final list = tester.getRect(_list);
  expect(list.top, closeTo(field.bottom, 1), reason: '$list under $field');
  // Held on the field: by both edges upright; sideways by its far edge,
  // or where that is past the far side's safe area (the field reaches past
  // it, the rows of the list keep out of the island), 12 inside it.
  if (way == RailSide.left) {
    expect(list.right, closeTo(math.min(field.right, size.width - 62 - 12), 1));
  } else if (way == RailSide.right) {
    expect(list.left, closeTo(math.max(field.left, 62 + 12), 1));
  } else {
    expect(list.left, closeTo(field.left, 1));
  }
  if (way == null) expect(list.width, closeTo(field.width, 1));
  if (way != null) {
    expect(list.width, greaterThanOrEqualTo(sidewaysSheetContentWidth));
  }
  expect(list.left, greaterThanOrEqualTo(0), reason: '$list on $size');
  expect(list.right, lessThanOrEqualTo(size.width), reason: '$list on $size');
  expect(
    list.bottom,
    lessThanOrEqualTo(size.height - keyboard + 0.5),
    reason: '$list above a keyboard of $keyboard on $size',
  );
  // Whatever room is left, a row of the list shows in it.
  final row = tester.getRect(find.text('Munich'));
  expect(row.bottom, lessThanOrEqualTo(list.bottom + 0.5));
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

  /// Opens Plan [from], searches, turns the phone [to], puts the keyboard
  /// away, and turns back with the keyboard up again.
  Future<void> searchAndTurn(WidgetTester tester, _Way from, _Way to) async {
    // Where the sheet rests each way up, seen by turning at rest first.
    await _turn(tester, to, keyboard: false, announce: false);
    await pumpRecordingApp(
      tester,
      initialLocation: plannerRoute,
      surfaceSize: to == null ? _upright : _sideways,
      expectTextFits: false,
    );
    await tester.pumpAndSettle();
    final restTo = _sheet(tester);
    await _turn(tester, from, keyboard: false);
    final restFrom = _sheet(tester);

    await tester.enterText(find.byType(TextField), 'munich');
    // The keyboard comes up once the field has focus.
    await _turn(tester, from, announce: false);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    _expectListUnderField(tester, from);

    await _turn(tester, to);
    _expectListUnderField(tester, to);

    // The keyboard put away, the field keeps its focus and its list, and
    // the sheet comes back to where it rests this way up.
    await _turn(tester, to, keyboard: false, announce: false);
    _expectListUnderField(tester, to, keyboardUp: false);
    _expectRect(_sheet(tester), restTo, 'the sheet at rest');

    // Back again, the keyboard up, and down once more.
    await _turn(tester, from);
    _expectListUnderField(tester, from);
    await _turn(tester, from, keyboard: false, announce: false);
    _expectListUnderField(tester, from, keyboardUp: false);
    _expectRect(_sheet(tester), restFrom, 'the sheet at rest');
    await unmountApp(tester);
  }

  const turns = <(_Way, _Way)>[
    (null, RailSide.left),
    (null, RailSide.right),
    (RailSide.left, RailSide.right),
    (RailSide.right, RailSide.left),
    (RailSide.left, null),
    (RailSide.right, null),
  ];
  for (final (from, to) in turns) {
    testWidgets('the open result list follows the field from ${_name(from)} '
        'to ${_name(to)} and back', (tester) async {
      await searchAndTurn(tester, from, to);
    });
  }

  testWidgets('with the keyboard put away the list survives a turn too', (
    tester,
  ) async {
    await _turn(tester, null, keyboard: false, announce: false);
    await pumpRecordingApp(
      tester,
      initialLocation: plannerRoute,
      surfaceSize: _upright,
      expectTextFits: false,
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'munich');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    for (final way in <_Way>[RailSide.left, RailSide.right, null]) {
      await _turn(tester, way, keyboard: false);
      expect(_fieldText(tester), 'munich');
      expect(find.text('Munich'), findsOneWidget);
      final field = tester.getRect(find.byType(SearchField));
      expect(tester.getRect(_list).top, closeTo(field.bottom, 1));
    }
    await unmountApp(tester);
  });
}

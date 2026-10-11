import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/theme.dart';
import 'package:velorki/features/shared/presentation/gesture_zone_guard.dart';
import 'package:velorki/l10n/generated/app_localizations.dart';

import '../support/app.dart';

/// A modal sheet on the root navigator, as the planner's point sheet opens
/// one: a draggable sheet with a button at its foot.
Future<void> _open(WidgetTester tester, {required bool guarded}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildLightTheme(),
      locale: testLocale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: guarded ? gestureZoneAppBuilder : null,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            useRootNavigator: true,
            isScrollControlled: true,
            builder: (_) => DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.4,
              minChildSize: 0.4,
              builder: (context, controller) => ListView(
                controller: controller,
                children: [
                  for (var i = 0; i < 30; i++)
                    ListTile(
                      key: ValueKey('row$i'),
                      title: Text('row $i'),
                      onTap: () => tapped = i,
                    ),
                ],
              ),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

int? tapped;

double _top(WidgetTester tester) => tester.getTopLeft(find.byType(ListView)).dy;

void _insets(WidgetTester tester, {double bottom = 0, double gestures = 0}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(400, 800);
  tester.view.viewPadding = FakeViewPadding(bottom: bottom);
  tester.view.padding = tester.view.viewPadding;
  tester.view.systemGestureInsets = FakeViewPadding(bottom: gestures);
  addTearDown(() {
    tester.view
      ..resetPhysicalSize()
      ..resetDevicePixelRatio()
      ..resetViewPadding()
      ..resetPadding()
      ..resetSystemGestureInsets();
  });
}

void main() {
  setUp(() => tapped = null);

  for (final guarded in [false, true]) {
    testWidgets(
      'a swipe up from the bottom edge ${guarded ? 'leaves' : 'drags'} '
      'an open modal sheet',
      (tester) async {
        _insets(tester, bottom: 34);
        await _open(tester, guarded: guarded);
        final rest = _top(tester);
        await tester.dragFrom(const Offset(200, 790), const Offset(0, -500));
        await tester.pumpAndSettle();
        if (guarded) {
          expect(_top(tester), rest);
        } else {
          expect(_top(tester), isNot(rest));
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }

  testWidgets('a drag from above the zone still moves the modal sheet', (
    tester,
  ) async {
    _insets(tester, bottom: 34);
    await _open(tester, guarded: true);
    final rest = _top(tester);
    await tester.dragFrom(const Offset(200, 500), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(_top(tester), isNot(rest));
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('a tap above the zone reaches a row, one in it does not', (
    tester,
  ) async {
    _insets(tester, bottom: 34);
    await _open(tester, guarded: true);
    await tester.tapAt(const Offset(200, 790));
    expect(tapped, isNull);
    await tester.tapAt(const Offset(200, 700));
    expect(tapped, isNotNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('Android with three buttons has no zone: the sheet is dragged '
      'from the edge as before', (tester) async {
    _insets(tester, bottom: 48);
    await _open(tester, guarded: true);
    final rest = _top(tester);
    await tester.dragFrom(const Offset(200, 790), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(_top(tester), isNot(rest));
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('Android with gesture navigation guards the gesture inset', (
    tester,
  ) async {
    _insets(tester, bottom: 24, gestures: 32);
    await _open(tester, guarded: true);
    final rest = _top(tester);
    await tester.dragFrom(const Offset(200, 790), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(_top(tester), rest);
    await tester.dragFrom(const Offset(200, 700), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(_top(tester), isNot(rest));
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/app/shell_layout.dart';
import 'package:velorki/features/map/presentation/map_attribution.dart';

void main() {
  // A tablet with Android's gesture navigation: a gesture zone and a bottom
  // inset for the handle.
  const tablet = MediaQueryData(
    size: Size(1280, 800),
    viewPadding: EdgeInsets.only(bottom: 24),
    systemGestureInsets: EdgeInsets.only(bottom: 32),
  );

  test('in a wide window the chip stands above the gesture handle', () {
    expect(
      shellAttributionFloor(tablet, ShellLayout.wide, TargetPlatform.android),
      24,
    );
    expect(
      shellAttributionFloor(tablet, ShellLayout.wide, TargetPlatform.iOS),
      24,
    );
  });

  test('turned sideways the band along the bottom stays the map\'s', () {
    expect(
      shellAttributionFloor(
        tablet,
        const ShellLayout(sideRail: true),
        TargetPlatform.android,
      ),
      isNull,
    );
  });
}

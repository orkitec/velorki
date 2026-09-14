import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/map/presentation/map_chrome.dart';
import 'package:velorki/features/planner/presentation/planner_map_host.dart';

void main() {
  group('PlannerMapHost', () {
    testWidgets('an embedded map keeps the follow flags of its owner', (
      tester,
    ) async {
      MapChromeInsets? seen;
      var located = 0;
      var compassed = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mapViewBuilderProvider.overrideWithValue(
              (_) => Builder(
                builder: (context) {
                  seen = MapChromeInsets.maybeOf(context);
                  return const SizedBox.expand();
                },
              ),
            ),
          ],
          child: MaterialApp(
            home: MapChromeInsets(
              controlsTop: 12,
              following: true,
              headingUp: true,
              bearingDeg: 90,
              onLocate: () => located++,
              onCompass: () => compassed++,
              child: PlannerMapHost(onMapReady: (_) {}, embedded: true),
            ),
          ),
        ),
      );

      final chrome = seen!;
      // The re-wrap only takes the routing-tile button away.
      expect(chrome.showRoutingTiles, isFalse);
      expect(chrome.controlsTop, 12);
      expect(chrome.following, isTrue);
      expect(chrome.headingUp, isTrue);
      expect(chrome.bearingDeg, 90);
      chrome.onLocate!();
      expect(located, 1);
      chrome.onCompass!();
      expect(compassed, 1);
    });
  });
}

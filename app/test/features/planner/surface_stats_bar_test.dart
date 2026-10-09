import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/planner/presentation/route_format.dart';
import 'package:velorki/features/planner/presentation/surface_stats_bar.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

import '../../support/app.dart';

const _stats = SurfaceStats(
  pavedShare: 0.8,
  unpavedShare: 0.15,
  unknownShare: 0.05,
  cyclewayShare: 0.3,
  busyShare: 0.04,
  coveredLengthM: 10000,
  totalLengthM: 10000,
  bikeInfrastructureShare: 0.68,
);

Future<void> _pump(WidgetTester tester, SurfaceStats stats) async {
  await tester.binding.setSurfaceSize(const Size(360, 640));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    testApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: SurfaceStatsBar(stats: stats),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('the share on bike infrastructure sits with the others', (
    tester,
  ) async {
    await _pump(tester, _stats);
    expect(
      find.text(
        l10n.labelWithPercent(
          l10n.surfaceBikeInfrastructure,
          formatPercent(l10n, 0.68),
        ),
      ),
      findsOneWidget,
    );
    expectNoClippedText(tester);
  });

  testWidgets('figures stored before the share show the cycleway count', (
    tester,
  ) async {
    await _pump(
      tester,
      SurfaceStats.fromJson(<String, dynamic>{
        'paved': 1,
        'cycleway': 0.3,
        'coveredLengthM': 1000,
        'totalLengthM': 1000,
      }),
    );
    expect(
      find.text(
        l10n.labelWithPercent(
          l10n.surfaceBikeInfrastructure,
          formatPercent(l10n, 0.3),
        ),
      ),
      findsOneWidget,
    );
  });
}

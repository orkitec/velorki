/// What the AI end-to-end widget tests share: the app's relay client on the
/// in-process [MockRelay], the oracle's Madeira tile with its gazetteer, and
/// waiting on work that runs on real files and isolates.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/geo/track_surface.dart';
import 'package:velorki/features/assistant/application/ai_request_settings.dart';
import 'package:velorki/features/assistant/application/route_digest_service.dart';
import 'package:velorki/features/assistant/presentation/assistant_sheet.dart';
import 'package:velorki/features/integrations/common/data/relay_client_provider.dart';
import 'package:velorki/features/search/data/gazetteer_store.dart';
import 'package:velorki/features/settings/data/language_controller.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../../support/app.dart';
import '../../../support/mock_relay.dart';
import '../../planner/support/fakes.dart';

export '../../../support/mock_relay.dart';
export '../../../support/openapi_schema.dart';

/// The app's relay client, on [relay]'s HTTP client: the one seam. The app
/// is in the language under test, as Settings would have put it, so the
/// request asks for that language.
List<Override> mockRelayOverrides(MockRelay relay) => [
  relayClientProvider.overrideWith((ref) {
    final client = relay.client();
    ref.onDispose(client.close);
    return client;
  }),
  appLocaleProvider.overrideWithValue(testLocale),
  systemLocalesProvider.overrideWithValue([testLocale]),
];

/// The language tag every request has to carry: the app's.
String get appLanguageTag => testLocale.toLanguageTag();

/// [finder] inside the assistant sheet.
Finder inSheet(Finder finder) =>
    find.descendant(of: find.byType(AssistantSheet), matching: finder);

/// The on-device router behind the planner harness' backend.
class RealRouting extends FakeRoutingBackend {
  /// Routes with [inner].
  RealRouting(this.inner);

  /// The router.
  final RoutingBackend inner;

  @override
  Future<RouteResult> route(RouteQuery q, {CancelToken? cancel}) {
    queries.add(q);
    return inner.route(q, cancel: cancel);
  }
}

/// The oracle's Madeira tile, the committed gazetteer over it and the digest
/// service on both, as the app builds them.
class Madeira {
  Madeira._(this.local, this.composite, this.gazetteer, this.digests);

  /// Funchal, where the plans start.
  static const funchal = LatLng(32.6475, -16.9087);

  /// Machico, where they end.
  static const machico = LatLng(32.7167, -16.7667);

  /// Opens everything; call inside `tester.runAsync`, and [close] the same
  /// way.
  static Future<Madeira> open() async {
    final local = LocalRoutingBackend(
      segmentsDir: '../tools/brouter-oracle/tiles',
      profilesDir: '../brouter/profiles',
    );
    final composite = CompositeRoutingBackend(
      local: local,
      localTiles: local.availableTiles,
    );
    final gazetteer = GazetteerStore(Directory('../tools/gazetteer/fixtures'));
    await gazetteer.refresh();
    return Madeira._(
      local,
      composite,
      gazetteer,
      RouteDigestService(
        surfaces: TrackSurfaceService(local: local, decide: composite.decide),
        gazetteer: () async => gazetteer,
      ),
    );
  }

  /// The on-device router.
  final LocalRoutingBackend local;

  /// The router as the app composes it.
  final CompositeRoutingBackend composite;

  /// The gazetteer of the tile.
  final GazetteerStore gazetteer;

  /// The digest service over both.
  final RouteDigestService digests;

  /// The overrides that put them in the app.
  List<Override> get overrides => [
    routeDigestServiceProvider.overrideWithValue(digests),
  ];

  /// Closes the files.
  Future<void> close() async {
    gazetteer.close();
    await local.dispose();
  }
}

/// Pumps until [done], letting real files and isolates run between frames,
/// which pumping alone does not.
Future<void> settle(
  WidgetTester tester,
  bool Function() done, {
  String? what,
}) async {
  // Routing on the tile happens in real time, and a CI runner is several
  // times slower than a laptop: bounded by the clock, not by a count.
  final clock = Stopwatch()..start();
  while (!done() && clock.elapsed < const Duration(seconds: 90)) {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
  }
  await tester.pump();
  expect(done(), isTrue, reason: 'waited for ${what ?? 'it'}');
}

/// The text field of the sheet.
TextField sheetField(WidgetTester tester) =>
    tester.widget<TextField>(inSheet(find.byType(TextField)));

/// The sheet's main button, whatever it says.
FilledButton sendButton(WidgetTester tester) =>
    tester.widget<FilledButton>(inSheet(find.byType(FilledButton)).last);

/// Whether the sheet takes input: the field is editable and Send works.
bool sheetUnlocked(WidgetTester tester) =>
    !sheetField(tester).readOnly && sendButton(tester).onPressed != null;

/// Brings [finder] in the sheet into view and taps it.
Future<void> tapInSheet(WidgetTester tester, Finder finder) async {
  final target = inSheet(finder);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

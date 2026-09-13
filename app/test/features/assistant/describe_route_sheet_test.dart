import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/core/plus/plus_gate.dart';
import 'package:velorki/features/assistant/data/ai_consent_controller.dart';
import 'package:velorki/features/assistant/domain/ai_consent.dart';
import 'package:velorki/features/assistant/presentation/describe_route_sheet.dart';
import 'package:velorki/features/integrations/common/data/relay_client_provider.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/planner/domain/route_profile.dart';
import 'package:velorki/features/planner/domain/routing_options.dart';
import 'package:velorki/features/planner/domain/saved_route.dart';
import 'package:velorki/features/planner/domain/waypoint.dart';
import 'package:velorki_api/velorki_api.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../planner/support/pump.dart';
import 'support/fakes.dart';

/// The route the sheet describes.
SavedRoute _route({RouteSource source = RouteSource.planned}) => SavedRoute(
  id: 'r1',
  name: 'Isar loop',
  source: source,
  profile: RouteProfile.trekking,
  createdAt: DateTime(2026, 9, 1),
  updatedAt: DateTime(2026, 9, 1),
  distanceM: 42000,
  ascentM: 380,
  descentM: 380,
  bounds: const BoundingBox(south: 48, west: 11, north: 48.2, east: 11.2),
  geometryBlob: PackedTrack.encode(const [
    TrackPoint(LatLng(48, 11)),
    TrackPoint(LatLng(48.1, 11.1)),
  ]),
  waypoints: const [
    Waypoint(pos: LatLng(48, 11), name: 'Munich'),
    Waypoint(pos: LatLng(48.1, 11.1), name: 'Grünwald'),
  ],
  options: const RoutingOptions(),
);

/// A route detail stand-in: the button is the sheet's only way in.
class _Host extends StatelessWidget {
  const _Host(this.route);

  final SavedRoute route;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: DescribeRouteButton(route: route)),
  );
}

/// Everything one sheet test drives.
class _Opened {
  _Opened(this.relay, this.container);

  /// The relay the sheet streamed from.
  final ManualRelayClient relay;

  /// The scope the sheet reads its providers from.
  final ProviderContainer container;

  /// The library the description is written to.
  RouteRepository get repository => container.read(routeRepositoryProvider);
}

/// Pumps the host, taps "Describe this route" and waits for the sheet.
///
/// Never [WidgetTester.pumpAndSettle]: while the model is writing the sheet
/// shows a spinner, which never settles.
Future<_Opened> _openSheet(
  WidgetTester tester, {
  AiConsent? consent = AiConsent.textOnly,
  bool entitled = true,
  bool withRelay = true,
  SavedRoute? route,
}) async {
  final subject = route ?? _route();
  final relay = ManualRelayClient();
  await pumpScreen(
    tester,
    _Host(subject),
    extraOverrides: [
      relayClientProvider.overrideWithValue(withRelay ? relay : null),
    ],
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(_Host)),
  );
  container.read(plusEntitledProvider.notifier).value = entitled;
  if (consent != null) {
    await container.read(aiConsentControllerProvider.notifier).set(consent);
  }
  await container.read(routeRepositoryProvider).restore(subject);

  await tester.tap(find.text('Describe this route'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
  return _Opened(relay, container);
}

/// The sheet's "Save as description" button.
FilledButton _saveButton(WidgetTester tester) => tester.widget<FilledButton>(
  find.widgetWithText(FilledButton, 'Save as description'),
);

/// Streams [parts] into the open request and closes it, as the relay does.
Future<void> _stream(
  WidgetTester tester,
  ManualRelayClient relay,
  List<String> parts,
) async {
  for (final part in parts) {
    relay.emit(TextEvent(part));
    await tester.pump();
  }
  await relay.finish();
  await tester.pump();
}

void main() {
  testWidgets('the sheet opens writing and appends the text as it arrives', (
    tester,
  ) async {
    final opened = await _openSheet(tester);

    // The request went out on its own: the rider already pressed a button.
    expect(opened.relay.planCalls.single.step, 'describe');
    expect(opened.relay.planCalls.single.routeSummary?.distanceKm, 42);
    expect(find.text('Description'), findsOneWidget);
    expect(find.text('Writing…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNull);

    opened.relay.emit(const TextEvent('A gentle loop '));
    await tester.pump();

    expect(find.text('A gentle loop '), findsOneWidget);
    expect(find.text('Writing…'), findsOneWidget);
    // Nothing to keep while the model is still writing.
    expect(_saveButton(tester).onPressed, isNull);

    opened.relay.emit(const TextEvent('along the Isar.'));
    await tester.pump();

    // Appended, not replaced.
    expect(find.text('A gentle loop along the Isar.'), findsOneWidget);

    await opened.relay.finish();
    await tester.pump();

    expect(find.text('Writing…'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('A gentle loop along the Isar.'), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNotNull);
  });

  testWidgets('saving writes the description to the route and says so', (
    tester,
  ) async {
    final opened = await _openSheet(tester);
    await _stream(tester, opened.relay, ['A gentle loop ', 'along the Isar.']);

    await tester.tap(find.text('Save as description'));
    await tester.pumpAndSettle();

    final stored = await opened.repository.routeById('r1');
    expect(stored?.description, 'A gentle loop along the Isar.');
    expect(stored?.aiDescriptionGenerated, isTrue);
    // The sheet has done its job and gets out of the way.
    expect(find.byType(DescribeRouteSheet), findsNothing);
    expect(find.text('The description was saved.'), findsOneWidget);

    await unmountApp(tester);
  });

  testWidgets('nothing is written until the rider saves', (tester) async {
    final opened = await _openSheet(tester);
    await _stream(tester, opened.relay, ['A gentle loop along the Isar.']);

    expect(find.text('A gentle loop along the Isar.'), findsOneWidget);
    expect((await opened.repository.routeById('r1'))?.description, isNull);
  });

  testWidgets('writing again replaces the first answer instead of adding to '
      'it', (tester) async {
    final opened = await _openSheet(tester);
    await _stream(tester, opened.relay, ['A gentle loop along the Isar.']);

    await tester.tap(find.text('Write again'));
    await tester.pump();

    expect(opened.relay.planCalls.length, 2);
    // The old text went with the old answer.
    expect(find.text('A gentle loop along the Isar.'), findsNothing);
    expect(find.text('Writing…'), findsOneWidget);

    await _stream(tester, opened.relay, ['A hilly ride ', 'up to Grünwald.']);

    expect(find.text('A hilly ride up to Grünwald.'), findsOneWidget);
    expect(find.textContaining('A gentle loop'), findsNothing);
    expect(_saveButton(tester).onPressed, isNotNull);
  });

  testWidgets('a failed stream is reported and can be tried again', (
    tester,
  ) async {
    final opened = await _openSheet(tester);

    opened.relay.emit(
      const ErrorEvent(
        RelayError(
          code: RelayErrorCode.upstreamError,
          message: 'the model is unavailable',
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text(
        'The description could not be written: The assistant could not '
        'answer: the model is unavailable',
      ),
      findsOneWidget,
    );
    expect(find.text('Writing…'), findsNothing);
    expect(_saveButton(tester).onPressed, isNull);

    await tester.tap(find.text('Write again'));
    await tester.pump();
    await _stream(tester, opened.relay, ['A gentle loop along the Isar.']);

    expect(opened.relay.planCalls.length, 2);
    expect(find.textContaining('could not be written'), findsNothing);
    expect(find.text('A gentle loop along the Isar.'), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNotNull);
  });

  testWidgets('without Velorki Plus the sheet says the assistant is part of '
      'it', (tester) async {
    final opened = await _openSheet(tester, entitled: false);

    expect(
      find.text(
        'The description could not be written: The AI assistant is part of '
        'Velorki Plus.',
      ),
      findsOneWidget,
    );
    expect(opened.relay.planCalls, isEmpty);
    expect(_saveButton(tester).onPressed, isNull);
  });

  testWidgets('a build without a relay says the assistant is unavailable', (
    tester,
  ) async {
    final opened = await _openSheet(tester, withRelay: false);

    expect(
      find.text(
        'The description could not be written: This build of Velorki has no '
        'server configured, so the assistant is unavailable.',
      ),
      findsOneWidget,
    );
    expect(opened.relay.planCalls, isEmpty);
  });

  testWidgets('the first description asks for consent before anything is '
      'sent', (tester) async {
    final opened = await _openSheet(tester, consent: null);

    expect(find.text('Before the assistant asks'), findsOneWidget);
    expect(opened.relay.planCalls, isEmpty);

    await tester.tap(find.text('Allow, text only'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      opened.container.read(aiConsentControllerProvider),
      AiConsent.textOnly,
    );
    expect(opened.relay.planCalls.single.step, 'describe');

    await _stream(tester, opened.relay, ['A gentle loop along the Isar.']);
    expect(find.text('A gentle loop along the Isar.'), findsOneWidget);
  });

  testWidgets('refusing consent sends nothing and leaves the sheet open', (
    tester,
  ) async {
    final opened = await _openSheet(tester, consent: null);

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(opened.relay.planCalls, isEmpty);
    expect(
      opened.container.read(aiConsentControllerProvider),
      AiConsent.denied,
    );
    expect(find.byType(DescribeRouteSheet), findsOneWidget);
    expect(find.text('Writing…'), findsNothing);
    expect(_saveButton(tester).onPressed, isNull);
  });

  testWidgets('a route imported from Strava is never offered a description', (
    tester,
  ) async {
    await pumpScreen(tester, _Host(_route(source: RouteSource.strava)));

    expect(find.text('Describe this route'), findsNothing);
  });
}

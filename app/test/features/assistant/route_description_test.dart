import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/app/app_config.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/core/plus/plus_gate.dart';
import 'package:velorki/features/assistant/application/ai_request_settings.dart';
import 'package:velorki/features/assistant/application/route_description_controller.dart';
import 'package:velorki/features/assistant/application/route_digest_service.dart';
import 'package:velorki/features/assistant/domain/ai_consent.dart';
import 'package:velorki/features/assistant/domain/assistant_state.dart';
import 'package:velorki/features/integrations/common/data/relay_client_provider.dart';
import 'package:velorki/features/planner/data/route_repository.dart';
import 'package:velorki/features/planner/domain/route_profile.dart';
import 'package:velorki/features/planner/domain/routing_options.dart';
import 'package:velorki/features/planner/domain/saved_route.dart';
import 'package:velorki/features/planner/domain/waypoint.dart';
import 'package:velorki/features/settings/data/units.dart';
import 'package:velorki_api/velorki_api.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../integrations/support/fakes.dart';
import 'support/fakes.dart' show FakeRouteDigestService;

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

const RouteDigest _digest = RouteDigest(
  profile: 'trekking',
  loop: false,
  towns: <DigestTown>[
    DigestTown(
      name: 'Grünwald',
      kind: 'village',
      km: 12.5,
      at: DigestPoint(lat: 48.04, lon: 11.52),
    ),
  ],
);

Future<ProviderContainer> _container({
  required FakeRelayClient relay,
  required VelorkiDatabase db,
  AiConsent consent = AiConsent.textOnly,
  bool entitled = true,
  RouteDigestService? digests,
  Map<String, Object> prefs = const <String, Object>{},
  List<Locale> phone = const <Locale>[Locale('en', 'GB')],
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    aiConsentPrefsKey: consent.name,
    ...prefs,
  });
  final preferences = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      relayClientProvider.overrideWithValue(relay),
      velorkiDatabaseProvider.overrideWithValue(db),
      routeDigestServiceProvider.overrideWithValue(
        digests ?? FakeRouteDigestService(),
      ),
      systemLocalesProvider.overrideWithValue(phone),
      localeCountryProvider.overrideWithValue(phone.first.countryCode),
    ],
  );
  addTearDown(container.dispose);
  container.read(plusEntitledProvider.notifier).value = entitled;
  return container;
}

void main() {
  late VelorkiDatabase db;

  setUp(() => db = VelorkiDatabase.memory());
  tearDown(() => db.close());

  test('a Strava route is never described', () {
    expect(canDescribe(_route()), isTrue);
    expect(canDescribe(_route(source: RouteSource.strava)), isFalse);
  });

  test('the summary carries numbers, not geometry', () {
    final summary = summaryOf(_route());
    expect(summary.distanceKm, 42);
    expect(summary.ascentM, 380);
    expect(summary.waypoints, ['Munich', 'Grünwald']);
  });

  test('text deltas are streamed and saved on request', () async {
    final relay = FakeRelayClient(
      planEvents: const <PlanEvent>[
        TextEvent('A gentle loop '),
        TextEvent('along the Isar.'),
        DoneEvent(),
      ],
    );
    final container = await _container(relay: relay, db: db);
    final repository = container.read(routeRepositoryProvider);
    final route = _route();
    await repository.restore(route);

    final controller = container.read(
      routeDescriptionControllerProvider.notifier,
    );
    await controller.describe(route, locale: 'en');

    var state = container.read(routeDescriptionControllerProvider);
    expect(state.running, isFalse);
    expect(state.text, 'A gentle loop along the Isar.');
    expect(state.canSave, isTrue);
    expect(relay.planCalls.single.step, 'describe');
    expect(relay.planCalls.single.routeSummary?.distanceKm, 42);

    await controller.save(route);

    state = container.read(routeDescriptionControllerProvider);
    expect(state.saved, isTrue);
    final stored = await repository.routeById('r1');
    expect(stored?.description, 'A gentle loop along the Isar.');
    expect(stored?.aiDescriptionGenerated, isTrue);
  });

  test('the digest goes with the summary', () async {
    final relay = FakeRelayClient(
      planEvents: const <PlanEvent>[TextEvent('Past Grünwald.'), DoneEvent()],
    );
    final digests = FakeRouteDigestService(digest: _digest);
    final container = await _container(relay: relay, db: db, digests: digests);

    await container
        .read(routeDescriptionControllerProvider.notifier)
        .describe(_route());

    expect(digests.asked, ['r1']);
    final summary = relay.planCalls.single.routeSummary!;
    expect(summary.digest, _digest);
    expect(summary.distanceKm, 42);
  });

  test('without a digest the figures still go', () async {
    for (final digests in [
      FakeRouteDigestService(),
      FakeRouteDigestService(error: StateError('no tile')),
    ]) {
      final relay = FakeRelayClient(
        planEvents: const <PlanEvent>[TextEvent('A loop.'), DoneEvent()],
      );
      final container = await _container(
        relay: relay,
        db: db,
        digests: digests,
      );

      await container
          .read(routeDescriptionControllerProvider.notifier)
          .describe(_route());

      final state = container.read(routeDescriptionControllerProvider);
      expect(state.problem, isNull);
      expect(state.text, 'A loop.');
      final summary = relay.planCalls.single.routeSummary!;
      expect(summary.digest, isNull);
      expect(summary.waypoints, ['Munich', 'Grünwald']);
    }
  });

  test(
    "it is asked for in the app's language and units, not the phone's",
    () async {
      final relay = FakeRelayClient(
        planEvents: const <PlanEvent>[TextEvent('A loop.'), DoneEvent()],
      );
      final container = await _container(
        relay: relay,
        db: db,
        phone: const [Locale('de', 'DE')],
        prefs: const <String, Object>{
          'language.locale': 'en',
          'units.system': 'imperial',
        },
      );

      await container
          .read(routeDescriptionControllerProvider.notifier)
          .describe(_route());

      final call = relay.planCalls.single;
      expect(call.locale, 'en');
      expect(call.units, PlanUnits.imperial);
    },
  );

  test('without Velorki Plus nothing is asked for', () async {
    final relay = FakeRelayClient();
    final container = await _container(relay: relay, db: db, entitled: false);

    await container
        .read(routeDescriptionControllerProvider.notifier)
        .describe(_route());

    expect(
      container.read(routeDescriptionControllerProvider).problem?.failure,
      AssistantFailure.notEntitled,
    );
    expect(relay.planCalls, isEmpty);
  });

  test('a relay error is reported and nothing is saved', () async {
    final relay = FakeRelayClient(
      planEvents: const <PlanEvent>[
        ErrorEvent(
          RelayError(
            code: RelayErrorCode.upstreamError,
            message: 'the model is unavailable',
          ),
        ),
      ],
    );
    final container = await _container(relay: relay, db: db);

    await container
        .read(routeDescriptionControllerProvider.notifier)
        .describe(_route());

    final state = container.read(routeDescriptionControllerProvider);
    expect(state.problem?.failure, AssistantFailure.relay);
    expect(state.canSave, isFalse);
  });
}

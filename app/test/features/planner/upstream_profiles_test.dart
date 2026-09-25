import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/planner/data/routing_backend_provider.dart';
import 'package:velorki/features/planner/domain/route_profile.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/fakes.dart';

void main() {
  test('a server not redeployed with the variants is asked for the upstream '
      'profile, the device\'s own engine for the variant', () async {
    final server = FakeRoutingBackend();
    final device = LocalRoutingBackend(
      segmentsDir: '../tools/brouter-oracle/tiles',
      profilesDir: '../brouter/profiles',
    );
    addTearDown(device.dispose);
    final backend = CompositeRoutingBackend(
      local: device,
      remote: UpstreamProfiles(server),
      localTiles: () => <TileName>{TileName.parse('W20_N30')},
    );
    final profile = RouteProfile.trekking.engineName;
    expect(profile, 'velorki-trekking');

    // In Funchal, on the tile on disk: the device routes it with the variant.
    final funchal = await backend.route(
      RouteQuery(
        points: const [LatLng(32.6405, -16.9290), LatLng(32.6477, -16.9086)],
        profile: profile,
      ),
    );
    expect(backend.lastSource, RoutingSource.local);
    expect(funchal.lengthM, greaterThan(1000));
    expect(server.queries, isEmpty);

    // Off the tile: the server answers, asked for the upstream name.
    await backend.route(
      RouteQuery(
        points: const [LatLng(48.0, 11.0), LatLng(48.1, 11.1)],
        profile: profile,
      ),
    );
    expect(backend.lastSource, RoutingSource.remote);
    expect(server.queries.single.profile, 'trekking');
  });

  test('a profile that is not one of the variants goes out as it is', () async {
    final server = FakeRoutingBackend();
    await UpstreamProfiles(server).route(
      const RouteQuery(
        points: [LatLng(48, 11), LatLng(48.1, 11.1)],
        profile: 'shortest',
      ),
    );
    expect(server.queries.single.profile, 'shortest');
  });
}

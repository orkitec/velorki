import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// Madeira: entirely inside W20_N30.
const madeira = RouteQuery(
  points: [LatLng(32.65, -16.92), LatLng(32.72, -16.77)],
);

/// Munich to Hamburg: a 610 km diagonal, so the 20 % margin spreads the
/// corridor over the four tiles E5/E10 × N45/N50.
const germany = RouteQuery(
  points: [LatLng(48.137, 11.575), LatLng(53.551, 9.993)],
);

RouteResult get sample => RouteResult.fromGeoJson(
  jsonDecode(File('test/fixtures/route_trekking.geojson').readAsStringSync())
      as Map<String, dynamic>,
);

/// A [LocalRoutingBackend] that never spawns an isolate.
class FakeLocal extends LocalRoutingBackend {
  FakeLocal() : super(segmentsDir: '/no/segments', profilesDir: '/no/profiles');

  int calls = 0;

  @override
  Future<RouteResult> route(RouteQuery q, {CancelToken? cancel}) async {
    calls++;
    return sample;
  }
}

class FakeRemote implements RoutingBackend {
  int calls = 0;

  @override
  Future<RouteResult> route(RouteQuery q, {CancelToken? cancel}) async {
    calls++;
    return sample;
  }
}

CompositeRoutingBackend composite({
  LocalRoutingBackend? local,
  RoutingBackend? remote,
  Set<TileName> tiles = const <TileName>{},
  String? requiredFormatVersion,
  Map<TileName, String>? localFormatVersions,
}) => CompositeRoutingBackend(
  local: local,
  remote: remote,
  localTiles: () => tiles,
  requiredFormatVersion: requiredFormatVersion,
  localFormatVersions: localFormatVersions,
);

const madeiraTile = TileName(-20, 30);
final germanTiles = <TileName>{
  const TileName(5, 45),
  const TileName(10, 45),
  const TileName(5, 50),
  const TileName(10, 50),
};

void main() {
  test('the required tiles are the tile rule applied to the waypoints', () {
    final backend = composite(local: FakeLocal(), remote: FakeRemote());
    expect(backend.requiredTiles(madeira), [madeiraTile]);
    expect(backend.requiredTiles(germany).toSet(), germanTiles);
  });

  test('a round trip covers its own radius, not just its start point', () {
    final backend = composite(local: FakeLocal(), remote: FakeRemote());
    const start = RouteQuery(points: [LatLng(32.6, -15.4)]);
    expect(backend.requiredTiles(start), [madeiraTile]);
    // A 40 km radius reaches over the tile edge at lon -15.
    expect(
      backend
          .requiredTiles(
            start.copyWith(roundTrip: true, roundTripDistanceM: 40000),
          )
          .map((t) => t.name),
      containsAll(<String>['W20_N30', 'W15_N30']),
    );
  });

  group('all tiles local', () {
    test('routes on the device', () async {
      final local = FakeLocal();
      final remote = FakeRemote();
      final backend = composite(
        local: local,
        remote: remote,
        tiles: {madeiraTile},
      );

      final decision = backend.decide(madeira);
      expect(decision.source, RoutingSource.local);
      expect(decision.missingTiles, isEmpty);
      expect(decision.hasLocalCoverage, isTrue);
      expect(decision.canRoute, isTrue);
      expect(decision.failure, isNull);

      expect(backend.lastSource, isNull);
      await backend.route(madeira);
      expect(local.calls, 1);
      expect(remote.calls, 0);
      expect(backend.lastSource, RoutingSource.local);
    });

    test('a matching format version keeps it local', () async {
      final local = FakeLocal();
      final backend = composite(
        local: local,
        remote: FakeRemote(),
        tiles: {madeiraTile},
        requiredFormatVersion: '11.2',
        localFormatVersions: {madeiraTile: '11.2'},
      );
      await backend.route(madeira);
      expect(backend.lastSource, RoutingSource.local);
      expect(local.calls, 1);
    });
  });

  group('partial coverage', () {
    test('falls back to the server', () async {
      final local = FakeLocal();
      final remote = FakeRemote();
      final backend = composite(
        local: local,
        remote: remote,
        tiles: {const TileName(10, 45), const TileName(10, 50)},
      );

      final decision = backend.decide(germany);
      expect(decision.source, RoutingSource.remote);
      expect(decision.missingTiles.map((t) => t.name), ['E5_N45', 'E5_N50']);
      expect(decision.hasLocalCoverage, isFalse);

      await backend.route(germany);
      expect(local.calls, 0);
      expect(remote.calls, 1);
      expect(backend.lastSource, RoutingSource.remote);
    });

    test('a mismatched format version counts as missing', () async {
      final backend = composite(
        local: FakeLocal(),
        remote: FakeRemote(),
        tiles: {madeiraTile},
        requiredFormatVersion: '11.2',
        localFormatVersions: {madeiraTile: '10.1'},
      );
      final decision = backend.decide(madeira);
      expect(decision.source, RoutingSource.remote);
      expect(decision.missingTiles, [madeiraTile]);
      await backend.route(madeira);
      expect(backend.lastSource, RoutingSource.remote);
    });

    test('an unknown format version counts as missing', () {
      final backend = composite(
        local: FakeLocal(),
        remote: FakeRemote(),
        tiles: {madeiraTile},
        requiredFormatVersion: '11.2',
      );
      expect(backend.decide(madeira).missingTiles, [madeiraTile]);
    });

    test('without a local backend everything goes to the server', () async {
      final remote = FakeRemote();
      final backend = composite(remote: remote, tiles: {madeiraTile});
      expect(backend.decide(madeira).source, RoutingSource.remote);
      await backend.route(madeira);
      expect(remote.calls, 1);
    });
  });

  group('no coverage and no server', () {
    test('names the missing tiles and their count', () async {
      final local = FakeLocal();
      final backend = composite(local: local, tiles: {const TileName(10, 45)});

      final decision = backend.decide(germany);
      expect(decision.source, isNull);
      expect(decision.canRoute, isFalse);
      expect(decision.requiredTiles.toSet(), germanTiles);
      expect(decision.missingTiles.map((t) => t.name), [
        'E5_N45',
        'E5_N50',
        'E10_N50',
      ]);

      await expectLater(
        backend.route(germany),
        throwsA(
          isA<RoutingException>()
              .having((e) => e.kind, 'kind', RoutingErrorKind.missingTiles)
              .having(
                (e) => e.missingTiles.map((t) => t.name).toList(),
                'missingTiles',
                ['E5_N45', 'E5_N50', 'E10_N50'],
              )
              .having((e) => e.message, 'message', contains('3 tiles'))
              .having(
                (e) => e.message,
                'message',
                contains('E5_N45, E5_N50, E10_N50'),
              ),
        ),
      );
      expect(local.calls, 0);
      expect(backend.lastSource, isNull);
    });

    test('one missing tile reads as one tile', () {
      final backend = composite(local: FakeLocal());
      final failure = backend.decide(madeira).failure!;
      expect(failure.missingTiles, [madeiraTile]);
      expect(failure.message, contains('1 tile that is not downloaded'));
      expect(failure.message, contains('W20_N30'));
    });

    test('the UI can price the download from a manifest', () {
      final backend = composite(
        local: FakeLocal(),
        tiles: {const TileName(10, 45)},
      );
      final manifest = SegmentsManifest.parse(
        '[{"tile": "E5_N45", "bytes": 212408832},'
        ' {"tile": "E5_N50", "bytes": 100000000},'
        ' {"tile": "E10_N50", "bytes": 50000000}]',
      );
      final decision = backend.decide(germany);
      expect(decision.missingTiles, hasLength(3));
      expect(decision.missingBytes(manifest), 362408832);
    });
  });

  test('needs at least one backend', () {
    expect(
      () => CompositeRoutingBackend(localTiles: () => const <TileName>{}),
      throwsArgumentError,
    );
  });

  test('a cancel token reaches the chosen backend', () async {
    final cancel = CancelToken()..cancel('enough');
    final backend = composite(
      remote: _CancellingRemote(),
      tiles: {madeiraTile},
    );
    await expectLater(
      backend.route(madeira, cancel: cancel),
      throwsA(
        isA<RoutingException>().having(
          (e) => e.kind,
          'kind',
          RoutingErrorKind.cancelled,
        ),
      ),
    );
    expect(backend.lastSource, isNull, reason: 'no successful route yet');
  });

  test('toString says what it is wired to', () {
    final backend = composite(local: FakeLocal(), remote: FakeRemote());
    expect(backend.toString(), contains('local: true'));
    expect(backend.toString(), contains('remote: true'));
    expect(
      backend.decide(madeira).toString(),
      'RoutingDecision(remote, 1 tiles, 1 missing)',
    );
  });
}

class _CancellingRemote implements RoutingBackend {
  @override
  Future<RouteResult> route(RouteQuery q, {CancelToken? cancel}) async {
    if (cancel != null && cancel.isCancelled) throw cancel.toException();
    return sample;
  }
}

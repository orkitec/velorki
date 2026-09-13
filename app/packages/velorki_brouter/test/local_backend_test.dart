// The on-device backend. The routing tests need the two rd5 tiles of the
// oracle's cache and are skipped without them; everything above the engine
// (parameter building, cancellation before the isolate starts, the tile
// listing) runs everywhere.

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// Funchal to Machico, the pair the corpus' Madeira cases live around.
const funchalToMachico = RouteQuery(
  points: [LatLng(32.65, -16.92), LatLng(32.72, -16.77)],
);

/// Munich to Hamburg: nowhere near the two tiles we have.
const germany = RouteQuery(
  points: [LatLng(48.137, 11.575), LatLng(53.551, 9.993)],
);

/// The rd5 tiles are committed under `tools/brouter-oracle/tiles/`; the
/// tile-backed tests only run when `BROUTER_SEGMENTS_DIR` points at a directory
/// holding them (`tools/brouter-oracle/fetch.sh` fills the oracle's cache).
final String? segmentsDir = Platform.environment['BROUTER_SEGMENTS_DIR'];

/// The repo's profiles (`brouter/profiles`), overridable like in brouter_dart.
final String profilesDir =
    Platform.environment['BROUTER_PROFILES_DIR'] ?? '../../../brouter/profiles';

/// The oracle's corpus, recorded against the pinned BRouter server.
final String oracleDir =
    Platform.environment['BROUTER_ORACLE_DIR'] ??
    '../../../tools/brouter-oracle';

String? get corpusSkipReason =>
    skipReason ??
    (File('$oracleDir/corpus/index.json').existsSync()
        ? null
        : 'the oracle corpus is not in $oracleDir');

String? get skipReason {
  final dir = segmentsDir;
  if (dir == null) {
    return 'BROUTER_SEGMENTS_DIR is not set '
        '(point it at a directory with W20_N30.rd5)';
  }
  if (!File('$dir/W20_N30.rd5').existsSync()) {
    return 'W20_N30.rd5 not found in $dir '
        '(run tools/brouter-oracle/fetch.sh)';
  }
  if (!File('$profilesDir/lookups.dat').existsSync()) {
    return 'lookups.dat not found in $profilesDir '
        '(set BROUTER_PROFILES_DIR)';
  }
  return null;
}

void main() {
  group('without an engine', () {
    test('availableTiles lists the rd5 files and nothing else', () async {
      final dir = await Directory.systemTemp.createTemp('velorki_segments');
      addTearDown(() => dir.delete(recursive: true));
      File('${dir.path}/W20_N30.rd5').writeAsStringSync('x');
      File('${dir.path}/E5_N45.rd5').writeAsStringSync('x');
      File('${dir.path}/E10_N45.rd5.part').writeAsStringSync('x');
      File('${dir.path}/manifest.json').writeAsStringSync('{}');
      File('${dir.path}/planet.rd5').writeAsStringSync('x');
      Directory('${dir.path}/old').createSync();

      final backend = LocalRoutingBackend(
        segmentsDir: dir.path,
        profilesDir: profilesDir,
      );
      expect(backend.availableTiles(), {
        const TileName(-20, 30),
        const TileName(5, 45),
      });
    });

    test('a missing segments directory has no tiles', () {
      final backend = LocalRoutingBackend(
        segmentsDir: '/velorki/does/not/exist',
        profilesDir: profilesDir,
      );
      expect(backend.availableTiles(), isEmpty);
      expect(backend.worker, isNull);
    });

    test('an already cancelled token never starts the isolate', () async {
      final backend = LocalRoutingBackend(
        segmentsDir: '/velorki/does/not/exist',
        profilesDir: profilesDir,
      );
      final cancel = CancelToken()..cancel('user went back');
      await expectLater(
        backend.route(funchalToMachico, cancel: cancel),
        throwsA(
          isA<RoutingException>()
              .having((e) => e.kind, 'kind', RoutingErrorKind.cancelled)
              .having((e) => e.message, 'message', 'user went back'),
        ),
      );
      expect(backend.worker, isNull, reason: 'no isolate was spawned');
      await backend.dispose();
    });

    test('an impossible query is rejected before the isolate', () async {
      final backend = LocalRoutingBackend(
        segmentsDir: '/velorki/does/not/exist',
        profilesDir: profilesDir,
      );
      await expectLater(
        backend.route(const RouteQuery(points: [LatLng(32.65, -16.92)])),
        throwsA(
          isA<RoutingException>().having(
            (e) => e.kind,
            'kind',
            RoutingErrorKind.invalid,
          ),
        ),
      );
      expect(backend.worker, isNull);
      await backend.dispose();
    });

    test('disposing twice is fine, routing afterwards is not', () async {
      final backend = LocalRoutingBackend(
        segmentsDir: '/velorki/does/not/exist',
        profilesDir: profilesDir,
      );
      await backend.dispose();
      await backend.dispose();
      await expectLater(
        backend.route(funchalToMachico),
        throwsA(
          isA<RoutingException>().having(
            (e) => e.message,
            'message',
            contains('disposed'),
          ),
        ),
      );
    });
  });

  group('on the real tiles', () {
    late LocalRoutingBackend backend;

    setUp(() {
      backend = LocalRoutingBackend(
        segmentsDir: segmentsDir ?? '/unset',
        profilesDir: profilesDir,
        maxMemMb: 64,
      );
    });

    tearDown(() => backend.dispose());

    test('lists the tiles it has', () {
      expect(
        backend.availableTiles(),
        containsAll(<TileName>[const TileName(-20, 30)]),
      );
    }, skip: skipReason);

    test(
      'routes Funchal to Machico with trekking',
      () async {
        final result = await backend.route(funchalToMachico);

        // The road distance is 15 km as the crow flies; the coast road and the
        // climbs make it a little over 20 km.
        expect(result.lengthM, greaterThan(20000));
        expect(result.lengthM, lessThan(35000));
        expect(result.ascentM, greaterThan(0));
        expect(result.plainAscentM, isNot(0));
        expect(result.geometry, isNotEmpty);
        expect(result.geometry.first.ele, isNotNull);
        expect(result.messages, isNotEmpty);
        expect(result.creator, contains('BRouter'));
        expect(result.totalTime, isNotNull);

        // The waypoints are on the route.
        expect(
          result.geometry.first.pos.lat,
          closeTo(funchalToMachico.points.first.lat, 0.02),
        );
        expect(
          result.geometry.last.pos.lon,
          closeTo(funchalToMachico.points.last.lon, 0.02),
        );

        // The same `messages` table the server path produces, so the surface
        // statistics come out of it unchanged.
        final stats = result.surfaceStats;
        expect(stats.totalLengthM, result.lengthM);
        expect(stats.coveredLengthM, greaterThan(result.lengthM * 0.9));
        expect(
          stats.pavedShare + stats.unpavedShare + stats.unknownShare,
          closeTo(stats.coveredLengthM / stats.totalLengthM, 1e-9),
        );
        expect(stats.pavedShare, greaterThan(0.5), reason: 'a coast road');

        printOnFailure(
          'Funchal->Machico: ${(result.lengthM / 1000).toStringAsFixed(2)} km, '
          '+${result.ascentM.round()} m, ${result.geometry.length} points, '
          '${result.messages.length} messages, $stats',
        );
      },
      skip: skipReason,
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'a corpus case comes out exactly as the server recorded it',
      () async {
        final index = jsonDecode(
          File('$oracleDir/corpus/index.json').readAsStringSync(),
        ) as Map<String, dynamic>;
        final requests = jsonDecode(
          File('$oracleDir/corpus/requests.json').readAsStringSync(),
        ) as Map<String, dynamic>;
        final recorded = (index['cases'] as List).firstWhere(
          (c) => (c as Map<String, dynamic>)['id'] == 'pair-000',
        ) as Map<String, dynamic>;
        final request = (requests['cases'] as List).firstWhere(
          (c) => (c as Map<String, dynamic>)['id'] == 'pair-000',
        ) as Map<String, dynamic>;
        final waypoints = (request['waypoints'] as List)
            .map((p) => LatLng((p as List)[1] as double, p[0] as double))
            .toList();

        final result = await backend.route(
          RouteQuery(points: waypoints, profile: request['profile'] as String),
        );
        final fromServer = RouteResult.fromGeoJson(
          jsonDecode(
            File('$oracleDir/corpus/${recorded['response']}')
                .readAsStringSync(),
          ) as Map<String, dynamic>,
        );

        expect(
          result.lengthM,
          double.parse(recorded['track_length'] as String),
        );
        expect(
          result.ascentM,
          double.parse(recorded['filtered_ascend'] as String),
        );
        expect(
          result.plainAscentM,
          double.parse(recorded['plain_ascend'] as String),
        );
        expect(result.geometry.length, recorded['coordinates']);
        // the corpus counts the header row of the messages table, we do not
        expect(result.messages.length, (recorded['messages'] as int) - 1);
        expect(result.positions, fromServer.positions);
        expect(
          result.messages.map((m) => m.raw),
          fromServer.messages.map((m) => m.raw),
        );
        expect(result.surfaceStats, fromServer.surfaceStats);
      },
      skip: corpusSkipReason,
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'the isolate is reused between requests',
      () async {
        await backend.route(funchalToMachico);
        final first = backend.worker;
        expect(first, isNotNull);
        await backend.route(funchalToMachico);
        expect(identical(backend.worker, first), isTrue);
      },
      skip: skipReason,
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'an unknown profile is an invalid request',
      () async {
        await expectLater(
          backend.route(funchalToMachico.copyWith(profile: 'no-such-profile')),
          throwsA(
            isA<RoutingException>().having(
              (e) => e.kind,
              'kind',
              RoutingErrorKind.invalid,
            ),
          ),
        );
      },
      skip: skipReason,
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'a start in the Atlantic has no route',
      () async {
        await expectLater(
          backend.route(
            const RouteQuery(
              points: [LatLng(32.0, -17.5), LatLng(32.72, -16.77)],
            ),
          ),
          throwsA(
            isA<RoutingException>().having(
              (e) => e.kind,
              'kind',
              RoutingErrorKind.noRoute,
            ),
          ),
        );
      },
      skip: skipReason,
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'a cancel token stops the search',
      () async {
        final cancel = CancelToken();
        final pending = backend.route(funchalToMachico, cancel: cancel);
        await Future<void>.delayed(const Duration(milliseconds: 40));
        cancel.cancel('another candidate won');

        await expectLater(
          pending,
          throwsA(
            isA<RoutingException>()
                .having((e) => e.kind, 'kind', RoutingErrorKind.cancelled)
                .having((e) => e.message, 'message', 'another candidate won'),
          ),
        );

        // The backend survives a cancellation and routes again.
        final result = await backend.route(funchalToMachico);
        expect(result.lengthM, greaterThan(20000));
      },
      skip: skipReason,
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'a deadline is reported as a timeout, not as a cancellation',
      () async {
        // Warm the isolate up so the clock measures the search, not the spawn.
        await backend.route(funchalToMachico);
        await expectLater(
          backend.route(
            funchalToMachico.copyWith(timeout: const Duration(milliseconds: 1)),
          ),
          throwsA(
            isA<RoutingException>()
                .having((e) => e.kind, 'kind', RoutingErrorKind.network)
                .having(
                  (e) => e.message,
                  'message',
                  contains('did not finish'),
                ),
          ),
        );
      },
      skip: skipReason,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });

  group('through the composite backend', () {
    late LocalRoutingBackend local;
    late CompositeRoutingBackend backend;

    setUp(() {
      local = LocalRoutingBackend(
        segmentsDir: segmentsDir ?? '/unset',
        profilesDir: profilesDir,
      );
      backend = CompositeRoutingBackend(
        local: local,
        localTiles: local.availableTiles,
      );
    });

    tearDown(() => local.dispose());

    test(
      'a Madeira route goes to the device',
      () async {
        expect(backend.decide(funchalToMachico).source, RoutingSource.local);
        final result = await backend.route(funchalToMachico);
        expect(backend.lastSource, RoutingSource.local);
        expect(result.lengthM, greaterThan(20000));
        expect(result.lengthM, lessThan(35000));
      },
      skip: skipReason,
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('a German route asks for its tiles', () async {
      final decision = backend.decide(germany);
      expect(decision.source, isNull);
      expect(decision.missingTiles.map((t) => t.name), [
        'E5_N45',
        'E10_N45',
        'E5_N50',
        'E10_N50',
      ]);
      await expectLater(
        backend.route(germany),
        throwsA(
          isA<RoutingException>()
              .having((e) => e.kind, 'kind', RoutingErrorKind.missingTiles)
              .having((e) => e.missingTiles, 'missingTiles', hasLength(4)),
        ),
      );
    }, skip: skipReason);

    test(
      'with a server configured the German route falls back to it',
      () async {
        final remote = _StubRemote();
        final withRemote = CompositeRoutingBackend(
          local: local,
          remote: remote,
          localTiles: local.availableTiles,
        );
        expect(withRemote.decide(germany).source, RoutingSource.remote);
        await withRemote.route(germany);
        expect(remote.calls, 1);
        expect(withRemote.lastSource, RoutingSource.remote);
      },
      skip: skipReason,
    );
  });
}

class _StubRemote implements RoutingBackend {
  int calls = 0;

  @override
  Future<RouteResult> route(RouteQuery q, {CancelToken? cancel}) async {
    calls++;
    return RouteResult(
      geometry: const [],
      lengthM: 0,
      ascentM: 0,
      descentM: 0,
      messages: const [],
      raw: const {},
    );
  }
}

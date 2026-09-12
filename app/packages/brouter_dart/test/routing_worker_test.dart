// The RoutingWorker isolate: a corpus case routed through the worker is the
// recorded body, cancel interrupts a search cooperatively, progress is
// reported, and the typed RoutingRequest builds the oracle's query.

import 'dart:convert';

import 'package:brouter_dart/brouter_dart.dart';
import 'package:brouter_dart/isolate.dart';
import 'package:test/test.dart';

import 'corpus_support.dart';
import 'mapaccess_support.dart';

void main() {
  final skip = tilesMissing;
  final cases = loadCorpus();
  final pair = cases.firstWhere((c) => c.id == 'pair-000');
  // the longest recorded track: the slowest search of the corpus
  final long = () {
    CorpusCase? best;
    var bestBytes = 0;
    for (final c in cases) {
      final n = c.responseFile.lengthSync();
      if (n > bestBytes) {
        bestBytes = n;
        best = c;
      }
    }
    return best!;
  }();

  late RoutingWorker worker;

  setUpAll(() async {
    worker = await RoutingWorker.spawn(
      segmentsDir: segmentsDir,
      profilesDir: profilesDir,
      yieldInterval: 200,
    );
  });

  tearDownAll(() async {
    await worker.dispose();
  });

  test('routes a corpus case in the worker isolate, byte-identical', () async {
    final body = await worker.routeQuery(pair.query);
    expect(utf8.encode(body), pair.responseFile.readAsBytesSync());
  }, skip: skip);

  test('RoutingRequest.route parses the result', () async {
    final result = await worker.route(
      RoutingRequest(
        points: const [
          LonLat(-16.863901, 32.647377),
          LonLat(-16.887019, 32.651685),
        ],
        profile: 'trekking',
      ),
    );
    final expected = RoutingResult.parse(pair.responseFile.readAsStringSync());
    expect(result.geojson, pair.responseFile.readAsStringSync());
    expect(result.trackLength, expected.trackLength);
    expect(result.coordinates, expected.coordinates);
    expect(result.messages, expected.messages);
    expect(result.times, expected.times);
  }, skip: skip);

  test('reports progress and can be cancelled cooperatively', () async {
    var progress = 0;
    final future = worker.routeQuery(
      long.query,
      onProgress: (p) {
        progress++;
        if (progress == 3) worker.cancel();
      },
    );
    await expectLater(future, throwsA(isA<RoutingCancelledException>()));
    expect(progress, greaterThanOrEqualTo(3));
    // the worker is still usable afterwards
    final body = await worker.routeQuery(pair.query);
    expect(utf8.encode(body), pair.responseFile.readAsBytesSync());
  }, skip: skip);

  test('an error of the engine is a RoutingException', () async {
    // a point in the Atlantic: "from-position not mapped in existing datafile"
    await expectLater(
      worker.route(
        RoutingRequest(
          points: const [LonLat(-18.0, 32.0), LonLat(-16.887019, 32.651685)],
          profile: 'trekking',
        ),
      ),
      throwsA(isA<RoutingException>()),
    );
  }, skip: skip);

  test('toQuery reproduces the corpus queries', () {
    final rt = cases.firstWhere((c) => c.id == 'roundtrip-000');
    expect(
      RoutingRequest(
        points: const [LonLat(-16.9085, 32.6485)],
        profile: 'trekking',
        roundTrip: true,
        roundTripDistance: 1200,
        direction: 0,
        roundTripPoints: 5,
      ).toQuery(),
      'lonlats=-16.9085,32.6485&profile=trekking&alternativeidx=0&format=geojson&engineMode=4&roundTripDistance=1200&direction=0&roundTripPoints=5',
    );
    expect(rt.query, contains('engineMode=4'));
    final nogo = cases.firstWhere((c) => c.id == 'nogo-000');
    expect(
      RoutingRequest(
        points: const [
          LonLat(-16.839044, 32.655749),
          LonLat(-16.80416, 32.670006),
        ],
        profile: 'trekking',
        nogos: const [NogoCircle(LonLat(-16.821602, 32.662878), 120)],
      ).toQuery(),
      Uri.decodeComponent(nogo.query),
    );
  });
}

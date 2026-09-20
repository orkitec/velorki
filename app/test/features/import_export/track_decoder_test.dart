import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/import_export/data/track_decoder.dart';
import 'package:velorki/features/import_export/domain/imported_track.dart';
import 'package:velorki/features/planner/domain/route_poi.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_fit/velorki_fit.dart';
import 'package:velorki_geo/velorki_geo.dart';

import 'support/fixtures.dart';

void main() {
  group('a Ride with GPS route export', () {
    test('imports as a route from its cue-sheet points, named and with its '
        'waypoint', () {
      final track = decodeTrack(
        fixtureBytes('ridewithgps.gpx'),
        fileName: 'Isar nach Norden.gpx',
      );
      expect(track.format, ImportFormat.gpx);
      expect(track.points, hasLength(3));
      expect(track.name, 'Isar nach Norden');
      expect(track.creator, 'http://ridewithgps.com/');
      expect(track.pois, hasLength(1));
      expect(track.pois.single.name, 'Trinkwasser');
      expect(track.pois.single.kind, PoiKind.water);
      expect(track.suggestedKind, ImportKind.route);
    });

    test(
      'its cue sheet becomes turn instructions with the author\'s words',
      () {
        final track = decodeTrack(
          fixtureBytes('ridewithgps.gpx'),
          fileName: 'Isar nach Norden.gpx',
        );
        expect(track.turns.map((t) => t.kind), <TurnKind>[
          TurnKind.straight,
          TurnKind.left,
          TurnKind.end,
        ]);
        expect(track.turns.map((t) => t.pointIndex), <int>[0, 1, 2]);
        expect(track.turns[1].note, 'Turn left onto Widenmayerstraße');
        expect(track.turns[0].note, 'Start of route');
      },
    );

    test('a GPX track has no cue sheet, so it gets no turns', () {
      final track = decodeTrack(fixtureBytes('komoot.gpx'), fileName: 'k.gpx');
      expect(track.turns, isEmpty);
    });
  });

  group('sniffing decides the decoder, not the name', () {
    test('a GPX named .fit still decodes as GPX', () {
      final track = decodeTrack(fixtureBytes('komoot.gpx'), fileName: 'a.fit');
      expect(track.format, ImportFormat.gpx);
    });

    test('a FIT named .gpx still decodes as FIT', () {
      final track = decodeTrack(
        fixtureBytes('activity.fit'),
        fileName: 'a.gpx',
      );
      expect(track.format, ImportFormat.fit);
    });

    test('XML that is not GPX is refused', () {
      expect(
        () => decodeTrack(fixtureBytes('not_gpx.xml'), fileName: 'x.gpx'),
        throwsA(
          isA<ImportException>().having(
            (e) => e.failure,
            'failure',
            ImportFailure.unknownFormat,
          ),
        ),
      );
    });

    test('a damaged GPX is reported as malformed, not as unknown', () {
      // Real <gpx so the sniffer says yes, but the document never closes.
      final bytes = Uint8List.fromList(
        utf8.encode('<?xml version="1.0"?><gpx version="1.1"><trk><trkseg>'),
      );
      expect(
        () => decodeTrack(bytes, fileName: 'broken.gpx'),
        throwsA(
          isA<ImportException>().having(
            (e) => e.failure,
            'failure',
            ImportFailure.malformed,
          ),
        ),
      );
    });

    test('a GPX with no geometry is reported as empty', () {
      final bytes = Uint8List.fromList(
        utf8.encode(
          '<?xml version="1.0"?>'
          '<gpx version="1.1" creator="x"><metadata><name>n</name>'
          '</metadata></gpx>',
        ),
      );
      expect(
        () => decodeTrack(bytes, fileName: 'nothing.gpx'),
        throwsA(
          isA<ImportException>().having(
            (e) => e.failure,
            'failure',
            ImportFailure.empty,
          ),
        ),
      );
    });

    test('arbitrary bytes are refused', () {
      final bytes = Uint8List.fromList(List<int>.filled(64, 0x42));
      expect(
        () => decodeTrack(bytes, fileName: 'noise.bin'),
        throwsA(isA<ImportException>()),
      );
    });
  });

  group('GPX', () {
    test('a komoot track keeps its name, points and times', () {
      final track = decodeTrack(
        fixtureBytes('komoot.gpx'),
        fileName: 'komoot.gpx',
      );
      expect(track.format, ImportFormat.gpx);
      expect(track.name, 'Feierabendrunde am Ammersee');
      expect(track.creator, 'komoot.de');
      expect(track.pointCount, 3);
      expect(track.hasTimestamps, isTrue);
      expect(track.hasElevation, isTrue);
      expect(track.startTime, DateTime.utc(2024, 6, 12, 16, 4, 41));
      expect(track.endTime, DateTime.utc(2024, 6, 12, 16, 4, 51));
      expect(track.points.first.lat, closeTo(48.01429, 1e-9));
    });

    test('a route-only file reads its <rte> and its waypoints', () {
      final track = decodeTrack(
        fixtureBytes('route.gpx'),
        fileName: 'route.gpx',
      );
      expect(track.name, 'Starnberger See loop');
      expect(track.pointCount, 4);
      expect(track.hasTimestamps, isFalse);
      expect(track.pois.single.pos, const LatLng(47.998, 11.34));
    });
  });

  group('FIT', () {
    test('a Garmin activity decodes into timed points', () {
      final track = decodeTrack(
        fixtureBytes('activity.fit'),
        fileName: 'activity.fit',
      );
      expect(track.format, ImportFormat.fit);
      expect(track.pointCount, greaterThan(100));
      expect(track.hasTimestamps, isTrue);
      expect(track.bounds, isNotNull);
    });

    test('a FIT file with no records is reported as empty', () {
      // Our own encoder cannot produce one, so take a valid file and cut it
      // back to header plus CRC.
      final real = fixtureBytes('activity.fit');
      final headerSize = real[0];
      final stub = Uint8List(headerSize + 2)
        ..setRange(0, headerSize, real)
        ..[4] = 0
        ..[5] = 0
        ..[6] = 0
        ..[7] = 0;
      expect(looksLikeFit(stub), isTrue);
      expect(
        () => decodeTrack(stub, fileName: 'stub.fit'),
        throwsA(isA<ImportException>()),
      );
    });
  });

  group('ImportCandidate', () {
    test('timestamps make it a ride', () {
      final candidate = decodeCandidate(
        fixtureBytes('komoot.gpx'),
        fileName: 'komoot.gpx',
        sourceHint: 'share',
      );
      expect(candidate.suggested, ImportKind.ride);
      expect(candidate.sourceHint, 'share');
      expect(candidate.suggestedName, 'Feierabendrunde am Ammersee');
    });

    test('no timestamps make it a route', () {
      final candidate = decodeCandidate(
        fixtureBytes('route.gpx'),
        fileName: 'route.gpx',
      );
      expect(candidate.suggested, ImportKind.route);
    });

    test('a file without a metadata name falls back to the file name', () {
      final track = ImportedTrack(
        format: ImportFormat.fit,
        points: [TrackPoint(const LatLng(48, 11))],
      );
      expect(
        ImportCandidate.of(
          track,
          fileName: 'Ride 2026-09-12.fit',
        ).suggestedName,
        'Ride 2026-09-12',
      );
      expect(
        ImportCandidate.of(track, fileName: 'noextension').suggestedName,
        'noextension',
      );
      expect(
        ImportCandidate.of(track, fileName: '.fit').suggestedName,
        'Import',
      );
    });

    test('the suggestion follows the track, not the format', () {
      final timed = ImportedTrack(
        format: ImportFormat.gpx,
        points: [TrackPoint(const LatLng(48, 11), time: DateTime.utc(2026))],
      );
      expect(timed.suggestedKind, ImportKind.ride);
      final untimed = ImportedTrack(
        format: ImportFormat.fit,
        points: [TrackPoint(const LatLng(48, 11))],
      );
      expect(untimed.suggestedKind, ImportKind.route);
    });
  });

  test('every fixture file is really there', () {
    for (final name in const [
      'komoot.gpx',
      'strava.gpx',
      'route.gpx',
      'not_gpx.xml',
      'activity.fit',
    ]) {
      expect(File(fixturePath(name)).existsSync(), isTrue, reason: name);
    }
  });
}

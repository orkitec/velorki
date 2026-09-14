import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

Map<String, dynamic> loadFixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  late RouteResult result;

  setUpAll(() {
    result = RouteResult.fromGeoJson(loadFixture('route_trekking.geojson'));
  });

  group('geometry', () {
    test('every coordinate becomes a TrackPoint with elevation', () {
      expect(result.geometry, hasLength(11));
      expect(result.geometry.first.pos.lat, 48.137213);
      expect(result.geometry.first.pos.lon, 11.575612);
      expect(result.geometry.first.ele, 515);
      expect(result.geometry.last.ele, 505);
      expect(result.geometry.every((p) => p.ele != null), isTrue);
      expect(result.positions, hasLength(11));
    });

    test('the bounding box spans the route', () {
      final b = result.bounds!;
      expect(b.south, 48.136002);
      expect(b.north, 48.142744);
      expect(b.west, 11.575612);
      expect(b.east, 11.617833);
    });
  });

  group('properties', () {
    test('length, ascent and plain ascent come from the properties', () {
      expect(result.lengthM, 6000);
      expect(result.ascentM, 85);
      expect(result.plainAscentM, 62);
      expect(result.creator, 'BRouter-1.7.8');
      expect(result.name, 'brouter_trekking_0');
    });

    test('descent is derived from ascent and the net elevation change', () {
      // 515 m start, 505 m end -> net -10 m, so descent = 85 - (-10) = 95.
      expect(result.descentM, 95);
    });

    test('time, energy and the per-point times are kept', () {
      expect(result.totalTime, const Duration(seconds: 1301));
      expect(result.energyJ, 180000);
      expect(result.times, hasLength(11));
      expect(result.times.first, 0);
      expect(result.times.last, closeTo(1301, 0.01));
    });

    test('the whole document stays available as raw', () {
      expect(result.raw['type'], 'FeatureCollection');
    });
  });

  group('messages', () {
    test('the header row is consumed and every data row parsed', () {
      expect(result.messages, hasLength(6));
    });

    test('coordinates come back from microdegrees', () {
      final first = result.messages.first;
      expect(first.position.lon, closeTo(11.578901, 1e-9));
      expect(first.position.lat, closeTo(48.138440, 1e-9));
    });

    test('typed columns', () {
      final track = result.messages[2];
      expect(track.distanceM, 1500);
      expect(track.elevationM, 548);
      expect(track.costPerKm, 1900);
      expect(track.elevCost, 140);
      expect(track.turnCost, 0);
      expect(track.nodeCost, 0);
      expect(track.initialCost, 60);
      expect(track.timeS, 759);
      expect(track.energyJ, 105000);
    });

    test('way tags are split on space then =', () {
      expect(result.messages[2].wayTags, {
        'highway': 'track',
        'surface': 'gravel',
        'tracktype': 'grade3',
      });
      expect(result.messages[2].highway, 'track');
      expect(result.messages[2].surface, 'gravel');
      expect(result.messages[4].wayTags['maxspeed'], '70');
    });

    test('node tags are parsed and default to empty', () {
      expect(result.messages[3].nodeTags, {'barrier': 'gate'});
      expect(result.messages[0].nodeTags, isEmpty);
    });

    test('the raw row is keyed by header column', () {
      expect(
        result.messages[0].raw['WayTags'],
        'highway=cycleway surface=asphalt',
      );
    });
  });

  group('turn instructions', () {
    // The rows are what BRouter writes into `voicehints`, with the quirks of
    // the wire format: numbers may arrive as strings, the rows are not sorted
    // and an unknown command has to be dropped rather than guessed at.
    RouteResult parseWithHints(List<Object?> hints) =>
        RouteResult.fromGeoJson(<String, dynamic>{
          'type': 'FeatureCollection',
          'features': [
            {
              'type': 'Feature',
              'properties': <String, dynamic>{
                'track-length': '1234',
                'voicehints': hints,
              },
              'geometry': {
                'type': 'LineString',
                'coordinates': [
                  [11.0, 48.0],
                  [11.1, 48.1],
                  [11.2, 48.2],
                  [11.3, 48.3],
                  [11.4, 48.4],
                ],
              },
            },
          ],
        });

    late RouteResult hinted;

    setUpAll(() {
      hinted = parseWithHints(<Object?>[
        // out of order, so the parser has to sort them
        [4, 100, 0, 0.0, 0],
        ['2', '13', '2', '310.5', '-95'],
        [1, 5, 0, 120.25, 88],
        // command 42 is none of BRouter's, the row goes
        [3, 42, 0, 10.0, 0],
      ]);
    });

    test('rows become hints in point order', () {
      expect(hinted.turns.map((t) => t.pointIndex), [1, 2, 4]);
      expect(hinted.turns.map((t) => t.kind), [
        TurnKind.right,
        TurnKind.roundabout,
        TurnKind.end,
      ]);
    });

    test('strings are read as numbers', () {
      final roundabout = hinted.turns[1];
      expect(roundabout.exitNumber, 2);
      expect(roundabout.distanceToNextM, 310.5);
      expect(roundabout.angleDeg, -95);
    });

    test('the plain columns survive', () {
      final right = hinted.turns.first;
      expect(right.exitNumber, 0);
      expect(right.distanceToNextM, 120.25);
      expect(right.angleDeg, 88);
    });

    test('an unknown command is skipped, not guessed', () {
      expect(hinted.turns.any((t) => t.pointIndex == 3), isFalse);
    });

    test('rows that are not rows are ignored', () {
      final r = parseWithHints(<Object?>[
        'nonsense',
        42,
        <Object?>[1],
        [2, 5],
      ]);
      expect(r.turns, [const TurnHint(pointIndex: 2, kind: TurnKind.right)]);
    });

    test('a response without voicehints has no turns', () {
      expect(result.turns, isEmpty);
    });
  });

  group('surface stats', () {
    test('shares are relative to the track length', () {
      final s = result.surfaceStats;
      // 1200 cycleway/asphalt + 800 residential/paving_stones
      //   + 900 primary/asphalt = 2900 of 6000
      expect(s.pavedShare, closeTo(2900 / 6000, 1e-12));
      // 1500 track/gravel + 600 path (no surface tag) = 2100
      expect(s.unpavedShare, closeTo(2100 / 6000, 1e-12));
      // 1000 tertiary with an empty surface value
      expect(s.unknownShare, closeTo(1000 / 6000, 1e-12));
      // highway=cycleway 1200 + cycleway=lane 1000
      expect(s.cyclewayShare, closeTo(2200 / 6000, 1e-12));
      expect(s.busyShare, closeTo(900 / 6000, 1e-12));
      expect(s.coveredLengthM, 6000);
      expect(s.totalLengthM, 6000);
    });

    test('the surface shares add up to one when the messages cover it all', () {
      final s = result.surfaceStats;
      expect(s.pavedShare + s.unpavedShare + s.unknownShare, closeTo(1, 1e-12));
    });

    test('toString is readable', () {
      expect(result.surfaceStats.toString(), contains('paved: 48.3%'));
    });
  });

  group('malformed documents', () {
    test('not a FeatureCollection', () {
      expect(
        () => RouteResult.fromGeoJson({'type': 'Feature'}),
        throwsA(
          isA<RoutingException>().having(
            (e) => e.kind,
            'kind',
            RoutingErrorKind.invalid,
          ),
        ),
      );
    });

    test('no LineString feature', () {
      expect(
        () => RouteResult.fromGeoJson({
          'type': 'FeatureCollection',
          'features': [
            {
              'type': 'Feature',
              'geometry': {
                'type': 'Point',
                'coordinates': <double>[1, 2],
              },
            },
          ],
        }),
        throwsA(isA<RoutingException>()),
      );
    });

    test('a malformed coordinate', () {
      expect(
        () => RouteResult.fromGeoJson({
          'type': 'FeatureCollection',
          'features': [
            {
              'type': 'Feature',
              'properties': <String, dynamic>{},
              'geometry': {
                'type': 'LineString',
                'coordinates': [
                  [11.0],
                ],
              },
            },
          ],
        }),
        throwsA(isA<RoutingException>()),
      );
    });

    test('a messages table without a header row', () {
      expect(
        () => RouteResult.fromGeoJson({
          'type': 'FeatureCollection',
          'features': [
            {
              'type': 'Feature',
              'properties': {
                'messages': [
                  ['1', '2', '3'],
                ],
              },
              'geometry': {
                'type': 'LineString',
                'coordinates': [
                  [11.0, 48.0],
                  [11.1, 48.1],
                ],
              },
            },
          ],
        }),
        throwsA(
          isA<RoutingException>().having(
            (e) => e.message,
            'message',
            contains('messages table'),
          ),
        ),
      );
    });

    test('a LineString feature after other features is still found', () {
      final r = RouteResult.fromGeoJson({
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'geometry': {
              'type': 'Point',
              'coordinates': <double>[11, 48],
            },
          },
          {
            'type': 'Feature',
            'properties': {'track-length': '1234'},
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                [11.0, 48.0],
                [11.1, 48.1],
              ],
            },
          },
        ],
      });
      expect(r.lengthM, 1234);
      expect(r.geometry, hasLength(2));
      expect(r.geometry.first.ele, isNull);
      expect(r.descentM, 0);
      expect(r.messages, isEmpty);
      expect(r.surfaceStats, SurfaceStats.empty);
      expect(r.totalTime, isNull);
      expect(r.toString(), contains('1.23 km'));
    });
  });
}

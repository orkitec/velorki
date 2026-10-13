import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/geo/track_turns.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

import '../../features/navigation/support/fake_turns.dart';

List<LatLng> _line(List<TrackPoint> points) => [for (final p in points) p.pos];

/// Every [every]th point of [line] and its last, as a router's coarser way
/// over the same streets.
List<LatLng> _coarse(List<LatLng> line, int every) => [
  for (var i = 0; i < line.length; i += every) line[i],
  if ((line.length - 1) % every != 0) line.last,
];

void main() {
  group('mapRoutedTurns', () {
    test('puts a turn of the router on the track point at that corner, '
        'though the router has fewer points', () {
      final track = _line(leggedTrack());
      final along = cumulativeDistancesMeters(track);
      // The router's way: every fifth point, the corner (index 30) among them.
      final matched = _coarse(track, 5);
      final corner = matched.indexOf(track[30]);

      final turns = mapRoutedTurns(
        track: track,
        trackAlong: along,
        matched: matched,
        turns: <TurnHint>[
          TurnHint(
            pointIndex: corner,
            kind: TurnKind.right,
            angleDeg: 90,
            note: 'Main Street',
          ),
          TurnHint(pointIndex: matched.length - 1, kind: TurnKind.end),
        ],
      );

      expect(turns, hasLength(1));
      expect(turns.single.pointIndex, 30);
      expect(turns.single.kind, TurnKind.right);
      expect(turns.single.note, 'Main Street', reason: 'the words are kept');
    });

    test('drops the turns where the router left the track: a detour round '
        'a stretch the map has no way for', () {
      // Due north for 1.2 km; the router goes round its middle 400 m on a
      // street 150 m to the east.
      final track = _line(leggedTrack(legs: 1, legM: 1200));
      final along = cumulativeDistancesMeters(track);
      final a = track[20]; // 400 m
      final b = track[40]; // 800 m
      final matched = <LatLng>[
        track.first,
        a,
        destinationPoint(a, 90, 150),
        destinationPoint(b, 90, 150),
        b,
        track.last,
      ];

      final turns = mapRoutedTurns(
        track: track,
        trackAlong: along,
        matched: matched,
        turns: const <TurnHint>[
          TurnHint(pointIndex: 1, kind: TurnKind.right, angleDeg: 90),
          TurnHint(pointIndex: 2, kind: TurnKind.left, angleDeg: -90),
          TurnHint(pointIndex: 3, kind: TurnKind.left, angleDeg: -90),
          TurnHint(pointIndex: 4, kind: TurnKind.right, angleDeg: 90),
        ],
      );

      expect(turns, isEmpty);
    });

    test('drops a turn the track does not make: the router went into a '
        'side street and out again to reach a waypoint', () {
      final track = _line(leggedTrack(legs: 1, legM: 1000));
      final along = cumulativeDistancesMeters(track);
      final mid = track[25];
      // A spur of 20 m to the east and back: within the tolerance, but the
      // track goes straight on there.
      final spur = destinationPoint(mid, 90, 20);
      final matched = <LatLng>[track.first, mid, spur, mid, track.last];

      final turns = mapRoutedTurns(
        track: track,
        trackAlong: along,
        matched: matched,
        turns: const <TurnHint>[
          TurnHint(pointIndex: 1, kind: TurnKind.right, angleDeg: 90),
          TurnHint(pointIndex: 2, kind: TurnKind.uTurn, angleDeg: 180),
          TurnHint(pointIndex: 3, kind: TurnKind.right, angleDeg: 90),
        ],
      );

      expect(turns, isEmpty);
    });

    test('a U-turn where the track bends is the sharp turn it makes; where '
        'the track goes back the way it came, it stays a U-turn', () {
      // A hairpin: north 300 m, then back south-east, the two arms apart.
      final hairpin = _line(leggedTrack(legs: 2, legM: 300, turnDeg: 135));
      final turns = mapRoutedTurns(
        track: hairpin,
        trackAlong: cumulativeDistancesMeters(hairpin),
        matched: hairpin,
        turns: const <TurnHint>[
          TurnHint(pointIndex: 15, kind: TurnKind.uTurnLeft, angleDeg: -180),
        ],
      );
      expect(turns.single.kind, TurnKind.sharpRight);
      expect(turns.single.angleDeg, closeTo(135, 5));

      final back = _line(leggedTrack(legs: 2, legM: 300, turnDeg: 180));
      final turned = mapRoutedTurns(
        track: back,
        trackAlong: cumulativeDistancesMeters(back),
        matched: back,
        turns: const <TurnHint>[
          TurnHint(pointIndex: 15, kind: TurnKind.uTurn, angleDeg: 180),
        ],
      );
      expect(turned.single.kind, TurnKind.uTurn);
      expect(turned.single.pointIndex, 15);
    });

    test('on a track that passes a junction twice, the turn goes to the '
        'pass it was made on', () {
      // North 400 m to a junction, on 200 m and back to it, then east.
      final start = const LatLng(48, 11);
      final out = leggedTrack(legs: 1, legM: 600, start: start);
      final junction = out[20].pos;
      final line = <LatLng>[
        ..._line(out),
        // Back south to the junction, the same points the other way.
        for (var i = 29; i >= 20; i--) out[i].pos,
        // East from it.
        for (var m = 20.0; m <= 400; m += 20) destinationPoint(junction, 90, m),
      ];
      final firstPass = 20;
      final secondPass = line.lastIndexOf(junction);
      expect(secondPass, greaterThan(firstPass));

      final turns = mapRoutedTurns(
        track: line,
        trackAlong: cumulativeDistancesMeters(line),
        matched: line,
        turns: <TurnHint>[
          // Heading south at the junction, east is to the left.
          TurnHint(pointIndex: secondPass, kind: TurnKind.left, angleDeg: -90),
        ],
      );

      expect(turns.single.pointIndex, secondPass);
    });

    test('keeps only the turns the chunk owns', () {
      final track = _line(leggedTrack(legs: 3, legM: 400));
      final along = cumulativeDistancesMeters(track);
      final turns = <TurnHint>[
        const TurnHint(pointIndex: 20, kind: TurnKind.right, angleDeg: 90),
        const TurnHint(pointIndex: 40, kind: TurnKind.right, angleDeg: 90),
      ];
      List<int> owned(int from, int to) => [
        for (final t in mapRoutedTurns(
          track: track,
          trackAlong: along,
          matched: track,
          turns: turns,
          ownFrom: from,
          ownTo: to,
        ))
          t.pointIndex,
      ];

      expect(owned(0, 30), [20]);
      expect(owned(30, 61), [40]);
      expect(owned(0, 61), [20, 40]);
    });
  });

  group('finishTurns', () {
    test('sorts, keeps one turn per point, none on the ends, measures to the '
        'next and ends with the finish', () {
      final line = _line(leggedTrack(legs: 1, legM: 200, stepM: 20));
      final along = cumulativeDistancesMeters(line);
      final turns = finishTurns(const <TurnHint>[
        TurnHint(pointIndex: 6, kind: TurnKind.left),
        TurnHint(pointIndex: 0, kind: TurnKind.right),
        TurnHint(pointIndex: 3, kind: TurnKind.right),
        TurnHint(pointIndex: 6, kind: TurnKind.right),
        TurnHint(pointIndex: 10, kind: TurnKind.right),
      ], along);

      expect(turns.map((t) => t.pointIndex), [3, 6, 10]);
      expect(turns.map((t) => t.kind), [
        TurnKind.right,
        TurnKind.left,
        TurnKind.end,
      ]);
      expect(turns.first.distanceToNextM, closeTo(60, 0.5));
      expect(turns[1].distanceToNextM, closeTo(80, 0.5));
    });
  });

  group('trackChunks', () {
    test('overlap by the waypoints asked for and cover every one', () {
      expect(trackChunks(12, 5, 2), [(0, 4), (2, 6), (4, 8), (6, 10), (8, 11)]);
      expect(trackChunks(3, 5, 2), [(0, 2)]);
      expect(trackChunks(1, 5, 2), isEmpty);
    });
  });

  group('TrackTurnService.generate', () {
    test('every corner of a zigzag gets exactly one turn, wherever the '
        'chunks meet', () async {
      // Ten legs of 300 m, turning right and left by turns: nine corners.
      final points = <TrackPoint>[];
      var here = const LatLng(48, 11);
      points.add(TrackPoint(here));
      final corners = <int>[];
      for (var leg = 0; leg < 10; leg++) {
        final heading = leg.isEven ? 30.0 : 330.0;
        for (var m = 20; m <= 300; m += 20) {
          here = destinationPoint(here, heading, 20);
          points.add(TrackPoint(here));
        }
        if (leg < 9) corners.add(points.length - 1);
      }
      for (final size in <int>[5, 6, 7, 50]) {
        final backend = TrackFollowingBackend();
        final service = fakeTurnService(backend, maxPointsPerQuery: size);

        final result = await service.generate(points: points);

        expect(result.state, TrackTurnsState.generated);
        final made = result.turns.where((t) => t.kind != TurnKind.end);
        expect(made.map((t) => t.pointIndex), corners, reason: 'chunks $size');
        expect(made.map((t) => t.kind), [
          for (var i = 0; i < corners.length; i++)
            i.isEven ? TurnKind.left : TurnKind.right,
        ], reason: 'chunks $size');
        if (size < 50) expect(backend.queries.length, greaterThan(1));
        expect(result.turns.last.kind, TurnKind.end);
        expect(result.turns.last.pointIndex, points.length - 1);
      }
    });

    test('a stretch the router cannot follow has no turns; the rest has '
        'theirs', () async {
      final points = leggedTrack(legs: 6, legM: 300);
      final backend = TrackFollowingBackend();
      final all = await fakeTurnService(
        backend,
        maxPointsPerQuery: 5,
      ).generate(points: points);
      final full = all.turns.where((t) => t.kind != TurnKind.end).toList();
      expect(full, hasLength(5));

      // The chunks through the third corner fail.
      final failing = TrackFollowingBackend()..failAt.add(points[90].pos);
      final some = await fakeTurnService(
        failing,
        maxPointsPerQuery: 5,
      ).generate(points: points);

      expect(some.state, TrackTurnsState.generated);
      final kept = some.turns.where((t) => t.kind != TurnKind.end).toList();
      expect(kept, isNotEmpty);
      expect(kept.length, lessThan(full.length));
      expect(kept.map((t) => t.pointIndex), isNot(contains(90)));
      for (final t in kept) {
        expect(full.map((f) => f.pointIndex), contains(t.pointIndex));
      }
    });

    test('says why there are none: no routing, no tiles, or no way at '
        'all', () async {
      final points = leggedTrack();
      final none = await TrackTurnService(
        local: null,
        decide: (_) => throw StateError('not asked'),
      ).generate(points: points);
      expect(none.state, TrackTurnsState.noRouting);

      const tile = TileName(10, 45);
      final missing = await fakeTurnService(
        TrackFollowingBackend(),
        missing: () => const <TileName>[tile],
      ).generate(points: points);
      expect(missing.state, TrackTurnsState.noTiles);
      expect(missing.missingTiles, [tile]);

      final lost = TrackFollowingBackend()..failAt.add(points.first.pos);
      final unmatched = await fakeTurnService(lost).generate(points: points);
      expect(unmatched.state, TrackTurnsState.unmatched);
    });

    test('reports its progress chunk by chunk', () async {
      final seen = <(int, int)>[];
      await fakeTurnService(
        TrackFollowingBackend(),
        maxPointsPerQuery: 5,
      ).generate(
        points: leggedTrack(legs: 4, legM: 300),
        onProgress: (done, total) => seen.add((done, total)),
      );
      expect(seen.first.$1, 0);
      expect(seen.last.$1, seen.last.$2);
      expect(seen.length, seen.last.$2 + 1);
    });
  });
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/geo/ride_stats.dart';
import 'package:velorki/features/recording/domain/ride.dart';
import 'package:velorki/features/recording/domain/ride_upload.dart';
import 'package:velorki_geo/velorki_geo.dart';

final DateTime _start = DateTime.utc(2026, 9, 12, 10);

List<TrackPoint> _track(int count) => <TrackPoint>[
  for (var i = 0; i < count; i++)
    TrackPoint(
      LatLng(48 + i * 0.001, 11 + i * 0.002),
      ele: 500 + i.toDouble(),
      time: _start.add(Duration(seconds: i * 10)),
    ),
];

Ride _ride({
  Uint8List? geometry,
  List<RidePause> pauses = const <RidePause>[],
  Map<String, RideUpload> uploads = const <String, RideUpload>{},
  String? notes = 'felt good',
  String? routeId = 'route-3',
}) => Ride(
  id: 'ride-1',
  name: 'Morning loop',
  startedAt: _start,
  endedAt: _start.add(const Duration(minutes: 30)),
  stats: const RideStats(distanceM: 12345.6, pointCount: 5),
  geometry: geometry ?? PackedTrack.encode(_track(5)),
  routeId: routeId,
  pauses: pauses,
  uploads: uploads,
  notes: notes,
);

void main() {
  group('RidePause', () {
    test('a pause that is still open has no length yet', () {
      expect(RidePause(startedAt: _start).duration, Duration.zero);
      expect(RidePause(startedAt: _start).endedAt, isNull);
    });

    test('a closed pause lasts from its start to its end', () {
      final pause = RidePause(
        startedAt: _start,
        endedAt: _start.add(const Duration(minutes: 4, seconds: 30)),
      );

      expect(pause.duration, const Duration(minutes: 4, seconds: 30));
    });

    test('ending an open pause keeps the start it had', () {
      final open = RidePause(startedAt: _start);

      final closed = open.ending(_start.add(const Duration(minutes: 2)));

      expect(closed.startedAt, _start);
      expect(closed.duration, const Duration(minutes: 2));
      // The original is left alone.
      expect(open.endedAt, isNull);
    });

    test('a closed pause survives the pauses column', () {
      final pause = RidePause(
        startedAt: _start,
        endedAt: _start.add(const Duration(minutes: 2)),
      );

      expect(RidePause.fromJson(pause.toJson()), pause);
    });

    test('an open pause is written without an end', () {
      final json = RidePause(startedAt: _start).toJson();

      expect(json.containsKey('end'), isFalse);
      expect(RidePause.fromJson(json).endedAt, isNull);
    });

    test('times are written and read back as UTC', () {
      final pause = RidePause(startedAt: _start.toLocal());

      expect(pause.toJson()['start'], '2026-09-12T10:00:00.000Z');
      expect(RidePause.fromJson(pause.toJson()).startedAt.isUtc, isTrue);
    });

    test('a pause without a readable start is read as the epoch', () {
      // A ride that opens is worth more than a pause that is exact.
      final pause = RidePause.fromJson(const <String, Object?>{
        'start': 'yesterday',
      });

      expect(
        pause.startedAt,
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
      expect(pause.endedAt, isNull);
    });

    test('two pauses over the same interval are the same pause', () {
      final end = _start.add(const Duration(minutes: 2));
      final pause = RidePause(startedAt: _start, endedAt: end);
      final same = RidePause(startedAt: _start, endedAt: end);

      expect(pause, same);
      expect(pause.hashCode, same.hashCode);
      expect(pause, isNot(RidePause(startedAt: _start)));
    });

    test('toString names both ends of the pause', () {
      expect(
        RidePause(startedAt: _start).toString(),
        'RidePause(2026-09-12 10:00:00.000Z → null)',
      );
    });
  });

  group('encodeRidePauses / decodeRidePauses', () {
    test('a list of pauses survives the column', () {
      final pauses = <RidePause>[
        RidePause(
          startedAt: _start,
          endedAt: _start.add(const Duration(minutes: 2)),
        ),
        RidePause(startedAt: _start.add(const Duration(minutes: 10))),
      ];

      expect(decodeRidePauses(encodeRidePauses(pauses)), pauses);
    });

    test('an empty list is written as an empty array', () {
      expect(encodeRidePauses(const <RidePause>[]), '[]');
      expect(decodeRidePauses('[]'), isEmpty);
    });

    test('a ride with no pauses column has no pauses', () {
      expect(decodeRidePauses(null), isEmpty);
      expect(decodeRidePauses(''), isEmpty);
    });

    test('an unreadable column yields no pauses rather than an error', () {
      // Better a ride that opens without its pauses than one that cannot be
      // opened at all.
      expect(decodeRidePauses('not json'), isEmpty);
      expect(
        decodeRidePauses('{"start": "2026-09-12T10:00:00.000Z"}'),
        isEmpty,
      );
    });

    test('entries that are not pauses are skipped', () {
      final decoded = decodeRidePauses(
        jsonEncode(<Object?>[
          42,
          <String, Object?>{'start': '2026-09-12T10:00:00.000Z'},
        ]),
      );

      expect(decoded, hasLength(1));
      expect(decoded.single.startedAt, _start);
    });
  });

  group('Ride', () {
    test('reads its track back out of the packed geometry', () {
      final ride = _ride();

      expect(ride.points, hasLength(5));
      expect(ride.points.first.pos, const LatLng(48.0, 11.0));
      expect(ride.points.first.time, _start);
      expect(ride.points.last.ele, 504);
    });

    test('decodes the geometry once and keeps the points', () {
      final ride = _ride();

      expect(identical(ride.points, ride.points), isTrue);
    });

    test('the positions are the track without its measurements', () {
      final ride = _ride();

      expect(ride.positions, hasLength(5));
      expect(ride.positions.first, const LatLng(48.0, 11.0));
      expect(ride.positions.last, const LatLng(48.004, 11.008));
    });

    test('the bounds cover the whole track', () {
      final bounds = _ride().bounds;

      expect(bounds, isNotNull);
      expect(bounds!.south, 48.0);
      expect(bounds.north, 48.004);
      expect(bounds.west, 11.0);
      expect(bounds.east, 11.008);
    });

    test('a ride without geometry has no points and no bounds', () {
      final ride = _ride(geometry: Uint8List(0));

      expect(ride.points, isEmpty);
      expect(ride.positions, isEmpty);
      expect(ride.bounds, isNull);
    });

    test('a geometry from another format yields no points', () {
      // An unreadable blob must not make the rides list throw.
      final ride = _ride(geometry: Uint8List.fromList(<int>[99, 0, 0, 0]));

      expect(ride.points, isEmpty);
      expect(ride.bounds, isNull);
    });

    test('a geometry cut short mid-record keeps the whole points', () {
      final full = PackedTrack.encode(_track(3));
      final truncated = Uint8List.sublistView(
        full,
        0,
        PackedTrack.headerLength + 2 * PackedTrack.bytesPerPoint + 10,
      );

      expect(_ride(geometry: truncated).points, hasLength(2));
    });

    test('an upload is found by the service that made it', () {
      final upload = RideUpload(
        status: RideUploadStatus.done,
        uploadedAt: _start,
        activityId: '77',
      );
      final ride = _ride(uploads: <String, RideUpload>{'strava': upload});

      expect(ride.uploadFor('strava'), upload);
      expect(ride.uploadFor('rwgps'), isNull);
    });

    test('copyWith replaces only the name it is given', () {
      final ride = _ride();

      final renamed = ride.copyWith(name: 'Evening loop');

      expect(renamed.name, 'Evening loop');
      expect(renamed.id, ride.id);
      expect(renamed.startedAt, ride.startedAt);
      expect(renamed.endedAt, ride.endedAt);
      expect(renamed.stats, ride.stats);
      expect(renamed.geometry, same(ride.geometry));
      expect(renamed.routeId, ride.routeId);
      expect(renamed.notes, ride.notes);
      expect(renamed.uploads, ride.uploads);
    });

    test('copyWith adds the uploads without touching the notes', () {
      final ride = _ride();
      final upload = RideUpload(
        status: RideUploadStatus.done,
        uploadedAt: _start,
        activityId: '77',
      );

      final uploaded = ride.copyWith(
        uploads: <String, RideUpload>{'strava': upload},
      );

      expect(uploaded.uploadFor('strava'), upload);
      expect(uploaded.notes, 'felt good');
      expect(uploaded.name, 'Morning loop');
    });

    test('copyWith with nothing to replace keeps every field', () {
      final ride = _ride(pauses: <RidePause>[RidePause(startedAt: _start)]);

      final copy = ride.copyWith();

      expect(copy.name, ride.name);
      expect(copy.notes, ride.notes);
      expect(copy.pauses, ride.pauses);
      expect(copy.routeId, ride.routeId);
    });

    test('copyWith cannot clear the notes, only overwrite them', () {
      final ride = _ride();

      // Passing null means "leave it alone"; an empty string clears it.
      expect(ride.copyWith(notes: null).notes, 'felt good');
      expect(ride.copyWith(notes: '').notes, '');
    });

    test('a ride that followed no route and kept no notes says so', () {
      final ride = _ride(routeId: null, notes: null);

      expect(ride.routeId, isNull);
      expect(ride.notes, isNull);
      expect(ride.pauses, isEmpty);
      expect(ride.uploads, isEmpty);
    });

    test('toString names the ride and its statistics', () {
      expect(
        _ride().toString(),
        'Ride(ride-1, Morning loop, ${_ride().stats})',
      );
    });
  });
}

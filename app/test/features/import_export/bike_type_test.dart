import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/files/bike_type.dart';
import 'package:velorki/core/files/track_exporter.dart';
import 'package:velorki/core/files/track_exporter_impl.dart';
import 'package:velorki/features/import_export/data/track_decoder.dart';
import 'package:velorki/features/planner/domain/route_profile.dart';
import 'package:velorki_fit/velorki_fit.dart';
import 'package:velorki_geo/velorki_geo.dart';
import 'package:velorki_gpx/velorki_gpx.dart';

final List<TrackPoint> _points = <TrackPoint>[
  for (var i = 0; i < 4; i++)
    TrackPoint(LatLng(48.0 + i * 0.001, 11.0 + i * 0.001), ele: 500),
];

void main() {
  group('a GPX <type>', () {
    test('names a bike by its words, whatever the case', () {
      for (final type in [
        'road',
        'Road_Biking',
        'roadbike',
        'Racing',
        'Rennrad',
      ]) {
        expect(profileFromGpxType(type), RouteProfile.fastbike, reason: type);
      }
      for (final type in [
        'mountain',
        'mountain_biking',
        'MTB',
        'enduro',
        'Downhill',
      ]) {
        expect(profileFromGpxType(type), RouteProfile.mtb, reason: type);
      }
      for (final type in ['gravel', 'gravel_cycling', 'Cyclocross']) {
        expect(profileFromGpxType(type), RouteProfile.gravel, reason: type);
      }
      for (final type in ['touring', 'Trekking', 'bikepacking']) {
        expect(profileFromGpxType(type), RouteProfile.trekking, reason: type);
      }
    });

    test('that is generic, a number or missing names none', () {
      for (final type in [null, '', 'cycling', 'biking', 'Biking', '1', '9']) {
        expect(profileFromGpxType(type), isNull, reason: '$type');
      }
    });

    test('is written for every bike, and read back as the same one', () {
      expect(gpxTypeOf(RouteProfile.fastbike), 'road_biking');
      expect(gpxTypeOf(RouteProfile.mtb), 'mountain_biking');
      expect(gpxTypeOf(RouteProfile.gravel), 'gravel_cycling');
      expect(gpxTypeOf(RouteProfile.trekking), 'touring');
      expect(gpxTypeOf(RouteProfile.shortest), 'cycling');
      for (final profile in [
        RouteProfile.fastbike,
        RouteProfile.mtb,
        RouteProfile.gravel,
        RouteProfile.trekking,
      ]) {
        expect(profileFromGpxType(gpxTypeOf(profile)), profile);
      }
    });

    test('of a route is read as well as that of a track', () {
      final track = decodeTrack(
        Uint8List.fromList(
          utf8.encode(
            GpxCodec.encodeTrack(points: _points, type: 'mountain_biking'),
          ),
        ),
        fileName: 't.gpx',
      );
      expect(track.profile, RouteProfile.mtb);
      final route = decodeTrack(
        Uint8List.fromList(
          utf8.encode(GpxCodec.encodeRoute(points: _points, type: 'Rennrad')),
        ),
        fileName: 'r.gpx',
      );
      expect(route.profile, RouteProfile.fastbike);
    });
  });

  group('a FIT file', () {
    test('names a bike by its sub-sport', () {
      expect(
        profileFromFit(FitSport.cycling, FitSubSport.road),
        RouteProfile.fastbike,
      );
      expect(
        profileFromFit(FitSport.cycling, FitSubSport.mountain),
        RouteProfile.mtb,
      );
      expect(
        profileFromFit(FitSport.eBiking, FitSubSport.eBikeMountain),
        RouteProfile.mtb,
      );
      expect(
        profileFromFit(FitSport.cycling, FitSubSport.gravelCycling),
        RouteProfile.gravel,
      );
      expect(
        profileFromFit(FitSport.cycling, FitSubSport.cyclocross),
        RouteProfile.gravel,
      );
      for (final sub in [
        null,
        FitSubSport.generic,
        FitSubSport.commuting,
        FitSubSport.eBikeFitness,
      ]) {
        expect(profileFromFit(FitSport.cycling, sub), isNull, reason: '$sub');
      }
      expect(profileFromFit(FitSport.running, FitSubSport.road), isNull);
    });

    test('is written with the sub-sport of the bike', () {
      expect(fitSubSportOf(RouteProfile.fastbike), FitSubSport.road);
      expect(fitSubSportOf(RouteProfile.mtb), FitSubSport.mountain);
      expect(fitSubSportOf(RouteProfile.gravel), FitSubSport.gravelCycling);
      expect(fitSubSportOf(RouteProfile.trekking), FitSubSport.generic);
      expect(fitSubSportOf(RouteProfile.shortest), FitSubSport.generic);
    });

    test('an activity names its bike from the session', () {
      final track = decodeTrack(
        FitCodec.encodeActivity(
          [
            for (var i = 0; i < _points.length; i++)
              TrackPoint(_points[i].pos, time: DateTime.utc(2026, 9, 24, 8, i)),
          ],
          name: 'Ride',
          subSport: FitSubSport.gravelCycling,
        ),
        fileName: 'a.fit',
      );
      expect(track.profile, RouteProfile.gravel);
    });
  });

  group('a route exported and imported again', () {
    late Directory temp;
    late ShareTrackExporter exporter;
    setUp(() {
      temp = Directory.systemTemp.createTempSync('velorki_bike_type');
      exporter = ShareTrackExporter(
        temporaryDirectory: () async => temp,
        shareFiles: (file, {required String mimeType}) async {},
      );
    });
    tearDown(() => temp.deleteSync(recursive: true));

    for (final format in [TrackFormat.gpx, TrackFormat.fit]) {
      test('keeps its bike, as ${format.name}', () async {
        for (final profile in [
          RouteProfile.fastbike,
          RouteProfile.mtb,
          RouteProfile.gravel,
        ]) {
          final file = await exporter.write(
            name: 'Ride',
            points: _points,
            kind: TrackKind.route,
            format: format,
            profile: profile,
          );
          final track = decodeTrack(
            file.readAsBytesSync(),
            fileName: file.path,
          );
          expect(track.profile, profile, reason: '${format.name} $profile');
        }
      });
    }

    test('without a bike goes out as a plain ride and names none', () async {
      final file = await exporter.write(
        name: 'Ride',
        points: _points,
        kind: TrackKind.route,
        format: TrackFormat.gpx,
        profile: RouteProfile.shortest,
      );
      final track = decodeTrack(file.readAsBytesSync(), fileName: file.path);
      expect(track.profile, isNull);
    });
  });
}

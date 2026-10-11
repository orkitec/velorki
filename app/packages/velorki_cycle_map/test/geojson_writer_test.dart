import 'dart:convert';

import 'package:test/test.dart';
import 'package:velorki_cycle_map/velorki_cycle_map.dart';

/// BRouter's integers for [lon], [lat].
List<int> at(double lon, double lat) => [
  ((lon + 180) * 1e6).round(),
  ((lat + 90) * 1e6).round(),
];

Map<String, dynamic> decode(String pieces) =>
    jsonDecode(GeoJsonWriter.collection([pieces])) as Map<String, dynamic>;

void main() {
  final cycleway = CycleBits.pack(kind: CycleKind.cycleway);
  final laneRoute = CycleBits.pack(
    lane: Side.right,
    contraflow: true,
    routes: CycleBits.routeNational | CycleBits.routeLocal,
  );
  final gravel = CycleBits.pack(unpaved: true, rough: true, mtbScale: 2);

  CellWays sample() {
    final b = CellWaysBuilder()
      ..addLine([...at(-16.9, 32.65), ...at(-16.89, 32.651)], cycleway)
      ..addLine([...at(-16.9, 32.6), ...at(-16.8999, 32.6)], laneRoute)
      ..addLine([...at(-16.9, 32.7), ...at(-16.8, 32.7)], gravel)
      ..addBarrier(
        at(-16.9, 32.65)[0],
        at(-16.9, 32.65)[1],
        BarrierClass.carry,
      );
    return b.build();
  }

  test('writes lines and barriers as valid GeoJSON with short properties', () {
    final json = decode(
      GeoJsonWriter().cellFeatures(sample(), CycleContent.all, 16),
    );
    final features = json['features'] as List;
    expect(features, hasLength(4));
    final first = features[0] as Map;
    expect(first['properties'], {'k': 1, 't': 0, 'l': 0});
    expect(first['geometry'], {
      'type': 'LineString',
      'coordinates': [
        [-16.9, 32.65],
        [-16.89, 32.651],
      ],
    });
    expect((features[1] as Map)['properties'], {
      'k': 0,
      't': 0,
      'l': Side.right,
      'rc': RoadClass.minor,
      'cf': 1,
      'nn': 1,
      'nl': 1,
    });
    expect((features[2] as Map)['properties'], {
      'k': 0,
      't': 0,
      'l': 0,
      'u': 1,
      'r': 1,
      'm': 2,
    });
    expect(features[3], {
      'type': 'Feature',
      'properties': {'b': BarrierClass.carry},
      'geometry': {
        'type': 'Point',
        'coordinates': [-16.9, 32.65],
      },
    });
  });

  test('leaves out what is not wanted', () {
    final writer = GeoJsonWriter();
    final infra = decode(
      writer.cellFeatures(sample(), CycleContent.infrastructure, 16),
    );
    expect(infra['features'], hasLength(2)); // the cycleway and the lane
    final surface = decode(
      writer.cellFeatures(sample(), CycleContent.surface, 16),
    );
    expect(surface['features'], hasLength(1));
    expect(writer.cellFeatures(sample(), CycleContent.paths, 16), isEmpty);
  });

  test('rounds to five decimals, either side of zero', () {
    final b = CellWaysBuilder()
      ..addLine([
        ...[180000000 - 1234567, 90000000 + 5],
        ...[180000000 + 4, 90000000 - 15],
      ], cycleway);
    final json = decode(GeoJsonWriter().cellFeatures(b.build(), -1, 16));
    final coords =
        ((json['features'] as List)[0] as Map)['geometry']['coordinates'];
    expect(coords, [
      [-1.23457, 0.00001],
      [0, -0.00002],
    ]);
  });

  test('an empty collection', () {
    expect(jsonDecode(GeoJsonWriter.collection(['', ''])), {
      'type': 'FeatureCollection',
      'features': <Object>[],
    });
  });

  test('the new properties and steep pieces', () {
    final b = CellWaysBuilder()
      ..addLine(
        [...at(-16.9, 32.6), ...at(-16.89, 32.6)],
        CycleBits.pack(
          kind: CycleKind.cycleway,
          oneway: Direction.backward,
          mtbRoute: true,
          unpaved: true,
          rugged: true,
          traffic: TrafficClass.limit30,
        ),
      )
      ..addLine(
        [...at(-16.9, 32.61), ...at(-16.89, 32.61)],
        CycleBits.pack(
          sharedLane: Side.left,
          leftDirection: Direction.forward,
          rightDirection: Direction.both,
          lane: Side.right,
          road: RoadClass.major,
        ),
      )
      ..addLine([
        ...at(-16.9, 32.62),
        ...at(-16.9, 32.6201),
      ], CycleBits.pack(kind: CycleKind.steps, ramp: true))
      ..addClimb([...at(-16.9, 32.63), ...at(-16.9, 32.64)], 2);
    final features =
        decode(
              GeoJsonWriter().cellFeatures(b.build(), CycleContent.all, 16),
            )['features']
            as List;
    Map props(int i) => (features[i] as Map)['properties'] as Map;
    expect(props(0), {
      'k': CycleKind.cycleway.index,
      't': 0,
      'l': 0,
      'o': Direction.backward,
      'mr': 1,
      'u': 1,
      'rg': 1,
      'tr': TrafficClass.limit30,
    });
    expect(props(1), {
      'k': 0,
      't': 0,
      'l': Side.right,
      's': Side.left,
      'rc': RoadClass.major,
      'dl': Direction.forward,
      'dr': Direction.both,
    });
    expect(props(2), {'k': CycleKind.steps.index, 't': 0, 'l': 0, 'rp': 1});
    expect(props(3), {'c': 2});
    expect(((features[3] as Map)['geometry'] as Map)['coordinates'], [
      [-16.9, 32.63],
      [-16.9, 32.64],
    ]);
  });

  test('climbs, traffic and steps only when wanted', () {
    final b = CellWaysBuilder()
      ..addLine([
        ...at(-16.9, 32.6),
        ...at(-16.89, 32.6),
      ], CycleBits.pack(traffic: TrafficClass.noMotor))
      ..addLine([
        ...at(-16.9, 32.62),
        ...at(-16.9, 32.6201),
      ], CycleBits.pack(kind: CycleKind.steps))
      ..addClimb([...at(-16.9, 32.63), ...at(-16.9, 32.64)], 1);
    final cell = b.build();
    final writer = GeoJsonWriter();
    int count(int wanted) =>
        (decode(writer.cellFeatures(cell, wanted, 16))['features'] as List)
            .length;
    expect(count(CycleContent.infrastructure), 0);
    expect(count(CycleContent.traffic), 1);
    expect(count(CycleContent.barriers), 1);
    expect(count(CycleContent.climbs), 1);
  });

  test('one-way streets only when wanted, and not with contraflow', () {
    final b = CellWaysBuilder()
      ..addLine([
        ...at(-16.9, 32.6),
        ...at(-16.89, 32.6),
      ], CycleBits.pack(oneway: Direction.forward))
      ..addLine([
        ...at(-16.9, 32.61),
        ...at(-16.89, 32.61),
      ], CycleBits.pack(oneway: Direction.forward, contraflow: true));
    final cell = b.build();
    final writer = GeoJsonWriter();
    List<Object?> features(int wanted) =>
        decode(writer.cellFeatures(cell, wanted, 16))['features'] as List;
    expect(features(CycleContent.infrastructure), isEmpty);
    final oneway = features(CycleContent.onewayStreets);
    expect(oneway, hasLength(1));
    expect(((oneway.single as Map)['properties'] as Map)['o'], 1);
  });

  test('no line of fewer than two distinct points, and no repeats', () {
    final cycleway = CycleBits.pack(kind: CycleKind.cycleway);
    final b = CellWaysBuilder()
      // Two points a few centimetres apart: one point at five decimals.
      ..addLine([...at(-16.9, 32.6), 163100001, 122600001], cycleway)
      ..addLine([
        ...at(-16.9, 32.61),
        ...at(-16.9, 32.61),
        ...at(-16.89, 32.61),
      ], cycleway)
      ..addClimb([...at(-16.9, 32.63), ...at(-16.9, 32.63)], 2);
    final features =
        decode(
              GeoJsonWriter().cellFeatures(b.build(), CycleContent.all, 16),
            )['features']
            as List;
    expect(features, hasLength(1));
    expect(((features.single as Map)['geometry'] as Map)['coordinates'], [
      [-16.9, 32.61],
      [-16.89, 32.61],
    ]);
  });
}

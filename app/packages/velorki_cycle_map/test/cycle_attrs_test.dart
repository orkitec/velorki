import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:velorki_cycle_map/velorki_cycle_map.dart';

CycleAttrs way(Map<String, String> tags) => CycleAttrs(classifyWay(tags));

void main() {
  group('kind', () {
    test('a cycleway', () {
      expect(way({'highway': 'cycleway'}).kind, CycleKind.cycleway);
    });

    test('a path signed for bikes, or split from the walkers', () {
      expect(
        way({'highway': 'path', 'bicycle': 'designated'}).kind,
        CycleKind.cycleway,
      );
      expect(
        way({
          'highway': 'footway',
          'bicycle': 'designated',
          'foot': 'designated',
          'segregated': 'yes',
        }).kind,
        CycleKind.cycleway,
      );
    });

    test('a path for bikes and walkers together is shared', () {
      expect(
        way({'highway': 'path', 'bicycle': 'designated', 'foot': 'designated'})
            .kind,
        CycleKind.shared,
      );
      expect(
        way({'highway': 'cycleway', 'foot': 'designated', 'segregated': 'no'})
            .kind,
        CycleKind.shared,
      );
    });

    test('a footway bikes may use', () {
      expect(
        way({'highway': 'footway', 'bicycle': 'yes'}).kind,
        CycleKind.allowed,
      );
      expect(
        way({'highway': 'pedestrian', 'bicycle': 'permissive'}).kind,
        CycleKind.allowed,
      );
    });

    test('a cycle street, whatever the highway', () {
      expect(
        way({'highway': 'residential', 'bicycle_road': 'yes'}).kind,
        CycleKind.cyclestreet,
      );
      expect(
        way({'highway': 'residential', 'cyclestreet': 'yes'}).kind,
        CycleKind.cyclestreet,
      );
    });

    test('plain ways and ways closed to bikes are nothing', () {
      expect(way({'highway': 'residential'}).isEmpty, isTrue);
      expect(way({'highway': 'path'}).isEmpty, isTrue);
      expect(way({'highway': 'footway', 'bicycle': 'no'}).isEmpty, isTrue);
      expect(
        way({'highway': 'path', 'bicycle': 'designated'}).kind,
        isNot(CycleKind.none),
      );
      expect(
        way({'highway': 'cycleway', 'bicycle': 'dismount'}).isEmpty,
        isTrue,
      );
      expect(way({}).isEmpty, isTrue);
    });

    test('unknown values count as absent', () {
      expect(way({'highway': 'footway', 'bicycle': 'unknown'}).isEmpty, isTrue);
    });
  });

  group('lanes and tracks beside a road', () {
    test('without a side, both sides', () {
      final a = way({'highway': 'secondary', 'cycleway': 'lane'});
      expect(a.kind, CycleKind.none);
      expect(a.lane, Side.both);
      expect(a.track, 0);
      expect(way({'highway': 'primary', 'cycleway': 'track'}).track, Side.both);
    });

    test('per side', () {
      final a = way({
        'highway': 'tertiary',
        'cycleway:left': 'track',
        'cycleway:right': 'lane',
      });
      expect(a.track, Side.left);
      expect(a.lane, Side.right);
      expect(
        way({'highway': 'tertiary', 'cycleway:both': 'lane'}).lane,
        Side.both,
      );
      expect(
        way({'highway': 'tertiary', 'cycleway:right': 'sidepath'}).track,
        Side.right,
      );
    });

    test('bus lanes, marked lanes and shoulders are shared, not lanes', () {
      final bus = way({'highway': 'primary', 'cycleway:right': 'share_busway'});
      expect(bus.lane, 0);
      expect(bus.sharedLane, Side.right);
      expect(
        way({'highway': 'primary', 'cycleway': 'shared_lane'}).sharedLane,
        Side.both,
      );
      expect(
        way({'highway': 'primary', 'cycleway:left': 'shoulder'}).sharedLane,
        Side.left,
      );
    });

    test('separately drawn and none are nothing', () {
      expect(
        way({'highway': 'primary', 'cycleway:both': 'separate'}).isEmpty,
        isTrue,
      );
      expect(way({'highway': 'primary', 'cycleway': 'no'}).isEmpty, isTrue);
    });

    test('a sidewalk signed for bikes is a track', () {
      expect(
        way({'highway': 'primary', 'sidewalk:right:bicycle': 'designated'})
            .track,
        Side.right,
      );
      // One bikes may use but that isn't theirs is shared.
      expect(
        way({'highway': 'primary', 'sidewalk:bicycle': 'yes'}).sharedLane,
        Side.both,
      );
    });

    test('an opposite lane without a side is on the left', () {
      final a = way({
        'highway': 'residential',
        'oneway': 'yes',
        'cycleway': 'opposite_lane',
      });
      expect(a.lane, Side.left);
      expect(a.contraflow, isTrue);
    });
  });

  group('contraflow', () {
    test('a one-way open to bikes both ways', () {
      expect(
        way({'highway': 'residential', 'oneway': 'yes', 'oneway:bicycle': 'no'})
            .contraflow,
        isTrue,
      );
      expect(
        way({'highway': 'residential', 'oneway': 'yes', 'cycleway': 'opposite'})
            .contraflow,
        isTrue,
      );
      expect(
        way({
          'highway': 'residential',
          'oneway': 'yes',
          'cycleway:left:oneway': '-1',
        }).contraflow,
        isTrue,
      );
    });

    test('bikes allowed against the stored direction', () {
      expect(
        way({
          'highway': 'residential',
          'oneway': 'yes',
          'bicycle:backward': 'yes',
        }).contraflow,
        isTrue,
      );
      expect(
        way({
          'highway': 'residential',
          'oneway': '-1',
          'bicycle:forward': 'yes',
        }).contraflow,
        isTrue,
      );
    });

    test('not on a two-way street or a plain one-way', () {
      expect(
        way({'highway': 'residential', 'oneway:bicycle': 'no'}).contraflow,
        isFalse,
      );
      expect(
        way({'highway': 'residential', 'oneway': 'yes'}).contraflow,
        isFalse,
      );
    });
  });

  group('cycle routes', () {
    test('by network', () {
      expect(
        way({'highway': 'secondary', 'route_bicycle_icn': 'yes'}).routes,
        CycleBits.routeNational,
      );
      expect(
        way({'highway': 'secondary', 'route_bicycle_ncn': 'yes'}).routes,
        CycleBits.routeNational,
      );
      expect(
        way({
          'highway': 'track',
          'route_bicycle_rcn': 'yes',
          'route_bicycle_lcn': 'yes',
        }).routes,
        CycleBits.routeRegional | CycleBits.routeLocal,
      );
    });

    test('proposed routes are not routes', () {
      expect(
        way({'highway': 'secondary', 'route_bicycle_ncn': 'proposed'}).isEmpty,
        isTrue,
      );
    });

    test('not on ways bikes may not use', () {
      expect(
        way({'highway': 'motorway', 'route_bicycle_ncn': 'yes'}).isEmpty,
        isTrue,
      );
    });
  });

  group('surface', () {
    test('unpaved by surface or by track grade', () {
      expect(way({'highway': 'track', 'surface': 'gravel'}).unpaved, isTrue);
      expect(way({'highway': 'track', 'tracktype': 'grade3'}).unpaved, isTrue);
      expect(way({'highway': 'track', 'tracktype': 'grade1'}).unpaved, isFalse);
      expect(
        way({'highway': 'track', 'tracktype': 'grade3', 'surface': 'asphalt'})
            .unpaved,
        isFalse,
      );
      expect(way({'highway': 'residential'}).unpaved, isFalse);
    });

    test('rough by smoothness or cobbles', () {
      expect(
        way({'highway': 'residential', 'smoothness': 'bad'}).rough,
        isTrue,
      );
      expect(
        way({'highway': 'residential', 'surface': 'cobblestone'}).rough,
        isTrue,
      );
      expect(
        way({'highway': 'residential', 'smoothness': 'good'}).rough,
        isFalse,
      );
    });

    test('not on ways bikes may not use', () {
      expect(way({'highway': 'motorway', 'surface': 'gravel'}).isEmpty, isTrue);
    });
  });

  test('mtb scale', () {
    expect(way({'highway': 'path', 'mtb:scale': '2'}).mtbScale, 2);
    expect(way({'highway': 'path', 'mtb:scale': '1+'}).mtbScale, 1);
    expect(way({'highway': 'path'}).mtbScale, isNull);
  });

  test('every part survives packing', () {
    final a = CycleAttrs(
      CycleBits.pack(
        kind: CycleKind.shared,
        track: Side.right,
        lane: Side.left,
        contraflow: true,
        routes: CycleBits.routeLocal,
        unpaved: true,
        rough: true,
        mtbScale: 6,
      ),
    );
    expect(a.kind, CycleKind.shared);
    expect(a.track, Side.right);
    expect(a.lane, Side.left);
    expect(a.contraflow, isTrue);
    expect(a.routes, CycleBits.routeLocal);
    expect(a.unpaved, isTrue);
    expect(a.rough, isTrue);
    expect(a.mtbScale, 6);
  });

  group('barriers', () {
    test('by class', () {
      expect(classifyNode({'barrier': 'bollard'}), BarrierClass.narrow);
      expect(classifyNode({'barrier': 'cycle_barrier'}), BarrierClass.narrow);
      expect(classifyNode({'barrier': 'gate'}), BarrierClass.gate);
      expect(classifyNode({'barrier': 'stile'}), BarrierClass.carry);
      expect(classifyNode({'barrier': 'entrance'}), 0);
      expect(classifyNode({}), 0);
    });

    test('a gate open to bikes is no barrier, a bollard still narrows', () {
      expect(classifyNode({'barrier': 'gate', 'bicycle': 'yes'}), 0);
      expect(
        classifyNode({'barrier': 'bollard', 'bicycle': 'yes'}),
        BarrierClass.narrow,
      );
    });

    test('anything closed to bikes is carried', () {
      expect(
        classifyNode({'barrier': 'entrance', 'bicycle': 'no'}),
        BarrierClass.carry,
      );
    });
  });

  group('direction', () {
    test('a one-way cycleway, either way', () {
      expect(
        way({'highway': 'cycleway', 'oneway': 'yes'}).oneway,
        Direction.forward,
      );
      expect(
        way({'highway': 'cycleway', 'oneway': '-1'}).oneway,
        Direction.backward,
      );
      expect(way({'highway': 'cycleway'}).oneway, Direction.none);
    });

    test('oneway:bicycle wins on a path', () {
      expect(
        way({
          'highway': 'path',
          'bicycle': 'designated',
          'oneway': 'yes',
          'oneway:bicycle': 'no',
        }).oneway,
        Direction.none,
      );
      expect(
        way({
          'highway': 'path',
          'bicycle': 'designated',
          'oneway:bicycle': 'yes',
        }).oneway,
        Direction.forward,
      );
    });

    test('a contraflow street keeps the direction of its traffic', () {
      expect(
        way({'highway': 'residential', 'oneway': '-1', 'oneway:bicycle': 'no'})
            .oneway,
        Direction.backward,
      );
    });

    test('a plain one-way street carries its direction', () {
      final a = way({'highway': 'residential', 'oneway': 'yes'});
      expect(a.isEmpty, isFalse);
      expect(a.kind, CycleKind.none);
      expect(a.oneway, Direction.forward);
      expect(a.contraflow, isFalse);
      expect(
        way({'highway': 'tertiary', 'oneway': '-1'}).oneway,
        Direction.backward,
      );
    });

    test('roundabouts, two-way and closed roads are no one-way street', () {
      expect(
        way({'highway': 'primary', 'junction': 'roundabout'}).isEmpty,
        isTrue,
      );
      expect(way({'highway': 'residential', 'oneway': 'no'}).isEmpty, isTrue);
      expect(
        way({'highway': 'primary', 'oneway': 'yes', 'bicycle': 'no'}).oneway,
        Direction.none,
      );
      expect(way({'highway': 'track', 'oneway': 'yes'}).isEmpty, isTrue);
    });

    test('per side, from cycleway:*:oneway and opposite_*', () {
      final a = way({
        'highway': 'secondary',
        'cycleway:left': 'track',
        'cycleway:left:oneway': 'no',
        'cycleway:right': 'lane',
        'cycleway:right:oneway': 'yes',
      });
      expect(a.leftDirection, Direction.both);
      expect(a.rightDirection, Direction.forward);
      expect(
        way({
          'highway': 'residential',
          'oneway': 'yes',
          'cycleway:left': 'opposite_lane',
        }).leftDirection,
        Direction.backward,
      );
    });

    test('no side direction without a lane on that side', () {
      expect(
        way({
          'highway': 'secondary',
          'cycleway:right': 'lane',
          'cycleway:left:oneway': 'yes',
        }).leftDirection,
        Direction.none,
      );
    });
  });

  group('road size, for the offset of lanes', () {
    test('by highway, only where there is something beside the road', () {
      expect(
        way({'highway': 'primary', 'cycleway': 'lane'}).road,
        RoadClass.major,
      );
      expect(
        way({'highway': 'tertiary', 'cycleway': 'lane'}).road,
        RoadClass.middle,
      );
      expect(
        way({'highway': 'residential', 'cycleway': 'lane'}).road,
        RoadClass.minor,
      );
      expect(
        way({'highway': 'primary', 'route_bicycle_ncn': 'yes'}).road,
        RoadClass.minor,
      );
    });
  });

  group('steps', () {
    test('steps, with or without a ramp', () {
      expect(way({'highway': 'steps'}).kind, CycleKind.steps);
      expect(way({'highway': 'steps'}).ramp, isFalse);
      expect(way({'highway': 'steps', 'ramp:bicycle': 'yes'}).ramp, isTrue);
    });
  });

  group('traffic', () {
    test('speed limits, living streets', () {
      expect(
        way({'highway': 'residential', 'maxspeed': '30'}).traffic,
        TrafficClass.limit30,
      );
      expect(
        way({'highway': 'residential', 'zone:maxspeed': '30'}).traffic,
        TrafficClass.limit30,
      );
      expect(
        way({'highway': 'residential', 'maxspeed': '20'}).traffic,
        TrafficClass.limit20,
      );
      expect(way({'highway': 'living_street'}).traffic, TrafficClass.limit20);
      expect(
        way({'highway': 'service', 'maxspeed': '10'}).traffic,
        TrafficClass.walk,
      );
      expect(way({'highway': 'residential', 'maxspeed': '50'}).isEmpty, isTrue);
    });

    test('no motor traffic, by the first access tag that says', () {
      expect(
        way({'highway': 'residential', 'motor_vehicle': 'no'}).traffic,
        TrafficClass.noMotor,
      );
      expect(
        way({
          'highway': 'unclassified',
          'motorcar': 'yes',
          'motor_vehicle': 'no',
        }).traffic,
        TrafficClass.none,
      );
      expect(
        way({'highway': 'service', 'access': 'agricultural'}).traffic,
        TrafficClass.noMotor,
      );
    });

    test('closed to bikes', () {
      expect(
        way({'highway': 'primary', 'bicycle': 'no'}).traffic,
        TrafficClass.noBikes,
      );
      expect(
        way({'highway': 'trunk', 'motorroad': 'yes'}).traffic,
        TrafficClass.noBikes,
      );
      expect(
        way({'highway': 'residential', 'access': 'no', 'bicycle': 'yes'})
            .traffic,
        isNot(TrafficClass.noBikes),
      );
      // A closed road carries no lanes or routes.
      final closed = way({
        'highway': 'primary',
        'bicycle': 'use_sidepath',
        'cycleway': 'lane',
        'route_bicycle_ncn': 'yes',
      });
      expect(closed.lane, 0);
      expect(closed.routes, 0);
    });

    test('not on paths and tracks', () {
      expect(way({'highway': 'track', 'maxspeed': '30'}).isEmpty, isTrue);
    });
  });

  group('surface grades', () {
    test('gravel and rugged', () {
      final gravel = way({'highway': 'track', 'surface': 'gravel'});
      expect(gravel.unpaved, isTrue);
      expect(gravel.rugged, isFalse);
      final mud = way({'highway': 'path', 'surface': 'mud'});
      expect(mud.unpaved, isTrue);
      expect(mud.rugged, isTrue);
      expect(way({'highway': 'track', 'tracktype': 'grade5'}).rugged, isTrue);
      expect(
        way({'highway': 'track', 'smoothness': 'horrible'}).rugged,
        isTrue,
      );
    });

    test('a paved road with bad smoothness is bumpy, not gravel', () {
      final a = way({'highway': 'residential', 'smoothness': 'bad'});
      expect(a.rough, isTrue);
      expect(a.unpaved, isFalse);
      final track = way({'highway': 'track', 'smoothness': 'bad'});
      expect(track.unpaved, isTrue);
      expect(track.rough, isFalse);
    });
  });

  test('mountain-bike routes', () {
    expect(way({'highway': 'path', 'route_mtb_': 'yes'}).mtbRoute, isTrue);
    expect(way({'highway': 'track', 'route_mtb_lcn': 'yes'}).mtbRoute, isTrue);
  });

  test('every new part survives packing, the top bit included', () {
    final a = CycleAttrs(
      CycleBits.pack(
        kind: CycleKind.steps,
        oneway: Direction.backward,
        leftDirection: Direction.both,
        rightDirection: Direction.forward,
        sharedLane: Side.left,
        ramp: true,
        traffic: TrafficClass.noBikes,
        road: RoadClass.major,
        mtbRoute: true,
        rugged: true,
      ),
    );
    // As a cell stores it: 32 bits, signed.
    final stored = CycleAttrs(Int32List.fromList([a.bits])[0]);
    for (final b in [a, stored]) {
      expect(b.kind, CycleKind.steps);
      expect(b.oneway, Direction.backward);
      expect(b.leftDirection, Direction.both);
      expect(b.rightDirection, Direction.forward);
      expect(b.sharedLane, Side.left);
      expect(b.ramp, isTrue);
      expect(b.traffic, TrafficClass.noBikes);
      expect(b.road, RoadClass.major);
      expect(b.mtbRoute, isTrue);
      expect(b.rugged, isTrue);
      expect(b.isEmpty, isFalse);
    }
  });
}

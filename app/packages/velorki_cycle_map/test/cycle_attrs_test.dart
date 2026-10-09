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

    test('a shared bus lane counts as a lane, sharrows do not', () {
      expect(
        way({'highway': 'primary', 'cycleway:right': 'share_busway'}).lane,
        Side.right,
      );
      expect(
        way({'highway': 'primary', 'cycleway': 'shared_lane'}).isEmpty,
        isTrue,
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
      expect(
        way({'highway': 'primary', 'sidewalk:bicycle': 'yes'}).isEmpty,
        isTrue,
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
}

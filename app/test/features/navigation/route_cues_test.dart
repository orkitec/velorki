import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/navigation/application/navigation_controller.dart';
import 'package:velorki/features/navigation/application/route_cues.dart';
import 'package:velorki/features/planner/domain/route_poi.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// A point [alongM] north of 48°/11°.
LatLng _at(double alongM, {double asideM = 0}) =>
    LatLng(48 + alongM / 111194.9266, 11 + asideM / 74405.0);

void main() {
  test('the cue sheet is the turns, the points of interest on the route and '
      'the finish, in route order', () {
    final route = GuidedRoute(
      key: 'saved:r',
      line: <LatLng>[for (var i = 0; i <= 10; i++) _at(i * 100.0)],
      turns: const <TurnHint>[
        // Straight without a note is not a line; with one it is.
        TurnHint(pointIndex: 1, kind: TurnKind.straight),
        TurnHint(pointIndex: 2, kind: TurnKind.straight, note: 'Gravel starts'),
        TurnHint(pointIndex: 6, kind: TurnKind.left),
      ],
      pois: <RoutePoi>[
        RoutePoi(pos: _at(400, asideM: 5), name: 'Tap', kind: PoiKind.water),
        RoutePoi(pos: _at(500, asideM: 500), name: 'Far away'),
      ],
    );
    final container = ProviderContainer(
      overrides: [activeGuidedRouteProvider.overrideWithValue(route)],
    );
    addTearDown(container.dispose);

    final cues = container.read(guidedRouteCuesProvider);

    expect(cues.map((c) => c.alongM.round()), <int>[200, 400, 600, 1000]);
    expect(cues[0].turn?.note, 'Gravel starts');
    expect(cues[1].poi?.name, 'Tap');
    expect(cues[2].turn?.kind, TurnKind.left);
    expect(cues[3].isFinish, isTrue);
  });

  test('no route, no cues', () {
    final container = ProviderContainer(
      overrides: [activeGuidedRouteProvider.overrideWithValue(null)],
    );
    addTearDown(container.dispose);
    expect(container.read(guidedRouteCuesProvider), isEmpty);
  });
}

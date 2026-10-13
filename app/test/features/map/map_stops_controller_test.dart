import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/map/application/map_stops_controller.dart';
import 'package:velorki/features/map/domain/stops_tiles.dart';
import 'package:velorki_brouter/velorki_brouter.dart' show TileName;
import 'package:velorki/features/map/testing/testing.dart';
import 'package:velorki/features/search/domain/search_result.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// One question the controller asked, held until the test answers it.
class _Ask {
  _Ask(this.box, this.kinds, this.limit, {required this.ranked});

  final BoundingBox box;
  final List<String> kinds;
  final int limit;
  final bool ranked;
  final Completer<List<SearchResult>> answer = Completer<List<SearchResult>>();
}

/// A gazetteer that answers when told to.
class _FakeStore {
  final List<_Ask> asks = <_Ask>[];

  Future<List<SearchResult>> find(
    BoundingBox box,
    List<String> kinds,
    int limit, {
    bool ranked = false,
  }) {
    final ask = _Ask(box, kinds, limit, ranked: ranked);
    asks.add(ask);
    return ask.answer.future;
  }

  /// Answers every question still open from [world]: the stops inside each
  /// box, in [world]'s order, at most the limit asked for.
  void answerAll(List<SearchResult> world) => answer(asks, world);

  /// Answers those of [asks] still open from [world], as [answerAll] does.
  static void answer(Iterable<_Ask> asks, List<SearchResult> world) {
    for (final ask in asks) {
      if (ask.answer.isCompleted) continue;
      final box = ask.box;
      ask.answer.complete(
        world
            .where(
              (s) =>
                  s.position.lat >= box.south &&
                  s.position.lat <= box.north &&
                  s.position.lon >= box.west &&
                  s.position.lon <= box.east,
            )
            .take(ask.limit)
            .toList(),
      );
    }
  }
}

SearchResult _stop(String name, LatLng at, {String kind = 'drinking_water'}) =>
    SearchResult(
      name: name,
      position: at,
      source: SearchSource.local,
      kind: SearchKind.poi,
      detail: kind,
    );

const BoundingBox _view = BoundingBox(
  south: 48,
  west: 11,
  north: 48.02,
  east: 11.03,
);

void main() {
  group('in the area on screen', () {
    /// The squares the stops of [view] are loaded by at [zoom].
    Set<BoundingBox> squares(BoundingBox view, double zoom) => <BoundingBox>{
      for (final tile in tilesCovering(
        grownBox(view, stopsAreaMargin),
        stopsTileZoom(zoom),
      ))
        tile.box,
    };

    /// [view] moved [dLat] north and [dLon] east.
    BoundingBox moved(BoundingBox view, double dLat, double dLon) =>
        BoundingBox(
          south: view.south + dLat,
          west: view.west + dLon,
          north: view.north + dLat,
          east: view.east + dLon,
        );

    test('asks once the camera has rested, for each square of the grid '
        'around the bounds it rests on', () {
      fakeAsync((async) {
        final store = _FakeStore();
        final map = FakeMapController()
          ..zoom = 14
          ..center = const LatLng(48.01, 11.0)
          ..visibleBounds = _view;
        final stops = MapStopsController(find: store.find)
          ..update(shown: true, kinds: const {'drinking_water', 'cafe'})
          ..attach(map);

        // Three idles in quick succession are one question.
        map.emitCameraIdle();
        async.elapse(const Duration(milliseconds: 100));
        map.emitCameraIdle();
        async.elapse(const Duration(milliseconds: 100));
        expect(store.asks, isEmpty);
        async.elapse(const Duration(milliseconds: 260));
        expect(store.asks.map((a) => a.box).toSet(), squares(_view, 14));
        expect(store.asks, hasLength(squares(_view, 14).length));
        for (final ask in store.asks) {
          expect(ask.kinds, <String>['cafe', 'drinking_water']);
          expect(ask.limit, stopsTileSafetyLimit);
          expect(ask.ranked, isTrue);
        }

        store.answerAll([
          _stop('Tap', const LatLng(48.01, 11.014)),
          _stop('Café', const LatLng(48.01, 11.02), kind: 'cafe'),
        ]);
        async.flushMicrotasks();
        expect(map.stops, hasLength(2));
        expect(
          map.stops.map((s) => s.kind),
          containsAll(<MapPoiKind>[MapPoiKind.water, MapPoiKind.food]),
        );
        expect(
          stops.stops.map((s) => s.name),
          containsAll(<String>['Tap', 'Café']),
        );
        // Each kind its own group, in the order the app knows them in.
        expect(map.stopGroups, <String>['drinking_water', 'cafe']);
        expect(
          map.stops.map((s) => s.group),
          containsAll(<String>['drinking_water', 'cafe']),
        );
        stops.dispose();
      });
    });

    test('a square draws every stop of the kinds shown, a numerous kind '
        'beside a rare one', () {
      fakeAsync((async) {
        final store = _FakeStore();
        final map = FakeMapController()
          ..zoom = 14
          ..visibleBounds = _view;
        final stops = MapStopsController(find: store.find)
          ..update(shown: true, kinds: const {'bicycle_parking', 'restaurant'})
          ..attach(map);
        async.elapse(stopsDebounce * 2);
        store.answerAll(<SearchResult>[
          for (var i = 0; i < 1000; i++)
            _stop(
              'Rack $i',
              LatLng(48.005 + (i % 40) * 0.0002, 11.005 + (i ~/ 40) * 0.0002),
              kind: 'bicycle_parking',
            ),
          for (var i = 0; i < 20; i++)
            _stop(
              'Restaurant $i',
              LatLng(48.01, 11.01 + i * 0.0002),
              kind: 'restaurant',
            ),
        ]);
        async.flushMicrotasks();

        int drawn(String kind) =>
            map.stops.where((s) => s.group == kind).length;
        expect(drawn('bicycle_parking'), 1000);
        expect(drawn('restaurant'), 20);
        stops.dispose();
      });
    });

    test('a pathological area draws no more than the bound, the squares '
        'on screen first', () {
      fakeAsync((async) {
        final onScreen = tilesCovering(_view, stopsTileZoom(14));
        final margin = tilesCovering(
          grownBox(_view, stopsAreaMargin),
          stopsTileZoom(14),
        ).difference(onScreen).toList()..sort();
        // A square of the margin that comes before the ones on screen.
        final early = margin.first.box;
        expect(margin.first.compareTo(onScreen.reduce(_first)), isNegative);
        final store = _FakeStore();
        final map = FakeMapController()
          ..zoom = 14
          ..visibleBounds = _view;
        final stops = MapStopsController(find: store.find)
          ..update(shown: true, kinds: const {'bicycle_parking', 'restaurant'})
          ..attach(map);
        async.elapse(stopsDebounce * 2);
        final dLat = (early.north - early.south) / 210;
        final dLon = (early.east - early.west) / 110;
        store.answerAll(<SearchResult>[
          for (var i = 0; i < stopsDrawSafetyLimit + 100; i++)
            _stop(
              'Rack $i',
              LatLng(
                early.south + (1 + i % 200) * dLat,
                early.west + (1 + i ~/ 200) * dLon,
              ),
              kind: 'bicycle_parking',
            ),
          for (var i = 0; i < 20; i++)
            _stop(
              'Restaurant $i',
              LatLng(48.01, 11.01 + i * 0.0002),
              kind: 'restaurant',
            ),
        ]);
        async.flushMicrotasks();

        expect(map.stops, hasLength(stopsDrawSafetyLimit));
        expect(map.stops.where((s) => s.group == 'restaurant'), hasLength(20));
        stops.dispose();
      });
    });

    test('a square holds the same stops wherever the camera stands', () {
      fakeAsync((async) {
        final world = <SearchResult>[
          for (var i = 0; i < 250; i++)
            _stop(
              'Café $i',
              LatLng(48.0 + (i % 20) * 0.001, 11.0 + (i ~/ 20) * 0.001),
              kind: 'cafe',
            ),
        ];
        List<SearchResult> seenFrom(BoundingBox view) {
          final store = _FakeStore();
          final map = FakeMapController()
            ..zoom = 14
            ..visibleBounds = view;
          final stops = MapStopsController(find: store.find)
            ..update(shown: true, kinds: const {'cafe'})
            ..attach(map);
          async.elapse(stopsDebounce * 2);
          store.answerAll(world);
          async.flushMicrotasks();
          final drawn = stops.stops;
          stops.dispose();
          return drawn;
        }

        final square = tilesCovering(
          const BoundingBox(
            south: 48.01,
            west: 11.01,
            north: 48.01,
            east: 11.01,
          ),
          13,
        ).single.box;
        bool inSquare(SearchResult s) =>
            s.position.lat >= square.south &&
            s.position.lat <= square.north &&
            s.position.lon >= square.west &&
            s.position.lon <= square.east;
        final here = seenFrom(_view).where(inSquare).toList();
        final there = seenFrom(moved(_view, 0.006, -0.009)).where(inSquare);
        expect(here, isNotEmpty);
        expect(here, hasLength(world.where(inSquare).length));
        expect(there.toList(), here);
      });
    });

    test('a pan inside the squares loaded leaves the map\'s stops as they '
        'are; one beyond them loads the new squares only', () {
      fakeAsync((async) {
        final store = _FakeStore();
        final map = FakeMapController()
          ..zoom = 14.5
          ..visibleBounds = _view;
        final stops = MapStopsController(find: store.find)
          ..update(shown: true, kinds: const {'drinking_water'})
          ..attach(map);
        async.elapse(stopsDebounce * 2);
        final world = <SearchResult>[
          for (var i = 0; i < 40; i++)
            _stop('Tap $i', LatLng(47.95 + i * 0.003, 10.95 + i * 0.004)),
        ];
        store.answerAll(world);
        async.flushMicrotasks();
        final writes = map.stopCalls.length;
        final asked = store.asks.length;

        // Small steps, as a finger nudges the map.
        for (var i = 1; i <= 4; i++) {
          map.visibleBounds = moved(_view, 0.0005 * i, 0.0008 * i);
          map.emitCameraIdle();
          async.elapse(stopsDebounce * 2);
        }
        expect(store.asks, hasLength(asked));
        expect(map.stopCalls, hasLength(writes));

        // Far enough east for new squares: only those are asked for.
        final east = moved(_view, 0, 0.06);
        map.visibleBounds = east;
        map.emitCameraIdle();
        async.elapse(stopsDebounce * 2);
        final fresh = store.asks.skip(asked).map((a) => a.box).toSet();
        expect(fresh, isNotEmpty);
        expect(fresh.intersection(squares(_view, 14.5)), isEmpty);
        expect(fresh, squares(east, 14.5).difference(squares(_view, 14.5)));
        store.answerAll(world);
        async.flushMicrotasks();
        expect(map.stopCalls, hasLength(writes + 1));
        stops.dispose();
      });
    });

    test('squares within reach are kept, and those beyond it dropped', () {
      fakeAsync((async) {
        final store = _FakeStore();
        final map = FakeMapController()
          ..zoom = 14
          ..visibleBounds = _view;
        final stops = MapStopsController(find: store.find)
          ..update(shown: true, kinds: const {'drinking_water'})
          ..attach(map);
        async.elapse(stopsDebounce * 2);
        // A tap in the westernmost squares loaded.
        final west = squares(_view, 14).map((b) => b.west).reduce(math.min);
        final tap = _stop('Far west', LatLng(48.01, west + 1e-4));
        store.answerAll([tap]);
        async.flushMicrotasks();
        expect(stops.stops, <SearchResult>[tap]);

        // Out of the margin, but within reach: kept.
        final nudged = moved(_view, 0, 0.008);
        expect(
          squares(nudged, 14).any((b) => b.west <= tap.position.lon),
          isFalse,
        );
        expect(
          tilesCovering(
            grownBox(nudged, stopsKeepMargin),
            13,
          ).any((t) => t.box.west <= tap.position.lon),
          isTrue,
        );
        map.visibleBounds = nudged;
        map.emitCameraIdle();
        async.elapse(stopsDebounce * 2);
        store.answerAll(const <SearchResult>[]);
        async.flushMicrotasks();
        expect(stops.stops, <SearchResult>[tap]);

        // Far beyond: gone.
        map.visibleBounds = moved(_view, 0, 0.2);
        map.emitCameraIdle();
        async.elapse(stopsDebounce * 2);
        store.answerAll(const <SearchResult>[]);
        async.flushMicrotasks();
        expect(stops.stops, isEmpty);
        stops.dispose();
      });
    });

    test('a zoom across a whole level loads the grid of that zoom', () {
      fakeAsync((async) {
        final store = _FakeStore();
        final map = FakeMapController()
          ..zoom = 14.2
          ..visibleBounds = _view;
        final stops = MapStopsController(find: store.find)
          ..update(shown: true, kinds: const {'drinking_water'})
          ..attach(map);
        async.elapse(stopsDebounce * 2);
        store.answerAll(const <SearchResult>[]);
        async.flushMicrotasks();
        final asked = store.asks.length;

        // Within the level: nothing new.
        map.zoom = 14.8;
        map.emitCameraIdle();
        async.elapse(stopsDebounce * 2);
        expect(store.asks, hasLength(asked));

        map.zoom = 12.5;
        map.emitCameraIdle();
        async.elapse(stopsDebounce * 2);
        final coarser = store.asks.skip(asked).toList();
        expect(coarser.map((a) => a.box).toSet(), squares(_view, 12.5));
        expect(coarser.first.limit, stopsTileSafetyLimit);
        stops.dispose();
      });
    });

    test('the stops are loaded around the part of the map the rider sees, '
        'with a margin', () {
      fakeAsync((async) {
        final store = _FakeStore();
        final map = FakeMapController()
          ..zoom = 14
          ..center = const LatLng(48.01, 11.015)
          ..visibleBounds = _view;
        // The sheet covers the lower half.
        final stops =
            MapStopsController(
                find: store.find,
                visibleShare: () => const Rect.fromLTRB(0, 0, 1, 0.5),
              )
              ..update(shown: true, kinds: const {'cafe'})
              ..attach(map);
        async.elapse(stopsDebounce * 2);
        const upper = BoundingBox(
          south: 48.01,
          west: 11.0,
          north: 48.02,
          east: 11.03,
        );
        final part = visiblePart(_view, const Rect.fromLTRB(0, 0, 1, 0.5));
        expect(part.south, closeTo(upper.south, 1e-9));
        expect(part.west, closeTo(upper.west, 1e-9));
        expect(part.north, closeTo(upper.north, 1e-9));
        expect(part.east, closeTo(upper.east, 1e-9));
        expect(store.asks.map((a) => a.box).toSet(), squares(part, 14));
        stops.dispose();
      });
    });

    test('a sheet pulled up or down asks again once it rests, for what it '
        'now leaves of the map', () {
      fakeAsync((async) {
        final store = _FakeStore();
        final map = FakeMapController()
          ..zoom = 14
          ..center = const LatLng(48.01, 11.015)
          ..visibleBounds = const BoundingBox(
            south: 47.9,
            west: 11,
            north: 48.02,
            east: 11.03,
          );
        var covered = 0.9;
        final stops =
            MapStopsController(
                find: store.find,
                visibleShare: () => Rect.fromLTRB(0, 0, 1, 1 - covered),
              )
              ..update(shown: true, kinds: const {'cafe'})
              ..attach(map);
        async.elapse(stopsDebounce * 2);
        store.answerAll(const <SearchResult>[]);
        async.flushMicrotasks();
        final asked = store.asks.length;

        // Dragged down in steps: one question once it rests.
        for (final share in [0.6, 0.3, 0.1]) {
          covered = share;
          stops.visibleAreaChanged();
          async.elapse(const Duration(milliseconds: 50));
        }
        async.elapse(stopsDebounce * 2);
        final fresh = store.asks.skip(asked).toList();
        expect(fresh, isNotEmpty);
        // Squares further south, under the sheet before, among them.
        final southmost = store.asks
            .take(asked)
            .map((a) => a.box.south)
            .reduce(math.min);
        expect(fresh.any((a) => a.box.south < southmost), isTrue);
        stops.dispose();
      });
    });

    test('a map that settles a hair below the zoom asked for shows the '
        'stops', () {
      fakeAsync((async) {
        final store = _FakeStore();
        final map = FakeMapController()
          // What iOS reported after a move to zoom 11.
          ..zoom = stopsMinZoom - 0.0007
          ..center = const LatLng(48.01, 11.015)
          ..visibleBounds = _view;
        final stops = MapStopsController(find: store.find)
          ..update(shown: true, kinds: const {'cafe'})
          ..attach(map);
        async.elapse(stopsDebounce * 2);
        expect(store.asks, isNotEmpty);
        stops.dispose();
      });
    });

    test('a place with two kinds is one pin', () {
      fakeAsync((async) {
        final store = _FakeStore();
        final map = FakeMapController()
          ..zoom = 15
          ..center = const LatLng(48.01, 11.015)
          ..visibleBounds = _view;
        final stops = MapStopsController(find: store.find)
          ..update(shown: true, kinds: const {'cafe', 'ice_cream'})
          ..attach(map);
        async.elapse(stopsDebounce * 2);
        store.answerAll([
          _stop('Mil Sabores', const LatLng(48.011, 11.015), kind: 'cafe'),
          _stop('Mil Sabores', const LatLng(48.011, 11.015), kind: 'ice_cream'),
          // The same name elsewhere is another place.
          _stop('Mil Sabores', const LatLng(48.015, 11.02), kind: 'cafe'),
        ]);
        async.flushMicrotasks();
        expect(map.stops, hasLength(2));
        expect(stops.stops.first.detail, 'cafe');
        stops.dispose();
      });
    });

    test('below the zoom where stops show nothing is asked and nothing '
        'drawn', () {
      fakeAsync((async) {
        final store = _FakeStore();
        final map = FakeMapController()
          ..zoom = stopsMinZoom - 0.5
          ..center = const LatLng(48.0, 11.0)
          ..visibleBounds = _view;
        final stops = MapStopsController(find: store.find)
          ..update(shown: true, kinds: const {'cafe'})
          ..attach(map);
        async.elapse(stopsDebounce * 2);
        expect(store.asks, isEmpty);
        expect(map.stops, isEmpty);

        map.zoom = stopsMinZoom;
        map.emitCameraIdle();
        async.elapse(stopsDebounce * 2);
        expect(store.asks, isNotEmpty);
        stops.dispose();
      });
    });

    test('an answer for squares panned away from before it came is not '
        'drawn', () {
      fakeAsync((async) {
        final store = _FakeStore();
        final map = FakeMapController()
          ..zoom = 14
          ..visibleBounds = _view;
        final stops = MapStopsController(find: store.find)
          ..update(shown: true, kinds: const {'drinking_water'})
          ..attach(map);
        async.elapse(stopsDebounce * 2);
        final first = List<_Ask>.of(store.asks);

        // The rider pans far on before the first answer is in.
        map.visibleBounds = moved(_view, 0.1, 0.1);
        map.emitCameraIdle();
        async.elapse(stopsDebounce * 2);
        final second = store.asks.skip(first.length).toList();
        expect(second, isNotEmpty);

        final world = [
          _stop('New', const LatLng(48.11, 11.11)),
          _stop('Old', const LatLng(48.01, 11.01)),
        ];
        _FakeStore.answer(second, world);
        async.flushMicrotasks();
        _FakeStore.answer(first, world);
        async.flushMicrotasks();

        expect(map.stops.map((s) => s.name), <String>['New']);
        stops.dispose();
      });
    });

    test('an answer for other kinds than are now wanted is dropped', () {
      fakeAsync((async) {
        final store = _FakeStore();
        final map = FakeMapController()
          ..zoom = 14
          ..visibleBounds = _view;
        final stops = MapStopsController(find: store.find)
          ..update(shown: true, kinds: const {'drinking_water'})
          ..attach(map);
        async.elapse(stopsDebounce * 2);
        final first = List<_Ask>.of(store.asks);
        stops.update(shown: true, kinds: const {'cafe'});
        async.elapse(stopsDebounce * 2);
        final second = store.asks.skip(first.length).toList();
        expect(second.first.kinds, <String>['cafe']);

        _FakeStore.answer(second, [
          _stop('Café', const LatLng(48.01, 11.01), kind: 'cafe'),
        ]);
        async.flushMicrotasks();
        _FakeStore.answer(first, [_stop('Tap', const LatLng(48.01, 11.02))]);
        async.flushMicrotasks();
        expect(map.stops.map((s) => s.name), <String>['Café']);

        // Nor is it kept for the squares: a pan inside them changes nothing.
        map.visibleBounds = moved(_view, 0.001, 0.001);
        map.emitCameraIdle();
        async.elapse(stopsDebounce * 2);
        expect(map.stops.map((s) => s.name), <String>['Café']);
        stops.dispose();
      });
    });

    test('zoomed out past where they show, the stops go and nothing is '
        'asked', () {
      fakeAsync((async) {
        final store = _FakeStore();
        final map = FakeMapController()
          ..zoom = 14
          ..visibleBounds = _view;
        final stops = MapStopsController(find: store.find)
          ..update(shown: true, kinds: const {'drinking_water'})
          ..attach(map);
        async.elapse(stopsDebounce * 2);
        store.answerAll([_stop('Tap', const LatLng(48.01, 11.014))]);
        async.flushMicrotasks();
        expect(map.stops, hasLength(1));
        final asked = store.asks.length;

        map.zoom = stopsMinZoom - 1;
        map.emitCameraIdle();
        async.elapse(stopsDebounce * 2);

        expect(store.asks, hasLength(asked));
        expect(map.stops, isEmpty);
        stops.dispose();
      });
    });

    test('switched off, the stops go, and an answer on its way is dropped', () {
      fakeAsync((async) {
        final store = _FakeStore();
        final map = FakeMapController()
          ..zoom = 14
          ..visibleBounds = _view;
        final stops = MapStopsController(find: store.find)
          ..update(shown: true, kinds: const {'drinking_water'})
          ..attach(map);
        async.elapse(stopsDebounce * 2);

        stops.update(shown: false, kinds: const {'drinking_water'});
        store.answerAll([_stop('Tap', const LatLng(48.01, 11.014))]);
        async.flushMicrotasks();

        expect(map.stops, isEmpty);
        expect(stops.mode, MapStopsMode.off);
        stops.dispose();
      });
    });

    test('detached, the stops come off the map and the idles are not '
        'listened to any more', () {
      fakeAsync((async) {
        final store = _FakeStore();
        final map = FakeMapController()
          ..zoom = 14
          ..visibleBounds = _view;
        final stops = MapStopsController(find: store.find)
          ..update(shown: true, kinds: const {'drinking_water'})
          ..attach(map);
        async.elapse(stopsDebounce * 2);
        store.answerAll([_stop('Tap', const LatLng(48.01, 11.014))]);
        async.flushMicrotasks();
        expect(map.onStopTapped, isNotNull);
        final asked = store.asks.length;

        stops.detach();
        async.flushMicrotasks();

        expect(map.stops, isEmpty);
        expect(map.cameraIdleListeners, isEmpty);
        expect(map.onStopTapped, isNull);
        map.emitCameraIdle();
        async.elapse(stopsDebounce * 2);
        expect(store.asks, hasLength(asked));
        stops.dispose();
      });
    });

    test('a tap on a stop reports the stop, and a picked stop is drawn '
        'chosen', () {
      fakeAsync((async) {
        final store = _FakeStore();
        final map = FakeMapController()
          ..zoom = 14
          ..visibleBounds = _view;
        final tapped = <SearchResult>[];
        final stops = MapStopsController(find: store.find)
          ..onStopTapped = tapped.add
          ..update(shown: true, kinds: const {'drinking_water'})
          ..attach(map);
        async.elapse(stopsDebounce * 2);
        final tap = _stop('Tap', const LatLng(48.01, 11.01));
        store.answerAll([tap]);
        async.flushMicrotasks();

        map.emitStopTapped(0);
        expect(tapped, <SearchResult>[tap]);

        stops.select(tap);
        expect(map.stops.single.selected, isTrue);
        stops.dispose();
      });
    });
  });

  group('along the route', () {
    // Due east along 48° N, a point every 500 m, 80 km.
    const mPerLon = 111195 * 0.66913;
    final line = <LatLng>[
      for (var m = 0.0; m <= 80000; m += 500) LatLng(48, 11 + m / mPerLon),
    ];
    LatLng beside(double km) => LatLng(48.0004, 11 + km * 1000 / mPerLon);

    test('asks over the route ahead in stretches and keeps what is beside '
        'it, whatever the zoom', () {
      fakeAsync((async) {
        final store = _FakeStore();
        final map = FakeMapController()..zoom = 9;
        final stops = MapStopsController(find: store.find)
          ..update(
            shown: true,
            kinds: const {'drinking_water', 'cafe'},
            routeKey: 'r1',
            routeLine: line,
            alongM: 10000,
          )
          ..attach(map);
        async.flushMicrotasks();
        expect(stops.mode, MapStopsMode.alongRoute);
        // Fifty kilometres in five-kilometre stretches.
        expect(store.asks.length, inInclusiveRange(9, 11));
        final behind = _stop('Behind', beside(5));
        final tap = _stop('Tap', beside(14));
        final cafe = _stop('Café', beside(12), kind: 'cafe');
        final tap2 = _stop('Tap 2', beside(30));
        final off = _stop('Off', const LatLng(48.1, 11.2));
        for (final ask in store.asks) {
          // Every stretch answers everything it holds; the two overlapping
          // at a seam answer a stop twice.
          ask.answer.complete([
            for (final s in [behind, tap, cafe, tap2, off])
              if (ask.box.contains(s.position)) s,
          ]);
        }
        async.flushMicrotasks();

        expect(stops.stops.map((s) => s.name), <String>[
          'Café',
          'Tap',
          'Tap 2',
        ]);
        expect(map.stops, hasLength(3));
        final next = stops.nextPerKind();
        expect(next.map((s) => s.stop.name), <String>['Café', 'Tap']);
        expect(next.first.aheadM, closeTo(2000, 80));

        // Riding on: no new question for less than a kilometre, and the
        // stop ridden past leaves the map.
        stops.update(
          shown: true,
          kinds: const {'drinking_water', 'cafe'},
          routeKey: 'r1',
          routeLine: line,
          alongM: 10900,
        );
        async.flushMicrotasks();
        final asked = store.asks.length;
        expect(stops.nextPerKind().first.aheadM, closeTo(1100, 80));

        stops.update(
          shown: true,
          kinds: const {'drinking_water', 'cafe'},
          routeKey: 'r1',
          routeLine: line,
          alongM: 12500,
        );
        async.flushMicrotasks();
        // A kilometre and more on: asked again.
        expect(store.asks.length, greaterThan(asked));
        // Until the answer is in, what was found is still there, less what
        // is behind.
        expect(stops.stops.map((s) => s.name), <String>['Tap', 'Tap 2']);
        stops.dispose();
      });
    });

    test('a new route asks again and drops the old route\'s answer', () {
      fakeAsync((async) {
        final store = _FakeStore();
        final map = FakeMapController();
        final stops = MapStopsController(find: store.find)
          ..update(
            shown: true,
            kinds: const {'drinking_water'},
            routeKey: 'r1',
            routeLine: line,
          )
          ..attach(map);
        async.flushMicrotasks();
        final first = List<_Ask>.of(store.asks);
        store.asks.clear();

        // A detour: another line under another key.
        final detour = <LatLng>[
          for (var i = 0; i <= 40; i++) LatLng(48 + i * 0.005, 11.06),
        ];
        stops.update(
          shown: true,
          kinds: const {'drinking_water'},
          routeKey: 'detour',
          routeLine: detour,
        );
        async.flushMicrotasks();
        expect(store.asks, isNotEmpty);
        for (final ask in first) {
          ask.answer.complete([_stop('Old', beside(3))]);
        }
        for (final ask in store.asks) {
          ask.answer.complete([
            if (ask.box.contains(const LatLng(48.1, 11.0602)))
              _stop('New', const LatLng(48.1, 11.0602)),
          ]);
        }
        async.flushMicrotasks();

        expect(stops.stops.map((s) => s.name), <String>['New']);
        stops.dispose();
      });
    });

    test('other kinds ask again', () {
      fakeAsync((async) {
        final store = _FakeStore();
        final map = FakeMapController();
        final stops = MapStopsController(find: store.find)
          ..update(
            shown: true,
            kinds: const {'drinking_water'},
            routeKey: 'r1',
            routeLine: line,
          )
          ..attach(map);
        async.flushMicrotasks();
        final asked = store.asks.length;

        stops.update(
          shown: true,
          kinds: const {'drinking_water', 'toilets'},
          routeKey: 'r1',
          routeLine: line,
        );
        async.flushMicrotasks();

        expect(store.asks.length, 2 * asked);
        expect(store.asks.last.kinds, <String>['drinking_water', 'toilets']);
        stops.dispose();
      });
    });
  });

  group('where nothing is downloaded', () {
    bool east(LatLng p) => p.lon >= 11.9;

    test('in the area, an uncovered middle asks for the download and a '
        'download that covers it takes the ask away and fetches', () {
      fakeAsync((async) {
        final store = _FakeStore();
        final coverage = FakeStopsCoverage(covered: east);
        final map = FakeMapController()
          ..zoom = stopsMinZoom
          ..center = const LatLng(48.01, 11.015)
          ..visibleBounds = _view;
        final stops = MapStopsController(find: store.find, coverage: coverage)
          ..update(shown: true, kinds: const {'cafe'})
          ..attach(map);
        var told = 0;
        stops.addListener(() => told++);
        async.elapse(stopsDebounce * 2);
        expect(stops.needsDownload, isTrue);
        // The chip speaks of the tile under the middle.
        expect(stops.missingArea, const TileName(10, 45));
        final asked = store.asks.length;

        // The download finished and the store re-scanned.
        coverage.changed((_) => true);
        async.flushMicrotasks();
        expect(stops.needsDownload, isFalse);
        expect(stops.missingArea, isNull);
        expect(told, greaterThan(0));
        async.elapse(stopsDebounce * 2);
        expect(store.asks.length, greaterThan(asked));
        stops.dispose();
      });
    });

    test(
      'in the area, a covered middle needs nothing; panning off it does',
      () {
        fakeAsync((async) {
          final store = _FakeStore();
          final map = FakeMapController()
            ..zoom = 14
            ..center = const LatLng(48.01, 11.015)
            ..visibleBounds = _view;
          final stops =
              MapStopsController(
                  find: store.find,
                  coverage: FakeStopsCoverage(covered: (p) => p.lon < 11.5),
                )
                ..update(shown: true, kinds: const {'cafe'})
                ..attach(map);
          async.elapse(stopsDebounce * 2);
          expect(stops.needsDownload, isFalse);

          map
            ..center = const LatLng(48.01, 12.015)
            ..visibleBounds = const BoundingBox(
              south: 48,
              west: 12,
              north: 48.02,
              east: 12.03,
            );
          map.emitCameraIdle();
          async.flushMicrotasks();
          expect(stops.needsDownload, isTrue);
          stops.dispose();
        });
      },
    );

    test('zoomed out over an uncovered area, the download is still '
        'offered', () {
      fakeAsync((async) {
        final store = _FakeStore();
        final map = FakeMapController()
          ..zoom = stopsMinZoom - 2
          ..center = const LatLng(48.01, 11.015)
          ..visibleBounds = _view;
        final stops =
            MapStopsController(
                find: store.find,
                coverage: FakeStopsCoverage(covered: (_) => false),
              )
              ..update(shown: true, kinds: const {'cafe'})
              ..attach(map);
        async.elapse(stopsDebounce * 2);
        expect(stops.needsDownload, isTrue);
        stops.dispose();
      });
    });

    test('with stops off nothing is missing', () {
      fakeAsync((async) {
        final store = _FakeStore();
        final map = FakeMapController()
          ..zoom = 14
          ..center = const LatLng(48.01, 11.015)
          ..visibleBounds = _view;
        final stops =
            MapStopsController(
                find: store.find,
                coverage: FakeStopsCoverage(covered: (_) => false),
              )
              ..update(shown: false, kinds: const {'cafe'})
              ..attach(map);
        async.elapse(stopsDebounce * 2);
        expect(stops.needsDownload, isFalse);
        stops.update(shown: true, kinds: const {'cafe'});
        async.flushMicrotasks();
        expect(stops.needsDownload, isTrue);
        stops.update(shown: false, kinds: const {'cafe'});
        expect(stops.needsDownload, isFalse);
        expect(stops.missingArea, isNull);
        stops.dispose();
      });
    });

    test('along a route, only a stretch ahead with no downloaded part asks '
        'for the download', () {
      fakeAsync((async) {
        const mPerLon = 111195 * 0.66913;
        final line = <LatLng>[
          for (var m = 0.0; m <= 80000; m += 500) LatLng(48, 11 + m / mPerLon),
        ];
        final store = _FakeStore();
        final stops =
            MapStopsController(
                find: store.find,
                coverage: FakeStopsCoverage(covered: east),
              )
              ..update(
                shown: true,
                kinds: const {'cafe'},
                routeKey: 'r1',
                routeLine: line,
              )
              ..attach(FakeMapController()..zoom = 9);
        async.flushMicrotasks();
        expect(stops.mode, MapStopsMode.alongRoute);
        expect(stops.needsDownload, isTrue);
        // The area is the one the rider is in.
        expect(stops.missingArea, const TileName(10, 45));

        // Ridden on until the downloaded part is within the stretch ahead.
        stops.update(
          shown: true,
          kinds: const {'cafe'},
          routeKey: 'r1',
          routeLine: line,
          alongM: 40000,
        );
        async.flushMicrotasks();
        expect(stops.needsDownload, isFalse);
        stops.dispose();
      });
    });
  });
}

StopsTile _first(StopsTile a, StopsTile b) => a.compareTo(b) <= 0 ? a : b;

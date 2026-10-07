import 'dart:ui' show Rect;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/features/map/application/map_stops_controller.dart';
import 'package:velorki/features/map/testing/testing.dart';
import 'package:velorki/features/search/domain/search_result.dart';
import 'package:velorki_geo/velorki_geo.dart';

/// One question the controller asked, held until the test answers it.
class _Ask {
  _Ask(this.box, this.kinds, this.limit, {this.near});

  final BoundingBox box;
  final LatLng? near;
  final List<String> kinds;
  final int limit;
  final Completer<List<SearchResult>> answer = Completer<List<SearchResult>>();
}

/// A gazetteer that answers when told to.
class _FakeStore {
  final List<_Ask> asks = <_Ask>[];

  Future<List<SearchResult>> find(
    BoundingBox box,
    List<String> kinds,
    int limit, {
    LatLng? near,
  }) {
    final ask = _Ask(box, kinds, limit, near: near);
    asks.add(ask);
    return ask.answer.future;
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
    test('asks once the camera has rested, for the bounds it rests on', () {
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
        expect(store.asks, hasLength(1));
        expect(store.asks.single.box, grownBox(_view, stopsAreaMargin));
        expect(store.asks.single.kinds, <String>['cafe', 'drinking_water']);
        expect(store.asks.single.limit, stopsAreaLimit);

        store.asks.single.answer.complete([
          _stop('Tap', const LatLng(48.01, 11.014)),
          _stop('Café', const LatLng(48.01, 11.02), kind: 'cafe'),
        ]);
        async.flushMicrotasks();
        expect(map.stops, hasLength(2));
        expect(map.stops.first.kind, MapPoiKind.water);
        expect(map.stops.last.kind, MapPoiKind.food);
        expect(stops.stops.map((s) => s.name), <String>['Tap', 'Café']);
        stops.dispose();
      });
    });

    test('a busy area draws every stop, nearest the middle first, and a '
        'limit drops the far ones', () {
      fakeAsync((async) {
        final store = _FakeStore();
        final map = FakeMapController()
          ..zoom = 12
          ..center = const LatLng(48.0, 11.0)
          ..visibleBounds = _view;
        final stops = MapStopsController(find: store.find)
          ..update(shown: true, kinds: const {'cafe'})
          ..attach(map);
        async.elapse(stopsDebounce * 2);
        // Furthest first, so the order of the answer is not what is kept;
        // more than the limit, as several gazetteers together can answer.
        store.asks.single.answer.complete([
          for (var i = stopsAreaLimit + 40; i > 0; i--)
            // Outward from the middle of what is visible.
            _stop('Café $i', LatLng(48.01 + i * 1e-5, 11.015), kind: 'cafe'),
        ]);
        async.flushMicrotasks();
        expect(map.stops, hasLength(stopsAreaLimit));
        expect(stops.stops.first.name, 'Café 1');
        expect(stops.stops.last.name, 'Café $stopsAreaLimit');
        stops.dispose();
      });
    });

    test('the stops are asked for around the part of the map the rider '
        'sees, with a margin, and ranked from its middle', () {
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
        void same(BoundingBox actual, BoundingBox expected) {
          expect(actual.south, closeTo(expected.south, 1e-9));
          expect(actual.west, closeTo(expected.west, 1e-9));
          expect(actual.north, closeTo(expected.north, 1e-9));
          expect(actual.east, closeTo(expected.east, 1e-9));
        }

        same(visiblePart(_view, const Rect.fromLTRB(0, 0, 1, 0.5)), upper);
        same(store.asks.single.box, grownBox(upper, stopsAreaMargin));
        // The limit keeps what is nearest the visible middle.
        expect(store.asks.single.near, upper.center);

        store.asks.single.answer.complete([
          _stop('Under the sheet', const LatLng(48.002, 11.015), kind: 'cafe'),
          _stop('In view', const LatLng(48.015, 11.016), kind: 'cafe'),
        ]);
        async.flushMicrotasks();
        expect(stops.stops.map((s) => s.name), <String>[
          'In view',
          'Under the sheet',
        ]);
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
          ..visibleBounds = _view;
        var covered = 0.5;
        final stops =
            MapStopsController(
                find: store.find,
                visibleShare: () => Rect.fromLTRB(0, 0, 1, 1 - covered),
              )
              ..update(shown: true, kinds: const {'cafe'})
              ..attach(map);
        async.elapse(stopsDebounce * 2);
        store.asks.single.answer.complete(const <SearchResult>[]);
        async.flushMicrotasks();

        // Dragged down in steps: one question once it rests.
        for (final share in [0.4, 0.3, 0.2]) {
          covered = share;
          stops.visibleAreaChanged();
          async.elapse(const Duration(milliseconds: 50));
        }
        async.elapse(stopsDebounce * 2);
        expect(store.asks, hasLength(2));
        expect(store.asks.last.near!.lat, closeTo(48.012, 1e-9));
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
        expect(stops.needsZoom, isTrue);

        map.zoom = stopsMinZoom;
        map.emitCameraIdle();
        async.elapse(stopsDebounce * 2);
        expect(store.asks, hasLength(1));
        expect(stops.needsZoom, isFalse);
        stops.dispose();
      });
    });

    test('an answer overtaken by a newer question is dropped', () {
      fakeAsync((async) {
        final store = _FakeStore();
        final map = FakeMapController()
          ..zoom = 14
          ..visibleBounds = _view;
        final stops = MapStopsController(find: store.find)
          ..update(shown: true, kinds: const {'drinking_water'})
          ..attach(map);
        async.elapse(stopsDebounce * 2);
        expect(store.asks, hasLength(1));

        // The rider pans on before the first answer is in.
        map.visibleBounds = const BoundingBox(
          south: 48.1,
          west: 11.1,
          north: 48.12,
          east: 11.13,
        );
        map.emitCameraIdle();
        async.elapse(stopsDebounce * 2);
        expect(store.asks, hasLength(2));

        store.asks[1].answer.complete([
          _stop('New', const LatLng(48.11, 11.11)),
        ]);
        async.flushMicrotasks();
        store.asks[0].answer.complete([
          _stop('Old', const LatLng(48.01, 11.01)),
        ]);
        async.flushMicrotasks();

        expect(map.stops.map((s) => s.name), <String>['New']);
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
        store.asks.single.answer.complete([
          _stop('Tap', const LatLng(48.01, 11.014)),
        ]);
        async.flushMicrotasks();
        expect(map.stops, hasLength(1));

        map.zoom = stopsMinZoom - 1;
        map.emitCameraIdle();
        async.elapse(stopsDebounce * 2);

        expect(store.asks, hasLength(1));
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
        store.asks.single.answer.complete([
          _stop('Tap', const LatLng(48.01, 11.014)),
        ]);
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
        store.asks.single.answer.complete([
          _stop('Tap', const LatLng(48.01, 11.014)),
        ]);
        async.flushMicrotasks();
        expect(map.onStopTapped, isNotNull);

        stops.detach();
        async.flushMicrotasks();

        expect(map.stops, isEmpty);
        expect(map.cameraIdleListeners, isEmpty);
        expect(map.onStopTapped, isNull);
        map.emitCameraIdle();
        async.elapse(stopsDebounce * 2);
        expect(store.asks, hasLength(1));
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
        store.asks.single.answer.complete([tap]);
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
}

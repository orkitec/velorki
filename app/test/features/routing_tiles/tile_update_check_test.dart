import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/routing_tiles/application/tile_update_check.dart';
import 'package:velorki/features/routing_tiles/domain/routing_tile.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

final DateTime _monday = DateTime.utc(2026, 9, 14, 8);

RoutingTile _tile(RoutingTileState state) => RoutingTile(
  tile: const TileName(-75, 40),
  bytes: 1,
  updatedAt: DateTime.utc(2026, 9, 1),
  formatVersion: '11.2',
  state: state,
);

class _Harness {
  _Harness({
    required this.prefs,
    List<RoutingTile> tiles = const [],
    bool mirrorDown = false,
    DateTime? now,
  }) : _now = now ?? _monday {
    checker = TileUpdateChecker(
      prefs: prefs,
      tiles: () async => tiles,
      fetch: () async {
        fetches++;
        if (mirrorDown) throw StateError('mirror down');
        return SegmentsManifest.empty;
      },
      apply: (_) async => applied++,
      clock: () => _now,
    );
  }

  static Future<_Harness> create({
    Map<String, Object> initial = const <String, Object>{},
    List<RoutingTile> tiles = const [],
    bool mirrorDown = false,
    DateTime? now,
  }) async {
    SharedPreferences.setMockInitialValues(initial);
    return _Harness(
      prefs: await SharedPreferences.getInstance(),
      tiles: tiles,
      mirrorDown: mirrorDown,
      now: now,
    );
  }

  final SharedPreferences prefs;
  late final TileUpdateChecker checker;
  final DateTime _now;
  int fetches = 0;
  int applied = 0;

  String? get stamp => prefs.getString(tileUpdateCheckKey);
}

void main() {
  test('a phone with a tile asks the mirror and remembers when', () async {
    final h = await _Harness.create(tiles: [_tile(RoutingTileState.ready)]);

    expect(await h.checker.checkIfDue(), isTrue);

    expect(h.fetches, 1);
    expect(h.applied, 1);
    expect(h.stamp, '2026-09-14T08:00:00.000Z');
  });

  test('a phone without tiles never asks', () async {
    final h = await _Harness.create(
      tiles: [_tile(RoutingTileState.downloading)],
    );

    expect(await h.checker.checkIfDue(), isFalse);

    expect(h.fetches, 0);
    expect(h.stamp, isNull);
  });

  test('a check within the week is skipped', () async {
    final h = await _Harness.create(
      initial: {tileUpdateCheckKey: '2026-09-08T08:00:01.000Z'},
      tiles: [_tile(RoutingTileState.ready)],
    );

    expect(await h.checker.checkIfDue(), isFalse);
    expect(h.fetches, 0);
  });

  test('a week later the mirror is asked again', () async {
    final h = await _Harness.create(
      initial: {tileUpdateCheckKey: '2026-09-07T08:00:00.000Z'},
      tiles: [_tile(RoutingTileState.stale)],
    );

    expect(await h.checker.checkIfDue(), isTrue);
    expect(h.fetches, 1);
    expect(h.stamp, '2026-09-14T08:00:00.000Z');
  });

  test('a mirror that cannot be reached is tried again next time', () async {
    final h = await _Harness.create(
      tiles: [_tile(RoutingTileState.ready)],
      mirrorDown: true,
    );

    expect(await h.checker.checkIfDue(), isFalse);

    expect(h.fetches, 1);
    expect(h.applied, 0);
    expect(h.stamp, isNull);
  });

  test('two occasions at once make one check', () async {
    final h = await _Harness.create(tiles: [_tile(RoutingTileState.ready)]);

    final results = await Future.wait([
      h.checker.checkIfDue(),
      h.checker.checkIfDue(),
    ]);

    expect(results, [true, false]);
    expect(h.fetches, 1);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:velorki/core/db/database.dart';
import 'package:velorki/features/routing_tiles/domain/routing_tile.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

RoutingTileRow _row({
  String name = 'E10_N45',
  int bytes = 131072000,
  DateTime? updatedAt,
  String formatVersion = '11.2',
  RoutingTileState state = RoutingTileState.ready,
}) => RoutingTileRow(
  name: name,
  bytes: bytes,
  updatedAt: updatedAt ?? DateTime.utc(2026, 9, 12, 1, 3),
  formatVersion: formatVersion,
  state: state,
);

RoutingTile _tile({
  String name = 'E10_N45',
  int bytes = 131072000,
  DateTime? updatedAt,
  String formatVersion = '11.2',
  RoutingTileState state = RoutingTileState.ready,
}) => RoutingTile.fromRow(
  _row(
    name: name,
    bytes: bytes,
    updatedAt: updatedAt,
    formatVersion: formatVersion,
    state: state,
  ),
);

void main() {
  group('reading a database row', () {
    test('parses the stored name into the tile it stands for', () {
      final tile = RoutingTile.fromRow(_row(name: 'W5_S10', bytes: 42));

      expect(tile.tile, const TileName(-5, -10));
      expect(tile.name, 'W5_S10');
      expect(tile.tile.fileName, 'W5_S10.rd5');
      expect(tile.bytes, 42);
      expect(tile.updatedAt, DateTime.utc(2026, 9, 12, 1, 3));
      expect(tile.formatVersion, '11.2');
      expect(tile.state, RoutingTileState.ready);
    });

    test('keeps the name a round trip through the row would give', () {
      expect(_tile(name: 'E0_N0').name, 'E0_N0');
      expect(_tile(name: 'E175_N85').name, 'E175_N85');
      expect(_tile(name: 'W180_S90').name, 'W180_S90');
    });

    test('a row whose name is not a tile is refused', () {
      expect(
        () => RoutingTile.fromRow(_row(name: 'lookups.dat')),
        throwsFormatException,
      );
      // 12 is not a multiple of five, so no mirror ever wrote such a file.
      expect(
        () => RoutingTile.fromRow(_row(name: 'E12_N45')),
        throwsFormatException,
      );
      expect(() => RoutingTile.fromRow(_row(name: '')), throwsFormatException);
    });
  });

  group('what the rider may do with a tile', () {
    test('a ready tile is usable and neither stale nor downloading', () {
      final tile = _tile(state: RoutingTileState.ready);

      expect(tile.isUsable, isTrue);
      expect(tile.isStale, isFalse);
      expect(tile.isDownloading, isFalse);
    });

    test('a stale tile is still usable, it is only out of date', () {
      final tile = _tile(state: RoutingTileState.stale);

      expect(tile.isUsable, isTrue);
      expect(tile.isStale, isTrue);
      expect(tile.isDownloading, isFalse);
    });

    test('a downloading tile is not usable yet', () {
      final tile = _tile(state: RoutingTileState.downloading);

      expect(tile.isUsable, isFalse);
      expect(tile.isStale, isFalse);
      expect(tile.isDownloading, isTrue);
    });

    test('an absent tile is none of the three', () {
      final tile = _tile(state: RoutingTileState.absent);

      expect(tile.isUsable, isFalse);
      expect(tile.isStale, isFalse);
      expect(tile.isDownloading, isFalse);
    });
  });

  group('the area a tile covers', () {
    test('the box runs five degrees north and east of the name', () {
      final bounds = _tile(name: 'E10_N45').tile.bounds;

      expect(bounds.west, 10);
      expect(bounds.south, 45);
      expect(bounds.east, 15);
      expect(bounds.north, 50);
    });

    test('a southern and western tile has negative corners', () {
      final bounds = _tile(name: 'W5_S10').tile.bounds;

      expect(bounds.west, -5);
      expect(bounds.south, -10);
      expect(bounds.east, 0);
      expect(bounds.north, -5);
    });

    test('the tile owns its south-west corner but not its north-east one', () {
      final tile = _tile(name: 'E10_N45').tile;

      expect(tile.contains(const LatLng(45, 10)), isTrue);
      expect(tile.contains(const LatLng(47.5, 12.5)), isTrue);
      expect(tile.contains(const LatLng(50, 10)), isFalse);
      expect(tile.contains(const LatLng(45, 15)), isFalse);
      expect(tile.contains(const LatLng(44.999, 10)), isFalse);
    });

    test('a coordinate in the Alps belongs to the tile of that name', () {
      expect(TileName.fromLatLng(const LatLng(48.14, 11.58)).name, 'E10_N45');
      expect(
        _tile(name: 'E10_N45').tile.contains(const LatLng(48.14, 11.58)),
        isTrue,
      );
    });
  });

  group('copying a tile', () {
    test('only the state changes, everything else is carried over', () {
      final ready = _tile(state: RoutingTileState.ready);

      final stale = ready.copyWith(state: RoutingTileState.stale);

      expect(stale.state, RoutingTileState.stale);
      expect(stale.tile, ready.tile);
      expect(stale.bytes, ready.bytes);
      expect(stale.updatedAt, ready.updatedAt);
      expect(stale.formatVersion, ready.formatVersion);
      expect(stale, isNot(ready));
    });

    test('copying without a state keeps the tile as it was', () {
      final tile = _tile(state: RoutingTileState.downloading);

      expect(tile.copyWith(), tile);
      expect(tile.copyWith().state, RoutingTileState.downloading);
    });
  });

  group('equality', () {
    test('two tiles built from the same row are the same tile', () {
      expect(_tile(), _tile());
      expect(_tile().hashCode, _tile().hashCode);
      expect(<RoutingTile>{_tile(), _tile()}, hasLength(1));
    });

    test('every field is part of the identity', () {
      final tile = _tile();

      expect(tile, isNot(_tile(name: 'E5_N45')));
      expect(tile, isNot(_tile(bytes: 1)));
      expect(tile, isNot(_tile(updatedAt: DateTime.utc(2020))));
      expect(tile, isNot(_tile(formatVersion: '11.1')));
      expect(tile, isNot(_tile(state: RoutingTileState.stale)));
    });

    test('a tile is not equal to something else entirely', () {
      expect(_tile(), isNot(const TileName(10, 45)));
    });
  });

  test('the description names the tile, its size and its state', () {
    expect(
      _tile(
        name: 'E5_N45',
        bytes: 17,
        state: RoutingTileState.downloading,
      ).toString(),
      'RoutingTile(E5_N45, 17 B, downloading)',
    );
  });
}

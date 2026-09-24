import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:velorki/features/map/data/position_provider.dart';
import 'package:velorki/features/map/data/shared_position_source.dart';
import 'package:velorki/features/recording/data/recording_positions.dart';
import 'package:flutter/foundation.dart';

import '../recording/support/fakes.dart';

/// Counts what reaches the platform: one controller per `positions` call,
/// closed when that subscription is cancelled.
class _CountingSource implements PositionSource {
  final List<geo.LocationSettings> opened = <geo.LocationSettings>[];
  final List<StreamController<geo.Position>> controllers =
      <StreamController<geo.Position>>[];
  int cancelled = 0;

  int get live => controllers.length - cancelled;

  @override
  Stream<geo.Position> positions(geo.LocationSettings settings) {
    late final StreamController<geo.Position> controller;
    controller = StreamController<geo.Position>(
      onCancel: () {
        cancelled++;
      },
    );
    opened.add(settings);
    controllers.add(controller);
    return controller.stream;
  }

  void emit(geo.Position position) => controllers.last.add(position);

  @override
  Future<geo.Position?> lastKnown() async => null;

  @override
  Future<geo.Position?> current({
    Duration timeLimit = const Duration(seconds: 10),
    geo.LocationAccuracy accuracy = geo.LocationAccuracy.high,
  }) async => null;
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  final recording = recordingLocationSettings(platform: TargetPlatform.iOS);

  test('two consumers share one platform stream', () async {
    final inner = _CountingSource();
    final source = SharedPositionSource(inner);
    final a = <geo.Position>[];
    final b = <geo.Position>[];

    final subA = source.positions(mapLocationSettings).listen(a.add);
    final subB = source.positions(mapLocationSettings).listen(b.add);
    await _settle();
    inner.emit(fakePosition(seconds: 1, meters: 10));
    await _settle();

    expect(inner.opened, hasLength(1));
    expect(a, hasLength(1));
    expect(b, hasLength(1));

    await subA.cancel();
    await subB.cancel();
    await _settle();
    expect(inner.live, 0);
    expect(source.activeSettings, isNull);
  });

  test('the recorder\'s background-capable settings take over the stream and '
      'the map keeps getting fixes', () async {
    final inner = _CountingSource();
    final source = SharedPositionSource(inner);
    final map = <geo.Position>[];
    final ride = <geo.Position>[];

    final mapSub = source.positions(mapLocationSettings).listen(map.add);
    await _settle();
    expect(inner.opened.single, same(mapLocationSettings));

    final rideSub = source.positions(recording).listen(ride.add);
    await _settle();

    expect(inner.opened, hasLength(2));
    expect(inner.opened.last, same(recording));
    expect(
      inner.live,
      1,
      reason: 'the map stream was closed before the new one opened',
    );
    inner.emit(fakePosition(seconds: 2, meters: 20));
    await _settle();
    expect(map, hasLength(1));
    expect(ride, hasLength(1));

    await rideSub.cancel();
    await _settle();
    expect(inner.opened, hasLength(3));
    expect(inner.opened.last, same(mapLocationSettings));
    expect(inner.live, 1);

    await mapSub.cancel();
    await _settle();
    expect(inner.live, 0);
  });

  test('a weaker request while a stronger one runs changes nothing', () async {
    final inner = _CountingSource();
    final source = SharedPositionSource(inner);

    final rideSub = source.positions(recording).listen((_) {});
    await _settle();
    final mapSub = source.positions(mapLocationSettings).listen((_) {});
    await _settle();

    expect(inner.opened, hasLength(1));
    expect(source.activeSettings, same(recording));

    await mapSub.cancel();
    await rideSub.cancel();
  });

  test('a platform error reaches every consumer', () async {
    final inner = _CountingSource();
    final source = SharedPositionSource(inner);
    Object? seen;

    final sub = source
        .positions(mapLocationSettings)
        .listen((_) {}, onError: (Object e) => seen = e);
    await _settle();
    inner.controllers.last.addError(StateError('gps off'));
    await _settle();

    expect(seen, isA<StateError>());
    await sub.cancel();
  });
}

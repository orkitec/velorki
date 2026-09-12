import 'package:test/test.dart';
import 'package:velorki_brouter/velorki_brouter.dart';
import 'package:velorki_geo/velorki_geo.dart';

void main() {
  const a = LatLng(48.0, 11.0);
  const b = LatLng(48.1, 11.1);

  test('defaults', () {
    const q = RouteQuery(points: [a, b]);
    expect(q.profile, 'trekking');
    expect(q.alternativeIdx, 0);
    expect(q.roundTrip, isFalse);
    expect(q.allowSameWayBack, isTrue);
    expect(q.nogos, isEmpty);
    expect(q.timeout, isNull);
    expect(q.start, a);
  });

  test('value equality covers the lists', () {
    const q1 = RouteQuery(
      points: [a, b],
      nogos: [NoGo(center: a, radiusM: 50)],
    );
    const q2 = RouteQuery(
      points: [a, b],
      nogos: [NoGo(center: a, radiusM: 50)],
    );
    expect(q1, q2);
    expect(q1.hashCode, q2.hashCode);
    expect(q1, isNot(const RouteQuery(points: [a, b])));
    expect(
      q1,
      isNot(
        const RouteQuery(
          points: [b, a],
          nogos: [NoGo(center: a, radiusM: 50)],
        ),
      ),
    );
  });

  test('copyWith replaces one field at a time', () {
    const q = RouteQuery(points: [a, b]);
    expect(q.copyWith(profile: 'mtb').profile, 'mtb');
    expect(q.copyWith(profile: 'mtb').points, q.points);
    expect(q.copyWith(roundTrip: true).roundTrip, isTrue);
    expect(q.copyWith(allowSameWayBack: false).allowSameWayBack, isFalse);
  });

  test('NoGo equality and toString', () {
    expect(
      const NoGo(center: a, radiusM: 50),
      const NoGo(center: a, radiusM: 50),
    );
    expect(
      const NoGo(center: a, radiusM: 50).hashCode,
      const NoGo(center: a, radiusM: 50).hashCode,
    );
    expect(
      const NoGo(center: a, radiusM: 50),
      isNot(const NoGo(center: a, radiusM: 50, weight: 2)),
    );
    expect(const NoGo(center: a, radiusM: 50).toString(), contains('NoGo'));
  });

  test('toString summarises the query', () {
    expect(const RouteQuery(points: [a, b]).toString(), contains('2 pts'));
  });

  test('RoutingException toString names the kind', () {
    expect(
      const RoutingException(
        kind: RoutingErrorKind.noRoute,
        message: 'nope',
      ).toString(),
      'RoutingException(noRoute): nope',
    );
  });
}

import 'package:test/test.dart';
import 'package:velorki_brouter/velorki_brouter.dart';

List<SegmentMessage> table(List<(String tags, double meters)> segments) =>
    SegmentMessage.parseTable([
      SegmentMessage.headerColumns,
      for (final (tags, meters) in segments)
        [
          '11500000',
          '48100000',
          '500',
          '${meters.round()}',
          '1000',
          '0',
          '0',
          '0',
          '0',
          tags,
          '',
          '60',
          '1000',
        ],
    ]);

void main() {
  test('an empty table or a zero length gives the empty stats', () {
    expect(SurfaceStats.fromMessages(const [], 1000), SurfaceStats.empty);
    expect(
      SurfaceStats.fromMessages(table([('highway=residential', 100)]), 0),
      SurfaceStats.empty,
    );
    expect(
      SurfaceStats.fromMessages(table([('highway=residential', 100)]), -5),
      SurfaceStats.empty,
    );
  });

  test('surface=* decides, whatever the highway is', () {
    final s = SurfaceStats.fromMessages(
      table([
        ('highway=track surface=asphalt', 400),
        ('highway=cycleway surface=gravel', 600),
      ]),
      1000,
    );
    expect(s.pavedShare, closeTo(0.4, 1e-12));
    expect(s.unpavedShare, closeTo(0.6, 1e-12));
    expect(s.unknownShare, 0);
  });

  test('track and path without a surface tag count as unpaved', () {
    final s = SurfaceStats.fromMessages(
      table([
        ('highway=track', 300),
        ('highway=path', 200),
        ('highway=residential', 500),
      ]),
      1000,
    );
    expect(s.unpavedShare, closeTo(0.5, 1e-12));
    expect(s.unknownShare, closeTo(0.5, 1e-12));
    expect(s.pavedShare, 0);
  });

  test('an unknown surface value is unknown, not a guess', () {
    final s = SurfaceStats.fromMessages(
      table([('highway=track surface=moon_dust', 1000)]),
      1000,
    );
    expect(s.unknownShare, 1);
    expect(s.unpavedShare, 0);
  });

  test('cycleway counts highway=cycleway and cycleway=* infrastructure', () {
    final s = SurfaceStats.fromMessages(
      table([
        ('highway=cycleway surface=asphalt', 200),
        ('highway=secondary cycleway=track surface=asphalt', 300),
        ('highway=secondary cycleway:right=lane surface=asphalt', 100),
        ('highway=secondary cycleway=no surface=asphalt', 200),
        ('highway=secondary cycleway=separate surface=asphalt', 200),
      ]),
      1000,
    );
    expect(s.cyclewayShare, closeTo(0.6, 1e-12));
    expect(s.pavedShare, closeTo(1.0, 1e-12));
  });

  test('busy counts primary, trunk and their links', () {
    final s = SurfaceStats.fromMessages(
      table([
        ('highway=primary surface=asphalt', 200),
        ('highway=trunk surface=asphalt', 200),
        ('highway=primary_link surface=asphalt', 100),
        ('highway=trunk_link surface=asphalt', 100),
        ('highway=secondary surface=asphalt', 400),
      ]),
      1000,
    );
    expect(s.busyShare, closeTo(0.6, 1e-12));
  });

  test('shares stay relative to the given total when messages fall short', () {
    final s = SurfaceStats.fromMessages(
      table([('highway=residential surface=asphalt', 500)]),
      2000,
    );
    expect(s.pavedShare, closeTo(0.25, 1e-12));
    expect(s.coveredLengthM, 500);
    expect(s.totalLengthM, 2000);
  });

  test('zero-length segments are skipped', () {
    final s = SurfaceStats.fromMessages(
      table([
        ('highway=residential surface=asphalt', 0),
        ('highway=track surface=gravel', 1000),
      ]),
      1000,
    );
    expect(s.pavedShare, 0);
    expect(s.unpavedShare, closeTo(1, 1e-12));
    expect(s.coveredLengthM, 1000);
  });

  test('equality and hashCode', () {
    final a = SurfaceStats.fromMessages(
      table([('highway=residential surface=asphalt', 100)]),
      100,
    );
    final b = SurfaceStats.fromMessages(
      table([('highway=residential surface=asphalt', 100)]),
      100,
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(SurfaceStats.empty));
  });
}

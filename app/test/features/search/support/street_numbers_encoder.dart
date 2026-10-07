import 'dart:typed_data';

/// `street_numbers.data` for [odd] and [even], each a list of
/// `(number, lat, lon)` in ascending number order: the builder's format,
/// written here so tests can make files without the Python builder.
Uint8List encodeStreetNumbers(
  List<(int, double, double)> odd,
  List<(int, double, double)> even,
) {
  final out = BytesBuilder()..addByte(1);
  void varint(int value) {
    var v = value;
    while (v >= 0x80) {
      out.addByte((v & 0x7f) | 0x80);
      v >>= 7;
    }
    out.addByte(v);
  }

  void signed(int value) => varint((value << 1) ^ (value >> 63));

  var lat = 0;
  var lon = 0;
  for (final run in <List<(int, double, double)>>[odd, even]) {
    varint(run.length);
    var number = 0;
    for (final (n, la, lo) in run) {
      final qLat = (la * 1e5).round();
      final qLon = (lo * 1e5).round();
      varint(n - number);
      signed(qLat - lat);
      signed(qLon - lon);
      number = n;
      lat = qLat;
      lon = qLon;
    }
  }
  return out.toBytes();
}

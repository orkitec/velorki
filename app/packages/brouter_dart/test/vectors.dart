// Helpers shared by the vector replay tests.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:brouter_dart/brouter_dart.dart';
import 'package:test/test.dart';

/// Loads `test/vectors/<name>` (the tests run with the package as cwd).
Map<String, dynamic> loadVector(String name) {
  final f = File('test/vectors/$name');
  return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
}

Uint8List loadBinary(String name) =>
    File('test/vectors/$name').readAsBytesSync();

Uint8List unhex(String h) {
  final b = Uint8List(h.length ~/ 2);
  for (var i = 0; i < b.length; i++) {
    b[i] = int.parse(h.substring(2 * i, 2 * i + 2), radix: 16);
  }
  return b;
}

String hex(Uint8List ab, [int? len]) {
  final sb = StringBuffer();
  for (var i = 0; i < (len ?? ab.length); i++) {
    sb.write(ab[i].toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

Uint8List? unhexOrNull(Object? h) => h == null ? null : unhex(h as String);

/// `bytes` zero-padded by `n`, like the Java generator decodes.
Uint8List padded(Uint8List bytes, int n) {
  final p = Uint8List(bytes.length + n);
  p.setRange(0, bytes.length, bytes);
  return p;
}

/// The Java vectors print doubles as `{"str": Double.toString, "bits": hex}`;
/// the bit pattern is what is compared.
int bitsOf(Object? d) =>
    hexToLong((d as Map<String, dynamic>)['bits'] as String);

/// `Long.toHexString` output (up to 16 hex digits, no sign) back to a Dart int.
int hexToLong(String h) {
  final s = h.padLeft(16, '0');
  final hi = int.parse(s.substring(0, 8), radix: 16);
  final lo = int.parse(s.substring(8), radix: 16);
  return (hi << 32) | lo;
}

/// Compares two op-result sequences and names the first differing op.
void expectSeq(
  List<Object?> actual,
  List<dynamic> expected,
  List<List<dynamic>> ops,
) {
  final n = actual.length < expected.length ? actual.length : expected.length;
  for (var i = 0; i < n; i++) {
    if (!_deepEq(actual[i], expected[i])) {
      throw TestFailure(
        'result $i of op ${ops[i]}: got ${actual[i]}, expected ${expected[i]}',
      );
    }
  }
  if (actual.length != expected.length) {
    throw TestFailure('${actual.length} results, expected ${expected.length}');
  }
}

bool _deepEq(Object? a, Object? b) {
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEq(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

double doubleOf(Object? d) => longBitsToDouble(bitsOf(d));

/// A description of a double mismatch that shows both representations.
String describeDouble(double v) =>
    '${v.toString()} (0x${doubleToRawLongBits(v).toUnsigned(64).toRadixString(16)})';

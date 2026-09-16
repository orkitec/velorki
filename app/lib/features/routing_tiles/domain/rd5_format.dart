import 'package:flutter/foundation.dart';

/// The rd5 tile format, identified by the lookup-table version pair that
/// `lookups.dat` declares (`---lookupversion:11`, `---minorversion:2`).
///
/// A tile is written with the table its builder had. The engine refuses a
/// tile whose major version differs from its own table, and a tile with a
/// newer minor version carries tag values the engine's table does not know,
/// so it must not be read either. Older tiles are fine: the table only grows.
@immutable
class Rd5Format {
  /// Creates a format version.
  const Rd5Format(this.major, this.minor);

  /// Parses `"11.2"`; `null` for anything else.
  static Rd5Format? parse(String? text) {
    if (text == null) return null;
    final parts = text.trim().split('.');
    if (parts.length != 2) return null;
    final major = int.tryParse(parts[0]);
    final minor = int.tryParse(parts[1]);
    if (major == null || minor == null) return null;
    return Rd5Format(major, minor);
  }

  /// Reads the version pair from the header lines of a `lookups.dat`.
  static Rd5Format? fromLookups(String lookupsDat) {
    int? major;
    int? minor;
    for (final line in lookupsDat.split('\n')) {
      if (line.startsWith('---lookupversion:')) {
        major = int.tryParse(line.substring(17).trim());
      } else if (line.startsWith('---minorversion:')) {
        minor = int.tryParse(line.substring(16).trim());
      }
      if (major != null && minor != null) return Rd5Format(major, minor);
      if (!line.startsWith('---')) break;
    }
    return null;
  }

  /// `---lookupversion`.
  final int major;

  /// `---minorversion`.
  final int minor;

  /// Whether a tile written in [tile] can be read with this table.
  bool canRead(Rd5Format tile) => tile.major == major && tile.minor <= minor;

  /// [canRead] for a version string as the manifest or the tile table carry
  /// it. An absent or unparseable version is let through: the engine still
  /// checks the major version in the file header, and nothing more is known.
  bool canReadVersion(String? version) {
    if (version == null || version.trim().isEmpty) return true;
    final parsed = parse(version);
    return parsed == null || canRead(parsed);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Rd5Format && other.major == major && other.minor == minor;

  @override
  int get hashCode => Object.hash(major, minor);

  @override
  String toString() => '$major.$minor';
}

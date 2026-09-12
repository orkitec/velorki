import 'package:velorki_geo/velorki_geo.dart';

/// One row of BRouter's `messages` table: a run of consecutive route nodes
/// that share the same OSM way tags.
///
/// BRouter emits the table as an array of string arrays whose first row is the
/// header
/// `Longitude Latitude Elevation Distance CostPerKm ElevCost TurnCost
/// NodeCost InitialCost WayTags NodeTags Time Energy`
/// (tab separated upstream, one JSON array element per column here). The
/// longitude and latitude columns are integers in **microdegrees**, the
/// elevation is metres, the distance is metres, the time is seconds and the
/// energy is joules.
class SegmentMessage {
  /// Creates a segment message.
  const SegmentMessage({
    required this.position,
    required this.elevationM,
    required this.distanceM,
    required this.costPerKm,
    required this.elevCost,
    required this.turnCost,
    required this.nodeCost,
    required this.initialCost,
    required this.wayTags,
    required this.nodeTags,
    required this.timeS,
    required this.energyJ,
    this.raw = const <String, String>{},
  });

  /// The column names BRouter writes in the header row.
  static const List<String> headerColumns = <String>[
    'Longitude',
    'Latitude',
    'Elevation',
    'Distance',
    'CostPerKm',
    'ElevCost',
    'TurnCost',
    'NodeCost',
    'InitialCost',
    'WayTags',
    'NodeTags',
    'Time',
    'Energy',
  ];

  /// End position of the segment.
  final LatLng position;

  /// Elevation at [position] in metres.
  final double elevationM;

  /// Length of the segment in metres.
  final double distanceM;

  /// Profile cost per kilometre, scaled by 1000 by BRouter.
  final int costPerKm;

  /// Elevation part of the cost.
  final int elevCost;

  /// Turn part of the cost.
  final int turnCost;

  /// Node part of the cost.
  final int nodeCost;

  /// Initial (way-entry) part of the cost.
  final int initialCost;

  /// OSM tags of the way this segment runs on, e.g.
  /// `{highway: residential, surface: asphalt}`.
  final Map<String, String> wayTags;

  /// OSM tags of the node at the end of the segment, usually empty.
  final Map<String, String> nodeTags;

  /// Travel time for the segment in seconds.
  final double timeS;

  /// Energy for the segment in joules.
  final double energyJ;

  /// The row as parsed, keyed by header column, for anything not modelled.
  final Map<String, String> raw;

  /// The value of `highway=*`, or `null`.
  String? get highway => wayTags['highway'];

  /// The value of `surface=*`, or `null`.
  String? get surface => wayTags['surface'];

  /// Parses BRouter's whole `messages` array, header row included.
  ///
  /// Rows shorter than the header are padded with empty strings; unknown extra
  /// columns land in [raw]. An empty or header-only table yields an empty
  /// list. Throws [FormatException] when the first row is not a header.
  static List<SegmentMessage> parseTable(List<dynamic> messages) {
    if (messages.isEmpty) return const <SegmentMessage>[];
    final header = _row(messages.first);
    if (!header.contains('Longitude') || !header.contains('WayTags')) {
      throw FormatException(
        'messages table does not start with a header row: $header',
      );
    }
    final out = <SegmentMessage>[];
    for (var i = 1; i < messages.length; i++) {
      out.add(fromRow(_row(messages[i]), header));
    }
    return out;
  }

  /// Parses one data row against a [header] row.
  static SegmentMessage fromRow(List<String> row, List<String> header) {
    final byName = <String, String>{};
    for (var i = 0; i < header.length; i++) {
      byName[header[i]] = i < row.length ? row[i] : '';
    }
    final lonMicro = _int(byName['Longitude']);
    final latMicro = _int(byName['Latitude']);
    return SegmentMessage(
      position: LatLng(latMicro / 1e6, lonMicro / 1e6),
      elevationM: _double(byName['Elevation']),
      distanceM: _double(byName['Distance']),
      costPerKm: _int(byName['CostPerKm']),
      elevCost: _int(byName['ElevCost']),
      turnCost: _int(byName['TurnCost']),
      nodeCost: _int(byName['NodeCost']),
      initialCost: _int(byName['InitialCost']),
      wayTags: parseTags(byName['WayTags']),
      nodeTags: parseTags(byName['NodeTags']),
      timeS: _double(byName['Time']),
      energyJ: _double(byName['Energy']),
      raw: byName,
    );
  }

  /// Splits BRouter's tag string (`key=value key=value`) into a map.
  ///
  /// Values may themselves contain `=`, so only the first one separates; a
  /// bare token without `=` maps to the empty string; empty input gives an
  /// empty map.
  static Map<String, String> parseTags(String? s) {
    if (s == null) return const <String, String>{};
    final trimmed = s.trim();
    if (trimmed.isEmpty) return const <String, String>{};
    final out = <String, String>{};
    for (final token in trimmed.split(RegExp(r'\s+'))) {
      if (token.isEmpty) continue;
      final eq = token.indexOf('=');
      if (eq < 0) {
        out[token] = '';
      } else {
        out[token.substring(0, eq)] = token.substring(eq + 1);
      }
    }
    return out;
  }

  static List<String> _row(dynamic v) => v is List
      ? v.map((e) => e == null ? '' : e.toString()).toList(growable: false)
      : throw FormatException('messages row is not a list: $v');

  static int _int(String? s) =>
      s == null || s.isEmpty ? 0 : (int.tryParse(s.trim()) ?? 0);

  static double _double(String? s) =>
      s == null || s.isEmpty ? 0.0 : (double.tryParse(s.trim()) ?? 0.0);

  @override
  String toString() => 'SegmentMessage($position, ${distanceM}m, $wayTags)';
}

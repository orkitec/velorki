// Port of btools.router.FormatCsv (BRouter v1.7.10).

import 'formatter.dart';
import 'osm_track.dart';
import 'routing_context.dart';

class FormatCsv extends Formatter {
  FormatCsv(RoutingContext super.rc);

  @override
  String format(OsmTrack t) {
    try {
      final sw = StringBuffer();
      writeMessages(sw, t);
      return sw.toString();
    } catch (ex) {
      return 'Error: $ex';
    }
  }

  void writeMessages(StringBuffer? bw, OsmTrack t) {
    _dumpLine(bw, Formatter.messagesHeader);
    for (final m in t.aggregateMessages()) {
      _dumpLine(bw, m);
    }
  }

  /// A null writer prints to stdout upstream; the port collects into
  /// [stdoutLines] instead.
  static final List<String> stdoutLines = <String>[];

  void _dumpLine(StringBuffer? bw, String s) {
    if (bw == null) {
      stdoutLines.add(s);
    } else {
      bw.write(s);
      bw.write('\n');
    }
  }
}

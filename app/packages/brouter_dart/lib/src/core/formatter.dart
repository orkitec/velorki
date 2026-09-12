// Port of btools.router.Formatter (BRouter v1.7.10).

import 'dart:io';

import '../jvm.dart';
import 'osm_track.dart';
import 'routing_context.dart';
import 'voice_hint.dart';

/// A `StringBuilder` stand-in with the two mutations the formatters use.
class JStringBuilder {
  final StringBuffer _sb = StringBuffer();

  void append(Object? o) => _sb.write(o);

  /// `sb.deleteCharAt(sb.lastIndexOf(","))`
  void deleteLastComma() {
    final s = _sb.toString();
    final idx = s.lastIndexOf(',');
    _sb.clear();
    _sb.write(s.substring(0, idx));
    _sb.write(s.substring(idx + 1));
  }

  int get length => _sb.length;

  @override
  String toString() => _sb.toString();
}

abstract class Formatter {
  static const String messagesHeader = OsmTrack.messagesHeader;

  RoutingContext? rc;

  Formatter([this.rc]);

  /// writes the track in gpx-format to a file
  void write(String filename, OsmTrack t) {
    File(filename).writeAsStringSync(format(t));
  }

  OsmTrack? read(String filename) {
    return null;
  }

  /// writes the track in a selected output format to a string
  String format(OsmTrack t);

  static String formatILon(int ilon) {
    return _formatPos(ilon - 180000000);
  }

  static String formatILat(int ilat) {
    return _formatPos(ilat - 90000000);
  }

  static String _formatPos(int p) {
    final negative = p < 0;
    if (negative) p = -p;
    final ac = List<int>.filled(12, 0);
    var i = 11;
    while (p != 0 || i > 3) {
      ac[i--] = 0x30 + (p % 10);
      p ~/= 10;
      if (i == 5) ac[i--] = 0x2e; // '.'
    }
    if (negative) ac[i--] = 0x2d; // '-'
    return String.fromCharCodes(ac, i + 1, 12);
  }

  static String getFormattedTime2(int s) {
    var seconds = d2i(s + 0.5);
    final hours = seconds ~/ 3600;
    final minutes = (seconds - hours * 3600) ~/ 60;
    seconds = seconds - hours * 3600 - minutes * 60;
    var time = '';
    if (hours != 0) time = '${hours}h ';
    if (minutes != 0) time = '$time${minutes}m ';
    if (seconds != 0) time = '$time${seconds}s';
    return time;
  }

  static String getFormattedEnergy(int energy) {
    return '${_format1(energy / 3600000.0)}kwh';
  }

  static String _format1(double n) {
    final s = '${d2l(n * 10 + 0.5)}';
    final len = s.length;
    return '${s.substring(0, len - 1)}.${s[len - 1]}';
  }

  static const String dateformat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";

  /// `SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)` in UTC of
  /// `new Date((long) (time * 1000f))`.
  static String getFormattedTime3(double time) {
    final ms = d2l(f32(time * 1000));
    final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    String p(int v, int w) => v.toString().padLeft(w, '0');
    return '${p(d.year, 4)}-${p(d.month, 2)}-${p(d.day, 2)}T${p(d.hour, 2)}:${p(d.minute, 2)}:${p(d.second, 2)}.${p(d.millisecond, 3)}Z';
  }

  int getJsonCommandIndex(int cmd, int timode) {
    switch (cmd) {
      case VoiceHint.tlu:
        return 10;
      case VoiceHint.tu:
        return 15;
      case VoiceHint.tshl:
        return 4;
      case VoiceHint.tl:
        return 2;
      case VoiceHint.tsll:
        return 3;
      case VoiceHint.kl:
        return 8;
      case VoiceHint.c:
        return 1;
      case VoiceHint.kr:
        return 9;
      case VoiceHint.tslr:
        return 6;
      case VoiceHint.tr:
        return 5;
      case VoiceHint.tshr:
        return 7;
      case VoiceHint.tru:
        return 11;
      case VoiceHint.rndb:
        return 13;
      case VoiceHint.rnlb:
        return 14;
      case VoiceHint.bl:
        return 16;
      case VoiceHint.el:
        return timode == 2 || timode == 9 ? 17 : 8;
      case VoiceHint.er:
        return timode == 2 || timode == 9 ? 18 : 9;
      case VoiceHint.offr:
        return 12;
      default:
        throw ArgumentError('unknown command: $cmd');
    }
  }

  /// used by comment style, osmand style
  String getCommandString(int cmd, int roundaboutExit, int timode) {
    switch (cmd) {
      case VoiceHint.tlu:
        return 'TU'; // should be changed to TLU when osmand uses new voice hint constants
      case VoiceHint.tu:
        return 'TU';
      case VoiceHint.tshl:
        return 'TSHL';
      case VoiceHint.tl:
        return 'TL';
      case VoiceHint.tsll:
        return 'TSLL';
      case VoiceHint.kl:
        return 'KL';
      case VoiceHint.c:
        return 'C';
      case VoiceHint.kr:
        return 'KR';
      case VoiceHint.tslr:
        return 'TSLR';
      case VoiceHint.tr:
        return 'TR';
      case VoiceHint.tshr:
        return 'TSHR';
      case VoiceHint.tru:
        return 'TRU';
      case VoiceHint.rndb:
        return 'RNDB$roundaboutExit';
      case VoiceHint.rnlb:
        return 'RNLB${-roundaboutExit}';
      case VoiceHint.bl:
        return 'BL';
      case VoiceHint.el:
        return timode == 2 || timode == 9 ? 'EL' : 'KL';
      case VoiceHint.er:
        return timode == 2 || timode == 9 ? 'ER' : 'KR';
      case VoiceHint.offr:
        return 'OFFR';
      case VoiceHint.end:
        return 'END';
      default:
        throw ArgumentError('unknown command: $cmd');
    }
  }

  /// used by trkpt/sym style
  String getCommandStringXX(int c, int roundaboutExit, int timode) {
    switch (c) {
      case VoiceHint.tlu:
        return 'TLU';
      case VoiceHint.tu:
        return 'TU';
      case VoiceHint.tshl:
        return 'TSHL';
      case VoiceHint.tl:
        return 'TL';
      case VoiceHint.tsll:
        return 'TSLL';
      case VoiceHint.kl:
        return 'KL';
      case VoiceHint.c:
        return 'C';
      case VoiceHint.kr:
        return 'KR';
      case VoiceHint.tslr:
        return 'TSLR';
      case VoiceHint.tr:
        return 'TR';
      case VoiceHint.tshr:
        return 'TSHR';
      case VoiceHint.tru:
        return 'TRU';
      case VoiceHint.rndb:
        return 'RNDB$roundaboutExit';
      case VoiceHint.rnlb:
        return 'RNLB${-roundaboutExit}';
      case VoiceHint.bl:
        return 'BL';
      case VoiceHint.el:
        return timode == 2 || timode == 9 ? 'EL' : 'KL';
      case VoiceHint.er:
        return timode == 2 || timode == 9 ? 'ER' : 'KR';
      case VoiceHint.offr:
        return 'OFFR';
      default:
        return 'unknown command: $c';
    }
  }

  /// used by gpsies style
  String getSymbolString(int cmd, int roundaboutExit, int timode) {
    switch (cmd) {
      case VoiceHint.tlu:
      case VoiceHint.tru:
      case VoiceHint.tu:
        return 'TU';
      case VoiceHint.tshl:
        return 'TSHL';
      case VoiceHint.tl:
        return 'Left';
      case VoiceHint.tsll:
        return 'TSLL';
      case VoiceHint.kl:
        return 'TSLL'; // ?
      case VoiceHint.c:
        return 'Straight';
      case VoiceHint.kr:
        return 'TSLR'; // ?
      case VoiceHint.tslr:
        return 'TSLR';
      case VoiceHint.tr:
        return 'Right';
      case VoiceHint.tshr:
        return 'TSHR';
      case VoiceHint.rndb:
        return 'RNDB$roundaboutExit';
      case VoiceHint.rnlb:
        return 'RNLB${-roundaboutExit}';
      case VoiceHint.bl:
        return 'BL';
      case VoiceHint.el:
        return timode == 2 || timode == 9 ? 'EL' : 'KL';
      case VoiceHint.er:
        return timode == 2 || timode == 9 ? 'ER' : 'KR';
      case VoiceHint.offr:
        return 'OFFR';
      default:
        throw ArgumentError('unknown command: $cmd');
    }
  }

  /// used by new locus trkpt style
  String getLocusSymbolString(int cmd, int roundaboutExit) {
    switch (cmd) {
      case VoiceHint.tlu:
        return 'u-turn_left';
      case VoiceHint.tu:
        return 'u-turn';
      case VoiceHint.tshl:
        return 'left_sharp';
      case VoiceHint.tl:
        return 'left';
      case VoiceHint.tsll:
        return 'left_slight';
      case VoiceHint.kl:
        return 'stay_left'; // ?
      case VoiceHint.c:
        return 'straight';
      case VoiceHint.kr:
        return 'stay_right'; // ?
      case VoiceHint.tslr:
        return 'right_slight';
      case VoiceHint.tr:
        return 'right';
      case VoiceHint.tshr:
        return 'right_sharp';
      case VoiceHint.tru:
        return 'u-turn_right';
      case VoiceHint.rndb:
        return 'roundabout_e$roundaboutExit';
      case VoiceHint.rnlb:
        return 'roundabout_e${-roundaboutExit}';
      case VoiceHint.bl:
        return 'beeline';
      case VoiceHint.el:
        return 'exit_left';
      case VoiceHint.er:
        return 'exit_right';
      default:
        throw ArgumentError('unknown command: $cmd');
    }
  }

  /// used by osmand style
  String getMessageString(int cmd, int roundaboutExit, int timode) {
    switch (cmd) {
      case VoiceHint.tlu:
        return 'u-turn'; // should be changed to u-turn-left when osmand uses new voice hint constants
      case VoiceHint.tu:
        return 'u-turn';
      case VoiceHint.tshl:
        return 'sharp left';
      case VoiceHint.tl:
        return 'left';
      case VoiceHint.tsll:
        return 'slight left';
      case VoiceHint.kl:
        return 'keep left';
      case VoiceHint.c:
        return 'straight';
      case VoiceHint.kr:
        return 'keep right';
      case VoiceHint.tslr:
        return 'slight right';
      case VoiceHint.tr:
        return 'right';
      case VoiceHint.tshr:
        return 'sharp right';
      case VoiceHint.tru:
        return 'u-turn'; // should be changed to u-turn-right when osmand uses new voice hint constants
      case VoiceHint.rndb:
        return 'Take exit $roundaboutExit';
      case VoiceHint.rnlb:
        return 'Take exit ${-roundaboutExit}';
      case VoiceHint.el:
        return timode == 2 || timode == 9 ? 'exit left' : 'keep left';
      case VoiceHint.er:
        return timode == 2 || timode == 9 ? 'exit right' : 'keep right';
      default:
        throw ArgumentError('unknown command: $cmd');
    }
  }

  /// used by old locus style
  int getLocusAction(int cmd, int roundaboutExit) {
    switch (cmd) {
      case VoiceHint.tlu:
        return 13;
      case VoiceHint.tu:
        return 12;
      case VoiceHint.tshl:
        return 5;
      case VoiceHint.tl:
        return 4;
      case VoiceHint.tsll:
        return 3;
      case VoiceHint.kl:
        return 9; // ?
      case VoiceHint.c:
        return 1;
      case VoiceHint.kr:
        return 10; // ?
      case VoiceHint.tslr:
        return 6;
      case VoiceHint.tr:
        return 7;
      case VoiceHint.tshr:
        return 8;
      case VoiceHint.tru:
        return 14;
      case VoiceHint.rndb:
        return 26 + roundaboutExit;
      case VoiceHint.rnlb:
        return 26 - roundaboutExit;
      case VoiceHint.el:
        return 9;
      case VoiceHint.er:
        return 10;
      default:
        throw ArgumentError('unknown command: $cmd');
    }
  }

  /// used by orux style
  int getOruxAction(int cmd, int roundaboutExit) {
    switch (cmd) {
      case VoiceHint.tlu:
      case VoiceHint.tu:
      case VoiceHint.tru:
        return 1003;
      case VoiceHint.tshl:
        return 1019;
      case VoiceHint.tl:
        return 1000;
      case VoiceHint.tsll:
        return 1017;
      case VoiceHint.kl:
        return 1015; // ?
      case VoiceHint.c:
        return 1002;
      case VoiceHint.kr:
        return 1014; // ?
      case VoiceHint.tslr:
        return 1016;
      case VoiceHint.tr:
        return 1001;
      case VoiceHint.tshr:
        return 1018;
      case VoiceHint.rndb:
      case VoiceHint.rnlb:
        return 1008 + roundaboutExit;
      case VoiceHint.el:
        return 1015;
      case VoiceHint.er:
        return 1014;
      default:
        throw ArgumentError('unknown command: $cmd');
    }
  }

  /// used by cruiser, equivalent to getCommandString() - osmand style - when osmand changes the voice hint  constants
  String getCruiserCommandString(int cmd, int roundaboutExit) {
    switch (cmd) {
      case VoiceHint.tlu:
        return 'TLU';
      case VoiceHint.tu:
        return 'TU';
      case VoiceHint.tshl:
        return 'TSHL';
      case VoiceHint.tl:
        return 'TL';
      case VoiceHint.tsll:
        return 'TSLL';
      case VoiceHint.kl:
        return 'KL';
      case VoiceHint.c:
        return 'C';
      case VoiceHint.kr:
        return 'KR';
      case VoiceHint.tslr:
        return 'TSLR';
      case VoiceHint.tr:
        return 'TR';
      case VoiceHint.tshr:
        return 'TSHR';
      case VoiceHint.tru:
        return 'TRU';
      case VoiceHint.rndb:
        return 'RNDB$roundaboutExit';
      case VoiceHint.rnlb:
        return 'RNLB${-roundaboutExit}';
      case VoiceHint.bl:
        return 'BL';
      case VoiceHint.el:
        return 'EL';
      case VoiceHint.er:
        return 'ER';
      case VoiceHint.offr:
        return 'OFFR';
      default:
        throw ArgumentError('unknown command: $cmd');
    }
  }

  /// used by cruiser, equivalent to getMessageString() - osmand style - when osmand changes the voice hint  constants
  String getCruiserMessageString(int cmd, int roundaboutExit) {
    switch (cmd) {
      case VoiceHint.tlu:
        return 'u-turn left';
      case VoiceHint.tu:
        return 'u-turn';
      case VoiceHint.tshl:
        return 'sharp left';
      case VoiceHint.tl:
        return 'left';
      case VoiceHint.tsll:
        return 'slight left';
      case VoiceHint.kl:
        return 'keep left';
      case VoiceHint.c:
        return 'straight';
      case VoiceHint.kr:
        return 'keep right';
      case VoiceHint.tslr:
        return 'slight right';
      case VoiceHint.tr:
        return 'right';
      case VoiceHint.tshr:
        return 'sharp right';
      case VoiceHint.tru:
        return 'u-turn right';
      case VoiceHint.rndb:
        return 'take exit $roundaboutExit';
      case VoiceHint.rnlb:
        return 'take exit ${-roundaboutExit}';
      case VoiceHint.bl:
        return 'beeline';
      case VoiceHint.el:
        return 'exit left';
      case VoiceHint.er:
        return 'exit right';
      case VoiceHint.offr:
        return 'offroad';
      default:
        throw ArgumentError('unknown command: $cmd');
    }
  }
}

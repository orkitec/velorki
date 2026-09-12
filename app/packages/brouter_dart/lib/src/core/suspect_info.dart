// Port of btools.router.SuspectInfo (BRouter v1.7.10).

class SuspectInfo {
  static const int triggerDeadEnd = 1;
  static const int triggerDeadStart = 2;
  static const int triggerNodeBlock = 4;
  static const int triggerBadAccess = 8;
  static const int triggerUnkAccess = 16;
  static const int triggerSharpExit = 32;
  static const int triggerSharpEntry = 64;
  static const int triggerSharpLink = 128;
  static const int triggerBadTr = 256;

  int prio = 0;
  int triggers = 0;

  static void addSuspect(
    Map<int, SuspectInfo> map,
    int id,
    int prio,
    int trigger,
  ) {
    var info = map[id];
    if (info == null) {
      info = SuspectInfo();
      map[id] = info;
    }
    info.prio = info.prio > prio ? info.prio : prio;
    info.triggers |= trigger;
  }

  static SuspectInfo addTrigger(SuspectInfo? old, int prio, int trigger) {
    old ??= SuspectInfo();
    old.prio = old.prio > prio ? old.prio : prio;
    old.triggers |= trigger;
    return old;
  }

  static String getTriggerText(int triggers) {
    final sb = StringBuffer();
    _addText(sb, 'dead-end', triggers, triggerDeadEnd);
    _addText(sb, 'dead-start', triggers, triggerDeadStart);
    _addText(sb, 'node-block', triggers, triggerNodeBlock);
    _addText(sb, 'bad-access', triggers, triggerBadAccess);
    _addText(sb, 'unkown-access', triggers, triggerUnkAccess);
    _addText(sb, 'sharp-exit', triggers, triggerSharpExit);
    _addText(sb, 'sharp-entry', triggers, triggerSharpEntry);
    _addText(sb, 'sharp-link', triggers, triggerSharpLink);
    _addText(sb, 'bad-tr', triggers, triggerBadTr);
    return sb.toString();
  }

  static void _addText(StringBuffer sb, String text, int mask, int bit) {
    if ((bit & mask) == 0) return;
    if (sb.length > 0) sb.write(',');
    sb.write(text);
  }
}

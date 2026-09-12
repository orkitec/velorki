// Oracle dump tool for the Velorki brouter_dart port.
//
// Single source file, compiled with `javac -cp <brouter-all.jar>`; it uses only
// public upstream API of BRouter 1.7.10.
//
//   dump-microcache <tile.rd5> <lon> <lat> [--profile <file.brf>] [--geometry]
//                                           [--limit <n>]
//       Open the rd5 through btools.mapaccess.PhysicalFile / OsmFile, decode the
//       one micro-cache that covers the given position and print every node in
//       it with its links, way tag strings and node tag strings as JSON.
//
//   eval-profile <profile.brf> <tagsfile> [--lookups <lookups.dat>]
//       Build a btools.expressions.BExpressionContextWay from lookups.dat plus
//       the profile, then evaluate every line of the tags file
//       ("highway=residential surface=asphalt ...") and print all cost
//       variables the profile produces, forward and reverse, as JSON.
//
// Everything is written to stdout as one JSON document; diagnostics go to stderr.

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import btools.codec.DataBuffers;
import btools.codec.MicroCache;
import btools.expressions.BExpressionContextWay;
import btools.expressions.BExpressionMetaData;
import btools.mapaccess.GeometryDecoder;
import btools.mapaccess.OsmFile;
import btools.mapaccess.OsmLink;
import btools.mapaccess.OsmNode;
import btools.mapaccess.OsmNodesMap;
import btools.mapaccess.OsmTransferNode;
import btools.mapaccess.PhysicalFile;
import btools.mapaccess.TurnRestriction;

public class Dump {

  // ------------------------------------------------------------------ main --

  public static void main(String[] args) throws Exception {
    if (args.length == 0) {
      usage();
      System.exit(2);
    }
    String cmd = args[0];
    if ("dump-microcache".equals(cmd)) {
      dumpMicroCache(args);
    } else if ("eval-profile".equals(cmd)) {
      evalProfile(args);
    } else {
      usage();
      System.exit(2);
    }
  }

  private static void usage() {
    System.err.println("usage:");
    System.err.println("  Dump dump-microcache <tile.rd5> <lon> <lat> [--profile <f.brf>] [--geometry] [--limit <n>]");
    System.err.println("  Dump eval-profile <profile.brf> <tagsfile> [--lookups <lookups.dat>]");
  }

  private static String opt(String[] args, String name, String dflt) {
    for (int i = 0; i < args.length - 1; i++) {
      if (args[i].equals(name)) return args[i + 1];
    }
    return dflt;
  }

  private static boolean flag(String[] args, String name) {
    for (String a : args) if (a.equals(name)) return true;
    return false;
  }

  // --------------------------------------------------------- micro-cache ----

  static int toIlon(double lon) { return (int) ((lon + 180.) * 1000000. + 0.5); }
  static int toIlat(double lat) { return (int) ((lat + 90.) * 1000000. + 0.5); }

  private static void dumpMicroCache(String[] args) throws Exception {
    File rd5 = new File(args[1]);
    double lon = Double.parseDouble(args[2]);
    double lat = Double.parseDouble(args[3]);
    String profile = opt(args, "--profile", null);
    boolean withGeometry = flag(args, "--geometry");
    int limit = Integer.parseInt(opt(args, "--limit", "-1"));

    int ilon = toIlon(lon);
    int ilat = toIlat(lat);

    // A way context is needed as the IByteArrayUnifier for link descriptions.
    // When --profile is given it is ALSO used as the TagValueValidator, which is
    // what the router does; without it nothing is filtered out and the dump is
    // the raw decoded content of the micro-cache (the L1 parity target).
    BExpressionMetaData meta = new BExpressionMetaData();
    BExpressionContextWay ctxWay = new BExpressionContextWay(meta);
    File lookups = new File(profile != null ? new File(profile).getParentFile() : rd5.getParentFile(), "lookups.dat");
    if (profile == null) {
      // fall back to the repo profiles dir next to the tool
      File guess = new File(new File(System.getProperty("user.dir")), "lookups.dat");
      if (!lookups.exists() && guess.exists()) lookups = guess;
    }
    String lookupsOpt = opt(args, "--lookups", null);
    if (lookupsOpt != null) lookups = new File(lookupsOpt);
    if (!lookups.exists()) {
      System.err.println("lookups.dat not found (tried " + lookups + "); pass --lookups <path>");
      System.exit(2);
    }
    meta.readMetaData(lookups);
    if (profile != null) {
      ctxWay.parseFile(new File(profile), "global");
    } else {
      ctxWay.finishMetaParsing();
    }
    ctxWay.setDecodeForbidden(true); // "detailed" mode: keep access=no ways too

    DataBuffers dataBuffers = new DataBuffers();
    PhysicalFile pf = new PhysicalFile(rd5, dataBuffers, meta.lookupVersion, meta.lookupMinorVersion);
    int div = pf.divisor;
    int cellsize = 1000000 / div;

    int lonDegree = ilon / 1000000;
    int latDegree = ilat / 1000000;
    OsmFile osmf = new OsmFile(pf, lonDegree, latDegree, dataBuffers);

    StringBuilder sb = new StringBuilder();
    sb.append("{\n");
    kv(sb, 1, "tool", "dump-microcache"); sb.append(",\n");
    kv(sb, 1, "file", rd5.getName()); sb.append(",\n");
    kv(sb, 1, "creationTime", pf.creationTime); sb.append(",\n");
    kv(sb, 1, "divisor", div); sb.append(",\n");
    kv(sb, 1, "cellsize", cellsize); sb.append(",\n");
    kv(sb, 1, "lookupVersion", meta.lookupVersion); sb.append(",\n");
    kv(sb, 1, "lookupMinorVersion", meta.lookupMinorVersion); sb.append(",\n");
    kv(sb, 1, "profile", profile == null ? null : new File(profile).getName()); sb.append(",\n");
    kv(sb, 1, "lon", lon); sb.append(",\n");
    kv(sb, 1, "lat", lat); sb.append(",\n");
    kv(sb, 1, "ilon", ilon); sb.append(",\n");
    kv(sb, 1, "ilat", ilat); sb.append(",\n");
    kv(sb, 1, "lonDegree", lonDegree); sb.append(",\n");
    kv(sb, 1, "latDegree", latDegree); sb.append(",\n");
    kv(sb, 1, "lonIdx", ilon / cellsize); sb.append(",\n");
    kv(sb, 1, "latIdx", ilat / cellsize); sb.append(",\n");
    kv(sb, 1, "hasData", osmf.hasData()); sb.append(",\n");

    if (!osmf.hasData()) {
      kv(sb, 1, "nodes", 0); sb.append("\n}\n");
      System.out.print(sb);
      return;
    }

    int lonIdx = ilon / cellsize;
    int latIdx = ilat / cellsize;
    MicroCache segment = osmf.createMicroCache(
        lonIdx, latIdx, dataBuffers,
        profile == null ? null : ctxWay,   // TagValueValidator
        null,                              // WaypointMatcher
        true, null);

    OsmNodesMap nodesMap = new OsmNodesMap();
    GeometryDecoder geometryDecoder = new GeometryDecoder();

    int size = segment.getSize();
    kv(sb, 1, "microcacheNodes", size); sb.append(",\n");
    kv(sb, 1, "microcacheDataSize", segment.getDataSize()); sb.append(",\n");
    kv(sb, 1, "limit", limit); sb.append(",\n");
    sb.append("  \"nodes\": [\n");

    boolean firstNode = true;
    int emitted = 0;
    for (int i = 0; i < size; i++) {
      if (limit >= 0 && emitted >= limit) break;
      long id = segment.getIdForIndex(i);
      OsmNode node = new OsmNode(id);
      if (!segment.getAndClear(id)) continue;
      node.parseNodeBody(segment, nodesMap, ctxWay);

      if (!firstNode) sb.append(",\n");
      firstNode = false;
      emitted++;
      sb.append("   {");
      sb.append("\"id64\": ").append(id);
      sb.append(", \"ilon\": ").append(node.ilon);
      sb.append(", \"ilat\": ").append(node.ilat);
      sb.append(", \"lon\": ").append(fmt6(node.ilon / 1000000. - 180.));
      sb.append(", \"lat\": ").append(fmt6(node.ilat / 1000000. - 90.));
      sb.append(", \"selev\": ").append(node.selev);
      sb.append(", \"nodeDescription\": ").append(
          node.nodeDescription == null ? "null" : quote(hex(node.nodeDescription)));

      // turn restrictions
      sb.append(", \"turnRestrictions\": [");
      boolean firstTr = true;
      for (TurnRestriction tr = node.firstRestriction; tr != null; tr = tr.next) {
        if (!firstTr) sb.append(", ");
        firstTr = false;
        sb.append("{\"isPositive\": ").append(tr.isPositive)
          .append(", \"exceptions\": ").append(tr.exceptions)
          .append(", \"fromLon\": ").append(tr.fromLon)
          .append(", \"fromLat\": ").append(tr.fromLat)
          .append(", \"toLon\": ").append(tr.toLon)
          .append(", \"toLat\": ").append(tr.toLat)
          .append("}");
      }
      sb.append("]");

      // links
      sb.append(", \"links\": [");
      boolean firstLink = true;
      for (OsmLink link = node.firstlink; link != null; link = link.getNext(node)) {
        OsmNode target = link.getTarget(node);
        boolean reverse = link.isReverse(node);
        if (!firstLink) sb.append(", ");
        firstLink = false;
        sb.append("{\"targetIlon\": ").append(target.ilon)
          .append(", \"targetIlat\": ").append(target.ilat)
          .append(", \"reverse\": ").append(reverse)
          .append(", \"bidirectional\": ").append(link.isBidirectional());
        byte[] d = link.descriptionBitmap;
        sb.append(", \"descriptionBitmap\": ").append(d == null ? "null" : quote(hex(d)));
        sb.append(", \"wayTags\": ").append(
            d == null ? "null" : quote(ctxWay.getKeyValueDescription(reverse, d)));
        byte[] g = link.geometry;
        sb.append(", \"geometryBytes\": ").append(g == null ? "null" : quote(hex(g)));
        if (withGeometry && g != null) {
          sb.append(", \"transferNodes\": [");
          boolean firstT = true;
          OsmTransferNode tn = geometryDecoder.decodeGeometry(g, node, target, reverse);
          for (; tn != null; tn = tn.next) {
            if (!firstT) sb.append(", ");
            firstT = false;
            sb.append("{\"ilon\": ").append(tn.ilon)
              .append(", \"ilat\": ").append(tn.ilat)
              .append(", \"selev\": ").append(tn.selev).append("}");
          }
          sb.append("]");
        }
        sb.append("}");
      }
      sb.append("]}");
    }
    sb.append("\n  ]\n}\n");
    System.out.print(sb);
    // PhysicalFile.ra (the RandomAccessFile) is package-private and there is no
    // public close() on PhysicalFile, so the handle is released by JVM exit.
  }

  // -------------------------------------------------------- profile eval ----

  private static final Pattern ASSIGN =
      Pattern.compile("^\\s*assign\\s+([A-Za-z_][A-Za-z0-9_]*)");

  private static final String[] BUILT_IN = {
      "costfactor", "turncost", "uphillcostfactor", "downhillcostfactor",
      "initialcost", "nodeaccessgranted", "initialclassifier",
      "trafficsourcedensity", "istrafficbackbone", "priorityclassifier",
      "classifiermask", "maxspeed", "uphillcost", "downhillcost",
      "uphillcutoff", "downhillcutoff", "uphillmaxslope", "downhillmaxslope",
      "uphillmaxslopecost", "downhillmaxslopecost"};

  private static void evalProfile(String[] args) throws Exception {
    File profile = new File(args[1]);
    File tagsFile = new File(args[2]);
    String lookupsOpt = opt(args, "--lookups", null);
    File lookups = lookupsOpt != null ? new File(lookupsOpt)
                                      : new File(profile.getParentFile(), "lookups.dat");
    if (!lookups.exists()) {
      System.err.println("lookups.dat not found (tried " + lookups + "); pass --lookups <path>");
      System.exit(2);
    }

    BExpressionMetaData meta = new BExpressionMetaData();
    BExpressionContextWay ctxWay = new BExpressionContextWay(meta);
    meta.readMetaData(lookups);
    ctxWay.parseFile(profile, "global");

    // BExpressionContext has no public way to enumerate its variable table
    // (variableData and getVariableValue(int) are package-private), so the
    // reported variable set is: the 20 build-in way variables plus every name
    // the profile assigns. getVariableValue(name, NaN) then reads them back.
    Set<String> names = new LinkedHashSet<>();
    for (String b : BUILT_IN) names.add(b);
    BufferedReader pr = new BufferedReader(new FileReader(profile));
    for (String line; (line = pr.readLine()) != null; ) {
      int c = line.indexOf('#');
      if (c >= 0) line = line.substring(0, c);
      Matcher m = ASSIGN.matcher(line);
      if (m.find()) names.add(m.group(1));
    }
    pr.close();

    List<String> lines = new ArrayList<>();
    BufferedReader tr = new BufferedReader(new FileReader(tagsFile));
    for (String line; (line = tr.readLine()) != null; ) {
      String t = line.trim();
      if (t.isEmpty() || t.startsWith("#")) continue;
      lines.add(t);
    }
    tr.close();

    StringBuilder sb = new StringBuilder();
    sb.append("{\n");
    kv(sb, 1, "tool", "eval-profile"); sb.append(",\n");
    kv(sb, 1, "profile", profile.getName()); sb.append(",\n");
    kv(sb, 1, "lookups", lookups.getName()); sb.append(",\n");
    kv(sb, 1, "lookupVersion", meta.lookupVersion); sb.append(",\n");
    kv(sb, 1, "lookupMinorVersion", meta.lookupMinorVersion); sb.append(",\n");
    sb.append("  \"cases\": [\n");

    for (int li = 0; li < lines.size(); li++) {
      String line = lines.get(li);
      int[] lookupData = ctxWay.createNewLookupData();
      List<String> unknown = new ArrayList<>();
      for (String tok : line.split("\\s+")) {
        int eq = tok.indexOf('=');
        if (eq <= 0) continue;
        String k = tok.substring(0, eq);
        String v = tok.substring(eq + 1);
        if (ctxWay.getLookupNameIdx(k) < 0) {
          unknown.add(k);
          continue;
        }
        ctxWay.addLookupValue(k, v, lookupData);
      }
      byte[] ab = ctxWay.encode(lookupData);

      if (li > 0) sb.append(",\n");
      sb.append("   {");
      sb.append("\"tags\": ").append(quote(line));
      sb.append(", \"unknownKeys\": ").append(jsonStrings(unknown));
      sb.append(", \"encoded\": ").append(quote(hex(ab)));
      sb.append(", \"decoded\": ").append(quote(ctxWay.getKeyValueDescription(false, ab)));
      for (boolean inverse : new boolean[]{false, true}) {
        ctxWay.evaluate(inverse, ab);
        sb.append(", \"").append(inverse ? "reverse" : "forward").append("\": {");
        boolean first = true;
        for (String n : names) {
          float val = ctxWay.getVariableValue(n, Float.NaN);
          if (Float.isNaN(val)) continue;
          if (!first) sb.append(", ");
          first = false;
          sb.append(quote(n)).append(": ").append(fmtFloat(val));
        }
        sb.append("}");
      }
      sb.append("}");
    }
    sb.append("\n  ]\n}\n");
    System.out.print(sb);
  }

  // ------------------------------------------------------------- json bits --

  private static void kv(StringBuilder sb, int indent, String k, Object v) {
    for (int i = 0; i < indent; i++) sb.append("  ");
    sb.append(quote(k)).append(": ");
    if (v == null) sb.append("null");
    else if (v instanceof String) sb.append(quote((String) v));
    else if (v instanceof Double) sb.append(fmt6((Double) v));
    else sb.append(v.toString());
  }

  private static String jsonStrings(List<String> xs) {
    StringBuilder b = new StringBuilder("[");
    for (int i = 0; i < xs.size(); i++) {
      if (i > 0) b.append(", ");
      b.append(quote(xs.get(i)));
    }
    return b.append("]").toString();
  }

  private static String quote(String s) {
    if (s == null) return "null";
    StringBuilder b = new StringBuilder("\"");
    for (int i = 0; i < s.length(); i++) {
      char c = s.charAt(i);
      switch (c) {
        case '"': b.append("\\\""); break;
        case '\\': b.append("\\\\"); break;
        case '\n': b.append("\\n"); break;
        case '\r': b.append("\\r"); break;
        case '\t': b.append("\\t"); break;
        default:
          if (c < 0x20) b.append(String.format("\\u%04x", (int) c));
          else b.append(c);
      }
    }
    return b.append('"').toString();
  }

  private static String hex(byte[] ab) {
    StringBuilder b = new StringBuilder(ab.length * 2);
    for (byte x : ab) b.append(String.format("%02x", x & 0xff));
    return b.toString();
  }

  private static String fmt6(double v) {
    return String.format(java.util.Locale.US, "%.6f", v);
  }

  /** Print a float exactly the way Java prints it, so 1e-6 comparison is possible. */
  private static String fmtFloat(float v) {
    if (Float.isNaN(v)) return "null";
    if (Float.isInfinite(v)) return v > 0 ? "1e999" : "-1e999";
    String s = Float.toString(v);
    return s;
  }
}

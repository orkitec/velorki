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
//                [--bits | --compact] [--context node --way-tags "<tags>"]
//       Build a btools.expressions.BExpressionContextWay from lookups.dat plus
//       the profile, then evaluate every line of the tags file
//       ("highway=residential surface=asphalt ...") and print all cost
//       variables the profile produces, forward and reverse, as JSON.
//       --bits prints every variable as the hex of Float.floatToIntBits instead
//       of Float.toString (the R3 bit-identical target); --compact additionally
//       de-duplicates the per-case variable vectors ("vectors" + a [forward,
//       reverse] index pair per case, no tags: the case order is the order of
//       the tags file) and lists every existing variable, NaN included, so
//       that tens of thousands of tag sets stay small; --encode adds the
//       "encoded" list (per case the encoded hex, or [hex, decoded] when the
//       decoded string differs from the input line, or [hex, decoded,
//       unknownKeys...]). --context node evaluates the node context (its
//       foreign way context is first evaluated with --way-tags, default
//       "highway=residential"); the "reverse" direction then means
//       nodeaccessgranted=yes. Both new modes also print usedTagList().
//
//   way-tags <tile.rd5> [--kind way|node] [--lookups <lookups.dat>]
//       Decode every micro-cache of the tile (no validator) and print every
//       distinct way tag string (BExpressionContextWay.getKeyValueDescription,
//       forward direction) -- or with --kind node every distinct node tag
//       string -- one per line, sorted, as a tags file for eval-profile.
//
//   math-vectors <outdir>
//       Write <outdir>/float.json: JVM float semantics the expressions module
//       depends on (Float.parseFloat incl. decimal strings on float midpoints,
//       Float.toString, float add/sub/mul/div, int/float conversions,
//       String.format("%3.1f"), Integer.parseInt, Arrays.hashCode(float[]),
//       Character.isWhitespace) as bit patterns for the Dart emulation.
//
//   core-vectors <outdir>
//       Write <outdir>/core.json: the JVM numerics brouter-core (track R4)
//       depends on -- Math.exp bit patterns (a HotSpot LIBM intrinsic on
//       x86_64), DecimalFormat("0.###") of float travel times, and
//       Double.toString of the elevation values the GeoJSON formatter prints.
//
//   codec-vectors <outdir>
//       Write deterministic L1 test vectors for the brouter-util and
//       brouter-codec classes (BitCoderContext, StatCoderContext, Crc32,
//       CheapRuler, CheapAngleMeter, ByteDataReader/Writer, Mix/DiffCoder
//       streams, TagValueCoder, NoisyDiffCoder, the long maps/sets, SortedHeap,
//       LruMap, ...) as <outdir>/<section>.json. Every input is recorded in the
//       JSON, so the Dart side replays without a random generator.
//
//   microcache-bytes <tile.rd5> <lon> <lat> <outfile>
//       Write the raw, still encoded micro-cache covering the position exactly
//       as it is stored in the rd5 (including the 4-byte crc footer).
//
//   microcache-listing <tile.rd5> <lon> <lat> [--bodies <n>]
//       Decode that micro-cache with MicroCache2 (no validator, no matcher)
//       and print, per node, the body length and the Crc32 of the body bytes,
//       the crc of all 64-bit ids and of all bodies, the id plus full body hex
//       of the first n nodes, and the result of re-encoding the cache with
//       MicroCache2.encodeMicroCache.
//
//   osmfile-index <tile.rd5>
//       The rd5 header as PhysicalFile reads it (file index, header crcs,
//       creation time, divisor, elevation type, lookup version) and, per
//       degree square, every non-empty micro-cache with its encoded size and
//       Crc32 (OsmFile.getDataInputForSubIdx). L2-mapaccess target.
//
//   nodes-cache-walk <segmentsDir> <lon> <lat> <lon2> <lat2> [--maxmem <bytes>]
//                    [--no-direct-weaving] [--cleanup-mode <n>] [--steps <n>]
//                    [--profile <file.brf>]
//       Exercise btools.mapaccess.NodesCache the way RoutingEngine does: match
//       the two waypoints (matchWaypointsToNodes), reset the cache, obtain the
//       matched graph nodes and expand their link targets, breadth-first walk
//       <steps> nodes from the first one (obtainNonHollowNode on every link
//       target), reset again and getStartNode. Prints the matches, the full
//       nodes (links, geometry, transfer nodes, turn restrictions), one record
//       per walked node and the cache's memory accounting (formatStatus).
//       The way context is lookups.dat only (no profile) with all tags used:
//       every way is kept, accessType 2. With --profile the real profile is
//       parsed instead (no setAllTagsUsed, exactly like RoutingEngine), so
//       inaccessible ways drop out and unused tags are filtered from the
//       descriptions; the JSON then carries a "profile" entry.
//
// Everything is written to stdout as one JSON document; diagnostics go to stderr.

import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.FileReader;
import java.io.IOException;
import java.io.OutputStreamWriter;
import java.io.Writer;
import java.nio.charset.StandardCharsets;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Deque;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Random;
import java.util.Set;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.TreeSet;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import btools.codec.DataBuffers;
import btools.codec.LinkedListContainer;
import btools.codec.MicroCache;
import btools.codec.MicroCache2;
import btools.codec.NoisyDiffCoder;
import btools.codec.StatCoderContext;
import btools.codec.TagValueCoder;
import btools.codec.TagValueWrapper;
import btools.util.BitCoderContext;
import btools.util.ByteArrayUnifier;
import btools.util.ByteDataReader;
import btools.util.ByteDataWriter;
import btools.util.CheapAngleMeter;
import btools.util.CheapRuler;
import btools.util.CompactLongMap;
import btools.util.CompactLongSet;
import btools.util.Crc32;
import btools.util.DenseLongMap;
import btools.util.DiffCoderDataInputStream;
import btools.util.DiffCoderDataOutputStream;
import btools.util.FrozenLongMap;
import btools.util.FrozenLongSet;
import btools.util.LruMap;
import btools.util.LruMapNode;
import btools.util.MixCoderDataInputStream;
import btools.util.MixCoderDataOutputStream;
import btools.util.SortedHeap;
import btools.util.TinyDenseLongMap;
import btools.expressions.BExpressionContext;
import btools.expressions.BExpressionContextNode;
import btools.expressions.BExpressionContextWay;
import btools.expressions.BExpressionMetaData;
import btools.mapaccess.GeometryDecoder;
import btools.mapaccess.MatchedWaypoint;
import btools.mapaccess.NodesCache;
import btools.mapaccess.OsmFile;
import btools.mapaccess.OsmLink;
import btools.mapaccess.OsmNode;
import btools.mapaccess.OsmNodePairSet;
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
    } else if ("codec-vectors".equals(cmd)) {
      codecVectors(args);
    } else if ("microcache-bytes".equals(cmd)) {
      microCacheBytes(args);
    } else if ("microcache-listing".equals(cmd)) {
      microCacheListing(args);
    } else if ("osmfile-index".equals(cmd)) {
      osmFileIndex(args);
    } else if ("nodes-cache-walk".equals(cmd)) {
      nodesCacheWalk(args);
    } else if ("way-tags".equals(cmd)) {
      wayTags(args);
    } else if ("math-vectors".equals(cmd)) {
      mathVectors(args);
    } else if ("core-vectors".equals(cmd)) {
      coreVectors(args);
    } else {
      usage();
      System.exit(2);
    }
  }

  private static void usage() {
    System.err.println("usage:");
    System.err.println("  Dump dump-microcache <tile.rd5> <lon> <lat> [--profile <f.brf>] [--geometry] [--limit <n>]");
    System.err.println("  Dump eval-profile <profile.brf> <tagsfile> [--lookups <lookups.dat>] [--bits | --compact [--encode]] [--context node --way-tags \"<tags>\"]");
    System.err.println("  Dump way-tags <tile.rd5> [--kind way|node] [--lookups <lookups.dat>]");
    System.err.println("  Dump math-vectors <outdir>");
    System.err.println("  Dump core-vectors <outdir>");
    System.err.println("  Dump codec-vectors <outdir>");
    System.err.println("  Dump microcache-bytes <tile.rd5> <lon> <lat> <outfile>");
    System.err.println("  Dump microcache-listing <tile.rd5> <lon> <lat> [--bodies <n>]");
    System.err.println("  Dump osmfile-index <tile.rd5>");
    System.err.println("  Dump nodes-cache-walk <segmentsDir> <lon> <lat> <lon2> <lat2> [--maxmem <bytes>] [--no-direct-weaving] [--cleanup-mode <n>] [--steps <n>] [--lookups <lookups.dat>] [--profile <file.brf>]");
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
    if (flag(args, "--bits") || flag(args, "--compact") || opt(args, "--context", null) != null) {
      evalProfile2(args);
      return;
    }
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


  private static final String[] BUILT_IN_NODE = {"initialcost"};

  /** The names eval-profile reports: the build-in variables plus every `assign <name>` of the profile. */
  private static Set<String> assignedNames(File profile, String[] builtIn) throws IOException {
    Set<String> names = new LinkedHashSet<>();
    for (String b : builtIn) names.add(b);
    BufferedReader pr = new BufferedReader(new FileReader(profile));
    for (String line; (line = pr.readLine()) != null; ) {
      int c = line.indexOf('#');
      if (c >= 0) line = line.substring(0, c);
      Matcher m = ASSIGN.matcher(line);
      if (m.find()) names.add(m.group(1));
    }
    pr.close();
    return names;
  }

  private static List<String> readTagLines(File tagsFile) throws IOException {
    List<String> lines = new ArrayList<>();
    BufferedReader tr = new BufferedReader(new FileReader(tagsFile));
    for (String line; (line = tr.readLine()) != null; ) {
      String t = line.trim();
      if (t.isEmpty() || t.startsWith("#")) continue;
      lines.add(t);
    }
    tr.close();
    return lines;
  }

  /** createNewLookupData + addLookupValue for every key=value of the line; unknown keys are collected. */
  private static int[] tagsToLookupData(BExpressionContext ctx, String line, List<String> unknown) {
    int[] lookupData = ctx.createNewLookupData();
    for (String tok : line.split("\\s+")) {
      int eq = tok.indexOf('=');
      if (eq <= 0) continue;
      String k = tok.substring(0, eq);
      String v = tok.substring(eq + 1);
      if (ctx.getLookupNameIdx(k) < 0) {
        unknown.add(k);
        continue;
      }
      ctx.addLookupValue(k, v, lookupData);
    }
    return lookupData;
  }

  private static String bitsHex(float v) {
    return String.format("%08x", Float.floatToIntBits(v));
  }

  /** eval-profile with --bits / --compact / --context node: float bit patterns, optional de-duplication. */
  private static void evalProfile2(String[] args) throws Exception {
    File profile = new File(args[1]);
    File tagsFile = new File(args[2]);
    String lookupsOpt = opt(args, "--lookups", null);
    File lookups = lookupsOpt != null ? new File(lookupsOpt)
                                      : new File(profile.getParentFile(), "lookups.dat");
    if (!lookups.exists()) {
      System.err.println("lookups.dat not found (tried " + lookups + "); pass --lookups <path>");
      System.exit(2);
    }
    boolean compact = flag(args, "--compact");
    boolean withEncode = flag(args, "--encode");
    String context = opt(args, "--context", "way");
    boolean nodeContext = "node".equals(context);
    if (!nodeContext && !"way".equals(context)) {
      System.err.println("--context must be way or node");
      System.exit(2);
    }
    String wayTagsLine = opt(args, "--way-tags", "highway=residential");

    BExpressionMetaData meta = new BExpressionMetaData();
    BExpressionContextWay ctxWay = new BExpressionContextWay(meta);
    BExpressionContextNode ctxNode = nodeContext ? new BExpressionContextNode(0, meta) : null; // hashSize 0 like ProfileCache
    if (ctxNode != null) ctxNode.setForeignContext(ctxWay);
    meta.readMetaData(lookups);
    ctxWay.parseFile(profile, "global");
    if (ctxNode != null) ctxNode.parseFile(profile, "global");
    BExpressionContext ctx = nodeContext ? ctxNode : ctxWay;

    Set<String> names = assignedNames(profile, nodeContext ? BUILT_IN_NODE : BUILT_IN);
    // a variable exists when getVariableValue does not return the default for two different defaults
    List<String> vars = new ArrayList<>();
    for (String n : names) {
      if (ctx.getVariableValue(n, 0f) == 0f && ctx.getVariableValue(n, 1f) == 1f) continue;
      vars.add(n);
    }

    byte[] wayAb = null;
    List<String> wayUnknown = new ArrayList<>();
    if (nodeContext) {
      wayAb = ctxWay.encode(tagsToLookupData(ctxWay, wayTagsLine, wayUnknown));
      ctxWay.evaluate(false, wayAb);
    }

    List<String> lines = readTagLines(tagsFile);

    StringBuilder sb = new StringBuilder();
    sb.append("{\n");
    kv(sb, 1, "tool", "eval-profile"); sb.append(",\n");
    kv(sb, 1, "profile", profile.getName()); sb.append(",\n");
    kv(sb, 1, "lookups", lookups.getName()); sb.append(",\n");
    kv(sb, 1, "lookupVersion", meta.lookupVersion); sb.append(",\n");
    kv(sb, 1, "lookupMinorVersion", meta.lookupMinorVersion); sb.append(",\n");
    kv(sb, 1, "context", context); sb.append(",\n");
    kv(sb, 1, "format", compact ? "compact" : "bits"); sb.append(",\n");
    kv(sb, 1, "tagsFile", tagsFile.getName()); sb.append(",\n");
    kv(sb, 1, "caseCount", lines.size()); sb.append(",\n");
    kv(sb, 1, "usedTags", ctx.usedTagList()); sb.append(",\n");
    if (nodeContext) {
      kv(sb, 1, "wayTags", wayTagsLine); sb.append(",\n");
      sb.append("  \"wayUnknownKeys\": ").append(jsonStrings(wayUnknown)).append(",\n");
      kv(sb, 1, "wayEncoded", wayAb == null ? null : hex(wayAb)); sb.append(",\n");
      kv(sb, 1, "wayDecoded", wayAb == null ? null : ctxWay.getKeyValueDescription(false, wayAb)); sb.append(",\n");
      kv(sb, 1, "wayUsedTags", ctxWay.usedTagList()); sb.append(",\n");
      kv(sb, 1, "wayCostfactor", bitsHex(ctxWay.getCostfactor())); sb.append(",\n");
    }
    sb.append("  \"variables\": ").append(jsonStrings(vars)).append(",\n");

    Map<String, Integer> vectors = new LinkedHashMap<>();
    StringBuilder cases = new StringBuilder();
    StringBuilder encodes = new StringBuilder();
    for (int li = 0; li < lines.size(); li++) {
      String line = lines.get(li);
      List<String> unknown = new ArrayList<>();
      int[] lookupData = tagsToLookupData(ctx, line, unknown);
      byte[] ab = ctx.encode(lookupData);
      String decoded = ab == null ? null : ctx.getKeyValueDescription(false, ab);

      if (li > 0) cases.append(",\n");
      if (compact) {
        cases.append("   [");
        if (withEncode) {
          if (li > 0) encodes.append(",\n");
          if (ab == null) {
            encodes.append("   null");
          } else if (decoded.equals(line) && unknown.isEmpty()) {
            encodes.append("   ").append(quote(hex(ab)));
          } else {
            List<String> e = new ArrayList<>();
            e.add(hex(ab));
            e.add(decoded);
            e.addAll(unknown);
            encodes.append("   ").append(jsonStrings(e));
          }
        }
      } else {
        cases.append("   {");
        cases.append("\"tags\": ").append(quote(line));
        cases.append(", \"unknownKeys\": ").append(jsonStrings(unknown));
        cases.append(", \"encoded\": ").append(ab == null ? "null" : quote(hex(ab)));
        cases.append(", \"decoded\": ").append(decoded == null ? "null" : quote(decoded));
      }
      for (boolean inverse : new boolean[]{false, true}) {
        if (ab == null) {
          // nothing encodable (all keys unknown): upstream would crash decoding an empty array
          cases.append(compact ? (inverse ? ", null" : "null") : (inverse ? ", \"reverse\": null" : ", \"forward\": null"));
          continue;
        }
        ctx.evaluate(inverse, ab);
        if (compact) {
          StringBuilder vec = new StringBuilder();
          for (String n : vars) {
            if (vec.length() > 0) vec.append(' ');
            vec.append(bitsHex(ctx.getVariableValue(n, Float.NaN)));
          }
          String key = vec.toString();
          Integer idx = vectors.get(key);
          if (idx == null) {
            idx = vectors.size();
            vectors.put(key, idx);
          }
          if (inverse) cases.append(", ");
          cases.append(idx);
        } else {
          cases.append(", \"").append(inverse ? "reverse" : "forward").append("\": {");
          boolean first = true;
          for (String n : vars) {
            if (!first) cases.append(", ");
            first = false;
            cases.append(quote(n)).append(": ").append(quote(bitsHex(ctx.getVariableValue(n, Float.NaN))));
          }
          cases.append("}");
        }
      }
      cases.append(compact ? "]" : "}");
    }
    if (compact && withEncode) {
      sb.append("  \"encoded\": [\n").append(encodes).append("\n  ],\n");
    }
    if (compact) {
      sb.append("  \"vectors\": [\n");
      boolean first = true;
      for (String v : vectors.keySet()) {
        if (!first) sb.append(",\n");
        first = false;
        sb.append("   ").append(quote(v));
      }
      sb.append("\n  ],\n");
    }
    sb.append("  \"cases\": [\n").append(cases).append("\n  ]\n}\n");
    System.out.print(sb);
  }

  // ------------------------------------------------------------ way-tags ----

  /** Every distinct way (or node) tag string of a tile, one per line, sorted. */
  private static void wayTags(String[] args) throws Exception {
    File rd5 = new File(args[1]);
    String kind = opt(args, "--kind", "way");
    boolean nodeKind = "node".equals(kind);
    String lookupsOpt = opt(args, "--lookups", null);
    if (lookupsOpt == null) { System.err.println("--lookups <lookups.dat> is required"); System.exit(2); }
    Matcher m = Pattern.compile("([EW])(\\d+)_([NS])(\\d+)\\.rd5").matcher(rd5.getName());
    if (!m.matches()) { System.err.println("tile name must look like W20_N30.rd5"); System.exit(2); }
    int lonBase = Integer.parseInt(m.group(2)) * (m.group(1).equals("W") ? -1 : 1) + 180;
    int latBase = Integer.parseInt(m.group(4)) * (m.group(3).equals("S") ? -1 : 1) + 90;

    BExpressionMetaData meta = new BExpressionMetaData();
    BExpressionContextWay ctxWay = new BExpressionContextWay(meta);
    BExpressionContextNode ctxNode = new BExpressionContextNode(meta);
    meta.readMetaData(new File(lookupsOpt));

    DataBuffers dataBuffers = new DataBuffers();
    PhysicalFile pf = new PhysicalFile(rd5, dataBuffers, meta.lookupVersion, meta.lookupMinorVersion);
    int div = pf.divisor;
    TreeSet<String> set = new TreeSet<>();
    long nodes = 0, described = 0, cells = 0;
    for (int lonDegree = lonBase; lonDegree < lonBase + 5; lonDegree++) {
      for (int latDegree = latBase; latDegree < latBase + 5; latDegree++) {
        OsmFile osmf = new OsmFile(pf, lonDegree, latDegree, dataBuffers);
        if (!osmf.hasData()) continue;
        for (int subIdx = 0; subIdx < div * div; subIdx++) {
          int lonIdx = lonDegree * div + subIdx % div;
          int latIdx = latDegree * div + subIdx / div;
          MicroCache segment = osmf.createMicroCache(lonIdx, latIdx, dataBuffers, null, null, true, null);
          int size = segment.getSize();
          if (size == 0) continue;
          cells++;
          OsmNodesMap nodesMap = new OsmNodesMap();
          for (int i = 0; i < size; i++) {
            long id = segment.getIdForIndex(i);
            OsmNode node = new OsmNode(id);
            if (!segment.getAndClear(id)) continue;
            node.parseNodeBody(segment, nodesMap, ctxWay);
            nodes++;
            if (nodeKind) {
              if (node.nodeDescription != null) {
                set.add(ctxNode.getKeyValueDescription(false, node.nodeDescription));
                described++;
              }
            } else {
              for (OsmLink link = node.firstlink; link != null; link = link.getNext(node)) {
                byte[] d = link.descriptionBitmap;
                if (d == null) continue;
                set.add(ctxWay.getKeyValueDescription(false, d));
                described++;
              }
            }
          }
        }
      }
    }
    pf.close();
    StringBuilder sb = new StringBuilder();
    sb.append("# ").append(kind).append(" tags of ").append(rd5.getName()).append(": ").append(set.size())
      .append(" distinct strings from ").append(described).append(nodeKind ? " node descriptions" : " link descriptions")
      .append(" (").append(nodes).append(" nodes, ").append(cells).append(" micro-caches, lookups ")
      .append(meta.lookupVersion).append('.').append(meta.lookupMinorVersion).append(")\n");
    for (String s : set) sb.append(s).append('\n');
    System.out.print(sb);
  }

  // -------------------------------------------------------- math vectors ----

  private static String floatEntry(float v) {
    return "[" + Float.floatToRawIntBits(v) + ", " + quote(Float.toString(v)) + "]";
  }


  // ---- brouter-core numerics (track R4) ---------------------------------------

  /** Math.exp, DecimalFormat("0.###") and Double.toString as the routing engine and FormatJson use them. */
  private static void coreVectors(String[] args) throws Exception {
    File outDir = new File(args[1]);
    outDir.mkdirs();
    Random rnd = new Random(20260912);
    StringBuilder sb = new StringBuilder();
    sb.append("{\n");
    kv(sb, 1, "tool", "core-vectors"); sb.append(",\n");
    kv(sb, 1, "vm", System.getProperty("java.vm.name") + " " + System.getProperty("java.version") + " " + System.getProperty("os.arch")); sb.append(",\n");

    // --- Math.exp: "hex(x) hex(exp(x))"
    List<Double> xs = new ArrayList<>();
    double[] specials = {0.0, -0.0, Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY, Double.MIN_VALUE, -Double.MIN_VALUE,
      Double.MIN_NORMAL, -Double.MIN_NORMAL, 0x1.0p-55, -0x1.0p-55, 0x1.fffffffffffffp-55, 0x1.0p-54, -0x1.0p-54, 0x1.0p-53, 0x1.0p-30, 1e-300, 1e-10,
      1.0, -1.0, 0.5, -0.5, 2.0, 10.0, -10.0, 100.0, -100.0, 700.0, -700.0, 709.0, 709.78, 709.782712893383973096, 709.7827128933840, 709.79, 710.0,
      -708.0, -708.39, -708.3964185322641, -708.4, -709.0, -740.0, -745.0, -745.1, -745.13, -745.133219101941108420, -745.1332191019412, -745.14, -746.0, -800.0, -1000.0,
      991.0, 992.0, 1000.0, 1023.0, 1023.9, 1023.99999, 1024.0, -1024.0, -1023.99, 2000.0, -2000.0, 1e10, -1e10, 1e300, -1e300, 3.0e2, -3.0e2,
      -0.01, -0.02, -0.03, -0.1, -0.25, -0.33, -0.5, -0.75, -1.5, -2.5, -3.5, -4.0, -5.0, -6.0, -7.0, -8.0, -9.0, -12.0, -15.0, -20.0, -25.0, -30.0, -40.0, -50.0,
      0.6931471805599453, -0.6931471805599453, 0.34657359027997264, 0.010830424696249144, 0.005415212348124572, -0.005415212348124572,
      0x1.62e42fefa39efp-1, 0x1.62e42fefa39efp0, 0x1.62e42fefa39efp1, 0x1.62e42fefa39efp5, 0x1.62e42fefa39efp9, -0x1.62e42fefa39efp9, -0x1.62e42fefa39efp5,
      -1022 * 0.6931471805599453, -1023 * 0.6931471805599453, -1024 * 0.6931471805599453, -1074 * 0.6931471805599453, -1075 * 0.6931471805599453,
      1023 * 0.6931471805599453, 1024 * 0.6931471805599453};
    for (double d : specials) xs.add(d);
    // the arguments StdPath.calcIncline really produces: -dist / 100. for integer distances
    for (int k = 1; k <= 6000; k++) xs.add(-k / 100.);
    for (int k = 6007; k <= 200000; k += 97) xs.add(-k / 100.);
    // Tobler (foot): -3.5 * |incline + 0.05|
    for (int i = 0; i < 400; i++) xs.add(-3.5 * Math.abs((rnd.nextDouble() - 0.5) * 2 + 0.05));
    // KinematicPath: -distanceTime / turnAngleDecayTime
    for (int i = 0; i < 400; i++) xs.add(-(rnd.nextDouble() * 60) / 5.);
    for (int i = 0; i < 2000; i++) xs.add((rnd.nextDouble() - 0.5) * 2);
    for (int i = 0; i < 2000; i++) xs.add((rnd.nextDouble() - 0.5) * 40);
    for (int i = 0; i < 1500; i++) xs.add((rnd.nextDouble() - 0.5) * 1420);
    for (int i = 0; i < 1500; i++) xs.add(-708 - rnd.nextDouble() * 38);   // subnormal results
    for (int i = 0; i < 300; i++) xs.add(-745.13 - rnd.nextDouble() * 0.02);  // around the underflow edge
    for (int i = 0; i < 300; i++) xs.add(709.78 + rnd.nextDouble() * 0.01);   // around the overflow edge
    for (int i = 0; i < 300; i++) xs.add(1023 + rnd.nextDouble());            // just below the 1024 branch
    for (int i = 0; i < 300; i++) xs.add(Math.pow(2, -60 + rnd.nextDouble() * 10) * (rnd.nextBoolean() ? 1 : -1)); // around the 2^-54 branch
    for (int i = 0; i < 500; i++) xs.add(Double.longBitsToDouble(rnd.nextLong()));
    List<String> ex = new ArrayList<>();
    for (double x : xs) ex.add(quote(hexd(x) + " " + hexd(Math.exp(x))));
    sb.append("  \"exp\": ").append(arr(ex, true)).append(",\n");

    // --- DecimalFormat("0.###", Locale.ENGLISH).format((double) f): "hex(floatbits) formatted"
    java.text.DecimalFormat df = (java.text.DecimalFormat) java.text.NumberFormat.getInstance(java.util.Locale.ENGLISH);
    df.applyPattern("0.###");
    List<Float> fs = new ArrayList<>();
    float[] fspecials = {0f, -0f, 1f, -1f, 0.5f, 0.0625f, 0.0005f, 0.00049f, 0.00051f, 0.001f, 0.0015f, 0.0025f, 0.0035f, 0.9995f, 0.9994f, 0.9996f, 1.0005f, 1.0015f, 1.2345f, 1.2335f,
      2.5f, 12.3455f, 999.9995f, 1183.4f, 1234.5675f, 1234.5685f, 0.1f, 0.2f, 0.3f, 100000.5f, 16777216f, 16777217f, 1e7f, 1.5e7f, 3.4028235e38f, 1e-3f, 1e-4f, 5e-4f, 4.9999e-4f, 5.0001e-4f,
      0.125f, 0.375f, 0.625f, 0.875f, 1.0625f, 7.4375f, 99.9995f, 0.0015f, 0.9375f, 123456.78f, 3599.9995f};
    for (float f : fspecials) fs.add(f);
    for (int k = 0; k <= 4000; k++) fs.add(k / 8f);        // dyadic values, exact ties at the 4th decimal (x.xxx5 for k odd multiples of ... )
    for (int k = 0; k <= 20000; k++) fs.add(k / 16f);
    for (int k = 1; k <= 3000; k++) fs.add(k * 0.001f);
    for (int k = 1; k <= 3000; k++) fs.add(k * 0.0005f);
    for (int i = 0; i < 4000; i++) fs.add(rnd.nextFloat() * 20000f);
    for (int i = 0; i < 2000; i++) fs.add(rnd.nextFloat() * 100f);
    for (int i = 0; i < 2000; i++) fs.add(rnd.nextFloat());
    for (int i = 0; i < 500; i++) fs.add(Float.intBitsToFloat(rnd.nextInt() & 0x7fffffff));
    for (int i = 0; i < 1000; i++) { float t = 0; for (int j = 0; j < 50; j++) t += rnd.nextFloat() * 20f; fs.add(t); }  // summed travel times
    List<String> dfs = new ArrayList<>();
    for (float f : fs) {
      if (Float.isNaN(f) || Float.isInfinite(f)) continue;
      dfs.add(quote(Integer.toHexString(Float.floatToRawIntBits(f)) + " " + df.format((double) f)));
    }
    sb.append("  \"decimalFormat\": ").append(arr(dfs, true)).append(",\n");

    // --- Double.toString of selev / 4. and of the speed hack ((int) (speed * 10)) / 10.f: "hex(bits) string"
    List<String> ds = new ArrayList<>();
    for (int k = -4000; k <= 36000; k += 3) ds.add(quote(hexd(k / 4.) + " " + Double.toString(k / 4.)));
    for (int k = -32768; k <= 32767; k += 977) ds.add(quote(hexd(k / 4.) + " " + Double.toString(k / 4.)));
    for (int i = 0; i < 1500; i++) { double d = (rnd.nextDouble() - 0.3) * Math.pow(10, rnd.nextInt(12) - 4); ds.add(quote(hexd(d) + " " + Double.toString(d))); }
    for (int i = 0; i < 500; i++) { double d = Double.longBitsToDouble(rnd.nextLong()); if (Double.isNaN(d) || Double.isInfinite(d)) continue; ds.add(quote(hexd(d) + " " + Double.toString(d))); }
    sb.append("  \"doubleToString\": ").append(arr(ds, true)).append(",\n");

    // --- float speed hack of FormatJson/FormatGpx: "hex(dist) hex(dtbits) string" of (((int) (speed * 10)) / 10.f) with speed = (3.6f * dist) / dt + 0.5
    List<String> sp = new ArrayList<>();
    for (int i = 0; i < 2000; i++) {
      int dist = 1 + rnd.nextInt(500);
      float dt = rnd.nextFloat() * 200f + 0.01f;
      double speed = ((3.6f * dist) / dt + 0.5);
      sp.add(quote(dist + " " + Integer.toHexString(Float.floatToRawIntBits(dt)) + " " + (((int) (speed * 10)) / 10.f)));
    }
    sb.append("  \"speedHack\": ").append(arr(sp, true)).append("\n");
    sb.append("}\n");
    writeFile(new File(outDir, "core.json"), sb.toString());
    System.err.println("wrote " + new File(outDir, "core.json"));
  }

  private static void mathVectors(String[] args) throws Exception {
    File outDir = new File(args[1]);
    outDir.mkdirs();
    Random rnd = new Random(20260912);
    StringBuilder sb = new StringBuilder();
    sb.append("{\n");
    kv(sb, 1, "tool", "math-vectors"); sb.append(",\n");
    kv(sb, 1, "seed", 20260912); sb.append(",\n");

    // --- Float.parseFloat: strings -> bits (null = NumberFormatException)
    List<String> strings = new ArrayList<>();
    for (String s : new String[]{
        "0", "0.0", "1", "1.0", "-1", "+1", "-0", "-0.0", "0.1", "0.2", "0.3", "0.7", "1.1", "1.15", "0.225", "0.01", "0.005", "0.333", "0.3333",
        "9999", "10000", "100000", "1000000", "1e6", "1E6", "1e-3", "1.5e2", "1.5E-2", ".5", "5.", "+.5", "-.5", "00012", "1.50", "3.4028235e38",
        "3.4028236e38", "3.4028237e38", "3.40282356e38", "1e39", "-1e39", "1.17549435e-38", "1.1754942e-38", "1.4e-45", "1.5e-45", "7e-46", "7.1e-46", "1e-46", "0.7e-45",
        "1.00000005960464477539", "1.000000059604644775390625", "1.0000000596046447753906251", "1.00000005960464477539062", "1.00000017881393421514957253748434595763683319091796875",
        "1.000000178813934215149572537484345957636833190917968750001", "1.00000017881393421514957253748434595763683319091796874999",
        "16777217", "16777219", "16777218.5", "16777216.5", "33554434", "33554435", "0.100000001490116119384765625", "0.1000000014901161193847656251",
        "2.2250738585072012e-308", "4.9e-324", "1e-400", "1e400", "NaN", "Infinity", "-Infinity", "+Infinity", "infinity", "nan", "1.5f", "1.5F", "1.5d", "1.5D",
        "0x1p3", "0x1.8p1", " 1 ", "\t2\n", "", " ", "abc", "1e", "e5", "1.2.3", "1,5", "30_mph", "1_000", "--1", "1-", "0x", "1e+", "1e+5", "1e-", "+-1", "1e05", "1.e5", ".e5",
        "residential", "yes", "30", "50", "5.1m", "3ft", "2'6\"", "100000000000000000000", "123456789", "1234567890", "12345678901234567890", "0.000001", "0.0000001", "1e-7", "1e7", "12345678"}) {
      strings.add(s);
    }
    for (int i = 0; i < 3000; i++) {
      StringBuilder d = new StringBuilder();
      if (rnd.nextInt(4) == 0) d.append('-');
      int nd = 1 + rnd.nextInt(9);
      for (int k = 0; k < nd; k++) d.append((char) ('0' + rnd.nextInt(10)));
      if (rnd.nextBoolean()) {
        d.append('.');
        int nf = rnd.nextInt(10);
        for (int k = 0; k < nf; k++) d.append((char) ('0' + rnd.nextInt(10)));
      }
      if (rnd.nextInt(3) == 0) {
        d.append(rnd.nextBoolean() ? 'e' : 'E');
        if (rnd.nextBoolean()) d.append(rnd.nextBoolean() ? '-' : '+');
        d.append(rnd.nextInt(50));
      }
      strings.add(d.toString());
    }
    // decimal strings exactly on, just above and just below a float midpoint
    for (int i = 0; i < 700; i++) {
      float f = Float.intBitsToFloat(rnd.nextInt() & 0x7fffffff);
      if (Float.isNaN(f) || Float.isInfinite(f)) continue;
      if (i % 2 == 0) f = Float.intBitsToFloat(rnd.nextInt(0x4f000000)); // more mid-range values
      float up = Math.nextUp(f);
      if (Float.isInfinite(up)) continue;
      java.math.BigDecimal mid = new java.math.BigDecimal(f).add(new java.math.BigDecimal(up)).divide(new java.math.BigDecimal(2));
      String ms = mid.toPlainString();
      strings.add(ms);
      strings.add(ms + "1");
      java.math.BigDecimal below = mid.subtract(java.math.BigDecimal.ONE.scaleByPowerOfTen(-(mid.scale() + 3)));
      strings.add(below.toPlainString());
      if (rnd.nextInt(5) == 0) strings.add(mid.toString());
    }
    sb.append("  \"parseFloat\": [\n");
    for (int i = 0; i < strings.size(); i++) {
      if (i > 0) sb.append(",\n");
      String s = strings.get(i);
      sb.append("   [").append(quote(s)).append(", ");
      try {
        float f = Float.parseFloat(s);
        sb.append(Float.floatToRawIntBits(f)).append(", ").append(quote(Float.toString(f)));
      } catch (NumberFormatException e) {
        sb.append("null, null");
      }
      sb.append("]");
    }
    sb.append("\n  ],\n");

    // --- Float.toString: bits -> string
    List<Float> floats = new ArrayList<>();
    for (float f : new float[]{0f, -0f, 1f, -1f, Float.MAX_VALUE, -Float.MAX_VALUE, Float.MIN_VALUE, Float.MIN_NORMAL, Float.NaN, Float.POSITIVE_INFINITY, Float.NEGATIVE_INFINITY,
        1e7f, 9999999f, 9999999.5f, 1e-3f, 0.001f, 0.00099999f, 1e-4f, 0.1f, 0.2f, 0.3f, 1.1f, 1e10f, 1e-10f, 123456.7f, 1234567f, 12345678f, 1.0E-5f, 2e23f, 1e23f, 8.816207E-4f, 1.0E-44f, 2.0E-45f,
        3.3f, 3.5f, 0.29f, 5.1f, 2.2352f, 1.4f, 1.6f, 100f, 0.5f, 0.05f, 33.333336f, 0.33333334f, 16777216f, 16777218f, 2147483647f, 1.9f, 4.35f, 9.5f, 1.17549435E-38f}) {
      floats.add(f);
    }
    for (int k = 0; k <= 5000; k++) floats.add(k / 100f);
    for (int i = 0; i < 2000; i++) floats.add((rnd.nextInt() & 0x7fffffff) / 100f);
    for (int i = 0; i < 1000; i++) floats.add(rnd.nextInt(1000000) / 100f);
    for (int i = 0; i < 8000; i++) {
      int exp = 1 + rnd.nextInt(254);
      int bits = (rnd.nextBoolean() ? 0x80000000 : 0) | (exp << 23) | rnd.nextInt(1 << 23);
      floats.add(Float.intBitsToFloat(bits));
    }
    for (int i = 0; i < 300; i++) floats.add(Float.intBitsToFloat(rnd.nextInt(1 << 23))); // subnormals
    for (int i = 0; i < 1000; i++) floats.add(Float.intBitsToFloat(rnd.nextInt())); // anything incl. NaN payloads
    sb.append("  \"toString\": [\n");
    for (int i = 0; i < floats.size(); i++) {
      if (i > 0) sb.append(",\n");
      sb.append("   ").append(floatEntry(floats.get(i)));
    }
    sb.append("\n  ],\n");

    // --- float arithmetic: [a, b, a+b, a-b, a*b, a/b] as raw bits
    sb.append("  \"arith\": [\n");
    for (int i = 0; i < 3000; i++) {
      float a, b;
      switch (i % 4) {
        case 0: a = Float.intBitsToFloat(rnd.nextInt()); b = Float.intBitsToFloat(rnd.nextInt()); break;
        case 1: a = rnd.nextInt(20000) / 100f; b = rnd.nextInt(20000) / 100f; break;
        case 2: a = (rnd.nextFloat() - 0.5f) * 1e5f; b = (rnd.nextFloat() - 0.5f) * 10f; break;
        default: a = floats.get(rnd.nextInt(floats.size())); b = floats.get(rnd.nextInt(floats.size())); break;
      }
      if (i > 0) sb.append(",\n");
      sb.append("   [").append(Float.floatToRawIntBits(a)).append(", ").append(Float.floatToRawIntBits(b)).append(", ")
        .append(Float.floatToRawIntBits(a + b)).append(", ").append(Float.floatToRawIntBits(a - b)).append(", ")
        .append(Float.floatToRawIntBits(a * b)).append(", ").append(Float.floatToRawIntBits(a / b)).append("]");
    }
    sb.append("\n  ],\n");

    // --- int <-> float: [i, bits(i / 100f), bits((float) i)] and [bits(f), (int) (Math.abs(f) * 100f), (int) f]
    sb.append("  \"intToFloat\": [\n");
    for (int i = 0; i < 3000; i++) {
      int v = i < 1500 ? rnd.nextInt() : (i < 2500 ? rnd.nextInt(200000) : rnd.nextInt(1 << 25) + (1 << 24));
      if (i > 0) sb.append(",\n");
      sb.append("   [").append(v).append(", ").append(Float.floatToRawIntBits(v / 100f)).append(", ").append(Float.floatToRawIntBits((float) v)).append("]");
    }
    sb.append("\n  ],\n");
    sb.append("  \"floatToInt\": [\n");
    for (int i = 0; i < 3000; i++) {
      float f = i < 1000 ? Float.intBitsToFloat(rnd.nextInt()) : (i < 2000 ? rnd.nextInt(100000) / 100f : (rnd.nextFloat() - 0.5f) * 1e10f);
      if (i == 2999) f = Float.NaN;
      if (i == 2998) f = Float.POSITIVE_INFINITY;
      if (i == 2997) f = -3e9f;
      if (i > 0) sb.append(",\n");
      sb.append("   [").append(Float.floatToRawIntBits(f)).append(", ").append((int) (Math.abs(f) * 100f)).append(", ").append((int) f).append("]");
    }
    sb.append("\n  ],\n");

    // --- String.format(Locale.US, "%3.1f", f): bits -> string
    List<Float> fmt = new ArrayList<>();
    for (int k = 0; k <= 2000; k++) fmt.add(k / 100f);
    for (int k = 0; k <= 200; k++) fmt.add(k / 1000f);
    for (int i = 0; i < 1500; i++) fmt.add(rnd.nextFloat() * 10000f);
    for (int i = 0; i < 300; i++) fmt.add(Float.intBitsToFloat(rnd.nextInt() & 0x7fffffff));
    for (int i = 0; i < 300; i++) fmt.add(rnd.nextInt(3000) * 0.3048f);
    for (int i = 0; i < 300; i++) fmt.add((rnd.nextInt(3000) + rnd.nextInt(12) / 12f) * 0.3048f);
    for (int i = 0; i < 300; i++) fmt.add(rnd.nextInt(30000) / 100f);
    for (int i = 0; i < 300; i++) fmt.add(rnd.nextInt(200) * 1.609344f);
    for (float f : new float[]{0.05f, 0.15f, 0.25f, 0.35f, 0.45f, 1.05f, 2.5f, 0.95f, 9.95f, 99.95f, 0.049999f, 1e10f, 1e-10f, -0.05f, -1.25f, Float.NaN, Float.POSITIVE_INFINITY, Float.NEGATIVE_INFINITY, Float.MAX_VALUE, Float.MIN_VALUE, 0f, -0f}) fmt.add(f);
    sb.append("  \"format1\": [\n");
    for (int i = 0; i < fmt.size(); i++) {
      if (i > 0) sb.append(",\n");
      float f = fmt.get(i);
      sb.append("   [").append(Float.floatToRawIntBits(f)).append(", ").append(quote(String.format(java.util.Locale.US, "%3.1f", f))).append("]");
    }
    sb.append("\n  ],\n");

    // --- Integer.parseInt: string -> value or null
    sb.append("  \"parseInt\": [\n");
    String[] ints = {"0", "1", "-1", "+1", "007", "2147483647", "2147483648", "-2147483648", "-2147483649", "12345678901", "", " ", " 1", "1 ", "1.0", "1e3", "abc", "-", "+", "--1", "+-1", "6", "12", "٣", "1_0", "0x10", "99999999999999999999"};
    for (int i = 0; i < ints.length; i++) {
      if (i > 0) sb.append(",\n");
      sb.append("   [").append(quote(ints[i])).append(", ");
      try {
        sb.append(Integer.parseInt(ints[i]));
      } catch (NumberFormatException e) {
        sb.append("null");
      }
      sb.append("]");
    }
    sb.append("\n  ],\n");

    // --- Arrays.hashCode(float[]): [[bits...], hash]
    sb.append("  \"arraysHashCode\": [\n");
    for (int i = 0; i < 200; i++) {
      int n = rnd.nextInt(45);
      float[] a = new float[n];
      for (int k = 0; k < n; k++) a[k] = k % 3 == 0 ? Float.intBitsToFloat(rnd.nextInt()) : rnd.nextInt(2000) / 100f;
      if (i == 0) a = new float[]{Float.NaN, Float.intBitsToFloat(0x7fc00001), Float.intBitsToFloat(0xffc00000), -0f, 0f};
      if (i > 0) sb.append(",\n");
      sb.append("   [[");
      for (int k = 0; k < a.length; k++) {
        if (k > 0) sb.append(", ");
        sb.append(Float.floatToRawIntBits(a[k]));
      }
      sb.append("], ").append(Arrays.hashCode(a)).append("]");
    }
    sb.append("\n  ],\n");

    // --- Character.isWhitespace: every code unit below 0x3100 that is whitespace
    sb.append("  \"isWhitespace\": [");
    boolean first = true;
    for (int c = 0; c < 0x3100; c++) {
      if (Character.isWhitespace((char) c)) {
        if (!first) sb.append(", ");
        first = false;
        sb.append(c);
      }
    }
    sb.append("],\n");

    // --- String.trim / split as used by the value conversion: [s, trimmed, split-on-"ft" pieces]
    sb.append("  \"split\": [\n");
    String[] splits = {"5ft", "5ft6in", "ft6", "ft", "5ft6ft", "5", "", "ftft", "5ftft", "a't", "1'6\"", "'6", "5'", "'", "50cm", "cm", "5 ft", "5kg", "kg5", "t", "5t", "5.5st", "st"};
    for (int i = 0; i < splits.length; i++) {
      if (i > 0) sb.append(",\n");
      String s = splits[i];
      sb.append("   [").append(quote(s)).append(", ").append(quote(s.trim()));
      for (String sep : new String[]{"ft", "'", "cm", "t", "st", "kg"}) {
        String[] sa = s.split(sep);
        sb.append(", ").append(jsonStrings(Arrays.asList(sa)));
      }
      sb.append("]");
    }
    sb.append("\n  ]\n}\n");
    writeFile(new File(outDir, "float.json"), sb.toString());
    System.err.println("wrote " + new File(outDir, "float.json"));
  }

  // ------------------------------------------------- raw micro-cache bytes --

  /** Locate the micro-cache for a position; returns {osmf, lonIdx, latIdx, subIdx}. */
  private static Object[] locateMicroCache(File rd5, double lon, double lat, DataBuffers dataBuffers) throws Exception {
    int ilon = toIlon(lon);
    int ilat = toIlat(lat);
    PhysicalFile pf = new PhysicalFile(rd5, dataBuffers, -1, -1);
    int div = pf.divisor;
    int cellsize = 1000000 / div;
    int lonDegree = ilon / 1000000;
    int latDegree = ilat / 1000000;
    OsmFile osmf = new OsmFile(pf, lonDegree, latDegree, dataBuffers);
    int lonIdx = ilon / cellsize;
    int latIdx = ilat / cellsize;
    int subIdx = (latIdx - div * latDegree) * div + (lonIdx - div * lonDegree);
    return new Object[]{osmf, lonIdx, latIdx, subIdx, div, pf};
  }

  /** The encoded micro-cache exactly as stored in the rd5, crc footer included. */
  private static byte[] rawMicroCache(OsmFile osmf, int subIdx) throws IOException {
    byte[] ab = new byte[65636];
    int asize = osmf.getDataInputForSubIdx(subIdx, ab);
    if (asize > ab.length) {
      ab = new byte[asize];
      asize = osmf.getDataInputForSubIdx(subIdx, ab);
    }
    return Arrays.copyOf(ab, asize);
  }

  private static void microCacheBytes(String[] args) throws Exception {
    File rd5 = new File(args[1]);
    double lon = Double.parseDouble(args[2]);
    double lat = Double.parseDouble(args[3]);
    File out = new File(args[4]);
    DataBuffers dataBuffers = new DataBuffers();
    Object[] loc = locateMicroCache(rd5, lon, lat, dataBuffers);
    OsmFile osmf = (OsmFile) loc[0];
    if (!osmf.hasData()) {
      System.err.println("no data for that degree square");
      System.exit(1);
    }
    byte[] raw = rawMicroCache(osmf, (Integer) loc[3]);
    try (FileOutputStream fos = new FileOutputStream(out)) {
      fos.write(raw);
    }
    System.err.println("wrote " + raw.length + " bytes (lonIdx=" + loc[1] + " latIdx=" + loc[2] + " divisor=" + loc[4] + ") to " + out);
  }

  /** All body bytes of a decoded cache in index order (getAndClear + readByte, public API only). */
  private static byte[][] readBodies(MicroCache mc) {
    int size = mc.getSize();
    byte[][] bodies = new byte[size][];
    for (int i = 0; i < size; i++) {
      long id = mc.getIdForIndex(i);
      if (!mc.getAndClear(id)) throw new IllegalStateException("getAndClear failed for index " + i);
      ByteArrayOutputStream bos = new ByteArrayOutputStream();
      while (mc.hasMoreData()) bos.write(mc.readByte());
      bodies[i] = bos.toByteArray();
    }
    return bodies;
  }

  private static void microCacheListing(String[] args) throws Exception {
    File rd5 = new File(args[1]);
    double lon = Double.parseDouble(args[2]);
    double lat = Double.parseDouble(args[3]);
    int nbodies = Integer.parseInt(opt(args, "--bodies", "50"));

    DataBuffers dataBuffers = new DataBuffers();
    Object[] loc = locateMicroCache(rd5, lon, lat, dataBuffers);
    OsmFile osmf = (OsmFile) loc[0];
    int lonIdx = (Integer) loc[1];
    int latIdx = (Integer) loc[2];
    int subIdx = (Integer) loc[3];
    int div = (Integer) loc[4];
    if (!osmf.hasData()) {
      System.err.println("no data for that degree square");
      System.exit(1);
    }
    byte[] raw = rawMicroCache(osmf, subIdx);
    int asize = raw.length;
    int crcData = Crc32.crc(raw, 0, asize - 4);
    int crcFooter = new ByteDataReader(raw, asize - 4).readInt();

    // decode #1: the listing
    StatCoderContext bc = new StatCoderContext(raw);
    MicroCache2 mc = new MicroCache2(bc, dataBuffers, lonIdx, latIdx, div, null, null);
    int readBytes = (bc.getReadingBitPosition() + 7) >> 3;
    int size = mc.getSize();
    long[] ids = new long[size];
    for (int i = 0; i < size; i++) ids[i] = mc.getIdForIndex(i);
    byte[][] bodies = readBodies(mc);
    ByteArrayOutputStream all = new ByteArrayOutputStream();
    for (byte[] b : bodies) all.write(b);
    byte[] allBytes = all.toByteArray();

    // decode #2: a fresh instance for re-encoding (getAndClear marks nodes consumed)
    MicroCache2 mc2 = new MicroCache2(new StatCoderContext(raw), new DataBuffers(), lonIdx, latIdx, div, null, null);
    byte[] encbuf = new byte[2 * asize + 65536];
    int enclen = mc2.encodeMicroCache(encbuf);
    byte[] enc = Arrays.copyOf(encbuf, enclen);
    MicroCache2 mc3 = new MicroCache2(new StatCoderContext(enc), new DataBuffers(), lonIdx, latIdx, div, null, null);
    String cmp = mc2.compareWith(mc3);

    StringBuilder sb = new StringBuilder();
    sb.append("{\n");
    kv(sb, 1, "tool", "microcache-listing"); sb.append(",\n");
    kv(sb, 1, "file", rd5.getName()); sb.append(",\n");
    kv(sb, 1, "divisor", div); sb.append(",\n");
    kv(sb, 1, "lonIdx", lonIdx); sb.append(",\n");
    kv(sb, 1, "latIdx", latIdx); sb.append(",\n");
    kv(sb, 1, "subIdx", subIdx); sb.append(",\n");
    kv(sb, 1, "encodedSize", asize); sb.append(",\n");
    kv(sb, 1, "encodedCrc", crcData); sb.append(",\n");
    kv(sb, 1, "footerCrc", crcFooter); sb.append(",\n");
    kv(sb, 1, "readBytes", readBytes); sb.append(",\n");
    kv(sb, 1, "size", size); sb.append(",\n");
    kv(sb, 1, "dataSize", mc.getDataSize()); sb.append(",\n");
    kv(sb, 1, "bodiesTotal", allBytes.length); sb.append(",\n");
    kv(sb, 1, "bodiesCrc", Crc32.crc(allBytes, 0, allBytes.length)); sb.append(",\n");
    ByteDataWriter idw = new ByteDataWriter(new byte[8 * size]);
    for (int i = 0; i < size; i++) idw.writeLong(ids[i]);
    kv(sb, 1, "idsCrc", Crc32.crc(idw.toByteArray(), 0, 8 * size)); sb.append(",\n");
    kv(sb, 1, "bodies", nbodies); sb.append(",\n");
    sb.append("  \"reencoded\": {");
    sb.append("\"length\": ").append(enclen);
    sb.append(", \"crc\": ").append(Crc32.crc(enc, 0, enclen));
    sb.append(", \"head\": ").append(quote(hex(Arrays.copyOf(enc, Math.min(64, enclen)))));
    sb.append(", \"compare\": ").append(cmp == null ? "null" : quote(cmp));
    sb.append("},\n");
    sb.append("  \"nodes\": [\n");
    for (int i = 0; i < size; i++) {
      if (i > 0) sb.append(",\n");
      sb.append("   \"").append(bodies[i].length).append(' ')
        .append(Crc32.crc(bodies[i], 0, bodies[i].length)).append('"');
    }
    sb.append("\n  ],\n");
    sb.append("  \"heads\": [\n");
    for (int i = 0; i < Math.min(nbodies, size); i++) {
      if (i > 0) sb.append(",\n");
      sb.append("   ").append(quote(ids[i] + " " + hex(bodies[i])));
    }
    sb.append("\n  ]\n}\n");
    System.out.print(sb);
  }


  // ------------------------------------------------------ mapaccess (R2) ----

  /** The 25-entry file index and the trailer, read the way PhysicalFile does (its fields are package-private). */
  private static void osmFileIndex(String[] args) throws Exception {
    File rd5 = new File(args[1]);
    String name = rd5.getName();
    // W20_N30.rd5 -> lonBase = 160 (degrees east of -180), latBase = 120
    Matcher m = Pattern.compile("([EW])(\\d+)_([NS])(\\d+)\\.rd5").matcher(name);
    if (!m.matches()) { System.err.println("tile name must look like W20_N30.rd5"); System.exit(2); }
    int lon = Integer.parseInt(m.group(2)) * (m.group(1).equals("W") ? -1 : 1);
    int lat = Integer.parseInt(m.group(4)) * (m.group(3).equals("S") ? -1 : 1);
    int lonBase = lon + 180;
    int latBase = lat + 90;

    byte[] head = new byte[200];
    long len;
    try (java.io.RandomAccessFile raf = new java.io.RandomAccessFile(rd5, "r")) {
      raf.readFully(head, 0, 200);
      len = raf.length();
    }
    ByteDataReader dis = new ByteDataReader(head);
    long[] fileIndex = new long[25];
    int headerVersion = -1;
    for (int i = 0; i < 25; i++) {
      long lv = dis.readLong();
      if (i == 0) headerVersion = (short) (lv >> 48);
      fileIndex[i] = lv & 0xffffffffffffL;
    }
    int[] headerCrcs = null;
    long pos = fileIndex[24];
    if (len != pos) {
      int extraLen = 8 + 26 * 4;
      if ((len - pos) > extraLen) extraLen++;
      byte[] extra = new byte[extraLen];
      try (java.io.RandomAccessFile raf = new java.io.RandomAccessFile(rd5, "r")) {
        raf.seek(pos);
        raf.readFully(extra, 0, extraLen);
      }
      ByteDataReader r = new ByteDataReader(extra);
      r.readLong(); // creationTime
      r.readInt();  // top index crc
      headerCrcs = new int[25];
      for (int i = 0; i < 25; i++) headerCrcs[i] = r.readInt();
    }

    DataBuffers dataBuffers = new DataBuffers();
    PhysicalFile pf = new PhysicalFile(rd5, dataBuffers, -1, -1);
    int div = pf.divisor;

    StringBuilder sb = new StringBuilder();
    sb.append("{\n");
    kv(sb, 1, "tool", "osmfile-index"); sb.append(",\n");
    kv(sb, 1, "file", name); sb.append(",\n");
    kv(sb, 1, "length", len); sb.append(",\n");
    kv(sb, 1, "headerLookupVersion", headerVersion); sb.append(",\n");
    kv(sb, 1, "checkVersionIntegrity", PhysicalFile.checkVersionIntegrity(rd5)); sb.append(",\n");
    kv(sb, 1, "creationTime", pf.creationTime); sb.append(",\n");
    kv(sb, 1, "divisor", div); sb.append(",\n");
    kv(sb, 1, "elevationType", pf.elevationType); sb.append(",\n");
    kv(sb, 1, "lonBase", lonBase); sb.append(",\n");
    kv(sb, 1, "latBase", latBase); sb.append(",\n");
    sb.append("  \"fileIndex\": ").append(longs(fileIndex)).append(",\n");
    sb.append("  \"fileHeaderCrcs\": ").append(headerCrcs == null ? "null" : ints(headerCrcs)).append(",\n");
    sb.append("  \"squares\": [\n");
    byte[] buf = new byte[4 * 1024 * 1024];
    for (int lonDegree = lonBase; lonDegree < lonBase + 5; lonDegree++) {
      for (int latDegree = latBase; latDegree < latBase + 5; latDegree++) {
        int tileIndex = (lonDegree % 5) * 5 + (latDegree % 5);
        OsmFile osmf = new OsmFile(pf, lonDegree, latDegree, dataBuffers);
        if (tileIndex > 0 || lonDegree > lonBase) sb.append(",\n");
        sb.append("   {\"tileIndex\": ").append(tileIndex)
          .append(", \"lonDegree\": ").append(lonDegree)
          .append(", \"latDegree\": ").append(latDegree)
          .append(", \"hasData\": ").append(osmf.hasData())
          .append(", \"fileOffset\": ").append(tileIndex > 0 ? fileIndex[tileIndex - 1] : 200L)
          .append(", \"elevationType\": ").append((int) pf.elevationType); // OsmFile copies it for every square of a present file
        if (osmf.hasData()) {
          int count = 0;
          long total = 0;
          StringBuilder caches = new StringBuilder();
          for (int subIdx = 0; subIdx < div * div; subIdx++) {
            int size = osmf.getDataInputForSubIdx(subIdx, buf);
            if (size == 0) continue;
            if (size > buf.length) throw new IllegalStateException("cache larger than 4 MB");
            if (count > 0) caches.append(", ");
            caches.append('"').append(subIdx).append(' ').append(size).append(' ').append(Crc32.crc(buf, 0, size)).append('"');
            count++;
            total += size;
          }
          sb.append(", \"cacheCount\": ").append(count).append(", \"cacheBytes\": ").append(total);
          sb.append(", \"caches\": [").append(caches).append("]");
        }
        sb.append("}");
      }
    }
    sb.append("\n  ]\n}\n");
    System.out.print(sb);
    pf.close();
  }

  private static MatchedWaypoint mwp(String name, double lon, double lat) {
    MatchedWaypoint w = new MatchedWaypoint();
    w.waypoint = new OsmNode(toIlon(lon), toIlat(lat));
    w.name = name;
    return w;
  }

  private static String posJson(OsmNode n) {
    return n == null ? "null" : "{\"ilon\": " + n.ilon + ", \"ilat\": " + n.ilat + "}";
  }

  private static String mwpJson(MatchedWaypoint w, boolean withNearest) {
    StringBuilder sb = new StringBuilder("{");
    sb.append("\"name\": ").append(quote(w.name));
    sb.append(", \"waypoint\": ").append(posJson(w.waypoint));
    sb.append(", \"crosspoint\": ").append(posJson(w.crosspoint));
    sb.append(", \"node1\": ").append(posJson(w.node1));
    sb.append(", \"node2\": ").append(posJson(w.node2));
    sb.append(", \"radius\": ").append(quote(hexd(w.radius)));
    sb.append(", \"directionToNext\": ").append(quote(hexd(w.directionToNext)));
    sb.append(", \"directionDiff\": ").append(quote(hexd(w.directionDiff)));
    sb.append(", \"wpttype\": ").append(w.wpttype);
    if (withNearest) {
      sb.append(", \"wayNearest\": [");
      for (int i = 0; i < w.wayNearest.size(); i++) {
        if (i > 0) sb.append(", ");
        sb.append(mwpJson(w.wayNearest.get(i), false));
      }
      sb.append("]");
    }
    return sb.append("}").toString();
  }

  /** A full node: everything OsmNode/OsmLink/TurnRestriction/GeometryDecoder expose. */
  private static String nodeJson(OsmNode node, GeometryDecoder gd) {
    StringBuilder sb = new StringBuilder("{");
    sb.append("\"id64\": ").append(node.getIdFromPos());
    sb.append(", \"ilon\": ").append(node.ilon);
    sb.append(", \"ilat\": ").append(node.ilat);
    sb.append(", \"selev\": ").append(node.selev);
    sb.append(", \"hollow\": ").append(node.isHollow());
    sb.append(", \"visitID\": ").append(node.visitID);
    sb.append(", \"nodeDescription\": ").append(node.nodeDescription == null ? "null" : quote(hex(node.nodeDescription)));
    sb.append(", \"turnRestrictions\": [");
    boolean first = true;
    for (TurnRestriction tr = node.firstRestriction; tr != null; tr = tr.next) {
      if (!first) sb.append(", ");
      first = false;
      sb.append("{\"isPositive\": ").append(tr.isPositive)
        .append(", \"exceptions\": ").append(tr.exceptions)
        .append(", \"fromLon\": ").append(tr.fromLon)
        .append(", \"fromLat\": ").append(tr.fromLat)
        .append(", \"toLon\": ").append(tr.toLon)
        .append(", \"toLat\": ").append(tr.toLat)
        .append("}");
    }
    sb.append("], \"links\": [");
    first = true;
    for (OsmLink link = node.firstlink; link != null; link = link.getNext(node)) {
      OsmNode target = link.getTarget(node);
      boolean reverse = link.isReverse(node);
      if (!first) sb.append(", ");
      first = false;
      int targetLinks = 0;
      for (OsmLink tl = target.firstlink; tl != null; tl = tl.getNext(target)) targetLinks++;
      sb.append("{\"targetIlon\": ").append(target.ilon)
        .append(", \"targetIlat\": ").append(target.ilat)
        .append(", \"targetSelev\": ").append(target.selev)
        .append(", \"targetHollow\": ").append(target.isHollow())
        .append(", \"targetVisitID\": ").append(target.visitID)
        .append(", \"targetLinks\": ").append(targetLinks)
        .append(", \"reverse\": ").append(reverse)
        .append(", \"bidirectional\": ").append(link.isBidirectional())
        .append(", \"linkIsNode\": ").append(link instanceof OsmNode);
      byte[] d = link.descriptionBitmap;
      sb.append(", \"descriptionBitmap\": ").append(d == null ? "null" : quote(hex(d)));
      byte[] g = link.geometry;
      sb.append(", \"geometryBytes\": ").append(g == null ? "null" : quote(hex(g)));
      sb.append(", \"transferNodes\": [");
      if (g != null) {
        boolean firstT = true;
        for (OsmTransferNode tn = gd.decodeGeometry(g, node, target, reverse); tn != null; tn = tn.next) {
          if (!firstT) sb.append(", ");
          firstT = false;
          sb.append("{\"ilon\": ").append(tn.ilon).append(", \"ilat\": ").append(tn.ilat).append(", \"selev\": ").append(tn.selev).append("}");
        }
      }
      sb.append("]}");
    }
    return sb.append("]}").toString();
  }

  /** One compact record per walked node: id, selev, link count, hollow targets, crc of all link data. */
  private static String walkRecord(OsmNode n, GeometryDecoder gd, ByteDataWriter w, byte[] buf) {
    w.reset(buf);
    int nlinks = 0;
    int nhollow = 0;
    for (OsmLink link = n.firstlink; link != null; link = link.getNext(n)) {
      OsmNode t = link.getTarget(n);
      boolean reverse = link.isReverse(n);
      nlinks++;
      if (t.isHollow()) nhollow++;
      w.writeLong(t.getIdFromPos());
      w.writeBoolean(reverse);
      w.writeBoolean(link.isBidirectional());
      w.writeShort(t.selev);
      w.writeVarBytes(link.descriptionBitmap);
      w.writeVarBytes(link.geometry);
      if (link.geometry != null) {
        for (OsmTransferNode tn = gd.decodeGeometry(link.geometry, n, t, reverse); tn != null; tn = tn.next) {
          w.writeInt(tn.ilon);
          w.writeInt(tn.ilat);
          w.writeShort(tn.selev);
        }
      }
    }
    for (TurnRestriction tr = n.firstRestriction; tr != null; tr = tr.next) {
      w.writeBoolean(tr.isPositive);
      w.writeShort(tr.exceptions);
      w.writeInt(tr.fromLon); w.writeInt(tr.fromLat); w.writeInt(tr.toLon); w.writeInt(tr.toLat);
    }
    byte[] data = w.toByteArray();
    return n.getIdFromPos() + " " + n.selev + " " + n.visitID + " " + nlinks + " " + nhollow + " " + Crc32.crc(data, 0, data.length);
  }

  private static void nodesCacheWalk(String[] args) throws Exception {
    File segDir = new File(args[1]);
    double lon = Double.parseDouble(args[2]);
    double lat = Double.parseDouble(args[3]);
    double lon2 = Double.parseDouble(args[4]);
    double lat2 = Double.parseDouble(args[5]);
    long maxmem = Long.parseLong(opt(args, "--maxmem", String.valueOf(64L * 1024L * 1024L)));
    boolean noDirect = flag(args, "--no-direct-weaving");
    int cleanupMode = Integer.parseInt(opt(args, "--cleanup-mode", "2"));
    int steps = Integer.parseInt(opt(args, "--steps", "200"));
    int collectMaxCost = Integer.parseInt(opt(args, "--collect-max-cost", "1500"));
    String lookupsOpt = opt(args, "--lookups", null);
    if (lookupsOpt == null) { System.err.println("--lookups <lookups.dat> is required"); System.exit(2); }
    if (noDirect) System.setProperty("disableDirectWeaving", "true");

    // lookups.dat only, no profile: every way is kept (accessType 2), all tag
    // indexes are "used" so nothing is filtered out of the descriptions.
    // A way context needs a parsed expression list before accessType() can be
    // called, so a minimal profile is used: costfactor 1 for every way (so
    // accessType is always 2, nothing is filtered, no noStartWay), plus
    // setAllTagsUsed() so the decoder keeps every tag of every description.
    // The Dart tests reproduce that with a trivial TagValueValidator.
    BExpressionMetaData meta = new BExpressionMetaData();
    BExpressionContextWay ctxWay = new BExpressionContextWay(meta); // registers itself; readMetaData finishes it
    meta.readMetaData(new File(lookupsOpt));
    String profileOpt = opt(args, "--profile", null);
    if (profileOpt != null) {
      // the real thing: RoutingEngine parses the profile and does not call
      // setAllTagsUsed (unless processUnusedTags), so unused tags are filtered
      // from the descriptions and inaccessible ways drop out
      ctxWay.parseFile(new File(profileOpt), "global");
    } else {
      File allWays = File.createTempFile("allways", ".brf");
      allWays.deleteOnExit();
      writeFile(allWays, "---context:way\nassign costfactor = 1\n");
      ctxWay.parseFile(allWays, "global");
      ctxWay.setAllTagsUsed();
    }

    GeometryDecoder gd = new GeometryDecoder();
    StringBuilder sb = new StringBuilder();
    sb.append("{\n");
    kv(sb, 1, "tool", "nodes-cache-walk"); sb.append(",\n");
    kv(sb, 1, "segmentsDir", segDir.getName()); sb.append(",\n");
    kv(sb, 1, "from", lon + "," + lat); sb.append(",\n");
    kv(sb, 1, "to", lon2 + "," + lat2); sb.append(",\n");
    kv(sb, 1, "maxmem", maxmem); sb.append(",\n");
    kv(sb, 1, "directWeaving", !noDirect); sb.append(",\n");
    kv(sb, 1, "cleanupMode", cleanupMode); sb.append(",\n");
    kv(sb, 1, "steps", steps); sb.append(",\n");
    kv(sb, 1, "collectMaxCost", collectMaxCost); sb.append(",\n");
    kv(sb, 1, "lookupVersion", meta.lookupVersion); sb.append(",\n");
    kv(sb, 1, "lookupMinorVersion", meta.lookupMinorVersion); sb.append(",\n");
    if (profileOpt != null) { kv(sb, 1, "profile", new File(profileOpt).getName()); sb.append(",\n"); }

    // phase 1: RoutingEngine.matchWaypointsToNodes = resetCache(false) + NodesCache.matchWaypointsToNodes
    NodesCache cache = new NodesCache(segDir, ctxWay, false, maxmem, null, false);
    List<MatchedWaypoint> list = new ArrayList<>();
    list.add(mwp("from", lon, lat));
    list.add(mwp("to", lon2, lat2));
    OsmNodePairSet islands = new OsmNodePairSet(500);
    boolean ok = cache.matchWaypointsToNodes(list, 250., islands);
    sb.append("  \"match\": {\"ok\": ").append(ok);
    sb.append(", \"firstFileAccessFailed\": ").append(cache.first_file_access_failed);
    sb.append(", \"firstFileAccessName\": ").append(quote(cache.first_file_access_name));
    sb.append(", \"status\": ").append(quote(cache.formatStatus()));
    sb.append(", \"nodesCreated\": ").append(cache.nodesMap.nodesCreated);
    sb.append(", \"elevationType\": ").append(cache.getElevationType(toIlon(lon), toIlat(lat)));
    sb.append(", \"waypoints\": [");
    for (int i = 0; i < list.size(); i++) {
      if (i > 0) sb.append(", ");
      sb.append(mwpJson(list.get(i), true));
    }
    sb.append("]},\n");
    if (!ok) {
      sb.append("  \"expand\": null, \"walk\": null, \"startNode\": null\n}\n");
      System.out.print(sb);
      cache.close();
      return;
    }

    // phase 2: findTrack = resetCache(false), cleanupMode, getGraphNode + obtainNonHollowNode + expandHollowLinkTargets
    NodesCache cache2 = new NodesCache(segDir, ctxWay, false, maxmem, cache, false);
    cache2.nodesMap.cleanupMode = cleanupMode;
    sb.append("  \"expand\": {\"statusAfterReset\": ").append(quote(cache2.formatStatus()));
    sb.append(", \"nodes\": [\n");
    // all graph nodes first (hollow, in the map), then obtain + expand: the
    // order RoutingEngine._findTrack uses, and the only one that works with
    // direct weaving (a proxy created after its cell was woven stays hollow)
    List<OsmNode> graphNodes = new ArrayList<>();
    for (MatchedWaypoint w : list) {
      graphNodes.add(cache2.getGraphNode(w.node1));
      graphNodes.add(cache2.getGraphNode(w.node2));
    }
    OsmNode walkStart = graphNodes.get(0);
    boolean firstN = true;
    for (OsmNode n : graphNodes) {
      boolean obtained = cache2.obtainNonHollowNode(n);
      cache2.expandHollowLinkTargets(n);
      if (!firstN) sb.append(",\n");
      firstN = false;
      sb.append("   {\"obtained\": ").append(obtained).append(", \"node\": ").append(nodeJson(n, gd)).append("}");
    }
    sb.append("\n  ], \"status\": ").append(quote(cache2.formatStatus()));
    sb.append(", \"nodesCreated\": ").append(cache2.nodesMap.nodesCreated).append("},\n");

    // phase 3: breadth-first over `steps` nodes, obtaining every link target
    Deque<OsmNode> queue = new ArrayDeque<>();
    Set<Long> seen = new HashSet<>();
    queue.add(walkStart);
    seen.add(walkStart.getIdFromPos());
    List<String> records = new ArrayList<>();
    List<OsmNode> walked = new ArrayList<>();
    byte[] recordBuf = new byte[1 << 20];
    ByteDataWriter w = new ByteDataWriter(recordBuf);
    int obtainedCount = 0, failedCount = 0;
    while (!queue.isEmpty() && records.size() < steps) {
      OsmNode n = queue.poll();
      for (OsmLink link = n.firstlink; link != null; link = link.getNext(n)) {
        OsmNode t = link.getTarget(n);
        boolean got = cache2.obtainNonHollowNode(t);
        if (got) obtainedCount++; else failedCount++;
        if (got && seen.add(t.getIdFromPos())) queue.add(t);
      }
      records.add(walkRecord(n, gd, w, recordBuf));
      walked.add(n);
    }
    ByteDataWriter all = new ByteDataWriter(new byte[records.size() * 128 + 16]);
    for (String r : records) for (byte b : r.getBytes(StandardCharsets.US_ASCII)) all.writeByte(b);
    byte[] allBytes = all.toByteArray();
    sb.append("  \"walk\": {\"visited\": ").append(records.size());
    sb.append(", \"queued\": ").append(queue.size());
    sb.append(", \"obtained\": ").append(obtainedCount);
    sb.append(", \"failed\": ").append(failedCount);
    sb.append(", \"crc\": ").append(Crc32.crc(allBytes, 0, allBytes.length));
    sb.append(", \"status\": ").append(quote(cache2.formatStatus()));
    sb.append(", \"nodesCreated\": ").append(cache2.nodesMap.nodesCreated);
    sb.append(", \"records\": ").append(arr(quoteAll(records), true)).append("},\n");

    // phase 3b: the memory-panic path of RoutingEngine: collectOutreachers with a
    // destination and a cost bound (nodes further away vanish), then canEscape
    OsmNodesMap nm = cache2.nodesMap;
    nm.destination = graphNodes.get(2); // node1 of "to"
    nm.currentMaxCost = collectMaxCost;
    nm.currentPathCost = 0;
    int nodesCreatedBefore = nm.nodesCreated;
    nm.collectOutreachers();
    int nodesCreatedCollected = nm.nodesCreated;
    boolean escStart = nm.canEscape(walkStart);
    boolean escEnd = nm.canEscape(graphNodes.get(2));
    nm.clearTemp();
    List<String> records2 = new ArrayList<>();
    for (OsmNode n : walked) records2.add(walkRecord(n, gd, w, recordBuf));
    all = new ByteDataWriter(new byte[records2.size() * 128 + 16]);
    for (String r : records2) for (byte b : r.getBytes(StandardCharsets.US_ASCII)) all.writeByte(b);
    allBytes = all.toByteArray();
    sb.append("  \"collect\": {\"nodesCreatedBefore\": ").append(nodesCreatedBefore);
    sb.append(", \"nodesCreated\": ").append(nodesCreatedCollected);
    sb.append(", \"canEscapeStart\": ").append(escStart);
    sb.append(", \"canEscapeEnd\": ").append(escEnd);
    sb.append(", \"nodesCreatedAfterEscape\": ").append(nm.nodesCreated);
    sb.append(", \"lastVisitID\": ").append(nm.lastVisitID);
    sb.append(", \"baseID\": ").append(nm.baseID);
    sb.append(", \"crc\": ").append(Crc32.crc(allBytes, 0, allBytes.length));
    sb.append(", \"records\": ").append(arr(quoteAll(records2), true)).append("},\n");

    // phase 4: a fresh reset (reusing the file cache / ghosting virgin caches) and getStartNode
    NodesCache cache3 = new NodesCache(segDir, ctxWay, false, maxmem, cache2, false);
    cache3.nodesMap.cleanupMode = cleanupMode;
    String statusAfterReset3 = cache3.formatStatus();
    OsmNode start = cache3.getStartNode(list.get(0).node1.getIdFromPos());
    sb.append("  \"startNode\": {\"statusAfterReset\": ").append(quote(statusAfterReset3));
    sb.append(", \"node\": ").append(start == null ? "null" : nodeJson(start, gd));
    sb.append(", \"status\": ").append(quote(cache3.formatStatus()));
    sb.append(", \"nodesCreated\": ").append(cache3.nodesMap.nodesCreated).append("}\n}\n");
    System.out.print(sb);
    cache3.close();
  }

  private static List<String> quoteAll(List<String> xs) {
    List<String> out = new ArrayList<>(xs.size());
    for (String x : xs) out.add(quote(x));
    return out;
  }

  // ------------------------------------------------------- codec vectors ----

  private static void codecVectors(String[] args) throws Exception {
    File outDir = new File(args[1]);
    outDir.mkdirs();
    writeFile(new File(outDir, "bitcoder.json"), vecBitCoder());
    writeFile(new File(outDir, "statcoder.json"), vecStatCoder());
    writeFile(new File(outDir, "crc32.json"), vecCrc32());
    writeFile(new File(outDir, "cheapruler.json"), vecCheapRuler());
    writeFile(new File(outDir, "bytedata.json"), vecByteData());
    writeFile(new File(outDir, "streams.json"), vecStreams());
    writeFile(new File(outDir, "tagvaluecoder.json"), vecTagValueCoder());
    writeFile(new File(outDir, "noisydiff.json"), vecNoisyDiff());
    writeFile(new File(outDir, "collections.json"), vecCollections());
    writeFile(new File(outDir, "trig.json"), vecTrig());
    System.err.println("wrote vectors to " + outDir);
  }

  private static void writeFile(File f, String s) throws IOException {
    try (Writer w = new OutputStreamWriter(new FileOutputStream(f), StandardCharsets.UTF_8)) {
      w.write(s);
    }
  }

  /** A little JSON array builder: elements are already-serialised JSON. */
  private static String arr(List<String> items, boolean multiline) {
    StringBuilder b = new StringBuilder("[");
    for (int i = 0; i < items.size(); i++) {
      if (i > 0) b.append(",");
      b.append(multiline ? "\n   " : " ");
      b.append(items.get(i));
    }
    b.append(multiline ? "\n  ]" : " ]");
    return b.toString();
  }

  private static String ints(int[] a) {
    StringBuilder b = new StringBuilder("[");
    for (int i = 0; i < a.length; i++) {
      if (i > 0) b.append(", ");
      b.append(a[i]);
    }
    return b.append("]").toString();
  }

  private static String longs(long[] a) {
    StringBuilder b = new StringBuilder("[");
    for (int i = 0; i < a.length; i++) {
      if (i > 0) b.append(", ");
      b.append(a[i]);
    }
    return b.append("]").toString();
  }

  /** A double as Java prints it plus its exact bit pattern. */
  private static String dbl(double v) {
    return "{\"str\": " + quote(Double.toString(v)) + ", \"bits\": " + quote(Long.toHexString(Double.doubleToRawLongBits(v))) + "}";
  }

  private static String hexOrNull(byte[] ab) {
    return ab == null ? "null" : quote(hex(ab));
  }

  private static byte[] randomBytes(Random r, int n) {
    byte[] ab = new byte[n];
    r.nextBytes(ab);
    return ab;
  }

  private static String section(String name, List<String> cases) {
    return "{\n  \"tool\": \"codec-vectors\",\n  \"section\": " + quote(name) + ",\n  \"cases\": " + arr(cases, true) + "\n}\n";
  }

  // ---- BitCoderContext -----------------------------------------------------

  private static String vecBitCoder() {
    List<String> cases = new ArrayList<>();
    int[] basic = {0, 1, 2, 3, 4, 5, 6, 7, 8, 14, 15, 16, 30, 31, 32, 62, 63, 64, 126, 127, 128, 254, 255, 256,
      510, 511, 512, 1022, 1023, 1024, 2046, 2047, 2048, 4094, 4095, 4096, 4097, 8190, 8191, 8192, 65535, 65536,
      1 << 20, (1 << 20) + 3, 1 << 24, (1 << 24) - 1, 1 << 28, 1 << 30, (1 << 30) + 12345, Integer.MAX_VALUE - 2, Integer.MAX_VALUE - 1,
      -1, -2, -100, -4096, Integer.MIN_VALUE, 0, 7, 0}; // encodeVarBits(Integer.MAX_VALUE) does not terminate upstream
    cases.add(bitCaseFromValues("varbits-basic", "varbits", basic));
    cases.add(bitCaseFromValues("varbits2-basic", "varbits2", basic));
    int[] pow = new int[31 + 101];
    for (int i = 0; i < 31; i++) pow[i] = (1 << i) + 3;
    for (int i = 0; i < 101; i++) pow[31 + i] = i * 997;
    cases.add(bitCaseFromValues("varbits-main", "varbits", pow));
    // bits
    {
      List<String> ops = new ArrayList<>();
      Random r = new Random(1);
      for (int i = 0; i < 300; i++) ops.add("[\"bit\", " + (r.nextBoolean() ? 1 : 0) + "]");
      cases.add(runBitCase("bits-300", ops));
    }
    // bounded
    {
      List<String> ops = new ArrayList<>();
      int[][] pairs = {{0, 0}, {1, 0}, {1, 1}, {2, 0}, {2, 1}, {2, 2}, {3, 3}, {4, 4}, {5, 3}, {6, 6}, {7, 0}, {7, 7},
        {8, 8}, {100, 37}, {100, 100}, {255, 255}, {256, 256}, {1023, 511}, {1023, 1023}, {65535, 12345},
        {1000000, 999999}, {(1 << 29) - 1, 123456789}, {1 << 29, 1 << 29}, {(1 << 30) - 1, (1 << 30) - 1}};
      for (int[] p : pairs) ops.add("[\"bounded\", " + p[0] + ", " + p[1] + "]");
      Random r = new Random(2);
      for (int i = 0; i < 200; i++) {
        int max = r.nextInt(5000);
        int v = max == 0 ? 0 : r.nextInt(max + 1);
        ops.add("[\"bounded\", " + max + ", " + v + "]");
      }
      cases.add(runBitCase("bounded", ops));
    }
    // mixed
    {
      List<String> ops = new ArrayList<>();
      Random r = new Random(3);
      for (int i = 0; i < 400; i++) {
        switch (r.nextInt(4)) {
          case 0: ops.add("[\"varbits\", " + r.nextInt(1 << r.nextInt(31)) + "]"); break;
          case 1: ops.add("[\"varbits2\", " + r.nextInt(1 << r.nextInt(31)) + "]"); break;
          case 2: ops.add("[\"bit\", " + (r.nextBoolean() ? 1 : 0) + "]"); break;
          default: { int max = r.nextInt(100000); ops.add("[\"bounded\", " + max + ", " + (max == 0 ? 0 : r.nextInt(max + 1)) + "]"); }
        }
      }
      cases.add(runBitCase("mixed-400", ops));
    }
    // read-only cases on random bytes
    for (int seed = 10; seed < 13; seed++) {
      Random r = new Random(seed);
      byte[] bytes = randomBytes(r, 256);
      List<String> ops = new ArrayList<>();
      List<String> results = new ArrayList<>();
      BitCoderContext ctx = new BitCoderContext(bytes);
      for (int i = 0; i < 60; i++) {
        int kind = r.nextInt(7);
        String op;
        int res;
        switch (kind) {
          case 0: { int n = 1 + r.nextInt(24); op = "[\"bits\", " + n + "]"; res = ctx.decodeBits(n); break; }
          case 1: { int n = 1 + r.nextInt(30); op = "[\"bitsrev\", " + n + "]"; res = ctx.decodeBitsReverse(n); break; }
          case 2: { op = "[\"bit\"]"; res = ctx.decodeBit() ? 1 : 0; break; }
          case 3: { int max = r.nextInt(5000); op = "[\"bounded\", " + max + "]"; res = ctx.decodeBounded(max); break; }
          case 4: { op = "[\"varbits\"]"; res = ctx.decodeVarBits(); break; }
          case 5: { op = "[\"varbits2\"]"; res = ctx.decodeVarBits2(); break; }
          default: { int pos = r.nextInt(1500); op = "[\"setpos\", " + pos + "]"; ctx.setReadingBitPosition(pos); res = ctx.getReadingBitPosition(); }
        }
        ops.add(op);
        results.add(Integer.toString(res));
        ops.add("[\"pos\"]");
        results.add(Integer.toString(ctx.getReadingBitPosition()));
      }
      cases.add("{\"name\": " + quote("read-random-" + seed) + ", \"bytes\": " + quote(hex(bytes))
        + ", \"readops\": " + arr(ops, false) + ", \"results\": " + arr(results, false) + "}");
    }
    return section("bitcoder", cases);
  }

  private static String bitCaseFromValues(String name, String op, int[] values) {
    List<String> ops = new ArrayList<>();
    for (int v : values) ops.add("[\"" + op + "\", " + v + "]");
    return runBitCase(name, ops);
  }

  /** Encode the op list, then decode it again; ops are JSON arrays like ["varbits", 5]. */
  private static String runBitCase(String name, List<String> ops) {
    byte[] buf = new byte[1 << 20];
    BitCoderContext ctx = new BitCoderContext(buf);
    List<Object[]> parsed = new ArrayList<>();
    for (String op : ops) parsed.add(parseOp(op));
    for (Object[] op : parsed) {
      String n = (String) op[0];
      if (n.equals("varbits")) ctx.encodeVarBits((Integer) op[1]);
      else if (n.equals("varbits2")) ctx.encodeVarBits2((Integer) op[1]);
      else if (n.equals("bit")) ctx.encodeBit(((Integer) op[1]) != 0);
      else if (n.equals("bounded")) ctx.encodeBounded((Integer) op[1], (Integer) op[2]);
      else throw new IllegalArgumentException(n);
    }
    int len = ctx.closeAndGetEncodedLength();
    byte[] bytes = Arrays.copyOf(buf, len);
    // decode from a zero-padded copy: the last op may read past the encoded
    // bytes (a micro-cache always has its crc footer behind the data)
    BitCoderContext rd = new BitCoderContext(Arrays.copyOf(bytes, len + DECODE_PADDING));
    List<String> decoded = new ArrayList<>();
    for (Object[] op : parsed) {
      String n = (String) op[0];
      int v;
      if (n.equals("varbits")) v = rd.decodeVarBits();
      else if (n.equals("varbits2")) v = rd.decodeVarBits2();
      else if (n.equals("bit")) v = rd.decodeBit() ? 1 : 0;
      else v = rd.decodeBounded((Integer) op[1]);
      decoded.add(Integer.toString(v));
    }
    return "{\"name\": " + quote(name) + ", \"ops\": " + arr(ops, false) + ", \"bytes\": " + quote(hex(bytes))
      + ", \"decodePadding\": " + DECODE_PADDING + ", \"decoded\": " + arr(decoded, false) + "}";
  }

  private static final int DECODE_PADDING = 8;

  /** parse ["name", int, int...] written by ourselves. */
  private static Object[] parseOp(String op) {
    String s = op.substring(1, op.length() - 1);
    String[] parts = s.split(",");
    Object[] res = new Object[parts.length];
    res[0] = parts[0].trim().replace("\"", "");
    for (int i = 1; i < parts.length; i++) res[i] = Integer.parseInt(parts[i].trim());
    return res;
  }

  // ---- StatCoderContext ----------------------------------------------------

  private static String vecStatCoder() {
    List<String> cases = new ArrayList<>();
    // ops: ["noisynum", v, nb] ["noisydiff", v, nb] ["predicted", v, predictor] ["sorted", [values]] ["varbits", v] ["bit", b]
    {
      List<String> ops = new ArrayList<>();
      int[] nbs = {0, 1, 2, 5, 10, 14, 20, 24}; // decodeBits() guarantees only 24 bits, and noisybits=31 would not terminate upstream
      int[] vals = {0, 1, 2, 3, 31, 32, 33, 1023, 1024, 1025, 65535, 1 << 20, (1 << 30) + 7, Integer.MAX_VALUE - 1};
      for (int nb : nbs) for (int v : vals) ops.add("[\"noisynum\", " + v + ", " + nb + "]");
      cases.add(runStatCase("noisynumber", ops));
    }
    {
      List<String> ops = new ArrayList<>();
      int[] nbs = {0, 1, 2, 5, 10, 14, 20, 24};
      int[] vals = {0, 1, -1, 2, -2, 3, -3, 31, -31, 32, -32, 33, -33, 511, -511, 512, -512, 513, -513, 1023, -1024,
        1025, -1025, 65535, -65536, 1 << 20, -(1 << 20), (1 << 30) + 7, -((1 << 30) + 7), Integer.MAX_VALUE - 1, -(Integer.MAX_VALUE - 1)}; // MIN_VALUE with noisybits=0 desyncs upstream (sign bit written but never read)
      for (int nb : nbs) for (int v : vals) ops.add("[\"noisydiff\", " + v + ", " + nb + "]");
      cases.add(runStatCase("noisydiff", ops));
    }
    {
      List<String> ops = new ArrayList<>();
      int[] preds = {0, 1, -1, 2, -2, 3, -3, 4, 5, 7, 8, 100, -100, 1023, -1023, 1024, -1024, 1025, 4095, 4096, 100000, -100000, 1 << 20, 1 << 29, -(1 << 29)};
      int[] vals = {0, 1, -1, 5, -5, 100, -100, 1000, -1000, 123456, -123456, 1 << 20, -(1 << 20)};
      for (int p : preds) for (int v : vals) ops.add("[\"predicted\", " + v + ", " + p + "]");
      cases.add(runStatCase("predicted", ops));
    }
    {
      List<String> ops = new ArrayList<>();
      ops.add("[\"sorted\", [0]]");
      ops.add("[\"sorted\", [5]]");
      ops.add("[\"sorted\", [0, 0]]");
      ops.add("[\"sorted\", [5, 5, 5]]");
      ops.add("[\"sorted\", [1, 2, 3, 1000, 536870912, 1073741823]]");
      ops.add("[\"sorted\", [0, 1073741823]]");
      Random r = new Random(4);
      for (int k = 0; k < 4; k++) {
        int n = 1 + r.nextInt(300);
        int[] a = new int[n];
        for (int i = 0; i < n; i++) a[i] = r.nextInt(k == 0 ? 1000 : (1 << 30));
        Arrays.sort(a);
        ops.add("[\"sorted\", " + ints(a) + "]");
      }
      // like a micro-cache: ids from shrinkId are < 2^30 and dense-ish
      int n = 2000;
      int[] a = new int[n];
      for (int i = 0; i < n; i++) a[i] = r.nextInt(1 << 30);
      Arrays.sort(a);
      ops.add("[\"sorted\", " + ints(a) + "]");
      cases.add(runStatCase("sortedarray", ops));
    }
    {
      List<String> ops = new ArrayList<>();
      Random r = new Random(5);
      for (int i = 0; i < 500; i++) {
        switch (r.nextInt(6)) {
          case 0: ops.add("[\"noisynum\", " + r.nextInt(1 << r.nextInt(31)) + ", " + r.nextInt(12) + "]"); break;
          case 1: ops.add("[\"noisydiff\", " + (r.nextInt(1 << r.nextInt(31)) * (r.nextBoolean() ? 1 : -1)) + ", " + r.nextInt(12) + "]"); break;
          case 2: ops.add("[\"predicted\", " + (r.nextInt(100000) - 50000) + ", " + (r.nextInt(100000) - 50000) + "]"); break;
          case 3: ops.add("[\"varbits\", " + r.nextInt(1 << r.nextInt(31)) + "]"); break;
          case 4: ops.add("[\"bit\", " + (r.nextBoolean() ? 1 : 0) + "]"); break;
          default: { int n = 1 + r.nextInt(20); int[] a = new int[n]; for (int j = 0; j < n; j++) a[j] = r.nextInt(1 << 16); Arrays.sort(a); ops.add("[\"sorted\", " + ints(a) + "]"); }
        }
      }
      cases.add(runStatCase("mixed-500", ops));
    }
    return section("statcoder", cases);
  }

  private static int[] parseIntList(String s) {
    s = s.trim();
    s = s.substring(1, s.length() - 1).trim();
    if (s.isEmpty()) return new int[0];
    String[] p = s.split(",");
    int[] a = new int[p.length];
    for (int i = 0; i < p.length; i++) a[i] = Integer.parseInt(p[i].trim());
    return a;
  }

  private static String runStatCase(String name, List<String> ops) {
    byte[] buf = new byte[1 << 20];
    StatCoderContext ctx = new StatCoderContext(buf);
    for (String op : ops) {
      String n = op.substring(2, op.indexOf('"', 2));
      if (n.equals("sorted")) {
        int[] a = parseIntList(op.substring(op.indexOf('[', 1), op.length() - 1));
        ctx.encodeSortedArray(a, 0, a.length, 0x20000000, 0);
      } else {
        Object[] p = parseOp(op);
        if (n.equals("noisynum")) ctx.encodeNoisyNumber((Integer) p[1], (Integer) p[2]);
        else if (n.equals("noisydiff")) ctx.encodeNoisyDiff((Integer) p[1], (Integer) p[2]);
        else if (n.equals("predicted")) ctx.encodePredictedValue((Integer) p[1], (Integer) p[2]);
        else if (n.equals("varbits")) ctx.encodeVarBits((Integer) p[1]);
        else if (n.equals("bit")) ctx.encodeBit(((Integer) p[1]) != 0);
        else throw new IllegalArgumentException(n);
      }
    }
    int len = ctx.closeAndGetEncodedLength();
    byte[] bytes = Arrays.copyOf(buf, len);
    StatCoderContext rd = new StatCoderContext(Arrays.copyOf(bytes, len + DECODE_PADDING));
    List<String> decoded = new ArrayList<>();
    for (String op : ops) {
      String n = op.substring(2, op.indexOf('"', 2));
      if (n.equals("sorted")) {
        int[] a = parseIntList(op.substring(op.indexOf('[', 1), op.length() - 1));
        int[] out = new int[a.length];
        rd.decodeSortedArray(out, 0, a.length, 29, 0);
        decoded.add(ints(out));
      } else {
        Object[] p = parseOp(op);
        int v;
        if (n.equals("noisynum")) v = rd.decodeNoisyNumber((Integer) p[2]);
        else if (n.equals("noisydiff")) v = rd.decodeNoisyDiff((Integer) p[2]);
        else if (n.equals("predicted")) v = rd.decodePredictedValue((Integer) p[2]);
        else if (n.equals("varbits")) v = rd.decodeVarBits();
        else v = rd.decodeBit() ? 1 : 0;
        decoded.add(Integer.toString(v));
      }
    }
    return "{\"name\": " + quote(name) + ", \"ops\": " + arr(ops, false) + ", \"bytes\": " + quote(hex(bytes))
      + ", \"decodePadding\": " + DECODE_PADDING + ", \"decoded\": " + arr(decoded, false) + "}";
  }

  // ---- Crc32 -----------------------------------------------------------------

  private static String vecCrc32() {
    List<String> cases = new ArrayList<>();
    List<byte[]> inputs = new ArrayList<>();
    inputs.add(new byte[0]);
    inputs.add("a".getBytes(StandardCharsets.US_ASCII));
    inputs.add("abc".getBytes(StandardCharsets.US_ASCII));
    inputs.add("123456789".getBytes(StandardCharsets.US_ASCII));
    byte[] seq = new byte[256];
    for (int i = 0; i < 256; i++) seq[i] = (byte) i;
    inputs.add(seq);
    byte[] ff = new byte[64];
    Arrays.fill(ff, (byte) 0xff);
    inputs.add(ff);
    inputs.add(randomBytes(new Random(6), 1000));
    for (byte[] in : inputs) {
      int[][] ranges = in.length < 1000 ? new int[][]{{0, in.length}} : new int[][]{{0, in.length}, {17, 500}, {999, 1}, {3, 0}};
      for (int[] rg : ranges) {
        cases.add("{\"bytes\": " + quote(hex(in)) + ", \"offset\": " + rg[0] + ", \"len\": " + rg[1] + ", \"crc\": " + Crc32.crc(in, rg[0], rg[1]) + "}");
      }
    }
    return section("crc32", cases);
  }

  // ---- CheapRuler / CheapAngleMeter -------------------------------------------

  private static String vecCheapRuler() {
    StringBuilder sb = new StringBuilder();
    sb.append("{\n  \"tool\": \"codec-vectors\",\n  \"section\": \"cheapruler\",\n");
    // the complete scale cache, as raw bits
    sb.append("  \"scaleCache\": [\n");
    for (int i = 0; i < 1800; i++) {
      double[] k = CheapRuler.getLonLatToMeterScales(i * 100000 + 50000);
      if (i > 0) sb.append(",\n");
      sb.append("   [").append(quote(Long.toHexString(Double.doubleToRawLongBits(k[0])))).append(", ")
        .append(quote(Long.toHexString(Double.doubleToRawLongBits(k[1])))).append("]");
    }
    sb.append("\n  ],\n");
    // named scale lookups
    int[] ilats = {0, 1, 99999, 100000, 100001, 50000000, 90000000, 122648500, 154141700, 179999999};
    List<String> scales = new ArrayList<>();
    for (int ilat : ilats) {
      double[] k = CheapRuler.getLonLatToMeterScales(ilat);
      scales.add("{\"ilat\": " + ilat + ", \"kx\": " + dbl(k[0]) + ", \"ky\": " + dbl(k[1]) + "}");
    }
    sb.append("  \"scales\": ").append(arr(scales, true)).append(",\n");
    // distances
    int[][] pts = {{163063505, 122635697, 163063509, 122636135}, {163091500, 122648500, 158073400, 154141700},
      {158073400, 154141700, 158073400, 154141700}, {0, 0, 359999999, 179999999}, {180000000, 90000000, 180000001, 90000001},
      {163063505, 122635697, 163063505, 122635697}, {100, 179999999, 359999900, 179999998}, {190000000, 135000000, 170000000, 45000000}};
    List<String> dists = new ArrayList<>();
    Random r = new Random(7);
    List<int[]> all = new ArrayList<>(Arrays.asList(pts));
    for (int i = 0; i < 40; i++) {
      int lon = r.nextInt(360000000), lat = r.nextInt(180000000);
      all.add(new int[]{lon, lat, lon + r.nextInt(200001) - 100000, Math.max(0, Math.min(179999999, lat + r.nextInt(200001) - 100000))});
    }
    for (int[] p : all) {
      dists.add("{\"p\": " + ints(p) + ", \"d\": " + dbl(CheapRuler.distance(p[0], p[1], p[2], p[3])) + "}");
    }
    sb.append("  \"distances\": ").append(arr(dists, true)).append(",\n");
    // destinations
    double[] angles = {0, 45, 90, 135, 180, 225, 270, 315, 359.9, -45, 720, 12.345};
    double[] dd = {0, 1, 100, 12345.678, 1e6};
    int[][] origins = {{163091500, 122648500}, {158073400, 154141700}, {180000000, 90000000}, {0, 0}, {359999999, 179999999}};
    List<String> dests = new ArrayList<>();
    for (int[] o : origins) for (double d : dd) for (double a : angles) {
      int[] res = CheapRuler.destination(o[0], o[1], d, a);
      dests.add("{\"lon\": " + o[0] + ", \"lat\": " + o[1] + ", \"dist\": " + dbl(d) + ", \"angle\": " + dbl(a) + ", \"res\": " + ints(res) + "}");
    }
    sb.append("  \"destinations\": ").append(arr(dests, true)).append(",\n");
    // angle meter
    List<String> angs = new ArrayList<>();
    int[][] triples = {{0, 0, 0, 0, 0, 0}, {163063505, 122635697, 163063509, 122636135, 163063458, 122636283},
      {163063505, 122635697, 163063509, 122636135, 163063509, 122636135}, {100, 100, 200, 100, 300, 100}, {100, 100, 200, 100, 100, 100},
      {100, 100, 200, 100, 200, 200}, {100, 100, 200, 100, 200, 0}, {100, 100, 200, 100, 300, 300}, {100, 100, 200, 100, 300, -100},
      {100, 100, 200, 100, 0, 200}, {100, 100, 200, 100, 0, 0}, {100, 100, 200, 100, 150, 400}, {100, 100, 200, 100, 150, -200},
      {1000, 122648500, 2000, 122648500, 2000, 122648501}};
    List<int[]> tl = new ArrayList<>(Arrays.asList(triples));
    for (int i = 0; i < 60; i++) {
      int lon = r.nextInt(360000000), lat = 1000000 + r.nextInt(178000000);
      tl.add(new int[]{lon + r.nextInt(2001) - 1000, lat + r.nextInt(2001) - 1000, lon, lat, lon + r.nextInt(2001) - 1000, lat + r.nextInt(2001) - 1000});
    }
    CheapAngleMeter am = new CheapAngleMeter();
    for (int[] t : tl) {
      double a = am.calcAngle(t[0], t[1], t[2], t[3], t[4], t[5]);
      angs.add("{\"p\": " + ints(t) + ", \"angle\": " + dbl(a) + ", \"cos\": " + dbl(am.getCosAngle())
        + ", \"getAngle\": " + dbl(CheapAngleMeter.getAngle(t[0], t[1], t[2], t[3]))
        + ", \"getDirection\": " + dbl(CheapAngleMeter.getDirection(t[0], t[1], t[2], t[3])) + "}");
    }
    sb.append("  \"angles\": ").append(arr(angs, true)).append(",\n");
    double[] norm = {0, 1, 359.9, 360, 360.1, 720.5, 1e6 + 0.25, -0.1, -1, -180, -359.9, -360, -360.1, -725, -1e6 - 0.25, 12.5};
    List<String> norms = new ArrayList<>();
    for (double a : norm) norms.add("{\"a\": " + dbl(a) + ", \"n\": " + dbl(CheapAngleMeter.normalize(a)) + "}");
    sb.append("  \"normalize\": ").append(arr(norms, true)).append(",\n");
    double[][] difs = {{0, 0}, {0, 180}, {180, 0}, {0, 181}, {181, 0}, {350, 10}, {10, 350}, {-90, 90}, {90, -90}, {720, 0}, {0.5, 359.5}, {359.5, 0.5},
      {45.25, 1000.75}, {-1000.75, 45.25}, {0, -180}, {0, 540}, {123.456, -654.321}};
    List<String> ds = new ArrayList<>();
    for (double[] d : difs) ds.add("{\"b1\": " + dbl(d[0]) + ", \"b2\": " + dbl(d[1]) + ", \"d\": " + dbl(CheapAngleMeter.getDifferenceFromDirection(d[0], d[1])) + "}");
    sb.append("  \"differences\": ").append(arr(ds, true)).append("\n}\n");
    return sb.toString();
  }

  // ---- ByteDataWriter / ByteDataReader -------------------------------------------

  private static String vecByteData() {
    List<String> cases = new ArrayList<>();
    // ops: ["int", v] ["long", v] ["short", v] ["byte", v] ["boolean", b] ["varsigned", v] ["varunsigned", v]
    //      ["varbytes", hex|null] ["modedesc", reverse, hex|null] ["sizeblock", n]  (n = number of following ops inside the block)
    List<String> ops = new ArrayList<>();
    int[] ints = {0, 1, -1, 127, 128, 255, 256, 32767, 32768, 65535, 65536, Integer.MAX_VALUE, Integer.MIN_VALUE, -2, 0x12345678, 0xdeadbeef};
    for (int v : ints) ops.add("[\"int\", " + v + "]");
    long[] longs = {0L, 1L, -1L, 255L, 65536L, 4294967295L, 4294967296L, Long.MAX_VALUE, Long.MIN_VALUE, -2L, 0x123456789abcdefL, 700352421268768177L};
    for (long v : longs) ops.add("[\"long\", " + v + "]");
    int[] shorts = {0, 1, -1, 127, 128, 255, 256, 32767, -32768, 65535, 65536, 70000, -70000};
    for (int v : shorts) ops.add("[\"short\", " + v + "]");
    int[] bytes = {0, 1, -1, 127, 128, 255, 256, 511, -129, 1000};
    for (int v : bytes) ops.add("[\"byte\", " + v + "]");
    ops.add("[\"boolean\", 1]");
    ops.add("[\"boolean\", 0]");
    int[] vs = {0, 1, -1, 63, 64, -64, -65, 127, 128, 8191, 8192, -8192, -8193, 1048575, 1048576, 134217727, 134217728, -134217728, -134217729,
      Integer.MAX_VALUE, -Integer.MAX_VALUE, Integer.MIN_VALUE, 1 << 30, -(1 << 30)};
    for (int v : vs) ops.add("[\"varsigned\", " + v + "]");
    int[] vu = {0, 1, 127, 128, 16383, 16384, 2097151, 2097152, 268435455, 268435456, Integer.MAX_VALUE, -1, Integer.MIN_VALUE, 0xfffffff0, 0x80000001};
    for (int v : vu) ops.add("[\"varunsigned\", " + v + "]");
    ops.add("[\"varbytes\", null]");
    ops.add("[\"varbytes\", \"\"]");
    ops.add("[\"varbytes\", \"6242a96c460972\"]");
    ops.add("[\"varbytes\", " + quote(hex(randomBytes(new Random(8), 200))) + "]");
    ops.add("[\"modedesc\", 0, null]");
    ops.add("[\"modedesc\", 1, null]");
    ops.add("[\"modedesc\", 0, \"626a9905\"]");
    ops.add("[\"modedesc\", 1, \"626a9905\"]");
    ops.add("[\"modedesc\", 1, " + quote(hex(randomBytes(new Random(9), 130))) + "]");
    ops.add("[\"sizeblock\", 0]");
    ops.add("[\"sizeblock\", 2]");
    ops.add("[\"varsigned\", 5]");
    ops.add("[\"varsigned\", -7]");
    ops.add("[\"sizeblock\", 3]");
    ops.add("[\"varsigned\", 100000]");
    ops.add("[\"varsigned\", -100000]");
    ops.add("[\"modedesc\", 0, \"6242a96c460972\"]");
    ops.add("[\"sizeblock\", 1]");
    ops.add("[\"varbytes\", " + quote(hex(randomBytes(new Random(11), 300))) + "]");
    ops.add("[\"sizeblock\", 1]");
    ops.add("[\"varbytes\", " + quote(hex(randomBytes(new Random(12), 2000))) + "]");
    ops.add("[\"int\", 42]");
    cases.add(runByteDataCase("all", ops));
    return section("bytedata", cases);
  }

  private static byte[] unhex(String h) {
    byte[] b = new byte[h.length() / 2];
    for (int i = 0; i < b.length; i++) b[i] = (byte) Integer.parseInt(h.substring(2 * i, 2 * i + 2), 16);
    return b;
  }

  /** parse ["name", arg, arg] with ints, null or "hex" strings. */
  private static Object[] parseOpAny(String op) {
    String s = op.substring(1, op.length() - 1);
    List<Object> res = new ArrayList<>();
    for (String part : s.split(",")) {
      part = part.trim();
      if (part.equals("null")) res.add(null);
      else if (part.startsWith("\"")) res.add(part.substring(1, part.length() - 1));
      else res.add(Long.parseLong(part));
    }
    return res.toArray();
  }

  private static String runByteDataCase(String name, List<String> ops) {
    ByteDataWriter w = new ByteDataWriter(new byte[1 << 20]);
    List<Object[]> parsed = new ArrayList<>();
    for (String op : ops) parsed.add(parseOpAny(op));
    List<Integer> blockStack = new ArrayList<>();
    List<Integer> blockRemaining = new ArrayList<>();
    for (Object[] op : parsed) {
      String n = (String) op[0];
      if (n.equals("int")) w.writeInt((int) (long) (Long) op[1]);
      else if (n.equals("long")) w.writeLong((Long) op[1]);
      else if (n.equals("short")) w.writeShort((int) (long) (Long) op[1]);
      else if (n.equals("byte")) w.writeByte((int) (long) (Long) op[1]);
      else if (n.equals("boolean")) w.writeBoolean(((Long) op[1]) != 0);
      else if (n.equals("varsigned")) w.writeVarLengthSigned((int) (long) (Long) op[1]);
      else if (n.equals("varunsigned")) w.writeVarLengthUnsigned((int) (long) (Long) op[1]);
      else if (n.equals("varbytes")) w.writeVarBytes(op[1] == null ? null : unhex((String) op[1]));
      else if (n.equals("modedesc")) w.writeModeAndDesc(((Long) op[1]) != 0, op[2] == null ? null : unhex((String) op[2]));
      else if (n.equals("sizeblock")) {
        blockStack.add(w.writeSizePlaceHolder());
        blockRemaining.add((int) (long) (Long) op[1]);
        if ((Long) op[1] == 0L) { w.injectSize(blockStack.remove(blockStack.size() - 1)); blockRemaining.remove(blockRemaining.size() - 1); }
        continue;
      } else throw new IllegalArgumentException(n);
      // close blocks
      while (!blockRemaining.isEmpty()) {
        int last = blockRemaining.size() - 1;
        int rem = blockRemaining.get(last) - 1;
        if (rem > 0) { blockRemaining.set(last, rem); break; }
        blockRemaining.remove(last);
        w.injectSize(blockStack.remove(blockStack.size() - 1));
      }
    }
    byte[] bytes = w.toByteArray();
    int size = w.size();
    ByteDataReader r = new ByteDataReader(bytes);
    List<String> decoded = new ArrayList<>();
    for (Object[] op : parsed) {
      String n = (String) op[0];
      if (n.equals("int")) decoded.add(Integer.toString(r.readInt()));
      else if (n.equals("long")) decoded.add(Long.toString(r.readLong()));
      else if (n.equals("short")) decoded.add(Integer.toString(r.readShort()));
      else if (n.equals("byte")) decoded.add(Integer.toString(r.readByte()));
      else if (n.equals("boolean")) decoded.add(r.readBoolean() ? "1" : "0");
      else if (n.equals("varsigned")) decoded.add(Integer.toString(r.readVarLengthSigned()));
      else if (n.equals("varunsigned")) decoded.add(Integer.toString(r.readVarLengthUnsigned()));
      else if (n.equals("varbytes")) decoded.add(hexOrNull(r.readVarBytes()));
      else if (n.equals("modedesc")) {
        int sizecode = r.readVarLengthUnsigned();
        int len = sizecode >> 1;
        byte[] d = null;
        if (len > 0) { d = new byte[len]; r.readFully(d); }
        decoded.add("[" + sizecode + ", " + hexOrNull(d) + "]");
      } else if (n.equals("sizeblock")) {
        decoded.add(Integer.toString(r.getEndPointer()));
      }
    }
    return "{\"name\": " + quote(name) + ", \"ops\": " + arr(ops, false) + ", \"bytes\": " + quote(hex(bytes)) + ", \"size\": " + size
      + ", \"hasMoreData\": " + r.hasMoreData() + ", \"decoded\": " + arr(decoded, false) + "}";
  }

  // ---- Mix / Diff coder streams ---------------------------------------------------

  private static String vecStreams() throws IOException {
    List<String> cases = new ArrayList<>();
    List<int[]> mixInputs = new ArrayList<>();
    mixInputs.add(new int[]{0});
    mixInputs.add(new int[]{5});
    mixInputs.add(new int[]{0, 0, 0, 0});
    mixInputs.add(new int[]{1, 2, 3, 4, 5, 6});
    mixInputs.add(new int[]{10, 10, 10, 11, 11, 9, 9, 9, 9, -5, -5, 100000, 100000, -100000, 3});
    mixInputs.add(new int[]{1000000000, -1000000000, 0, 2000000000, 2000000000, -147483647}); // a diff of Integer.MAX_VALUE would not terminate upstream
    Random r = new Random(13);
    int[] big = new int[3000];
    int v = 0;
    for (int i = 0; i < big.length; i++) {
      if (r.nextInt(3) == 0) v += r.nextInt(2001) - 1000;
      big[i] = v;
    }
    mixInputs.add(big);
    for (int[] in : mixInputs) {
      ByteArrayOutputStream bos = new ByteArrayOutputStream();
      MixCoderDataOutputStream mos = new MixCoderDataOutputStream(bos);
      for (int x : in) mos.writeMixed(x);
      mos.flush();
      byte[] bytes = bos.toByteArray();
      MixCoderDataInputStream mis = new MixCoderDataInputStream(new ByteArrayInputStream(bytes));
      int[] out = new int[in.length];
      for (int i = 0; i < in.length; i++) out[i] = mis.readMixed();
      cases.add("{\"kind\": \"mix\", \"values\": " + ints(in) + ", \"bytes\": " + quote(hex(bytes)) + ", \"decoded\": " + ints(out) + "}");
    }
    List<long[][]> diffInputs = new ArrayList<>();
    diffInputs.add(new long[][]{{0, 0}});
    diffInputs.add(new long[][]{{1, 0}, {2, 0}, {3, 0}, {-1, 1}, {-2, 1}, {1000000, 2}, {1000000, 2}, {-1000000, 2}});
    diffInputs.add(new long[][]{{1L << 40, 3}, {-(1L << 40), 3}, {1L << 60, 4}, {-(1L << 60), 4}, {(1L << 61) + 5, 5}, {0, 5}, {-((1L << 61) + 5), 5}}); // a diff of 2^62 or more would not terminate upstream
    long[][] rnd = new long[500][2];
    long[] last = new long[10];
    for (int i = 0; i < rnd.length; i++) {
      int idx = r.nextInt(10);
      last[idx] += (long) (r.nextGaussian() * (1L << r.nextInt(40)));
      rnd[i][0] = last[idx];
      rnd[i][1] = idx;
    }
    diffInputs.add(rnd);
    for (long[][] in : diffInputs) {
      ByteArrayOutputStream bos = new ByteArrayOutputStream();
      DiffCoderDataOutputStream dos = new DiffCoderDataOutputStream(bos);
      for (long[] x : in) dos.writeDiffed(x[0], (int) x[1]);
      dos.flush();
      byte[] bytes = bos.toByteArray();
      DiffCoderDataInputStream dis = new DiffCoderDataInputStream(new ByteArrayInputStream(bytes));
      long[] out = new long[in.length];
      long[] vals = new long[in.length];
      int[] idxs = new int[in.length];
      for (int i = 0; i < in.length; i++) { vals[i] = in[i][0]; idxs[i] = (int) in[i][1]; }
      for (int i = 0; i < in.length; i++) out[i] = dis.readDiffed(idxs[i]);
      cases.add("{\"kind\": \"diff\", \"values\": " + longs(vals) + ", \"idx\": " + ints(idxs) + ", \"bytes\": " + quote(hex(bytes)) + ", \"decoded\": " + longs(out) + "}");
    }
    return section("streams", cases);
  }

  // ---- TagValueCoder ------------------------------------------------------------

  private static String vecTagValueCoder() {
    List<String> cases = new ArrayList<>();
    // tag value sets are varbits streams "(delta, data)* 0": three real ones from
    // the Funchal dump plus synthetic ones encoded here
    List<String> poolList = new ArrayList<>(Arrays.asList("6242a96c460972", "626a9905", "6c"));
    Random pr = new Random(17);
    for (int k = 0; k < 12; k++) {
      int npairs = 1 + pr.nextInt(8);
      int[] pairs = new int[2 * npairs];
      for (int i = 0; i < npairs; i++) { pairs[2 * i] = 1 + pr.nextInt(k < 6 ? 5 : 40); pairs[2 * i + 1] = pr.nextInt(k < 6 ? 8 : 5000); }
      poolList.add(hex(tagBytes(pairs)));
    }
    poolList.add(hex(tagBytes(new int[]{1, 0})));
    poolList.add(hex(tagBytes(new int[]{200, 100000, 1, 1})));
    String[] pool = poolList.toArray(new String[0]);
    List<String[]> seqs = new ArrayList<>();
    seqs.add(new String[0]);
    seqs.add(new String[]{"6242a96c460972"});
    seqs.add(new String[]{null});
    seqs.add(new String[]{null, null, "6c"});
    seqs.add(new String[]{"6242a96c460972", "626a9905", "6242a96c460972", "6c", "6242a96c460972", null, "626a9905"});
    Random r = new Random(14);
    for (int k = 0; k < 3; k++) {
      int n = 50 + r.nextInt(400);
      String[] s = new String[n];
      for (int i = 0; i < n; i++) {
        int p = r.nextInt(pool.length + 1);
        s[i] = p == pool.length ? null : pool[(int) Math.min(pool.length - 1, Math.abs(r.nextGaussian()) * pool.length / 3)];
      }
      seqs.add(s);
    }
    for (String[] seq : seqs) {
      byte[][] datas = new byte[seq.length][];
      for (int i = 0; i < seq.length; i++) datas[i] = seq[i] == null ? null : unhex(seq[i]);
      byte[] buf = new byte[1 << 20];
      TagValueCoder coder = new TagValueCoder();
      BitCoderContext bc = null;
      for (int pass = 1; pass <= 3; pass++) {
        bc = new BitCoderContext(buf);
        coder.encodeDictionary(bc);
        for (byte[] d : datas) coder.encodeTagValueSet(d);
      }
      int len = bc.closeAndGetEncodedLength();
      byte[] bytes = Arrays.copyOf(buf, len);
      BitCoderContext rd = new BitCoderContext(Arrays.copyOf(bytes, len + DECODE_PADDING));
      TagValueCoder dec = new TagValueCoder(rd, new DataBuffers(), null);
      List<String> decoded = new ArrayList<>();
      for (int i = 0; i < datas.length; i++) {
        TagValueWrapper w = dec.decodeTagValueSet();
        decoded.add(w == null ? "null" : "[" + hexOrNull(w.data) + ", " + w.accessType + "]");
      }
      List<String> in = new ArrayList<>();
      for (String s : seq) in.add(s == null ? "null" : quote(s));
      cases.add("{\"input\": " + arr(in, false) + ", \"bytes\": " + quote(hex(bytes)) + ", \"readBits\": " + rd.getReadingBitPosition() + ", \"decoded\": " + arr(decoded, false) + "}");
    }
    return section("tagvaluecoder", cases);
  }

  /** Encode (delta, data) pairs the way BExpressionContext.encode() does. */
  private static byte[] tagBytes(int[] pairs) {
    byte[] buf = new byte[1024];
    BitCoderContext ctx = new BitCoderContext(buf);
    for (int i = 0; i < pairs.length; i += 2) {
      ctx.encodeVarBits(pairs[i]);
      ctx.encodeVarBits(pairs[i + 1]);
    }
    ctx.encodeVarBits(0);
    return Arrays.copyOf(buf, ctx.closeAndGetEncodedLength());
  }

  // ---- NoisyDiffCoder ------------------------------------------------------------

  private static String vecNoisyDiff() {
    List<String> cases = new ArrayList<>();
    List<int[]> ins = new ArrayList<>();
    ins.add(new int[0]);
    ins.add(new int[]{0});
    ins.add(new int[]{0, 0, 0, 0, 0});
    ins.add(new int[]{1, -1, 2, -2, 3, -3});
    ins.add(new int[]{1000, -1000, 5, 7, 100000, -100000, 0, 1});
    ins.add(new int[]{Integer.MAX_VALUE, Integer.MIN_VALUE, -Integer.MAX_VALUE, 1 << 30, -(1 << 30)});
    Random r = new Random(15);
    for (int k = 0; k < 5; k++) {
      int n = 20 + r.nextInt(500);
      int[] a = new int[n];
      int scale = 1 << (k * 4);
      for (int i = 0; i < n; i++) a[i] = (int) (r.nextGaussian() * scale);
      ins.add(a);
    }
    for (int[] in : ins) {
      byte[] buf = new byte[1 << 20];
      NoisyDiffCoder coder = new NoisyDiffCoder();
      StatCoderContext bc = null;
      for (int pass = 1; pass <= 3; pass++) {
        bc = new StatCoderContext(buf);
        coder.encodeDictionary(bc);
        for (int v : in) coder.encodeSignedValue(v);
      }
      int len = bc.closeAndGetEncodedLength();
      byte[] bytes = Arrays.copyOf(buf, len);
      StatCoderContext rd = new StatCoderContext(Arrays.copyOf(bytes, len + DECODE_PADDING));
      NoisyDiffCoder dec = new NoisyDiffCoder(rd);
      int[] out = new int[in.length];
      for (int i = 0; i < in.length; i++) out[i] = dec.decodeSignedValue();
      cases.add("{\"values\": " + ints(in) + ", \"bytes\": " + quote(hex(bytes)) + ", \"decoded\": " + ints(out) + "}");
    }
    return section("noisydiff", cases);
  }

  // ---- Math.sin / Math.cos / Math.atan2 -------------------------------------

  private static String hexd(double v) {
    return Long.toHexString(Double.doubleToRawLongBits(v));
  }

  /** Bit patterns of Math.sin/cos/atan2 for the arguments the port must reproduce. */
  private static String vecTrig() {
    List<Double> args = new ArrayList<>();
    double[] specials = {0.0, -0.0, Double.MIN_VALUE, -Double.MIN_VALUE, Double.MIN_NORMAL, -Double.MIN_NORMAL,
      0x1.0p-253, 0x1.fffffffffffffp-253, 0x1.0p-252, -0x1.0p-252, 0x1.0p-251, 1e-300, 1e-100, 1e-20, 1e-10, 1e-5,
      Math.PI / 2, -Math.PI / 2, Math.PI, -Math.PI, 2 * Math.PI, -2 * Math.PI, Math.PI / 4, Math.PI / 32, Math.PI / 64,
      1.0, -1.0, 0.5, 100.0, -100.0, 1000.0, 12345.6789, 86015.999, -86015.999, 86016.0, 90111.0, -90111.0,
      0x1.5ffffffffffffp16, 3.0, 1.5707963267948966, 4.71238898038469, 6.283185307179586};
    for (double d : specials) args.add(d);
    // (the 1800 scale-cache latitudes are covered by cheapruler.json)
    for (int i = 0; i < 1800; i += 25) args.add((Math.PI / 180.) * ((i * 100000 + 50000) * 1e-6 - 90));
    double[] angles = {0, 45, 90, 135, 180, 225, 270, 315, 359.9, -45, 720, 12.345};
    for (double a : angles) args.add((90. - a) * Math.PI / 180.);
    Random r = new Random(18);
    for (int i = 0; i < 600; i++) args.add((r.nextDouble() - 0.5) * 16);
    for (int i = 0; i < 200; i++) args.add((r.nextDouble() - 0.5) * 172000);
    for (int i = 0; i < 150; i++) args.add(Math.pow(2, -252 + r.nextDouble() * 240) * (r.nextBoolean() ? 1 : -1));
    List<String> sc = new ArrayList<>();
    for (double a : args) sc.add(quote(hexd(a) + " " + hexd(Math.sin(a)) + " " + hexd(Math.cos(a))));
    List<double[]> pairs = new ArrayList<>();
    double[] sv = {0.0, -0.0, 1.0, -1.0, 0.5, 2.0, 1e300, -1e300, 1e-300, -1e-300, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY, Double.NaN, 0.4375, 0.6875, 1.1875, 2.4375, 1e20, -1e20};
    for (double y : sv) for (double x : sv) pairs.add(new double[]{y, x});
    for (int i = 0; i < 500; i++) {
      double mag = Math.pow(10, r.nextInt(8) - 2);
      pairs.add(new double[]{(r.nextDouble() - 0.5) * mag, (r.nextDouble() - 0.5) * mag});
    }
    for (int i = 0; i < 150; i++) pairs.add(new double[]{r.nextInt(2000) - 1000, r.nextInt(2000) - 1000}); // like getAngle
    List<String> at = new ArrayList<>();
    for (double[] p : pairs) at.add(quote(hexd(p[0]) + " " + hexd(p[1]) + " " + hexd(Math.atan2(p[0], p[1]))));
    return "{\n  \"tool\": \"codec-vectors\",\n  \"section\": \"trig\",\n  \"vm\": " + quote(System.getProperty("java.vm.name") + " " + System.getProperty("java.version") + " " + System.getProperty("os.arch"))
      + ",\n  \"sincos\": " + arr(sc, true) + ",\n  \"atan2\": " + arr(at, true) + "\n}\n";
  }

  // ---- collections ------------------------------------------------------------------

  static final class LruNode extends LruMapNode {
    long key;
    LruNode(long key) { this.key = key; this.hash = (int) (key ^ (key >>> 32)); }
    @Override public int hashCode() { return hash; }
    @Override public boolean equals(Object o) { return o instanceof LruNode && ((LruNode) o).key == key; }
  }

  private static String vecCollections() {
    StringBuilder sb = new StringBuilder();
    sb.append("{\n  \"tool\": \"codec-vectors\",\n  \"section\": \"collections\",\n");
    Random r = new Random(16);

    // SortedHeap: ops ["add", key, id] ["pop"] ["extract", n] ["size"] ["peak"]
    {
      List<String> ops = new ArrayList<>();
      List<String> results = new ArrayList<>();
      SortedHeap<Integer> heap = new SortedHeap<>();
      int id = 0;
      for (int i = 0; i < 2500; i++) {
        int kind = r.nextInt(10);
        if (kind < 6) {
          int key = i < 1250 ? r.nextInt(50) : r.nextInt(1 << 20) - (1 << 19);
          heap.add(key, id);
          ops.add("[\"add\", " + key + ", " + id + "]");
          results.add("null");
          id++;
        } else if (kind < 9) {
          Integer p = heap.popLowestKeyValue();
          ops.add("[\"pop\"]");
          results.add(p == null ? "null" : p.toString());
        } else if (kind == 9 && r.nextInt(20) == 0) {
          int n = 1 + r.nextInt(12);
          Object[] t = new Object[n];
          int cnt = heap.getExtract(t);
          ops.add("[\"extract\", " + n + "]");
          List<String> vals = new ArrayList<>();
          for (int j = 0; j < cnt; j++) vals.add(t[j].toString());
          results.add("[" + cnt + ", " + arr(vals, false) + "]");
        } else {
          ops.add("[\"size\"]");
          results.add(Integer.toString(heap.getSize()));
        }
      }
      ops.add("[\"peak\"]");
      results.add(Integer.toString(heap.getPeakSize()));
      while (true) {
        Integer p = heap.popLowestKeyValue();
        ops.add("[\"pop\"]");
        results.add(p == null ? "null" : p.toString());
        if (p == null) break;
      }
      sb.append("  \"sortedheap\": {\"ops\": ").append(arr(ops, false)).append(", \"results\": ").append(arr(results, false)).append("},\n");
    }

    // CompactLongMap / FrozenLongMap: ops ["put", key, id] ["fastput", key, id] ["get", key] ["contains", key] ["size"] ["freeze"] ["keys"] ["values"]
    {
      List<String> ops = new ArrayList<>();
      List<String> results = new ArrayList<>();
      CompactLongMap<Integer> map = new CompactLongMap<>();
      long[] keys = new long[400];
      for (int i = 0; i < keys.length; i++) keys[i] = i % 7 == 0 ? -r.nextLong() : (i % 5 == 0 ? r.nextInt(1000) : r.nextLong());
      keys[3] = 0; keys[4] = Long.MAX_VALUE; keys[5] = Long.MIN_VALUE; keys[6] = 700352421268768177L;
      int id = 0;
      for (int i = 0; i < 700; i++) {
        long key = keys[r.nextInt(keys.length)];
        int kind = r.nextInt(5);
        if (kind == 0) { boolean b = map.put(key, id); ops.add("[\"put\", " + key + ", " + id + "]"); results.add(Boolean.toString(b)); id++; }
        else if (kind == 1) { if (map.contains(key)) { ops.add("[\"contains\", " + key + "]"); results.add("true"); } else { map.fastPut(key, id); ops.add("[\"fastput\", " + key + ", " + id + "]"); results.add("null"); id++; } }
        else if (kind == 2) { Integer v = map.get(key); ops.add("[\"get\", " + key + "]"); results.add(v == null ? "null" : v.toString()); }
        else if (kind == 3) { ops.add("[\"contains\", " + key + "]"); results.add(Boolean.toString(map.contains(key))); }
        else { ops.add("[\"size\"]"); results.add(Integer.toString(map.size())); }
      }
      FrozenLongMap<Integer> fm = new FrozenLongMap<>(map);
      ops.add("[\"freeze\"]"); results.add(Integer.toString(fm.size()));
      ops.add("[\"keys\"]"); results.add(longs(fm.getKeyArray()));
      List<Integer> vl = fm.getValueList();
      int[] va = new int[vl.size()];
      for (int i = 0; i < va.length; i++) va[i] = vl.get(i);
      ops.add("[\"values\"]"); results.add(ints(va));
      for (int i = 0; i < 300; i++) {
        long key = r.nextInt(3) == 0 ? r.nextLong() : keys[r.nextInt(keys.length)];
        int kind = r.nextInt(4);
        if (kind == 0) { Integer v = fm.get(key); ops.add("[\"get\", " + key + "]"); results.add(v == null ? "null" : v.toString()); }
        else if (kind == 1) { ops.add("[\"contains\", " + key + "]"); results.add(Boolean.toString(fm.contains(key))); }
        else if (kind == 2) { String res; try { res = Boolean.toString(fm.put(key, id)); } catch (RuntimeException e) { res = "\"error\""; } ops.add("[\"put\", " + key + ", " + id + "]"); results.add(res); id++; }
        else { ops.add("[\"size\"]"); results.add(Integer.toString(fm.size())); }
      }
      sb.append("  \"compactlongmap\": {\"ops\": ").append(arr(ops, false)).append(", \"results\": ").append(arr(results, false)).append("},\n");
    }

    // CompactLongSet / FrozenLongSet: ops ["add", key] ["fastadd", key] ["contains", key] ["size"] ["freeze"]
    {
      List<String> ops = new ArrayList<>();
      List<String> results = new ArrayList<>();
      CompactLongSet set = new CompactLongSet();
      long[] keys = new long[300];
      for (int i = 0; i < keys.length; i++) keys[i] = i % 3 == 0 ? r.nextInt(500) - 250 : r.nextLong();
      keys[1] = Long.MIN_VALUE; keys[2] = Long.MAX_VALUE; keys[3] = 0;
      for (int i = 0; i < 1000; i++) {
        long key = keys[r.nextInt(keys.length)];
        int kind = r.nextInt(4);
        if (kind == 0) { ops.add("[\"add\", " + key + "]"); results.add(Boolean.toString(set.add(key))); }
        else if (kind == 1) { if (!set.contains(key)) { set.fastAdd(key); ops.add("[\"fastadd\", " + key + "]"); results.add("null"); } else { ops.add("[\"contains\", " + key + "]"); results.add("true"); } }
        else if (kind == 2) { ops.add("[\"contains\", " + key + "]"); results.add(Boolean.toString(set.contains(key))); }
        else { ops.add("[\"size\"]"); results.add(Integer.toString(set.size())); }
      }
      FrozenLongSet fs = new FrozenLongSet(set);
      ops.add("[\"freeze\"]"); results.add(Integer.toString(fs.size()));
      for (int i = 0; i < 300; i++) {
        long key = r.nextInt(3) == 0 ? r.nextLong() : keys[r.nextInt(keys.length)];
        ops.add("[\"contains\", " + key + "]"); results.add(Boolean.toString(fs.contains(key)));
      }
      sb.append("  \"compactlongset\": {\"ops\": ").append(arr(ops, false)).append(", \"results\": ").append(arr(results, false)).append("},\n");
    }

    // DenseLongMap / TinyDenseLongMap: ops ["put", key, value] ["get", key]
    for (int variant = 0; variant < 2; variant++) {
      List<String> ops = new ArrayList<>();
      List<String> results = new ArrayList<>();
      DenseLongMap map = variant == 0 ? new DenseLongMap() : new TinyDenseLongMap();
      long[] keys = new long[500];
      for (int i = 0; i < keys.length; i++) keys[i] = i < 400 ? r.nextInt(20000) : (long) r.nextInt(1 << 30) * 4;
      keys[0] = 0; keys[1] = 4095; keys[2] = 4096; keys[3] = 1L << 31; keys[4] = (1L << 32) + 3;
      for (int i = 0; i < 1200; i++) {
        long key = keys[r.nextInt(keys.length)];
        if (r.nextBoolean()) { int v = r.nextInt(255); map.put(key, v); ops.add("[\"put\", " + key + ", " + v + "]"); results.add("null"); }
        else { ops.add("[\"get\", " + key + "]"); results.add(Integer.toString(map.getInt(key))); }
      }
      ops.add("[\"get\", -1]"); results.add(Integer.toString(map.getInt(-1)));
      ops.add("[\"get\", 999999999999]"); results.add(Integer.toString(map.getInt(999999999999L)));
      sb.append(variant == 0 ? "  \"denselongmap\": {" : "  \"tinydenselongmap\": {").append("\"ops\": ").append(arr(ops, false)).append(", \"results\": ").append(arr(results, false)).append("},\n");
    }

    // LinkedListContainer: ["add", list, data] ["init", list] ["get"]
    {
      List<String> ops = new ArrayList<>();
      List<String> results = new ArrayList<>();
      LinkedListContainer c = new LinkedListContainer(10, new int[8]);
      for (int i = 0; i < 400; i++) {
        int kind = r.nextInt(3);
        if (kind == 0) { int l = r.nextInt(10), d = r.nextInt(1000) - 500; c.addDataElement(l, d); ops.add("[\"add\", " + l + ", " + d + "]"); results.add("null"); }
        else if (kind == 1) { int l = r.nextInt(10); ops.add("[\"init\", " + l + "]"); results.add(Integer.toString(c.initList(l))); }
        else { String res; try { res = Integer.toString(c.getDataElement()); } catch (IllegalArgumentException e) { res = "\"error\""; } ops.add("[\"get\"]"); results.add(res); }
      }
      sb.append("  \"linkedlistcontainer\": {\"ops\": ").append(arr(ops, false)).append(", \"results\": ").append(arr(results, false)).append("},\n");
    }

    // ByteArrayUnifier: ["unify", hex] -> index of the earlier call whose result is the identical instance, or -1
    {
      List<String> ops = new ArrayList<>();
      List<String> results = new ArrayList<>();
      ByteArrayUnifier u = new ByteArrayUnifier(16, true);
      List<byte[]> seen = new ArrayList<>();
      String[] pool = {"6242a96c460972", "626a9905", "6c", "00", "", "6242a96c460973", "ffff", "0102", "0103", "abcdef", "abcdee", "01", "02", "03", "04", "05", "06", "07", "08", "09", "0a"};
      for (int i = 0; i < 300; i++) {
        String h = pool[r.nextInt(pool.length)];
        byte[] in = unhex(("ff" + h + "ee")); // unify a slice, not the whole array
        byte[] res = u.unify(in, 1, in.length - 2);
        int same = -1;
        for (int j = 0; j < seen.size(); j++) if (seen.get(j) == res) { same = j; break; }
        seen.add(res);
        ops.add("[\"unify\", " + quote(h) + "]");
        results.add("[" + same + ", " + quote(hex(res)) + "]");
      }
      sb.append("  \"bytearrayunifier\": {\"ops\": ").append(arr(ops, false)).append(", \"results\": ").append(arr(results, false)).append("},\n");
    }

    // LruMap: ["put", key] ["get", key] ["touch", key] ["removelru"]  (bins=7, size=10)
    {
      List<String> ops = new ArrayList<>();
      List<String> results = new ArrayList<>();
      LruMap lru = new LruMap(7, 10);
      List<LruNode> nodes = new ArrayList<>();
      for (int i = 0; i < 600; i++) {
        int kind = r.nextInt(4);
        long key = r.nextInt(40) - 5;
        if (kind == 0) {
          LruNode probe = new LruNode(key);
          if (lru.get(probe) != null) { ops.add("[\"get\", " + key + "]"); results.add("true"); continue; }
          LruMapNode removed = lru.removeLru();
          ops.add("[\"removelru\"]"); results.add(removed == null ? "null" : Long.toString(((LruNode) removed).key));
          lru.put(probe); nodes.add(probe);
          ops.add("[\"put\", " + key + "]"); results.add("null");
        } else if (kind == 1) {
          LruMapNode e = lru.get(new LruNode(key));
          ops.add("[\"get\", " + key + "]"); results.add(e == null ? "false" : "true");
        } else if (kind == 2) {
          LruMapNode e = lru.get(new LruNode(key));
          if (e != null) { lru.touch(e); ops.add("[\"touch\", " + key + "]"); results.add("true"); }
          else { ops.add("[\"touch\", " + key + "]"); results.add("false"); }
        } else {
          LruMapNode removed = lru.removeLru();
          ops.add("[\"removelru\"]"); results.add(removed == null ? "null" : Long.toString(((LruNode) removed).key));
        }
      }
      sb.append("  \"lrumap\": {\"ops\": ").append(arr(ops, false)).append(", \"results\": ").append(arr(results, false)).append("}\n");
    }
    sb.append("}\n");
    return sb.toString();
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

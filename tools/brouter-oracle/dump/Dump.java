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
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Random;
import java.util.Set;
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
    } else if ("codec-vectors".equals(cmd)) {
      codecVectors(args);
    } else if ("microcache-bytes".equals(cmd)) {
      microCacheBytes(args);
    } else if ("microcache-listing".equals(cmd)) {
      microCacheListing(args);
    } else {
      usage();
      System.exit(2);
    }
  }

  private static void usage() {
    System.err.println("usage:");
    System.err.println("  Dump dump-microcache <tile.rd5> <lon> <lat> [--profile <f.brf>] [--geometry] [--limit <n>]");
    System.err.println("  Dump eval-profile <profile.brf> <tagsfile> [--lookups <lookups.dat>]");
    System.err.println("  Dump codec-vectors <outdir>");
    System.err.println("  Dump microcache-bytes <tile.rd5> <lon> <lat> <outfile>");
    System.err.println("  Dump microcache-listing <tile.rd5> <lon> <lat> [--bodies <n>]");
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

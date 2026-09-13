# brouter_dart

Pure-Dart port of the [BRouter](https://github.com/abrensch/brouter) routing
runtime for the Velorki app. No Flutter dependency; tested on the desktop VM.

Upstream tag: **v1.7.10** (`upstreamVersion` in `lib/src/version.dart`, the same
tag as `brouter/UPSTREAM_VERSION`, the Docker image and the test oracle in
`tools/brouter-oracle/`).

The port is deliberately mechanical: one Dart file per Java class, the same
class names, snake_case file names, the same method names, and no behavioural
"improvements" (see the plan: parity first). Where Dart cannot express a Java
construct the deviation is listed below.

## Track R1: `brouter-util` and `brouter-codec`

### Ported classes

`brouter-util` (`lib/src/util/`):

| Java | Dart | Notes |
|---|---|---|
| `BitCoderContext` | `bit_coder_context.dart` | static lookup tables built together on first use (Java's static initialiser is eager) |
| `ByteDataReader` | `byte_data_reader.dart` | `ab` is never null: a Java `null` array is [emptyBytes] |
| `ByteDataWriter` | `byte_data_writer.dart` | `size()` is `writtenSize()` (Dart has one namespace for fields and methods and `MicroCache` has a `size` field) |
| `Crc32` | `crc32.dart` | |
| `CheapRuler` | `cheap_ruler.dart` | `Math.cos`/`Math.sin` through `JMath` (see below) |
| `CheapAngleMeter` | `cheap_angle_meter.dart` | `Math.atan2` through `JMath` |
| `CompactLongMap<V>` | `compact_long_map.dart` | overloads renamed: `contains(id)`, `containsPut(id, doPut)`; `value_in`/`value_out` are `valueIn`/`valueOut` |
| `CompactLongSet` | `compact_long_set.dart` | |
| `FrozenLongMap<V>` | `frozen_long_map.dart` | |
| `FrozenLongSet` | `frozen_long_set.dart` | |
| `DenseLongMap` | `dense_long_map.dart` | the statistics print on the first `getInt` is not ported (counters are kept) |
| `TinyDenseLongMap` | `tiny_dense_long_map.dart` | values are stored as signed bytes, so `getInt` returns 128..254 as negative numbers, exactly like upstream |
| `SortedHeap<V>` | `sorted_heap.dart` | the 32-way unrolled `getMinBin` is a loop (a heap never has more than 31 bins) |
| `LazyArrayOfLists<E>` | `lazy_array_of_lists.dart` | `trimAll` is a no-op |
| `MixCoderDataInputStream` | `mix_coder_data_input_stream.dart` | over an in-memory byte array (`DataInputStream` in `jvm.dart`) |
| `MixCoderDataOutputStream` | `mix_coder_data_output_stream.dart` | writes into a `BytesBuilder` (`DataOutputStream` in `jvm.dart`); `stats()` returns the text instead of printing |
| `DiffCoderDataInputStream` | `diff_coder_data_input_stream.dart` | |
| `DiffCoderDataOutputStream` | `diff_coder_data_output_stream.dart` | |
| `IByteArrayUnifier` | `i_byte_array_unifier.dart` | |
| `ByteArrayUnifier` | `byte_array_unifier.dart` | `unify(byte[])` is `unifyAll` |
| `LongList` | `long_list.dart` | |
| `LruMap`, `LruMapNode` | `lru_map.dart`, `lru_map_node.dart` | |
| `ProgressListener` | `progress_listener.dart` | |
| `ReducedMedianFilter` | `reduced_median_filter.dart` | |
| `StringUtils` | `string_utils.dart` | |

Skipped: `StackSampler` (a thread-dump sampler for profiling; pure diagnostics,
needs threads).

`brouter-codec` (`lib/src/codec/`), all 11 classes:

| Java | Dart | Notes |
|---|---|---|
| `StatCoderContext` | `stat_coder_context.dart` | |
| `TagValueCoder` | `tag_value_coder.dart` | the decoder constructor is `TagValueCoder.decoder(bc, buffers, validator)`; the `PriorityQueue` is the one in `jvm.dart` (same poll order for a total order) |
| `TagValueWrapper` | `tag_value_wrapper.dart` | |
| `TagValueValidator` | `tag_value_validator.dart` | abstract class |
| `WaypointMatcher` | `waypoint_matcher.dart` | abstract class |
| `NoisyDiffCoder` | `noisy_diff_coder.dart` | decoder constructor is `NoisyDiffCoder.decoder(bc)` |
| `MicroCache` | `micro_cache.dart` | `faid`/`fapos`/`size` are public fields (protected upstream) |
| `MicroCache2` | `micro_cache2.dart` | decoder constructor is `MicroCache2.decode(bc, buffers, lonIdx, latIdx, divisor, validator, matcher)` |
| `DataBuffers` | `data_buffers.dart` | keeps upstream's 65636-byte (sic) buffers |
| `LinkedListContainer` | `linked_list_container.dart` | |
| `IntegerFifo3Pass` | `integer_fifo3_pass.dart` | |

### JVM emulation (`lib/src/jvm.dart`, `lib/src/jmath.dart`)

* Java `long` is Dart `int` (64-bit two's complement on the VM; this package
  does not target the web).
* Java `int` is emulated: `i32()` wraps to 32 bits, `ushr32()`/`shr32()`/`shl32()`
  mask the shift distance with `& 31` as the JVM does. They are applied wherever
  a value can overflow or is shifted (hash mixing, CRC, the bit coders, id
  packing), not on plain loop counters.
* Java `byte`/`short` are `toByte()`/`toShort()`; byte arrays are `Uint8List`,
  so a stored byte reads back unsigned and the sign is re-applied where upstream
  relies on it (`readByte`, `TinyDenseLongMap`, `TagValueSet.hashCode`).
* Integer `%` and `double %` use `remainder()` (`rem()`/`frem()`), because Dart's
  `%` is never negative and Java's takes the dividend's sign.
* `(int)`/`(long)` casts of doubles are `d2i()`/`d2l()` (NaN to 0, saturating);
  `Math.round` is `javaRound()` (OpenJDK's bit-twiddling version, so
  `round(0.49999999999999994)` is 0); `Math.toDegrees` multiplies by the JDK 9+
  constant.
* Java `float` is `f32()` (a `Float32List` round trip). **No class of util or
  codec uses `float`**; the helper is for the later modules.
* `Double.compare` is `javaDoubleCompare()` (-0.0 before 0.0, NaN last) and
  `Double.doubleToLongBits` is `doubleToLongBits()` (canonical NaN).
* `java.io.IOException` is `IOException` (`EofException` extends it); Java
  `RuntimeException`s are Dart `Error`s (`StateError`, `ArgumentError`).
* `JavaHashMap<K, V>` (in `jvm.dart`) is a hash map with the iteration order of
  `java.util.HashMap`: bucket order, insertion order inside a bucket, buckets
  split in place on resize. `OsmNodesMap` uses it because
  `collectOutreachers()` walks the hollow-node map in that order and its
  `nodesCreated` count depends on it. Bins of eight or more entries, which the
  JDK turns into red-black trees whose `next` order then depends on identity
  hash codes, are not emulated -- that order is not reproducible between two
  JVM runs either.
* `Math.sin`, `Math.cos`, `Math.atan2`: see `jmath.dart`. On HotSpot `sin` and
  `cos` are JIT intrinsics from Intel's LIBM and agree bit for bit neither with
  fdlibm (`StrictMath`) nor with the C library the Dart VM calls (60 of the 1800
  `CheapRuler` scale-cache entries differ). `JMath.sin`/`JMath.cos` transcribe
  the intrinsic's main path (`2^-252 <= |x| < 90112`, every argument the router
  produces) and were checked bit-identical against 2 000 000 JVM samples; for
  `|x| >= 90112` the port falls back to `dart:math` (last-ulp differences
  possible). `JMath.atan2`/`atan` are fdlibm, which is what `Math.atan2` calls on
  every platform. `Math.sqrt` is IEEE-exact in both VMs. The expressions
  module calls no transcendental function at all (see R3); `brouter-core`
  (track R4) adds `Math.exp`, transcribed the same way (`JMath.exp`, see R4);
  `log`/`pow` are not used by the runtime.
* `DataInputStream`/`DataOutputStream` (in-memory, big-endian; with
  `readDouble`/`writeDouble` and `writeStringBytes` = `DataOutput.writeBytes(String)`
  for `MatchedWaypoint`) and a `PriorityQueue` with `java.util.PriorityQueue`
  poll semantics live in `jvm.dart` for the stream coders and `TagValueCoder`.

### Upstream behaviour worth knowing

Found while generating the vectors; the port reproduces all of it:

* `encodeVarBits(Integer.MAX_VALUE)`, `encodeNoisyNumber(v, 31)` and a
  `MixCoder` diff of `Integer.MAX_VALUE` never terminate (`encodeBounded` with
  `max = 0x7fffffff` shifts its mask to 0).
* `decodeBits(n)` is only valid for `n <= 24` (`fillBuffer` guarantees 24 bits);
  `encodeNoisyNumber` accepts larger `noisybits` but cannot be decoded.
* `encodeNoisyDiff(Integer.MIN_VALUE, 0)` writes a sign bit the decoder never
  reads.
* `DiffCoderDataOutputStream.writeSigned` loops forever for a diff of 2^62 or
  more.

None of these values occur in rd5 data.

## Parity proof (L1)

`test/vectors/` holds vectors produced by the upstream classes through
`tools/brouter-oracle/dump/run_dump.sh codec-vectors <dir>` (all inputs are in
the JSON; the Java side uses a seeded `Random` only to pick them):

| Vector | Classes | What is replayed |
|---|---|---|
| `bitcoder.json` | `BitCoderContext` | encode sequences of varbits/varbits2/bit/bounded (0, negatives, up to 2^31-2) and their bytes; read-only op sequences on random bytes incl. `decodeBitsReverse`, `setReadingBitPosition` |
| `statcoder.json` | `StatCoderContext` | noisy numbers, noisy diffs, predicted values, sorted arrays (`encodeSortedArray` / `decodeSortedArray` with the micro-cache parameters) |
| `crc32.json` | `Crc32` | fixed inputs incl. offsets |
| `cheapruler.json` | `CheapRuler`, `CheapAngleMeter` | the complete 1800-entry scale cache, distances, destinations, angles, normalisation as raw double bits (plus `Double.toString`) |
| `trig.json` | `JMath` | `Math.sin`/`cos`/`atan2` bit patterns for ~1000 arguments incl. all special-case paths |
| `bytedata.json` | `ByteDataWriter`/`Reader` | every write method incl. `injectSize` with 1- and 2-byte size prefixes and nested blocks |
| `streams.json` | `MixCoder*`, `DiffCoder*` | value sequences, bytes and the read-back |
| `tagvaluecoder.json` | `TagValueCoder` | 3-pass Huffman dictionary encoding of tag sets (incl. an empty dictionary and null sets) and decoding |
| `noisydiff.json` | `NoisyDiffCoder` | 3-pass encoding and decoding |
| `collections.json` | `SortedHeap`, `CompactLongMap`/`FrozenLongMap`, `CompactLongSet`/`FrozenLongSet`, `DenseLongMap`, `TinyDenseLongMap`, `LinkedListContainer`, `ByteArrayUnifier`, `LruMap` | op/result sequences (pop order with duplicate keys, frozen key order, instance reuse, eviction order) |

`MicroCache2` is proven on two real micro-caches of the oracle's committed
tiles (`microcache-bytes <tile> <lon> <lat> <file>` writes the still-encoded
cache exactly as stored in the rd5, crc footer included):

* `microcache-W20_N30-funchal.bin` (Funchal, 8 779 nodes, 110 573 bytes) and
  `microcache-W25_N60-reykjavik.bin` (Reykjavík, 5 356 nodes, 59 567 bytes).
* `*.listing.json` (`microcache-listing`) records, from the Java decoder, the
  node count, data size, the read position, per node the body length and Crc32,
  the crc of all 64-bit ids and of all bodies, the id and full body hex of the
  first 50 nodes, and the result of `encodeMicroCache` on the decoded cache.
* `test/micro_cache2_test.dart` decodes the same bytes with the Dart
  `MicroCache2`, checks all of that, rebuilds the node/link listing the way
  `dump-microcache` (`OsmNode.parseNodeBody`) does and compares it with the
  committed `tools/brouter-oracle/dump/samples/microcache-*.json` (id, position,
  elevation, node tags, turn restrictions, and per link target, direction,
  description bitmap and geometry bytes; the decoded way-tag strings are
  compared in `test/expressions_microcache_test.dart` since R3), and
  re-encodes the cache: the result is byte-identical to the data in the rd5,
  in Java and in Dart.

## Track R2: `brouter-mapaccess`

`lib/src/mapaccess/`, 17 of the 20 upstream classes:

| Java | Dart | Notes |
|---|---|---|
| `PhysicalFile` | `physical_file.dart` | one synchronous `dart:io` `RandomAccessFile` per rd5 (`setPositionSync` + `readIntoSync` loop = `seek` + `readFully`), no mmap, never a whole file; `ra`, `fileIndex`, `fileHeaderCrcs` are public (package-private upstream); `headerLookupVersion` keeps the version the tile was built with (11 for the 1.7.10 tiles, `lookups.dat` is 11.2; only the major number is compared, exactly like upstream, and only when a version other than -1 is passed); `checkVersionIntegrity`/`checkFileIntegrity` ported, `main` not; `readFullySync()` is a top-level helper |
| `OsmFile` | `osm_file.dart` | the two `createMicroCache` overloads are `createMicroCache(ilon, ilat, ...)` and `createMicroCacheForIdx(lonIdx, latIdx, ..., reallyDecode, hollowNodes)`; `fileOffset`/`posIdx` getters added for the index test |
| `NodesCache` | `nodes_cache.dart` | takes the real `BExpressionContextWay` (R3): it is the `TagValueValidator` of the decoders, the `IByteArrayUnifier` of the link descriptions and the source of `meta.lookupVersion`/`lookupMinorVersion`, exactly like upstream (R2 had a `TagValueValidator?` seam here); `first_file_access_*` are `firstFileAccessFailed`/`firstFileAccessName`; `Boolean.getBoolean("disableDirectWeaving")` is the static `NodesCache.disableDirectWeaving`, read per instance in the constructor; no `storageconfig.txt` (see skipped) |
| `OsmNode` | `osm_node.dart` | `OsmNode([ilon, ilat])` and `OsmNode.fromId(id)`; the position overload of `addLink` is `addLinkTo`; **`==` is not overridden**: upstream's `equals`/`hashCode` (by position) are only consumed by `OsmNodesMap`'s hash map and are passed to it as `OsmNode.posEquals`/`posHashCode`, so `==` on nodes stays Java `==` (identity) and the many reference comparisons of the port need no `identical()` |
| `OsmLink` | `osm_link.dart` | `n1`, `n2`, `previous`, `next` are public (protected upstream); `OsmLink([source, target])` covers both constructors; `source` parameters are nullable (`new OsmLink(null, n1)` in the router) |
| `OsmLinkHolder`, `OsmPos` | `osm_link_holder.dart`, `osm_pos.dart` | abstract classes |
| `OsmTransferNode`, `TurnRestriction`, `NodesList` | same names | |
| `OsmNodePairSet` | `osm_node_pair_set.dart` | |
| `OsmNodesMap` | `osm_nodes_map.dart` | `hmap` is a `JavaHashMap` (see above); `minVisitIdInSubtree` stays recursive and catches `StackOverflowError` like upstream (the depth at which the two VMs overflow differs; none of the oracle walks gets near it); the test `main` is not ported |
| `MatchedWaypoint` | `matched_waypoint.dart` | `WAYPOINT_TYPE_*` are `waypointType*`; streams through `DataInputStream`/`DataOutputStream` |
| `GeometryDecoder` | `geometry_decoder.dart` | the 128-node pool and the last-result cache (by geometry identity) are kept: a returned chain is overwritten by the next call, exactly like upstream |
| `DirectWeaver` | `direct_weaver.dart` | **used**: `NodesCache.directWeaving` defaults to true in 1.7.10, so this is the decoder the router runs; `MicroCache2` decoding is only used with `-DdisableDirectWeaving=true`, by `AreaReader` and by the dump tools. Both paths are parity-proven (below) |
| `WaypointMatcherImpl` | `waypoint_matcher_impl.dart` | lives in mapaccess upstream, so it is ported here (not R4); `Collections.sort` is replaced by a stable insertion sort (`List.sort` is not stable; the list never exceeds six entries); the comparator uses `javaDoubleCompare`; the `_w_`/`_w2_` names use `OsmNode.posHashCode` |
| `Rd5DiffTool` | `rd5_diff_tool.dart` | **stub**, every method throws `UnimplementedError` with a TODO: 637 lines of streaming file IO for `.df5` delta files that only the Android `DownloadWorker` calls; the plan defers delta updates to R5 |

Skipped: `Rd5DiffManager` and `Rd5DiffValidator` (server-side batch tools that
build/validate delta files for a whole segment directory, MD5 of whole files),
`StorageConfigHelper` (reads the Android app's `storageconfig.txt` for a
secondary segment directory and a maptool directory; `NodesCache` therefore
has no secondary directory -- upstream with a null directory would look the
file up relative to the working directory, which no caller wants).

### Memory strategy

The accounting is upstream's, number for number, and the oracle's
`formatStatus()` (`collecting`, `noGhosts`, `cacheSum`, `cacheSumClean`,
`ghostSum`, `ghostWakeup`) is compared after every phase of every walk:

* `NodesCache(maxmem)`: `maxmemtiles = maxmem / 8` is the budget for decoded
  `MicroCache` bytes (`cacheSum += segment.getDataSize()` per created cache),
  `nodesMap.maxmem = 2 * maxmem / 3` the budget for woven nodes
  (`isInMemoryBounds`: `nodesCreated * 95 + paths * 200`, grown from 4 MB in
  1.9 MB steps). The router passes `memoryclass * 1 MB` (64 by default).
* When `cacheSum` reaches `maxmemtiles` the next cache creation runs
  `checkEnableCacheCleaning`: first `collectAll()` on every cache (the
  "collect unreferenced" pass: `MicroCache.collect(0)` drops every node body
  already consumed by `getAndClear`, clears `virgin`) and enables garbage
  collection -- from then on every `obtainNonHollowNode` collects its segment
  once half of it is consumed; the second time it drops the ghosts and doubles
  `maxmemtiles`.
* A `NodesCache(oldCache)` reuses the file handles, the `DataBuffers` and, in
  the same detail mode, the `OsmFile` rows: still-virgin caches become ghosts
  (`setGhostState`, counted in `ghostSum`), consumed ones are dropped; a ghost
  that is needed again is revived (`unGhost`, `ghostWakeup`).
* With direct weaving (the router's mode) a decoded cell is
  `MicroCache.emptyNonVirgin` with data size 0, so `cacheSum` stays 0, nothing
  is ever ghosted and the memory pressure is handled entirely on the node
  graph: `collectOutreachers()` (vanish nodes further from the destination than
  the remaining cost allows) and `canEscape()`, both in the walks.
* Byte level: the plan's raw-bytes LRU is `RawCellCache` (R5, below), in
  front of `OsmFile.getDataInputForSubIdx`; the decoding above it is
  unchanged.

## Parity proof (L2-mapaccess)

Two oracle commands were added to `tools/brouter-oracle/dump/Dump.java`
(`run_dump.sh` resolves bare tile names and the segments directory):

* `osmfile-index <tile>`: the rd5 header the way `PhysicalFile` reads it (file
  index, header crcs, creation time, divisor, elevation type, lookup version)
  and, per degree square, every non-empty micro-cache with its encoded size and
  Crc32 through `OsmFile.getDataInputForSubIdx`.
* `nodes-cache-walk [<segmentsDir>] <lon> <lat> <lon2> <lat2> [--maxmem <bytes>]
  [--no-direct-weaving] [--cleanup-mode <n>] [--steps <n>] [--collect-max-cost <n>]`:
  drives `NodesCache` the way `RoutingEngine` does. Phase 1
  `matchWaypointsToNodes` (fresh cache, `WaypointMatcherImpl`, 250 m); phase 2
  a reset cache (`oldCache`, ghost state), `getGraphNode` for all four matched
  nodes, then `obtainNonHollowNode` + `expandHollowLinkTargets` and a full dump
  of each node (links with target position/elevation/hollow state/visit id/link
  count, description and geometry bytes, transfer nodes from `GeometryDecoder`,
  turn restrictions); phase 3 a breadth-first walk over `steps` nodes calling
  `obtainNonHollowNode` on every link target, one record per node (`id selev
  visitID links hollowTargets crc-of-all-link-data`); phase 3b
  `collectOutreachers` with a destination and cost bound plus `canEscape`, and
  the records again; phase 4 another reset and `getStartNode`. The way context
  is `lookups.dat` with a one-line profile (`assign costfactor = 1`, so
  `accessType` is 2 for every way) and `setAllTagsUsed()`; the Dart side
  builds the same thing with the ported `BExpressionContextWay`
  (`allWaysValidator()` in `test/mapaccess_support.dart`). With `--profile
  trekking` (R3) the real profile is parsed instead, without
  `setAllTagsUsed`, like `RoutingEngine`.

`test/vectors/mapaccess/` holds the two index dumps and 14 walks (630 KB):
four per tile with direct weaving (64 MB, `cleanupMode` 2, plus one with
mode 0 and one with mode 1; `funchal`, `camacha`, `machico`, `reykjavik`,
`reykjanes`, `mosfellsbaer`, and `portosanto`/`keflavik` whose waypoints lie in
different degree squares), two per tile without direct weaving with
`maxmem` 200 000 and 400 steps, which is small enough that the garbage
collection enables, collects, cleans ghosts and doubles its budget inside the
walk, and one per tile with the real `trekking` profile (`*-trekking.json`,
400 steps: inaccessible ways drop out of the graph, unused tags are filtered
from the link descriptions, `checkStartWay` is consulted).
`test/nodes_cache_walk_test.dart` replays each walk with the Dart classes
and compares the whole JSON, first difference by path; `test/osm_file_test.dart`
compares the index dumps and additionally decodes every micro-cache of both
tiles (`MicroCache2` path, crc footer checked, `checkFileIntegrity`). Everything
is identical: node ids, coordinates, elevations, link targets and order,
description/geometry bytes, transfer nodes, turn restrictions, visit ids after
the peninsula cleanup, the waypoint matches (crosspoints, radii and directions
as raw double bits, `wayNearest` lists), `nodesCreated` before/after
`collectOutreachers`, and the cache status strings.

The tiles are committed under `tools/brouter-oracle/tiles/` (1.5 + 2.7 MB). The
tests read them from `BROUTER_SEGMENTS_DIR`, by default
`tools/brouter-oracle/.cache/segments4` (`tools/brouter-oracle/fetch.sh` copies
and checksums them into it, offline; CI runs it first), and skip with a message
when they are absent. The walks are bound to
the tile snapshot in `tools/brouter-oracle/tiles.sha256` like the corpus.

## Track R3: `brouter-expressions`

`lib/src/expressions/`, all 10 upstream classes plus `ProfileCache` of
`brouter-core`:

| Java | Dart | Lines | Notes |
|---|---|---:|---|
| `BExpressionContext` | `b_expression_context.dart` | 1184 | abstract, implements `IByteArrayUnifier`; overloads renamed: `encode(int[])` is `encodeLookupData`, `decode(int[], boolean, byte[])` is `decodeInto`, `evaluate(int[])` is `evaluateLookupData`, `getLookupValue(boolean, byte[], int)` is `getLookupValueOf`, `addLookupValue(String, int)` is `addLookupValueIndex`, `getVariableValue(int)` is `getVariableValueByIdx`; `parseFile(File, ...)` reads the file (UTF-8) and hands the text to `parseProfile(name, text, readOnlyContext, keyValues)` for profiles held in memory (app assets); `Boolean.getBoolean("disableExpressionCache")`/`"showErrors"` are the statics `disableExpressionCache`/`showErrors`; `dumpStatistics()` returns the lines instead of printing; read-only accessors `lookupCount`, `lookupName`, `lookupValueNames`, `variableNames`, `modelClass`, `context` were added for the tests (upstream has no way to enumerate the tables) |
| `BExpression` | `b_expression.dart` | 450 | |
| `BExpressionContextWay` | `b_expression_context_way.dart` | 104 | `implements TagValueValidator`; the two constructors are `BExpressionContextWay(meta, [hashSize = 4096])` |
| `BExpressionContextNode` | `b_expression_context_node.dart` | 18 | same constructor shape |
| `BExpressionMetaData` | `b_expression_meta_data.dart` | 107 | `readMetaData(File)` plus `readMetaDataLines(Iterable<String>)`; `readJavaLines` splits like `BufferedReader.readLine` |
| `BExpressionLookupValue` | `b_expression_lookup_value.dart` | 44 | `equals(String)` is `==` |
| `CacheNode`, `VarWrapper` | `cache_node.dart`, `var_wrapper.dart` | 33, 30 | `Arrays.equals(float[])` compares `floatToIntBits` |
| `ProfileComparator` | `profile_comparator.dart` | 65 | `testContext(...)` returns the printed lines and takes a `JavaRandom`; no `main` |
| `IntegrityCheckProfile` | `integrity_check_profile.dart` | 43 | `integrityTestProfiles` returns the printed lines; no `main` |
| `ProfileCache` (`btools.router`) | `profile_cache.dart` | 204 | the `RoutingContext` fields it touches are the `ProfileCacheClient` interface (R4's `RoutingContext` implements it); `System.getProperty("profileBaseDir")`/`Boolean.getBoolean("debugProfileCache")` are statics; the diagnostics go to `ProfileCache.log`; `lastModified() + checksum << 24` keeps upstream's precedence (`(lastModified + checksum) << 24`) |

Nothing of the module is skipped. `java.util.HashMap` iteration order is
irrelevant here (`variableName(idx)` looks up a unique index; `_parseFile`
iterates the injected `keyValues` in map order, which only decides variable
indices, never values).

### JVM emulation added for R3 (`lib/src/jfloat.dart`, 1033 lines)

`brouter-expressions` calls **no transcendental function** (no `Math.exp`,
`log`, `pow`, `sin`; only `Math.abs` on a float), so no intrinsic had to be
transcribed. What it does need, and what `run_dump.sh math-vectors`
(`test/vectors/expressions/float.json.gz`, `test/jfloat_test.dart`) verifies:

* **`float` arithmetic.** `variableData`, the cached result vectors and the
  build-in variables are `Float32List`s; `numberValue` and every intermediate
  is a double holding a float value; `add`/`sub`/`multiply`/`divide` round
  through `f32()` (double arithmetic on two floats followed by one rounding to
  float is the IEEE float result). `int / 100f` is `f32(f32(i) / 100.0)`,
  `(int) (Math.abs(f) * 100f)` is `d2i(f32(...))`, the `1000 + (int)...`
  addition wraps with `i32`. 3000 random `+ - * /` pairs (incl. NaN, inf,
  subnormals), 3000 int/float and 3000 float/int conversions: all identical.
* **`Float.parseFloat`** (`javaParseFloat`): the JDK grammar (`String.trim`,
  sign, `NaN`/`Infinity`, hex floats, `1.`/`.5`/`1.e5`, trailing `f`/`d`,
  exponent overflow rules, `NumberFormatException`) and correct rounding of
  the exact decimal with `BigInt`. `double.parse` + `f32` rounds twice and is
  wrong when the double lands on a float midpoint; the vector has 2100 decimal
  strings on, just above and just below float midpoints plus every numeric
  token of the seven profiles and 3000 random strings: 5341 parses identical,
  all rejections identical.
* **`Float.toString`** (`javaFloatToString`): JDK 17 still uses the old
  `FloatingDecimal.dtoa` (the `Double.toString` rewrite is JDK 19), which is
  not always the shortest repr, **and** its `int`/`long` branches overflow for
  some values (`b + m > tens`; "same bugs, too" in the JDK source), which
  changes the last digit -- 4 of 17 353 sample floats (all near 2^85, e.g.
  `7.5339564E25` where exact arithmetic gives `...65E25`). The port transcribes
  `dtoa` with all three branches (32-bit wrapping, 64-bit wrapping, exact
  `BigInt` for the `FDBigInteger` path), `estimateDecExp` (its double
  arithmetic is plain IEEE), `roundup` and `getChars`: 17 353 of 17 353
  identical (every `k/100f` for k <= 5000, 3000 more `int/100f`, 8000 random
  normal floats, 300 subnormals, 1000 random bit patterns, the specials).
  `getKeyValueDescription` uses it for numeric (`*`) lookup values, which end
  up in the routing messages.
* **`String.format(Locale.US, "%3.1f", f)`** (`javaFormatFixed`): the float is
  promoted to double, `dtoa` runs in non-compatible mode on the double bits,
  `FormattedFloatingDecimal.applyPrecision` rounds half-up on the decimal
  digits, `fillDecimal` + `Formatter.addZeros` format: 5224 of 5224 identical
  (all `k/100f` ties like `0.05f`, `k/1000f`, feet/inch/mph products, random).
* `Integer.parseInt` (ASCII digits only -- the JDK also takes other Unicode
  decimal digits, no tag value has them), `String.split` with the unit
  separators (trailing empty strings dropped, `"ft".split("ft")` is empty),
  `String.trim` (chars <= U+0020), `Character.isWhitespace` (checked for every
  code unit below U+3100), `Arrays.hashCode(float[])`, `java.util.Random`
  (`JavaRandom`, the 48-bit LCG, for `generateRandomValues`).

### Upstream behaviour worth knowing

* `getKeyValueDescription` lists the tags in lookup order, not input order.
* A parse error is reported at the line **after** the offending token when
  the token ends at a newline (`linenr` counts the newline first).
* `setVariableValue(name, value, create = true)` after `parseFile` NPEs
  (`lastAssignedExpression` is null by then); the router never does that.
* `encode()` throws `assertion failed encoding` for numeric values of
  21474836.48 and more (`1000 + (int) (v * 100f)` overflows); values up to
  10 000 000 are fine.
* `evaluate(inverse, ab)` on a `null`/empty description crashes in the
  uncached (node) path; the router never passes one.
* The shipped `lookups.dat` 11.2 has **no** `*` (numeric) lookup; the unit
  conversion and `Float.toString` paths are exercised with the upstream test
  table `test/fixtures/lookups_test.dat` (11.1, with `depth`/`maxheight`/
  `maxdraft`/`maxweight *`) and its profiles `soft_test.brf`
  (`v:maxspeed`) / `profile_test.brf` (constant folding, injected values),
  copied from `brouter-expressions/src/test/resources`.

## Parity proof (L2)

Oracle side (`tools/brouter-oracle/dump/Dump.java`, all additive, the four
existing commands and their committed samples are byte-identical --
re-checked after the change): `way-tags <tile> [--kind node]` prints every
distinct way (node) tag string of a tile through
`getKeyValueDescription`; `eval-profile ... --compact [--encode]` and
`--bits` print float bit patterns (`Float.floatToIntBits`) instead of
`Float.toString`, de-duplicated per profile; `--context node --way-tags`
evaluates the node context after its foreign way context; `nodes-cache-walk
--profile`; `math-vectors`.

`tools/brouter-oracle/dump/samples/tags-large.txt` is the union of both
tiles: **35 099 distinct way tag sets** (18 824 Madeira + 17 730 SW Iceland,
from 271 184 link descriptions); `node-tags-large.txt` has 769 distinct node
tag sets. `test/vectors/expressions/` (1.2 MB, the larger files gzipped)
holds, per profile, the way corpus evaluated forward and reverse
(`eval-<profile>-way.json.gz`: every existing variable of the context --
build-ins, way-context and global -- as hex float bits, de-duplicated into
vectors; the trekking file also carries the encoded bytes and decoded
string of every case) and the node corpus with `nodeaccessgranted` no/yes
after the way `highway=residential surface=asphalt`
(`eval-<profile>-node.json`), plus `eval-trekking-node-motorway.json` (node
context after a way with costfactor >= 10000), `eval-trekking-bits.json`
(the 20 `tags.txt` sets), `eval-profile_test-bits.json`,
`eval-soft_test-units.json` (78 unit strings: `12'6"`, `5000lbs`, `3ft6in`,
`50cm`, `10mph`, `3fathom`, ...) and `eval-soft_test-node.json.gz`.

`test/eval_profile_corpus_test.dart` re-encodes every line (bytes and decoded
string identical for all 35 099), evaluates it in both directions with the
Dart `BExpressionContextWay` and compares **every variable bit for bit**
(`floatToIntBits`, NaN canonicalised):

| Profile | Variables (way / node) | Distinct result vectors (way / node) | Result |
|---|---:|---:|---|
| trekking | 65 / 34 | 585 / 10 | identical |
| fastbike | 56 / 31 | 706 / 10 | identical |
| fastbike-lowtraffic | 56 / 31 | 691 / 10 | identical |
| fastbike-verylowtraffic | 55 / 29 | 557 / 8 | identical |
| gravel | 65 / 28 | 2066 / 18 | identical |
| mtb | 129 / 67 | 1277 / 12 | identical |
| shortest | 24 / 11 | 168 / 8 | identical |

70 198 way evaluations and 1 538 node evaluations per profile, no case
matches only to a tolerance. `usedTagList()` (which lookups the parser marks
as used after constant folding, i.e. what the decoders keep) is identical for
all 14 contexts, as are the parsed `expressionNodeCount`s of
`profile_test.brf` (144 optimised / 311 unoptimised, the upstream test's
numbers). The two committed `Float.toString` samples (`eval-trekking.json`,
`eval-gravel.json`) are reproduced exactly as well (a `Float.toString` string
parses back to the same float, so that comparison is bit-exact too).

`test/expressions_microcache_test.dart` decodes the Funchal cell with the real
trekking context as validator and unifier and reproduces
`dump-microcache --profile trekking` (8 779 -> 8 627 nodes, data size, and for
the 20 sampled nodes every link's target, direction, filtered description
bytes, way tag string and geometry), and the way tag strings of the two raw
dumps. `test/nodes_cache_walk_test.dart` replays the two `--profile trekking`
walks (400 steps each) with the real context through `NodesCache`: identical.

`test/expressions_test.dart` covers the `lookups.dat` parse (11.2 and the
11.1 test table, aliases, contexts), encode/decode round trips, the upstream
`ConstantOptimizerTest` (10 000 `JavaRandom(17464)` samples), the
`ProfileComparator` on both contexts, injected key/values, `---model:`,
foreign (`way:`) variables, `v:` lookups, `noStartWay` comments and
`checkStartWay`, `accessType`, `unify`, and the parse errors.

Run (R1-R3): `dart test`, `dart analyze`, `dart format --set-exit-if-changed .`.

## Track R4: `brouter-core`

`lib/src/core/`, all 33 remaining upstream classes (`ProfileCache` was ported
in R3), one file per class:

| Java | Dart | Lines | Notes |
|---|---|---:|---|
| `RoutingEngine` | `routing_engine.dart` | 2806 | the search. `run()`/`doRun`/`doRouting`/`doRoundTrip`/`doGetInfo`/`doSearch` and the `findTrack` chain are `async`: every `yieldInterval` (2000) node expansions of `_findTrack` the optional `yieldHook` is awaited and `progressListener` called, which is how the `RoutingWorker` isolate cancels cooperatively (`terminate()` then throws upstream's "operation killed by thread-priority-watchdog"); without a hook nothing suspends. Overloads renamed: `findTrack(refTracks, lastTracks)` stays, `findTrack(operationName, ...)` is `findTrackSegment`, the two `getStartPath` are `_getStartPathForWaypoint`/`_getStartPath`. `maxRunningTime` keeps the `> 0` guard (0 = no timeout, the oracle's `-DmaxRunningTime=0`). Not a `Thread`; no `debug.txt`/`stacks.txt`/`StackSampler`; `logInfo` goes to the optional `infoLog` sink; `System.getProperty("reportFormat")` is the static `reportFormat`; `Math.random()` (round trips without `direction`) is `dart:math` `Random`; the outfile/logfile writing of the CLI mode is kept |
| `RoutingContext` | `routing_context.dart` | 703 | implements `ProfileCacheClient`; `setModel(className)` resolves the three upstream model class names instead of reflection; `localFunction` is a non-null `String` (`''` for Java `null`, reported as "unknown"); `Integer` fields are `int?`; `setWaypoint(wp, endpoint, [pendingEndpoint])` covers both overloads; `createPath(OsmLink)` is `createStartPath`; the `snake_Case` fields are camelCase (`considerCrossing`, `costToLeftFromHClass1`, `sCx`, `defaultCr`) |
| `RoutingParamCollector` | `routing_param_collector.dart` | 455 | the parameter map is a `JavaHashMap<String, String>` (`HashMap` iteration order decides which of two conflicting keys wins); `URLDecoder.decode` is `javaUrlDecode`, `StringTokenizer` a local helper, `String.split` the `javaSplit` of R3 (trailing empties dropped), `Double.parseDouble` is `javaParseDouble` (new in jfloat: the JDK grammar, `double.parse` for the value; no hex floats) |
| `OsmPath` | `osm_path.dart` | 537 | abstract; the two `init` overloads are `initLink(link)` and `initFrom(origin, link, refTrack, detailMode, rc)`; `int += double` is `d2i(cost + nogoCost)`; `interpolateEle` casts through `d2i` then `toShort`; the start-direction faking uses `JMath.sin`/`cos` |
| `StdPath` | `std_path.dart` | 484 | every `float` operation rounds through `f32()`, in particular the elevation-hysteresis update `ehbd += -delta_h_micros - dist * downhillcutoff` (float arithmetic with both ints converted to float first, then `(int)`), `Math.min(int, float)`, `elevationCost` and `linkelevationcost += elevationCost`, and `sectionCost += dist * costfactor + 0.5f`; `calcIncline` uses `JMath.exp`; `Math.min`/`max` on floats are local helpers with Java's NaN rule |
| `KinematicPath`, `KinematicModel`, `KinematicPrePath` | same names | 333, 153, 63 | car model, `---model:btools.router.KinematicModel`; `JMath.exp` in the turn-angle decay; the two floating angles are `f32`; `getParam` writes `Float.toString` back into the params like upstream. Not exercised by the corpus (no car profile) |
| `KinematicNoCostModel`, `KinematicNoCostPath` | same names | 153, 329 | upstream copies of the two above with three lines changed; generated the same way |
| `OsmPathModel`, `OsmPrePath`, `StdModel` | same names | 20, 25, 35 | |
| `OsmPathElement` | `osm_path_element.dart` | 148 | `create(OsmPath)` and `createAt(ilon, ilat, selev, origin)`; `setTime`/`setEnergy`/`setAngle` round to float |
| `MessageData` | `message_data.dart` | 130 | `toMessage()` computes `(int) (costfactor * 1000 + 0.5f)` in float and truncates `ele / 4` like Java int division; `clone()` is `copy()` |
| `OsmTrack` | `osm_track.dart` | 621 | `version` is the upstream tag without `v` (the jar's implementation version); `OsmPathElementHolder` is top-level; `readBinary`/`writeBinary` use whole-file `DataInputStream`/`DataOutputStream`; `appendTrack` and `getTotalSeconds` keep the float arithmetic |
| `Formatter` | `formatter.dart` | 526 | `formatPos` transcribed; `getFormattedTime3` formats the UTC timestamp by hand; `JStringBuilder` provides `deleteCharAt(lastIndexOf(","))` |
| `FormatJson` | `format_json.dart` | 313 | **byte-exact** against the corpus: doubles appended to the builder go through `javaDoubleToString`, the `showspeed` float hack through `javaFloatToString`, `times` through `javaDecimalFormat` (`DecimalFormat("0.###")`, below); `formatAsWaypoint` ported |
| `FormatGpx`, `FormatKml`, `FormatCsv` | same names | 622, 131, 40 | ported mechanically, **unverified** (the corpus only records `format=geojson`); `String.format("%6s;%6d;...")` is `padLeft`; the two `formatWaypointGpx` overloads are `formatWaypointGpx` (node) and `formatMatchedWaypointGpx` |
| `VoiceHint`, `VoiceHintList`, `VoiceHintProcessor` | same names | 246, 59, 599 | float sums (`angle`, `roundAboutTurnAngle`, `tmpangle`, `angles`) round through `f32`; the `Float.MAX_VALUE` sentinel is `floatMaxValue`; `setTransportMode(int)` is `setTransportModeValue`. **Unverified**: the corpus runs `timode=0`, so no detours are registered and `processVoiceHints` returns before any hint is built |
| `OsmNodeNamed` | `osm_node_named.dart` | 104 | `OsmNodeNamed([OsmNode? n])`; the int products of `distanceWithinRadius` wrap with `mul32` |
| `OsmNogoPolygon` | `osm_nogo_polygon.dart` | 459 | `Point` is top-level; long/int arithmetic kept (`~/` for the long divisions of the collinear case, `mul32`/`i32` for the int products of `distanceWithinPolygon`) |
| `AreaInfo`, `AreaReader` | same names | 74, 358 | only used by `getRandomDirectionFromData`; `Collections.sort` is a stable merge sort |
| `SearchBoundary`, `SuspectInfo`, `RoutingIslandException` | same names | 82, 58, 6 | `RoutingIslandException` is an `Error` |
| `RoutingHelper` | `routing_helper.dart` | 37 | no secondary/maptool directory (`StorageConfigHelper` is not ported, see R2) |

Around the port:

* `lib/src/brouter.dart`: `BRouter(segmentsDir, profilesDir)` with
  `routeQuery(String query)` -- the exact `RouteServer.run` +
  `ServerHandler` flow (`getUrlParams`, `memoryclass = 128`,
  `profileBaseDir`, `getWayPointList`, `engineMode`, `setParams`,
  `RoutingEngine(...).doRun(maxRunningTime)`, `formatTrack`) -- and the typed
  `route(RoutingRequest) -> RoutingResult` (`toQuery()` builds the same query
  string; the result carries the GeoJSON plus parsed coordinates, lengths,
  ascends, messages and times). Errors are `RoutingException` with
  `getErrorMessage()`.
* `lib/isolate.dart`: `RoutingWorker.spawn/route/routeQuery/cancel/dispose`
  in a worker isolate, progress callbacks, cooperative cancel through the
  engine's yield hook (a plain port listener, not `await for`, which would
  pause the port during a route). `test/routing_worker_test.dart` runs it on
  the plain VM.

### JVM emulation added for R4

* **`Math.exp`** (`JMath.exp`, jmath.dart): the only transcendental function
  of the module (`StdPath.calcIncline`, the foot-mode Tobler function and
  the kinematic turn decay; there is no `log`/`pow`). It decides every
  `time`/`energy` value of the messages and the `times` array, so it is a
  transcription of HotSpot's x86_64 intrinsic `MacroAssembler::fast_exp`
  (macroAssembler_x86_exp.cpp of jdk17u, Intel LIBM: `e^x = 2^N * T[j] *
  (1 + P(r))` with a 64-entry table, no FMA) including the
  over/underflow branch that assembles subnormal results with integer
  arithmetic on the bit patterns, and the special cases. Verified
  bit-identical on 17 611 JVM samples (`run_dump.sh core-vectors`,
  `test/vectors/core/core.json.gz`, `test/core_numerics_test.dart`): every
  `-k/100` for `k <= 6000`, the Tobler/kinematic argument ranges, random
  arguments over the whole normal range, the subnormal-result range
  `[-746, -708]`, the overflow/underflow edges and the `2^-54`/`1024`
  branch points. (Upstream's aarch64 build has no exp intrinsic and calls
  fdlibm, so a server on ARM would differ in the last ulp; the oracle is
  x86_64.)
* **`DecimalFormat("0.###")`** (`javaDecimalFormat`, jfloat.dart) for the
  travel times: `DigitList.set` on the `FloatingDecimal` digits (the R3
  `dtoa` port already carried the `decimalDigitsRoundedUp`/`exactDecimalConversion`
  flags) with `HALF_EVEN` rounding and `subformat`; 39 550 float samples
  identical, ties included.
* **`Double.toString`** (`javaDoubleToString`, already in R3) for the
  elevations (`selev / 4.`) and other doubles the formatters append:
  15 402 samples identical.
* `javaParseDouble` (`Double.parseDouble`), `javaUrlDecode`,
  `javaStringHashCode` (`String.hashCode`, for `getKeyValueChecksum` and the
  parameter `HashMap`), `JavaHashMap.entries/keys/containsKey/ofStrings`,
  `shortMinValue`, `floatMaxValue`.
* The `float` fields of the paths and messages follow the R3 rule (double
  holding a float value, `f32()` after each float operation, `int op float`
  converts the int first); `Math.round` is `javaRound`, casts are
  `d2i`/`d2l`/`toShort`.

## Parity proof (L3)

`test/corpus_parity_test.dart` routes all 200 cases of
`tools/brouter-oracle/corpus` (`requests.json` query strings; the tiles from
`BROUTER_SEGMENTS_DIR`, skipped when absent; the profiles from
`brouter/profiles`) through `BRouter.routeQuery` and compares the produced
GeoJSON with `corpus/responses/<id>.geojson` **byte for byte** (on a
mismatch it first compares coordinates, `track-length`, `filtered ascend`,
`plain-ascend`, `cost`, `messages`, `times`, `total-time`, `total-energy`
field by field, then reports the first differing byte offset with a
context snippet). `BROUTER_CORPUS_ONLY=<id prefix>` restricts the run.

Result: **200 of 200 identical** on the first complete run -- 120 `pair`
(6 profiles x `alternativeidx` 0-3), 40 `triple`, 24 `nogo`, 16
`roundtrip` (`engineMode=4`, `roundTripDistance`, `direction`,
`roundTripPoints=5`); trekking, fastbike, fastbike-lowtraffic, gravel, mtb
and shortest; 47 160 coordinates, every message row and every travel time.
The whole corpus takes about 41 s (`dart test`), i.e. the search, the
`float` cost arithmetic, `Math.exp`, the elevation filtering, the
alternatives' reference-track penalty, nogo handling and the deterministic
round-trip point generation (`buildPointsFromCircle` from `direction`, no
`Math.random`) all match.

Speed (this laptop, x86_64, the same cases, medians of 5 after warm-up;
JVM = the oracle `RouteServer` after JIT warm-up):

| Case | Links processed | Dart | JVM |
|---|---:|---:|---:|
| pair-000 (trekking, 3.6 km) | 14 823 | 69 ms | 33 ms |
| triple-000 (trekking, via) | 7 780 | 50 ms | 24 ms |
| nogo-000 (trekking) | 18 549 | 86 ms | 37 ms |
| roundtrip-000 (trekking, 5 points) | 73 022 | 447 ms | 204 ms |
| roundtrip-007 (the longest body) | 72 852 | 305 ms | 132 ms |

About 2x the JIT-warm JVM at the end of R4; the R5 numbers (JIT and AOT,
before/after) are in the next section.

### What is not covered

* `FormatGpx`/`FormatKml`/`FormatCsv` and the voice hints
  (`timode > 0`) are ported but have no oracle vectors yet.
* `getRandomDirectionFromData` (round trips without `direction`) and the
  `AreaReader` behind it; `rawTrackPath` (`OsmTrack.readBinary`, the
  incremental recalculation of the Android app), `doGetInfo`
  (`engineMode` 2/3), `doSearch`, `correctMisplacedViaPoints`
  (`snapPathConnection`, false in all shipped profiles), `allowSamewayback`,
  polygon/polyline nogos, `nogoLats/Lons/Radi`, `straight`, `pois`,
  `heading`, `exportWaypoints` and `profile:` parameters run through the
  same code paths but are not in the corpus.
* The kinematic (car) model.

Run: `dart test` (about 50 s with the tiles, 8 s without), `dart analyze`,
`dart format --set-exit-if-changed .`.

## Track R5: performance and memory

Rule of the track: every step was checked against the L3 corpus (200 of 200
byte-identical, `test/corpus_parity_test.dart`) before it stayed.

### Tools

* `dart run tool/bench.dart [--runs N] [--only <id prefix>] [--no-worker]
  [--memoryclass N] [--no-rawcache] [--retain-rawcache]`: routes a fixed set
  (`pair-000`, `pair-005` = the longest corpus pair, `triple-031`,
  `nogo-000`, `roundtrip-000`, `roundtrip-003` = the longest round trip,
  Funchal -> Porto Moniz across Madeira (67 km, 237 641 links) and
  Reykjavik -> Keflavik (49 km, 298 918 links)) once cold and N times warm
  through `BRouter` and again through the `RoutingWorker` isolate (message
  costs included), prints medians/minimums, `ProcessInfo.currentRss`/`maxRss`
  and checks that every run produces the same bytes. `dart compile exe
  tool/bench.dart` gives the AOT figures a release app runs with.
* `dart run tool/profile.dart [--top N] [--callers <name>]... [--callees
  <name>]... [--memory] [--vm-flag <flag>]... -- <bench args>`: a sampling CPU
  profile of the bench through the VM service (`getCpuSamples`, raw JSON-RPC
  over a `dart:io` WebSocket, no packages): exclusive/inclusive tables, the
  callers of a leaf function, the leaf distribution inside a subtree, and
  with `--memory` the main isolate's peak heap (`getMemoryUsage` polled every
  20 ms). JIT only: the SDK's `dartaotruntime` is a product build without a
  VM service (`--aot` is implemented but refused by that runtime).
* `-DBROUTER_PROFILE=true` (`lib/src/profile.dart`, `kProfile`): Stopwatch
  counters around cell reads, direct weaving, `createPath`, the expression
  cache, `collectOutreachers`, waypoint matching, `_compileTrack` and
  formatting; dead code otherwise. The bench prints them per case.
* `BROUTER_MEMORYCLASS=64 dart test test/corpus_parity_test.dart` runs the
  corpus with another `memoryclass` (the app worker's default is 64, the
  server's 128): still 200 of 200 identical.

### Baseline (before R5)

This laptop (x86_64, ~4 GHz), medians of 5 warm runs on an idle machine
(the first attempts were skewed by an unrelated Gradle build; the minimum of
the runs was used to spot that). "Direct" is `BRouter.routeQuery` in the main
isolate, "worker" the same through `RoutingWorker`.

| Case | Links | JIT direct | JIT worker | AOT direct |
|---|---:|---:|---:|---:|
| pair-000 (trekking, 3.6 km) | 13 621 | 70 ms | 68 | 80 |
| pair-005 (trekking alt 1, 7.6 km) | 3 855 | 27 | 25 | 28 |
| triple-031 (fastbike alt 3, 14.5 km) | 163 466 | 431 | 436 | 503 |
| nogo-000 (trekking, 5.9 km) | 17 468 | 74 | 74 | 87 |
| roundtrip-000 (trekking, 5 points, 9.9 km) | 72 688 | 405 | 399 | 513 |
| roundtrip-003 (gravel, 20 km) | 200 941 | 598 | 595 | 778 |
| Funchal -> Porto Moniz (trekking, 67 km) | 237 641 | 751 | 773 | 932 |
| Reykjavik -> Keflavik (trekking, 49 km) | 298 918 | 697 | 720 | 881 |

### Where the time goes

Sampling profile of the Madeira route (JIT, 4 runs, `--callees`); the
`kProfile` counters agree (3 warm runs: 12 `findTrack` passes -- pass0,
pass1 and the re-tracking pass per segment -- 740 253 expansions, 862 089
`createPath`, 702 cells woven):

* `createPath` / `OsmPath.addAddionalPenalty`: ~50 % (`processWaySection`
  8 %, `CheapAngleMeter.calcAngle` 2.5 %, `RoutingContext.calcDistance`
  2.2 %, the `float` emulation `f32` 2.5 % and `d2i` 2 %, geometry decoding
  `GeometryDecoder`/`ByteDataReader` 3.5 %, `BExpressionContext.evaluate`
  1 %). The expression cache works: 1 269 522 requests, 0 misses when warm,
  84 % of them the same-array fast path.
* direct weaving: ~25 % (`decodeVarBits`, `decodeBit`, `_fillBuffer`,
  `decodePredictedValue`, the tag dictionary with `unify`/`accessType`,
  node/link/geometry allocation). Every pass re-weaves its cells: that is
  upstream's design (the decoded graph is the `NodesCache` that each pass
  replaces).
* the search loop itself (`_findTrack` without callees, heap operations):
  ~8 %; `SortedHeap` 3.5 %.
* `_compileTrack`: 3.4 % on the long routes (see B), formatting 1.5 %,
  waypoint matching 1 %.
* cell reads: **0.3 %** -- 723 reads, 11.4 MB, 8 ms for three 67 km routes
  (the page cache is warm; `RandomAccessFile` seek + read is not the
  bottleneck on this machine). The 23 % "libc" the first profile showed was
  the JIT waiting for the kernel compiler at startup, not routing.
* GC: 46 scavenges, 76 ms, per three long routes (`--verbose-gc`); one
  mark-sweep. Not a factor.

### What was done, in order, with its effect

| Step | Change | Effect (JIT / AOT, long routes) |
|---|---|---|
| A | `RawCellCache` (`lib/src/mapaccess/raw_cell_cache.dart`): an LRU of the still-encoded cells keyed by file id and position, bounded (16 MB), owned by `BRouter`, handed through `RoutingEngine.rawCache` -> `NodesCache(rawCache:)` -> `OsmFile(rawCache:)`; a hit copies the cell into the decoder's io buffer instead of `seek` + `readFully`. Released after every route (`BRouter.retainRawCache`, `RoutingWorker.spawn(retainRawCache:, rawCacheBytes:)` keep it across routes). Within a route it hits 3 of the 4 passes. | not measurable here (the reads were 0.3 %); kept for the plan's design (flash, no syscalls per pass) |
| B | `_compileTrack`: the elements are collected and reversed once instead of `nodes.insert(0, e)` per element (quadratic, and every shifted element passed a covariant list-store check: `Lists.copy` + `Type Test OsmPathElement` = 4.3 % of samples) | -3 to -4 % / same |
| C | `BitCoderContext` read path: `_b` never holds more than 31 bits in read mode (`fillBuffer` stops at 24..31, `decodeBit` refills 8), so every `ushr32`/`shr32`/`i32` wrap was a no-op and is now plain 64-bit arithmetic; the write path keeps `_b` as an unsigned 32-bit value; the varbits tables are held per instance instead of behind a lazily initialised static. `javaRound`: `doubleToRawLongBits` through `Float64List`/`Int64List` views instead of a big-endian `ByteData` round trip (two byte swaps per call). | -5 to -8 % / -5 to -8 % (A+B+C together: JIT 751 -> 684 ms, AOT 932 -> 834 ms) |
| D | `StdPath.processWaySection` (57 `f32` calls per way section) rounds through a `Float32List` fetched once from `RoutingContext.f32buf` (`FloatRounding.f32` in jvm.dart): a top-level `final` is lazily initialised and every access re-checks that, 2.6 ns vs 1.4 ns per call in an AOT micro-benchmark. `OsmLink.getTarget`/`getNext` load `n2` once. | JIT +-0 / AOT -8 to -12 % (834 -> 733 ms) |
| E | `d2i`: saturation checks before `isNaN` (a NaN fails both), 9 % faster in the micro-benchmark, same results | ~0.4 % |

Tried and dropped: `d2i` with one range check and `toInt()` (20 % slower:
`truncate()` is the intrinsic). Checked and left alone: the cooperative
yield already only awaits every `yieldInterval` (2000) expansions through a
counter (`_findTrack` self time is 1-3 %, the async machinery does not show
up); `SortedHeap`'s generic `List<V?>` stores (`Type Test OsmPath?`, 0.8 %);
the `JavaHashMap` closure calls of `OsmNodesMap` (0.3 %); `List<int>` /
string / `Map<String, ...>` in hot paths -- none found (`lookupData` is an
`Int32List`, `getKeyValueDescription` strings are only built in the detail
pass). The remaining time is the `float` emulation, `sqrt`, the bit decoding
and the allocation pattern of the mechanical port; the Dart compilers are
not HotSpot, and nothing structural is left without deviating from upstream.

### Result

Same machine and method, after R5 (`memoryclass` 128, raw cache on):

| Case | JIT direct | JIT worker | AOT direct | AOT worker | JVM (R4) |
|---|---:|---:|---:|---:|---:|
| pair-000 | 69 ms (70) | 103* | 72 (80) | 72 | 33 |
| pair-005 | 25 (27) | 23 | 23 (28) | 23 | |
| triple-031 | 407 (431) | 403 | 421 (503) | 432 | |
| nogo-000 | 68 (74) | 67 | 74 (87) | 76 | 37 |
| roundtrip-000 | 370 (405) | 375 | 410 (513) | 420 | 204 |
| roundtrip-003 | 555 (598) | 565 | 591 (778) | 604 | |
| Funchal -> Porto Moniz | 680 (751) | 692 | 741 (932) | 744 | |
| Reykjavik -> Keflavik | 646 (697) | 668 | 701 (881) | 703 | |

(baseline in parentheses; * the first case of a fresh JIT worker isolate is
cold, its AOT counterpart is not). JIT 4-12 % faster, AOT 10-20 % faster,
the worker adds nothing measurable. Against the JIT-warm JVM of R4 the port
is still 1.9-2.1x (pair-000 69 vs 33 ms, roundtrip-000 370 vs 204 ms).

Plan targets: the 67 km trekking route takes 0.74 s in AOT on this laptop.
A mid-range 2023 Android SoC is roughly 2-3x slower single-threaded than
this machine, which projects to 1.5-2.2 s for the "60 km trekking route in
under 3 s" target; that has not been measured on a device here.

### Memory

* Main isolate heap during the longest routes (`tool/profile.dart --memory`,
  JIT, includes the JIT's code objects): peak 64.5 MB used / 70 MB capacity
  for Funchal -> Porto Moniz, 77 MB / 80 MB for Reykjavik -> Keflavik; the
  same with `memoryclass` 64 (the node graph never reaches the bound on
  these routes: `collectOutreachers` ran twice per 67 km route, memory panic
  mode never). AOT process RSS peak for the whole bench including the worker
  isolate: 75.9 MB (55 MB after the runs). Under the 150 MB target.
* `maxmem` hook: `RoutingWorker.spawn(memoryclass:, largeDevice:)` -- 64 MB
  by default, 128 MB with `largeDevice: true` (the plan's >= 6 GB devices),
  an explicit value wins; `RoutingRequest.memoryclass` /
  `BRouter.routeQuery(memoryclass:)` override it per request. `BRouter`
  itself keeps the server's 128 (the oracle contract). With 64 the corpus
  is still 200 of 200 identical.
* `RawCellCache` is bounded by `maxBytes` (16 MB) with LRU eviction, holds
  copies (never the io buffer), and `BRouter.routeQuery` clears it in
  `finally` unless `retainRawCache` is set.
* Not done: an accounting of the Dart object sizes against upstream's
  `nodesCreated * 95 + paths * 200` (an `OsmNode` is ~136 bytes here with
  8-byte fields, so the graph is about 1.4x the accounted figure; with
  `memoryclass` 64 that bounds it at ~60 MB, with 128 at ~120 MB before the
  panic mode).

`test/raw_cell_cache_test.dart` covers the cache (bounds, LRU order, copy
semantics, identical bytes with the cache off, retention across routes).

Run: `dart test` (444 tests, about 50 s with the tiles), `dart analyze`,
`dart format --set-exit-if-changed .`; `dart run tool/bench.dart`.

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
  every platform. `Math.sqrt` is IEEE-exact in both VMs. `Math.exp` (used by the
  expressions module) is also a HotSpot intrinsic and will need the same
  treatment in track R3.
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
  description bitmap and geometry bytes; the decoded way-tag strings need the
  expressions module and are compared in R3), and re-encodes the cache: the
  result is byte-identical to the data in the rd5, in Java and in Dart.

## Track R2: `brouter-mapaccess`

`lib/src/mapaccess/`, 17 of the 20 upstream classes:

| Java | Dart | Notes |
|---|---|---|
| `PhysicalFile` | `physical_file.dart` | one synchronous `dart:io` `RandomAccessFile` per rd5 (`setPositionSync` + `readIntoSync` loop = `seek` + `readFully`), no mmap, never a whole file; `ra`, `fileIndex`, `fileHeaderCrcs` are public (package-private upstream); `headerLookupVersion` keeps the version the tile was built with (11 for the 1.7.10 tiles, `lookups.dat` is 11.2; only the major number is compared, exactly like upstream, and only when a version other than -1 is passed); `checkVersionIntegrity`/`checkFileIntegrity` ported, `main` not; `readFullySync()` is a top-level helper |
| `OsmFile` | `osm_file.dart` | the two `createMicroCache` overloads are `createMicroCache(ilon, ilat, ...)` and `createMicroCacheForIdx(lonIdx, latIdx, ..., reallyDecode, hollowNodes)`; `fileOffset`/`posIdx` getters added for the index test |
| `NodesCache` | `nodes_cache.dart` | takes a `TagValueValidator?` plus `lookupVersion`/`lookupMinorVersion` named parameters instead of the `BExpressionContextWay` (R3); a validator that also implements `IByteArrayUnifier` is used for the link descriptions, else a `ByteArrayUnifier(16384)` (upstream NPEs on a null context); `first_file_access_*` are `firstFileAccessFailed`/`firstFileAccessName`; `Boolean.getBoolean("disableDirectWeaving")` is the static `NodesCache.disableDirectWeaving`, read per instance in the constructor; no `storageconfig.txt` (see skipped) |
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
* Nothing is cached at the byte level yet; the plan's raw-bytes LRU is R5.

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
  `accessType` is 2 for every way) and `setAllTagsUsed()`; the Dart side uses
  the equivalent `AllWaysValidator` (`test/mapaccess_support.dart`).

`test/vectors/mapaccess/` holds the two index dumps and 12 walks (532 KB):
four per tile with direct weaving (64 MB, `cleanupMode` 2, plus one with
mode 0 and one with mode 1; `funchal`, `camacha`, `machico`, `reykjavik`,
`reykjanes`, `mosfellsbaer`, and `portosanto`/`keflavik` whose waypoints lie in
different degree squares) and two per tile without direct weaving with
`maxmem` 200 000 and 400 steps, which is small enough that the garbage
collection enables, collects, cleans ghosts and doubles its budget inside the
walk. `test/nodes_cache_walk_test.dart` replays each walk with the Dart classes
and compares the whole JSON, first difference by path; `test/osm_file_test.dart`
compares the index dumps and additionally decodes every micro-cache of both
tiles (`MicroCache2` path, crc footer checked, `checkFileIntegrity`). Everything
is identical: node ids, coordinates, elevations, link targets and order,
description/geometry bytes, transfer nodes, turn restrictions, visit ids after
the peninsula cleanup, the waypoint matches (crosspoints, radii and directions
as raw double bits, `wayNearest` lists), `nodesCreated` before/after
`collectOutreachers`, and the cache status strings.

The tiles are not committed (1.5 + 2.7 MB). The tests read them from
`BROUTER_SEGMENTS_DIR`, by default `tools/brouter-oracle/.cache/segments4`
(`tools/brouter-oracle/fetch.sh` downloads and checksums them; CI runs it
first), and skip with a message when they are absent. The walks are bound to
the tile snapshot in `tools/brouter-oracle/tiles.sha256` like the corpus.

Run: `dart test` (about 3 s), `dart analyze`, `dart format --set-exit-if-changed .`.

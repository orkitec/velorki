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
* `DataInputStream`/`DataOutputStream` (in-memory, big-endian) and a
  `PriorityQueue` with `java.util.PriorityQueue` poll semantics live in
  `jvm.dart` for the stream coders and `TagValueCoder`.

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

Run: `dart test` (about 5 s), `dart analyze`, `dart format --set-exit-if-changed .`.

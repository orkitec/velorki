/// brouter_dart: a pure-Dart port of the BRouter routing runtime.
///
/// Track R1: the `brouter-util` and `brouter-codec` modules; track R2:
/// `brouter-mapaccess`; track R3: `brouter-expressions` (plus `ProfileCache`
/// of `brouter-core`). See README.md for the class list and the JVM emulation
/// caveats.
library;

export 'src/codec/data_buffers.dart';
export 'src/codec/integer_fifo3_pass.dart';
export 'src/codec/linked_list_container.dart';
export 'src/codec/micro_cache.dart';
export 'src/codec/micro_cache2.dart';
export 'src/codec/noisy_diff_coder.dart';
export 'src/codec/stat_coder_context.dart';
export 'src/codec/tag_value_coder.dart';
export 'src/codec/tag_value_validator.dart';
export 'src/codec/tag_value_wrapper.dart';
export 'src/codec/waypoint_matcher.dart';
export 'src/expressions/b_expression.dart';
export 'src/expressions/b_expression_context.dart';
export 'src/expressions/b_expression_context_node.dart';
export 'src/expressions/b_expression_context_way.dart';
export 'src/expressions/b_expression_lookup_value.dart';
export 'src/expressions/b_expression_meta_data.dart';
export 'src/expressions/cache_node.dart';
export 'src/expressions/integrity_check_profile.dart';
export 'src/expressions/profile_cache.dart';
export 'src/expressions/profile_comparator.dart';
export 'src/expressions/var_wrapper.dart';
export 'src/jfloat.dart';
export 'src/jmath.dart';
export 'src/jvm.dart';
export 'src/mapaccess/direct_weaver.dart';
export 'src/mapaccess/geometry_decoder.dart';
export 'src/mapaccess/matched_waypoint.dart';
export 'src/mapaccess/nodes_cache.dart';
export 'src/mapaccess/nodes_list.dart';
export 'src/mapaccess/osm_file.dart';
export 'src/mapaccess/osm_link.dart';
export 'src/mapaccess/osm_link_holder.dart';
export 'src/mapaccess/osm_node.dart';
export 'src/mapaccess/osm_node_pair_set.dart';
export 'src/mapaccess/osm_nodes_map.dart';
export 'src/mapaccess/osm_pos.dart';
export 'src/mapaccess/osm_transfer_node.dart';
export 'src/mapaccess/physical_file.dart';
export 'src/mapaccess/rd5_diff_tool.dart';
export 'src/mapaccess/turn_restriction.dart';
export 'src/mapaccess/waypoint_matcher_impl.dart';
export 'src/util/bit_coder_context.dart';
export 'src/util/byte_array_unifier.dart';
export 'src/util/byte_data_reader.dart';
export 'src/util/byte_data_writer.dart';
export 'src/util/cheap_angle_meter.dart';
export 'src/util/cheap_ruler.dart';
export 'src/util/compact_long_map.dart';
export 'src/util/compact_long_set.dart';
export 'src/util/crc32.dart';
export 'src/util/dense_long_map.dart';
export 'src/util/diff_coder_data_input_stream.dart';
export 'src/util/diff_coder_data_output_stream.dart';
export 'src/util/frozen_long_map.dart';
export 'src/util/frozen_long_set.dart';
export 'src/util/i_byte_array_unifier.dart';
export 'src/util/lazy_array_of_lists.dart';
export 'src/util/long_list.dart';
export 'src/util/lru_map.dart';
export 'src/util/lru_map_node.dart';
export 'src/util/mix_coder_data_input_stream.dart';
export 'src/util/mix_coder_data_output_stream.dart';
export 'src/util/progress_listener.dart';
export 'src/util/reduced_median_filter.dart';
export 'src/util/sorted_heap.dart';
export 'src/util/string_utils.dart';
export 'src/util/tiny_dense_long_map.dart';
export 'src/version.dart';

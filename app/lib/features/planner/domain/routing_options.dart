import 'package:freezed_annotation/freezed_annotation.dart';

import 'route_profile.dart';

part 'routing_options.freezed.dart';

/// Everything the planner lets the user change about how a route is computed.
@freezed
abstract class RoutingOptions with _$RoutingOptions {
  const factory RoutingOptions({
    @Default(RouteProfile.trekking) RouteProfile profile,

    /// Which of BRouter's alternatives is shown, `0`..`3`.
    @Default(0) int alternativeIdx,
  }) = _RoutingOptions;

  const RoutingOptions._();

  /// The highest alternative index BRouter serves.
  static const int maxAlternativeIdx = 3;

  /// Parses the JSON written into the `routing_options_json` column.
  factory RoutingOptions.fromMap(Map<String, dynamic> json) {
    final idx = json['alternativeIdx'];
    return RoutingOptions(
      profile: RouteProfile.fromName(json['profile'] as String?),
      alternativeIdx: idx is int ? idx.clamp(0, maxAlternativeIdx) : 0,
    );
  }

  /// The JSON written into the `routing_options_json` column.
  Map<String, dynamic> toMap() => <String, dynamic>{
    'profile': profile.brouterName,
    'alternativeIdx': alternativeIdx,
  };
}

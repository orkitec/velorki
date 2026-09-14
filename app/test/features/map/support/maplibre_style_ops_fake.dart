import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:velorki/features/map/data/maplibre_map_controller.dart';

/// One call the adapter made on its [MapLibreStyleOps].
///
/// Everything is kept as plain JSON rather than as the plugin's property
/// objects, because [ml.LayerProperties] has no equality: comparing the style
/// the adapter emitted is the only way to assert on colours and expressions.
@immutable
class RecordedStyleCall {
  /// Records a call to [name] on the style ops.
  const RecordedStyleCall(
    this.name, {
    this.id,
    this.layerId,
    this.belowLayerId,
    this.enableInteraction,
    this.geojson,
    this.properties,
    this.visible,
    this.imageBytes,
    this.cameraUpdate,
  });

  /// The member that was called, e.g. `addLayer`.
  final String name;

  /// The source id, layer id or image name the call is about.
  final String? id;

  /// The layer id of an `addLayer` call; [id] is its source there.
  final String? layerId;

  /// What the layer was inserted below, `null` for "on top".
  final String? belowLayerId;

  /// Whether the layer takes part in feature interaction, i.e. can be dragged.
  final bool? enableInteraction;

  /// The feature collection of a GeoJSON source call.
  final Map<String, dynamic>? geojson;

  /// `toJson()` of the layer or source properties.
  final Map<String, dynamic>? properties;

  /// The argument of `setLayerVisibility`.
  final bool? visible;

  /// The bitmap handed to `addImage`.
  final Uint8List? imageBytes;

  /// `toJson()` of a camera update, e.g. `['newLatLngZoom', [8.5, 47], 14]`.
  final Object? cameraUpdate;

  @override
  String toString() {
    final parts = <String>[
      ?id,
      ?layerId,
      if (belowLayerId != null) 'below: $belowLayerId',
    ];
    return '$name(${parts.join(', ')})';
  }
}

/// A [MapLibreStyleOps] that records instead of talking to a platform view.
///
/// The adapter's whole job is the order and the content of these calls, so the
/// fake keeps an ordered [calls] log of the mutating ones and answers the
/// queries from scriptable fields — [scriptedSourceIds] to pretend the native
/// side dropped a source, [visibleRegionError] to pretend the view is gone.
class RecordingStyleOps implements MapLibreStyleOps {
  /// Every mutating call, in order. Queries are counted instead, so a z-order
  /// assertion is not disturbed by the adapter checking its sources.
  final List<RecordedStyleCall> calls = <RecordedStyleCall>[];

  /// The sources that currently exist, in creation order.
  final List<String> sourceIds = <String>[];

  /// The layers that currently exist, in creation order.
  final List<String> layerIds = <String>[];

  /// Answers [getSourceIds] hands out before falling back to [sourceIds];
  /// one entry is consumed per call.
  final List<List<String>> scriptedSourceIds = <List<String>>[];

  /// When set, [getSourceIds] throws it.
  Object? sourceIdsError;

  /// When set, [getVisibleRegion] throws it.
  Object? visibleRegionError;

  /// What [getVisibleRegion] answers.
  ml.LatLngBounds visibleRegion = ml.LatLngBounds(
    southwest: const ml.LatLng(47.0, 8.0),
    northeast: const ml.LatLng(48.0, 9.0),
  );

  /// How often [getSourceIds] was asked.
  int getSourceIdsCount = 0;

  /// How often [getVisibleRegion] was asked.
  int getVisibleRegionCount = 0;

  @override
  ml.CameraPosition? cameraPosition;

  @override
  final List<ml.OnFeatureDragCallback> onFeatureDrag =
      <ml.OnFeatureDragCallback>[];

  @override
  final List<ml.OnFeatureInteractionCallback> onFeatureTapped =
      <ml.OnFeatureInteractionCallback>[];

  /// The names of the [calls], in order.
  List<String> get names => calls.map((c) => c.name).toList();

  /// Every call to [name], in order.
  List<RecordedStyleCall> callsNamed(String name) =>
      calls.where((c) => c.name == name).toList();

  /// The last call to [name], or `null` if there was none.
  RecordedStyleCall? lastCall(String name) {
    final matching = callsNamed(name);
    return matching.isEmpty ? null : matching.last;
  }

  /// The last `setLayerProperties` call for [layerId].
  RecordedStyleCall? lastPropertiesOf(String layerId) {
    final matching = calls.where(
      (c) => c.name == 'setLayerProperties' && c.id == layerId,
    );
    return matching.isEmpty ? null : matching.last;
  }

  /// The `addLayer` call that created [layerId].
  RecordedStyleCall? addLayerOf(String layerId) {
    final matching = calls.where(
      (c) => c.name == 'addLayer' && c.layerId == layerId,
    );
    return matching.isEmpty ? null : matching.last;
  }

  /// The last feature collection written to [sourceId] by either GeoJSON call.
  Map<String, dynamic>? lastGeoJsonOf(String sourceId) {
    final matching = calls.where(
      (c) =>
          (c.name == 'addGeoJsonSource' || c.name == 'setGeoJsonSource') &&
          c.id == sourceId,
    );
    return matching.isEmpty ? null : matching.last.geojson;
  }

  /// Forgets the recorded calls; the sources, layers and scripts stay.
  void clearCalls() => calls.clear();

  /// Fires a drag event at every registered listener, as the plugin does.
  void emitFeatureDrag(
    String featureId,
    ml.LatLng current, {
    ml.DragEventType eventType = ml.DragEventType.drag,
  }) {
    for (final callback in List<ml.OnFeatureDragCallback>.of(onFeatureDrag)) {
      callback(
        const Point<double>(0, 0),
        current,
        current,
        const ml.LatLng(0, 0),
        featureId,
        null,
        eventType,
      );
    }
  }

  // ------------------------------------------------------------- recording

  @override
  Future<void> addGeoJsonSource(
    String sourceId,
    Map<String, dynamic> geojson,
  ) async {
    sourceIds.add(sourceId);
    calls.add(
      RecordedStyleCall('addGeoJsonSource', id: sourceId, geojson: geojson),
    );
  }

  @override
  Future<void> setGeoJsonSource(
    String sourceId,
    Map<String, dynamic> geojson,
  ) async {
    calls.add(
      RecordedStyleCall('setGeoJsonSource', id: sourceId, geojson: geojson),
    );
  }

  @override
  Future<void> addSource(
    String sourceId,
    ml.SourceProperties properties,
  ) async {
    sourceIds.add(sourceId);
    calls.add(
      RecordedStyleCall(
        'addSource',
        id: sourceId,
        properties: properties.toJson(),
      ),
    );
  }

  @override
  Future<void> addLayer(
    String sourceId,
    String layerId,
    ml.LayerProperties properties, {
    String? belowLayerId,
    bool enableInteraction = true,
  }) async {
    layerIds.add(layerId);
    calls.add(
      RecordedStyleCall(
        'addLayer',
        id: sourceId,
        layerId: layerId,
        belowLayerId: belowLayerId,
        enableInteraction: enableInteraction,
        properties: properties.toJson(),
      ),
    );
  }

  @override
  Future<void> removeLayer(String layerId) async {
    layerIds.remove(layerId);
    calls.add(RecordedStyleCall('removeLayer', id: layerId));
  }

  @override
  Future<void> removeSource(String sourceId) async {
    sourceIds.remove(sourceId);
    calls.add(RecordedStyleCall('removeSource', id: sourceId));
  }

  @override
  Future<void> setLayerProperties(
    String layerId,
    ml.LayerProperties properties,
  ) async {
    calls.add(
      RecordedStyleCall(
        'setLayerProperties',
        id: layerId,
        // The adapter's own calls never skip a colour, but the plugin does
        // send nulls on, so record exactly what would travel.
        properties: properties.toJson(),
      ),
    );
  }

  @override
  Future<void> setLayerVisibility(String layerId, bool visible) async {
    calls.add(
      RecordedStyleCall('setLayerVisibility', id: layerId, visible: visible),
    );
  }

  @override
  Future<void> addImage(String name, Uint8List bytes) async {
    calls.add(RecordedStyleCall('addImage', id: name, imageBytes: bytes));
  }

  @override
  Future<void> animateCamera(ml.CameraUpdate update) async {
    calls.add(
      RecordedStyleCall('animateCamera', cameraUpdate: update.toJson()),
    );
  }

  @override
  Future<void> moveCamera(ml.CameraUpdate update) async {
    calls.add(RecordedStyleCall('moveCamera', cameraUpdate: update.toJson()));
  }

  // --------------------------------------------------------------- queries

  @override
  Future<List<String>> getSourceIds() async {
    getSourceIdsCount++;
    final error = sourceIdsError;
    if (error != null) throw error;
    if (scriptedSourceIds.isNotEmpty) return scriptedSourceIds.removeAt(0);
    return List<String>.of(sourceIds);
  }

  @override
  Future<ml.LatLngBounds> getVisibleRegion() async {
    getVisibleRegionCount++;
    final error = visibleRegionError;
    if (error != null) throw error;
    return visibleRegion;
  }
}

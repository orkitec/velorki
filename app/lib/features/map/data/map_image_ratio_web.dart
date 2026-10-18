// The web side of a conditional import: what uses it is the same import
// on the phone side, which is the side dart_code_linter follows.
// ignore_for_file: unused-code

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Runs [add], which registers the style image [name] painted at
/// [pixelRatio] pixels per logical pixel, through maplibre_gl's browser
/// plugin.
///
/// The plugin hands maplibre-gl-js every image with `pixelRatio: 1`, so a
/// bitmap painted for a screen of two pixels per point came out twice the
/// size the phone draws it, and it skips a name the style already has, so a
/// new palette never replaced a marker. Maplibre's own `addImage` and
/// `hasImage` are wrapped once for the app's images: the image is added at
/// its ratio, whenever it is added (a new style adds it again), and while
/// [add] runs its name is not there yet, so a newer bitmap replaces it.
Future<void> addImageAtRatio(
  String name,
  double pixelRatio,
  Future<void> Function() add,
) {
  if (!_install()) return add();
  _ratios[name] = pixelRatio;
  // The plugin asks `hasImage` and calls `addImage` before its first await.
  _replacing = name;
  try {
    return add();
  } finally {
    _replacing = null;
  }
}

final Map<String, double> _ratios = <String, double>{};
String? _replacing;
bool? _installed;

bool _install() {
  if (_installed != null) return _installed!;
  final library = globalContext['maplibregl'];
  if (library == null || !library.isA<JSObject>()) return false;
  final map = (library as JSObject)['Map'];
  if (map == null || !map.isA<JSObject>()) return _installed = false;
  final prototype = (map as JSObject)['prototype'] as JSObject;
  final addImage = prototype['addImage'] as JSFunction;
  final hasImage = prototype['hasImage'] as JSFunction;
  final removeImage = prototype['removeImage'] as JSFunction;

  prototype['hasImage'] = ((JSObject self, JSString id) {
    if (id.toDart == _replacing) return false.toJS;
    return hasImage.callAsFunction(self, id);
  }).toJSCaptureThis;

  prototype['addImage'] =
      ((JSObject self, JSString id, JSAny? image, JSObject? options) {
        final ratio = _ratios[id.toDart];
        if (ratio != null) {
          options ??= JSObject();
          options['pixelRatio'] = ratio.toJS;
          final there = hasImage.callAsFunction(self, id) as JSBoolean?;
          if (there?.toDart ?? false) removeImage.callAsFunction(self, id);
        }
        return addImage.callAsFunction(self, id, image, options);
      }).toJSCaptureThis;
  return _installed = true;
}

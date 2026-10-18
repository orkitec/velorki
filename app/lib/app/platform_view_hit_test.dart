import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Whether a pointer at [position] in the view [viewId] reaches a platform
/// view (in a browser, the map's HTML element): nothing of Flutter's that
/// takes pointers is over it there. [position] is in logical pixels and may
/// fall between them, as a browser's pointer does on a screen with more
/// than one pixel per point.
bool platformViewAt(Offset position, int viewId) {
  final result = HitTestResult();
  WidgetsBinding.instance.hitTestInView(result, position, viewId);
  return result.path.any((entry) => entry.target is PlatformViewRenderBox);
}

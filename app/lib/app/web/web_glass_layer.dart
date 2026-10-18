import 'dart:js_interop';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web/web.dart' as web;

import '../../features/shared/application/glass_blur.dart';
import '../../features/shared/presentation/glass_backdrop.dart';

@JS('CSS.supports')
external bool _cssSupports(String property, String value);

/// The browser's blur behind the glass ([GlassBackdrop]).
///
/// The map is an HTML element under Flutter's canvas, so Flutter's own
/// blur cannot reach it. Inside each map's element this keeps one layer
/// of transparent boxes, one per piece of glass on screen, in the glass's
/// place and shape, with the browser's `backdrop-filter`: each blurs the
/// map right under the glass. The layer takes no pointer, and Flutter's
/// translucent glass is drawn over it as before. Where Flutter paints
/// something opaque between the map and the glass, it hides the box with
/// it, as it hides the map.
///
/// Where the browser has no `backdrop-filter`, the rider asked for less
/// transparency, or panning the map under the blur turns out too slow,
/// [GlassBlur] is switched off and the glass is drawn as Subtle instead.
abstract final class WebGlassLayer {
  static const String _layerClass = 'velorki-glass';

  static ProviderContainer? _container;
  static List<GlassRect> _shown = const <GlassRect>[];
  static bool _syncScheduled = false;

  /// Frame intervals taken while the map moved under the glass.
  static final List<double> _intervals = <double>[];
  static double _movedAt = -1e9;
  static double? _lastFrame;
  static bool _sampling = false;

  /// Starts blurring, or switches the blur off where it cannot work.
  /// Called once by the browser's bootstrap.
  static void install(ProviderContainer container) {
    _container = container;
    final backdropFilter =
        _cssSupports('backdrop-filter', 'blur(1px)') ||
        _cssSupports('-webkit-backdrop-filter', 'blur(1px)');
    final reduced = web.window
        .matchMedia('(prefers-reduced-transparency: reduce)')
        .matches;
    if (!browserBlursGlass(
      backdropFilter: backdropFilter,
      reducedTransparency: reduced,
      tooSlow: false,
    )) {
      container.read(glassBlurProvider.notifier).unavailable();
      return;
    }
    GlassBackdrop.tracked = true;
    SchedulerBinding.instance.addPersistentFrameCallback((_) => _schedule());
    void moved(web.Event event) {
      final target = event.target;
      if (target == null || !target.isA<web.Element>()) return;
      if ((target as web.Element).closest('.maplibregl-map') == null) return;
      if (event.isA<web.PointerEvent>() &&
          (event as web.PointerEvent).buttons == 0) {
        return;
      }
      _movedAt = web.window.performance.now();
      _sample();
    }

    web.window.addEventListener('pointermove', moved.toJS);
    web.window.addEventListener('wheel', moved.toJS);
  }

  /// Puts the boxes in place on the browser's next frame, by when the
  /// engine has moved the maps' elements to where this frame put them.
  static void _schedule() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    web.window.requestAnimationFrame(
      ((num _) {
        _syncScheduled = false;
        _sync();
      }).toJS,
    );
  }

  static void _sync() {
    if (_container == null || !_container!.read(glassBlurProvider)) {
      _shown = const <GlassRect>[];
    } else {
      _shown = visibleGlass();
    }
    final view = web.document.querySelector('flutter-view');
    if (view == null) return;
    final origin = view.getBoundingClientRect();
    final maps = web.document.querySelectorAll('.maplibregl-map');
    for (var i = 0; i < maps.length; i++) {
      final map = maps.item(i)! as web.HTMLElement;
      _layOut(map, origin);
    }
  }

  static void _layOut(web.HTMLElement map, web.DOMRect origin) {
    var layer = map.querySelector('.$_layerClass') as web.HTMLElement?;
    if (layer == null) {
      if (_shown.isEmpty) return;
      layer = web.HTMLDivElement()..className = _layerClass;
      layer.style
        ..position = 'absolute'
        ..left = '0'
        ..top = '0'
        ..right = '0'
        ..bottom = '0'
        ..pointerEvents = 'none'
        ..overflow = 'hidden'
        ..zIndex = '1';
      map.append(layer);
    }
    final at = map.getBoundingClientRect();
    final dx = origin.left - at.left;
    final dy = origin.top - at.top;
    final boxes = layer.children;
    while (boxes.length > _shown.length) {
      boxes.item(boxes.length - 1)!.remove();
    }
    while (boxes.length < _shown.length) {
      final box = web.HTMLDivElement();
      box.style
        ..position = 'absolute'
        ..pointerEvents = 'none';
      layer.append(box);
    }
    for (var i = 0; i < _shown.length; i++) {
      final glass = _shown[i];
      final box = boxes.item(i)! as web.HTMLElement;
      final blur = 'blur(${glass.sigma}px)';
      box.style
        ..left = '${glass.rect.left + dx}px'
        ..top = '${glass.rect.top + dy}px'
        ..width = '${glass.rect.width}px'
        ..height = '${glass.rect.height}px'
        ..borderRadius = '${glass.radius}px'
        ..opacity = '${glass.opacity}'
        ..setProperty('backdrop-filter', blur)
        ..setProperty('-webkit-backdrop-filter', blur);
    }
  }

  /// Times the browser's frames while the map moves under the glass, and
  /// switches the blur off once they say it is too slow.
  static void _sample() {
    if (_sampling || _shown.isEmpty) return;
    _sampling = true;
    _lastFrame = null;
    void frame(num now) {
      final last = _lastFrame;
      if (last != null) _intervals.add(now - last);
      _lastFrame = now.toDouble();
      if (_intervals.length > glassFrameWindow) _intervals.removeAt(0);
      if (framesTooSlow(_intervals)) {
        debugPrint('velorki: glass blur too slow here, drawn without it');
        _container?.read(glassBlurProvider.notifier).unavailable();
        _sampling = false;
        _sync();
        return;
      }
      if (now - _movedAt > 500) {
        _sampling = false;
        return;
      }
      web.window.requestAnimationFrame(frame.toJS);
    }

    web.window.requestAnimationFrame(frame.toJS);
  }
}

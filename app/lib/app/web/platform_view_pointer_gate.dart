import 'dart:js_interop';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// Gives the map's own DOM element only the pointers that Flutter's hit
/// test gives the map.
///
/// In a browser the map is a platform view: an HTML element under Flutter's
/// canvas whose events the browser hands it directly, wherever it lies under
/// the pointer. Without this, a click on the column or a button over the map
/// also landed on the map (a waypoint under the sheet), and the wheel over
/// the sheet zoomed the map under it instead of scrolling. The gate asks
/// Flutter, for each pointer, what it hits at that point: a widget over the
/// map gets the pointer, and the map only what reaches it.
///
/// - Hovering mouse or pen: platform views stop taking pointer events
///   (`pointer-events: none`, by an attribute on the root element) while
///   the pointer is over a widget, so the browser itself sends the events
///   to Flutter. Not while a button is down: a pan of the map that crosses
///   the column, or a drag of the sheet that crosses the map, stays with
///   whoever it began on.
/// - A press or a wheel the browser still sent to a platform view though a
///   widget is over it (a touch, which has no hover, or the first event
///   after the page loaded) is taken from the platform view before it sees
///   it, and dispatched to Flutter's view instead; the rest of that press
///   follows it there, and the mouse and touch events the browser derives
///   from it never reach the map. A touch has no hover, so for touch the
///   platform views stay open and every press is decided this way.
abstract final class PlatformViewPointerGate {
  static const String _attribute = 'data-platform-views';

  static web.Element? _view;
  static bool _open = true;

  /// Set while a copy made by [_reroute] is on its way, which passes the
  /// gate untouched.
  static bool _dispatching = false;

  /// The pointers rerouted to Flutter, until they go up.
  static final Set<int> _rerouted = <int>{};

  /// Whether a mouse or touch press now belongs to Flutter, so its derived
  /// mouse and touch events are kept from the platform view.
  static bool _mouseToFlutter = false;
  static bool _touchToFlutter = false;

  /// Starts gating. Called once by the browser's bootstrap.
  static void install() {
    final style = web.HTMLStyleElement()
      ..textContent =
          ':root[$_attribute="closed"] flt-platform-view'
          '{pointer-events:none !important}';
    web.document.head?.append(style);
    void listen(String type, void Function(web.Event) handler) =>
        web.window.addEventListener(
          type,
          handler.toJS,
          web.AddEventListenerOptions(capture: true, passive: false),
        );
    listen('pointermove', _onPointerMove);
    listen('pointerdown', _onPointerDown);
    for (final type in ['pointerup', 'pointercancel']) {
      listen(type, _onPointerEnd);
    }
    listen('wheel', _onWheel);
    for (final type in [
      'mousedown',
      'mousemove',
      'mouseup',
      'click',
      'dblclick',
      'contextmenu',
      'auxclick',
    ]) {
      listen(type, (event) => _keep(event, flutter: _mouseToFlutter));
    }
    for (final type in ['touchstart', 'touchmove', 'touchend', 'touchcancel']) {
      listen(type, (event) => _keep(event, flutter: _touchToFlutter));
    }
  }

  static web.Element? get _flutterView =>
      _view ??= web.document.querySelector('flutter-view');

  /// Whether Flutter's hit test at the event's point reaches a platform
  /// view: nothing of Flutter's that takes pointers is over it.
  static bool _platformViewAt(web.MouseEvent event) {
    final view = _flutterView;
    final flutter = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view == null || flutter == null) return true;
    final origin = view.getBoundingClientRect();
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      result,
      Offset(event.clientX - origin.left, event.clientY - origin.top),
      flutter.viewId,
    );
    return result.path.any((entry) => entry.target is PlatformViewRenderBox);
  }

  static bool _inPlatformView(web.Event event) {
    final target = event.target;
    return target != null &&
        target.isA<web.Element>() &&
        (target as web.Element).closest('flt-platform-view') != null;
  }

  static void _setOpen(bool open) {
    if (open == _open) return;
    _open = open;
    if (open) {
      web.document.documentElement?.removeAttribute(_attribute);
    } else {
      web.document.documentElement?.setAttribute(_attribute, 'closed');
    }
  }

  static void _onPointerMove(web.Event raw) {
    if (_dispatching) return;
    final event = raw as web.PointerEvent;
    if (_rerouted.contains(event.pointerId)) {
      if (_inPlatformView(event)) _reroute(event);
      return;
    }
    if (event.buttons == 0 && event.pointerType != 'touch') {
      final toMap = _platformViewAt(event);
      _mouseToFlutter = !toMap;
      _setOpen(toMap);
    }
  }

  static void _onPointerDown(web.Event raw) {
    if (_dispatching) return;
    final event = raw as web.PointerEvent;
    final toMap = _platformViewAt(event);
    // A touch's press brings the mouse events a browser derives from it
    // (a click after the tap), which follow it too.
    _mouseToFlutter = !toMap;
    if (event.pointerType == 'touch') _touchToFlutter = !toMap;
    if (!toMap && _inPlatformView(event)) {
      _rerouted.add(event.pointerId);
      _reroute(event);
    }
    // A touch has no hover to open them again before its next press, so
    // after a touch they are left open: a press on a widget is rerouted.
    _setOpen(toMap || event.pointerType == 'touch');
  }

  static void _onPointerEnd(web.Event raw) {
    if (_dispatching) return;
    final event = raw as web.PointerEvent;
    if (_rerouted.remove(event.pointerId) && _inPlatformView(event)) {
      _reroute(event);
    }
  }

  static void _onWheel(web.Event raw) {
    if (_dispatching) return;
    final event = raw as web.WheelEvent;
    if (!_inPlatformView(event)) return;
    if (_platformViewAt(event)) return;
    _setOpen(false);
    _reroute(event);
  }

  /// Keeps a derived mouse or touch event from a platform view while the
  /// press it belongs to is Flutter's.
  static void _keep(web.Event event, {required bool flutter}) {
    if (!flutter || !_inPlatformView(event)) return;
    event.stopImmediatePropagation();
    if (event.type == 'touchend' || event.type == 'touchcancel') {
      if ((event as web.TouchEvent).touches.length == 0) {
        _touchToFlutter = false;
      }
    }
  }

  /// Takes [event] from the platform view it was sent to and sends a copy to
  /// Flutter's view, as if the platform view were not there.
  static void _reroute(web.Event event) {
    final view = _flutterView;
    if (view == null) return;
    event
      ..stopImmediatePropagation()
      ..preventDefault();
    final web.Event copy;
    if (event.isA<web.WheelEvent>()) {
      event as web.WheelEvent;
      copy = web.WheelEvent(
        event.type,
        web.WheelEventInit(
          bubbles: true,
          cancelable: true,
          composed: true,
          clientX: event.clientX,
          clientY: event.clientY,
          screenX: event.screenX,
          screenY: event.screenY,
          ctrlKey: event.ctrlKey,
          shiftKey: event.shiftKey,
          altKey: event.altKey,
          metaKey: event.metaKey,
          buttons: event.buttons,
          deltaX: event.deltaX,
          deltaY: event.deltaY,
          deltaZ: event.deltaZ,
          deltaMode: event.deltaMode,
        ),
      );
    } else {
      final pointer = event as web.PointerEvent;
      copy = web.PointerEvent(
        event.type,
        web.PointerEventInit(
          bubbles: true,
          cancelable: true,
          composed: true,
          clientX: pointer.clientX,
          clientY: pointer.clientY,
          screenX: pointer.screenX,
          screenY: pointer.screenY,
          ctrlKey: pointer.ctrlKey,
          shiftKey: pointer.shiftKey,
          altKey: pointer.altKey,
          metaKey: pointer.metaKey,
          button: pointer.button,
          buttons: pointer.buttons,
          pointerId: pointer.pointerId,
          pointerType: pointer.pointerType,
          isPrimary: pointer.isPrimary,
          width: pointer.width,
          height: pointer.height,
          pressure: pointer.pressure,
          tiltX: pointer.tiltX,
          tiltY: pointer.tiltY,
        ),
      );
    }
    _dispatching = true;
    try {
      view.dispatchEvent(copy);
    } finally {
      _dispatching = false;
    }
  }
}

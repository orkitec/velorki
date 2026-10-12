import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'adaptive_docking_sheet.dart' show QuarterTurnedFrame;
import 'metric_chart.dart';

/// The touches of a chart over an x axis: a finger that lands or sweeps
/// reads out the place under it, a horizontal pinch zooms the axis around
/// the fingers, a drag while zoomed pans, and a double tap or the reset
/// button shows the whole axis again.
///
/// The touches are its own rather than a chart library's: a library's tap
/// and pan recognizers would sit inside these and reach the pointer router
/// first, and a pinch clears the scale slop on the very move the pan clears
/// its own, so the pan would win every pinch on registration order. One
/// [Listener] reads out under a landing finger at once, before any arena is
/// decided, and one scale recognizer tells a sweep, a pan and a pinch apart
/// by how many fingers it has. A scrollable around the chart beats that
/// recognizer on a vertical drag, as it would beat a pan, so the sheet the
/// chart sits in still scrolls and drags; a sideways swipe between pages
/// beats it on a sideways move too, so there the sweep is the page's —
/// except while zoomed, when a one-finger drag is the chart's, to pan.
///
/// With [onWindow] the caller owns the window and several charts can share
/// one; without it the chart keeps its own.
class ChartGestures extends StatefulWidget {
  /// Creates the touches.
  const ChartGestures({
    required this.extent,
    required this.builder,
    super.key,
    this.header,
    this.zoomable = false,
    this.window,
    this.onWindow,
    this.leftInset = 0,
    this.rightInset = 0,
    this.onRead,
    this.onReadEnd,
    this.resetLabel,
  });

  /// The whole x axis, from the first sample to the last.
  final ChartWindow extent;

  /// Builds the plot for the window shown, `null` for the whole axis: the
  /// part the fingers work on.
  final Widget Function(BuildContext context, ChartWindow? window) builder;

  /// Builds what goes above the plot for the window shown, untouchable: a
  /// caption, a read-out.
  final Widget Function(BuildContext context, ChartWindow? window)? header;

  /// Whether a pinch zooms the x axis.
  final bool zoomable;

  /// The stretch of the axis shown; `null` for all of it. Only read while
  /// [onWindow] is set.
  final ChartWindow? window;

  /// Called with the window a pinch, a drag or a double tap asks for, `null`
  /// for the whole axis. With it the chart shows [window] and nothing else.
  final ValueChanged<ChartWindow?>? onWindow;

  /// The room left of the plot, for the y axis labels; a finger there reads
  /// out the plot's left edge.
  final double leftInset;

  /// The room right of the plot.
  final double rightInset;

  /// A finger reads out the place [x] on the axis, in the axis' unit.
  final ValueChanged<double>? onRead;

  /// The finger reading out is gone: [lifted] when it left the screen, so a
  /// read-out may stay; otherwise a pinch or a pan took it, and what it
  /// landed on is not what the rider is after any more.
  final void Function({required bool lifted})? onReadEnd;

  /// The label of the button at the top right that shows the whole axis
  /// again while zoomed; `null` for no button, when another chart on the
  /// same window carries it.
  final String? resetLabel;

  @override
  State<ChartGestures> createState() => _ChartGesturesState();
}

class _ChartGesturesState extends State<ChartGestures> {
  // The window last asked for; `null` for the whole axis. The chart's own
  // when it keeps it, and a step ahead of [widget.window] when the caller
  // does, so two finger moves in one frame build on each other.
  ChartWindow? _window;

  // The window a pinch started from and where the fingers were, so the
  // stretch under them stays under them as they move.
  ChartWindow? _pinchFrom;
  double _pinchFocalX = 0;

  // How many fingers are on the chart: the first reads out, the second
  // takes the read-out away again.
  int _fingers = 0;

  // Whether a finger is reading out, so the end is said once.
  bool _reading = false;

  // How wide the plot is on screen, as of the last layout, for turning a
  // finger's pixels into the axis' unit.
  double _plotWidth = 0;

  bool get _controlled => widget.onWindow != null;

  @override
  void initState() {
    super.initState();
    _window = widget.window;
  }

  @override
  void didUpdateWidget(ChartGestures oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controlled) _window = widget.window;
  }

  /// The window as asked for, cut to the axis; `null` when it is the whole
  /// axis anyway.
  ChartWindow? _clamp(ChartWindow? window) {
    if (window == null) return null;
    final extent = widget.extent;
    final full = extent.end - extent.start;
    if (full <= 0) return null;
    final width = (window.end - window.start).clamp(
      full * chartMinWindowShare,
      full,
    );
    if (width >= full) return null;
    final start = window.start.clamp(extent.start, extent.end - width);
    return (start: start, end: start + width);
  }

  /// The window drawn.
  ChartWindow? get _shown => _clamp(_controlled ? widget.window : _window);

  /// The window the fingers work from: the one last asked for.
  ChartWindow? get _current => _clamp(_window);

  void _setWindow(ChartWindow? window) {
    final next = _clamp(window);
    if (next == _current) return;
    _window = next;
    if (_controlled) {
      widget.onWindow!(next);
    } else {
      setState(() {});
    }
  }

  /// The plot's x of a pixel [dx] in the chart, 0 to 1 across the plot.
  double _plotShare(double dx) =>
      _plotWidth <= 0 ? 0 : (dx - widget.leftInset) / _plotWidth;

  void _onPointerDown(PointerDownEvent event) {
    _fingers++;
    if (_fingers == 1) {
      _readAt(event.localPosition.dx);
    } else {
      // A second finger is a pinch on its way, not a place to read out.
      _endRead(lifted: false);
    }
  }

  void _onPointerUp(PointerEvent event) {
    if (_fingers > 0) _fingers--;
    if (_fingers == 0) _endRead(lifted: true);
  }

  /// Reads out the axis under the pixel [dx] in the chart, in the window
  /// shown.
  void _readAt(double dx) {
    final shown = _current ?? widget.extent;
    final share = _plotShare(dx).clamp(0.0, 1.0);
    _reading = true;
    widget.onRead?.call(shown.start + share * (shown.end - shown.start));
  }

  void _endRead({required bool lifted}) {
    if (!_reading) return;
    _reading = false;
    widget.onReadEnd?.call(lifted: lifted);
  }

  void _onScaleStart(ScaleStartDetails details) {
    _pinchFrom = _current ?? widget.extent;
    _pinchFocalX = details.localFocalPoint.dx;
    // A pinch or a pan moves the line under the finger: whatever it landed
    // on is not what the rider is after.
    if (details.pointerCount >= 2 || _pans) _endRead(lifted: false);
  }

  /// Whether one finger moving pans the window rather than sweeping.
  bool get _pans => widget.zoomable && _current != null;

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount < 2) {
      // One finger: a sweep of the read-out over the whole line, a pan of
      // the window once zoomed.
      if (_pans) {
        _pan(details.focalPointDelta.dx);
      } else if (_fingers == 1) {
        _readAt(details.localFocalPoint.dx);
      }
      return;
    }
    if (!widget.zoomable) return;
    final from = _pinchFrom;
    if (from == null || _plotWidth <= 0) return;
    final extent = widget.extent;
    final full = extent.end - extent.start;
    final fromWidth = from.end - from.start;
    final width = (fromWidth / details.horizontalScale).clamp(
      full * chartMinWindowShare,
      full,
    );
    // The point of the line the fingers closed on stays under them.
    final anchor = from.start + _plotShare(_pinchFocalX) * fromWidth;
    final start = anchor - _plotShare(details.localFocalPoint.dx) * width;
    _setWindow((start: start, end: start + width));
  }

  void _onScaleEnd(ScaleEndDetails details) => _pinchFrom = null;

  void _onDragStart(DragStartDetails details) {
    if (_pans) {
      _endRead(lifted: false);
    } else if (_fingers == 1) {
      _readAt(details.localPosition.dx);
    }
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_pans) {
      _pan(details.delta.dx);
    } else if (_fingers == 1) {
      _readAt(details.localPosition.dx);
    }
  }

  /// Moves the window by a finger's [dx] pixels, the line following the
  /// finger.
  void _pan(double dx) {
    final current = _current;
    if (current == null || _plotWidth <= 0) return;
    final shift = -dx / _plotWidth * (current.end - current.start);
    _setWindow((start: current.start + shift, end: current.end + shift));
  }

  /// Whether the chart is in a sheet turned a quarter, whose drag runs
  /// sideways on the screen.
  static bool _inTurnedSheet(BuildContext context) =>
      (context
                  .findAncestorWidgetOfExactType<QuarterTurnedFrame>()
                  ?.quarterTurns ??
              0)
          .isOdd;

  @override
  Widget build(BuildContext context) {
    final window = _shown;
    final header = widget.header;
    final plot = LayoutBuilder(
      builder: (context, constraints) {
        _plotWidth =
            constraints.maxWidth - widget.leftInset - widget.rightInset;
        final gestures = <Type, GestureRecognizerFactory>{
          ScaleGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<ScaleGestureRecognizer>(
                ScaleGestureRecognizer.new,
                (r) => r
                  ..onStart = _onScaleStart
                  ..onUpdate = _onScaleUpdate
                  ..onEnd = _onScaleEnd,
              ),
          // Zoomed, a one-finger sideways drag is the chart's pan even
          // under a page swipe, which would otherwise take it at a smaller
          // slop than the scale recognizer's. In a sheet turned sideways it
          // is the chart's sweep too: there the sheet's own drag runs along
          // the chart's x axis and would take every sweep, and the sheet
          // has its handle and the rest of its content to be dragged by.
          // After the scale recognizer, so a pinch, which clears its slop
          // on the same move, stays one.
          if (_pans || _inTurnedSheet(context))
            HorizontalDragGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  HorizontalDragGestureRecognizer
                >(
                  HorizontalDragGestureRecognizer.new,
                  (r) => r
                    ..onStart = _onDragStart
                    ..onUpdate = _onDragUpdate,
                ),
          // The double tap holds the arena for a moment, which only a
          // zoomable chart pays for.
          if (widget.zoomable)
            DoubleTapGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  DoubleTapGestureRecognizer
                >(
                  DoubleTapGestureRecognizer.new,
                  (r) => r..onDoubleTap = () => _setWindow(null),
                ),
        };
        final touchable = Listener(
          onPointerDown: _onPointerDown,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerUp,
          child: RawGestureDetector(
            gestures: gestures,
            child: widget.builder(context, window),
          ),
        );
        final label = widget.resetLabel;
        if (!widget.zoomable || label == null) return touchable;
        return Stack(
          children: [
            touchable,
            if (window != null)
              Positioned(
                top: 0,
                right: 0,
                child: TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: Theme.of(context).textTheme.labelSmall,
                  ),
                  onPressed: () => _setWindow(null),
                  child: Text(label),
                ),
              ),
          ],
        );
      },
    );
    if (header == null) return plot;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [header(context, window), plot],
    );
  }
}

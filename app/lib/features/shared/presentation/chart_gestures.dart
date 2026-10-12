import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import 'adaptive_docking_sheet.dart' show QuarterTurnedFrame;
import 'metric_chart.dart';

/// How tall the band over a chart's plot is that the cursor's handle sits
/// in, so the handle never covers the line.
const double chartCursorBandHeight = 32;

/// Radius of the handle's badge, inside its rim.
const double chartCursorBadgeRadius = 12;

/// How wide the dark rim round the handle's badge is.
const double chartCursorRimWidth = 2;

/// The side of the handle's touch target, from the top of the band down.
const double chartCursorTargetSize = 48;

/// How far a screen reader's step moves the cursor, as a share of the
/// stretch of the axis shown.
const double chartCursorStepShare = 0.01;

/// The badge of a chart's cursor handle, for finding it.
const Key chartCursorHandleKey = ValueKey<String>('chart-cursor-handle');

/// The touches of a chart over an x axis, and its cursor.
///
/// The cursor is a line across the plot topped by a handle, a badge with
/// the rider on it: dragging the handle moves the cursor like a slider,
/// zoomed or not, and a double tap on it hides the cursor. A tap on the
/// plot puts the cursor there, and one finger sweeping the plot moves it
/// along — until the chart is zoomed, when the sweep pans the window
/// instead and the handle is what moves the cursor. A horizontal pinch
/// zooms the axis around the fingers, and a double tap on the plot or the
/// reset button shows the whole axis again. The cursor stays after the
/// finger lifts; a pan or a zoom that leaves it outside the window takes it
/// to the nearest edge.
///
/// The touches are its own rather than a chart library's: a library's tap
/// and pan recognizers would sit inside these and reach the pointer router
/// first, and a pinch clears the scale slop on the very move the pan clears
/// its own, so the pan would win every pinch on registration order. One
/// [Listener] tells a tap, and one scale recognizer tells a sweep, a pan
/// and a pinch apart by how many fingers it has. A scrollable around the
/// chart beats that recognizer on a vertical drag, as it would beat a pan,
/// so the sheet the chart sits in still scrolls and drags; a sideways swipe
/// between pages beats it on a sideways move too, so there the sweep is the
/// page's — except while zoomed, when a one-finger drag is the chart's, to
/// pan. The handle takes every touch that lands on it at once, ahead of all
/// of them.
///
/// With [onWindow] the caller owns the window and several charts can share
/// one; with [cursor] the caller owns the cursor, and charts handed the same
/// one share it. Without them the chart keeps its own.
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
    this.bottomInset = 0,
    this.cursor,
    this.metresPerUnit = 1,
    this.cursorLabel,
    this.cursorValue,
    this.resetLabel,
  });

  /// The whole x axis, from the first sample to the last.
  final ChartWindow extent;

  /// Builds the plot for the window shown, `null` for the whole axis: the
  /// part the fingers work on. It is drawn under [chartCursorBandHeight] of
  /// room for the cursor's handle.
  final Widget Function(BuildContext context, ChartWindow? window) builder;

  /// Builds what goes above the plot for the window shown and the cursor,
  /// in the axis' unit and `null` while hidden; untouchable: a caption, a
  /// read-out.
  final Widget Function(
    BuildContext context,
    ChartWindow? window,
    double? cursor,
  )?
  header;

  /// Whether a pinch zooms the x axis.
  final bool zoomable;

  /// The stretch of the axis shown; `null` for all of it. Only read while
  /// [onWindow] is set.
  final ChartWindow? window;

  /// Called with the window a pinch, a drag or a double tap asks for, `null`
  /// for the whole axis. With it the chart shows [window] and nothing else.
  final ValueChanged<ChartWindow?>? onWindow;

  /// The room left of the plot, for the y axis labels; a finger there puts
  /// the cursor on the plot's left edge.
  final double leftInset;

  /// The room right of the plot.
  final double rightInset;

  /// The room under the plot, for the x axis labels; the cursor's line
  /// stops above it.
  final double bottomInset;

  /// Where the cursor stands, in metres along the line, `null` while it is
  /// hidden; the chart keeps its own when left out.
  final ValueNotifier<double?>? cursor;

  /// How many metres one unit of the x axis is, to turn [cursor] into the
  /// axis' unit and back.
  final double metresPerUnit;

  /// What a screen reader calls the handle; "Position on the route" when
  /// left out.
  final String? cursorLabel;

  /// What a screen reader says the cursor at [x], in the axis' unit, reads.
  final String Function(double x)? cursorValue;

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

  // How many fingers are on the plot: one sweeps, two pinch.
  int _fingers = 0;

  // Where a finger that may yet be a tap came down on the plot; `null` once
  // it moved too far or a second finger joined it.
  Offset? _tapAt;

  // How wide the plot is on screen, as of the last layout, for turning a
  // finger's pixels into the axis' unit.
  double _plotWidth = 0;

  // The cursor while the caller does not hand one in.
  ValueNotifier<double?>? _ownCursor;

  // The plot and its band, for placing a finger on the handle.
  final GlobalKey _stackKey = GlobalKey();

  // A finger on the handle: where it came down, how far from the cursor's
  // line, and whether it has moved off the spot.
  Offset? _handleDown;
  double _handleGrab = 0;
  bool _handleMoved = false;

  // Whether a tap on the handle has just ended, so a second one now is a
  // double tap; and whether the finger on it now is that second tap.
  Timer? _handleTapped;
  bool _secondTap = false;

  bool get _controlled => widget.onWindow != null;

  ValueNotifier<double?> get _cursor =>
      widget.cursor ?? (_ownCursor ??= ValueNotifier<double?>(null));

  @override
  void initState() {
    super.initState();
    _window = widget.window;
    _cursor.addListener(_cursorMoved);
  }

  @override
  void didUpdateWidget(ChartGestures oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controlled) _window = widget.window;
    if (!identical(oldWidget.cursor, widget.cursor)) {
      (oldWidget.cursor ?? _ownCursor)?.removeListener(_cursorMoved);
      _cursor.addListener(_cursorMoved);
    }
    // A cursor of its own belongs to the line it was put on.
    if (widget.cursor == null && oldWidget.extent != widget.extent) {
      _ownCursor?.value = null;
    }
  }

  @override
  void dispose() {
    _cursor.removeListener(_cursorMoved);
    _ownCursor?.dispose();
    _handleTapped?.cancel();
    super.dispose();
  }

  void _cursorMoved() {
    if (mounted) setState(() {});
  }

  /// The cursor in the axis' unit; `null` while it is hidden.
  double? get _cursorX {
    final metres = _cursor.value;
    return metres == null ? null : metres / widget.metresPerUnit;
  }

  set _cursorX(double? x) =>
      _cursor.value = x == null ? null : x * widget.metresPerUnit;

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

  /// The stretch of the axis the fingers work on.
  ChartWindow get _visible => _current ?? widget.extent;

  void _setWindow(ChartWindow? window) {
    final next = _clamp(window);
    if (next == _current) return;
    _window = next;
    if (_controlled) {
      widget.onWindow!(next);
    } else {
      setState(() {});
    }
    // A cursor the window left behind waits at its nearest edge.
    final x = _cursorX;
    final shown = next ?? widget.extent;
    if (x != null && (x < shown.start || x > shown.end)) {
      _cursorX = x.clamp(shown.start, shown.end);
    }
  }

  /// The plot's x of a pixel [dx] in the chart, 0 to 1 across the plot.
  double _plotShare(double dx) =>
      _plotWidth <= 0 ? 0 : (dx - widget.leftInset) / _plotWidth;

  /// Puts the cursor on the axis under the pixel [dx] in the chart, in the
  /// window shown.
  void _moveCursorTo(double dx) {
    final shown = _visible;
    final share = _plotShare(dx).clamp(0.0, 1.0);
    _cursorX = shown.start + share * (shown.end - shown.start);
  }

  void _onPointerDown(PointerDownEvent event) {
    _fingers++;
    // A second finger is a pinch on its way, not a place to go to.
    _tapAt = _fingers == 1 ? event.localPosition : null;
  }

  void _onPointerMove(PointerMoveEvent event) {
    final at = _tapAt;
    if (at != null && (event.localPosition - at).distance > kTouchSlop) {
      _tapAt = null;
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_fingers > 0) _fingers--;
    final at = _tapAt;
    _tapAt = null;
    if (at != null && _fingers == 0) _moveCursorTo(at.dx);
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (_fingers > 0) _fingers--;
    _tapAt = null;
  }

  void _onScaleStart(ScaleStartDetails details) {
    _pinchFrom = _visible;
    _pinchFocalX = details.localFocalPoint.dx;
  }

  /// Whether one finger moving pans the window rather than sweeping.
  bool get _pans => widget.zoomable && _current != null;

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount < 2) {
      // One finger: a sweep of the cursor over the whole line, a pan of
      // the window once zoomed.
      if (_pans) {
        _pan(details.focalPointDelta.dx);
      } else if (_fingers == 1) {
        _moveCursorTo(details.localFocalPoint.dx);
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
    if (!_pans && _fingers == 1) _moveCursorTo(details.localPosition.dx);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_pans) {
      _pan(details.delta.dx);
    } else if (_fingers == 1) {
      _moveCursorTo(details.localPosition.dx);
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

  /// [global] in the plot's own pixels, the band and the insets included.
  Offset? _inPlot(Offset global) {
    final box = _stackKey.currentContext?.findRenderObject();
    return box is RenderBox && box.hasSize ? box.globalToLocal(global) : null;
  }

  /// The pixel of [x] on the axis across the chart, in the window [shown].
  double _pixelOf(double x, ChartWindow shown) {
    final width = shown.end - shown.start;
    return widget.leftInset +
        (width <= 0 ? 0 : (x - shown.start) / width) * _plotWidth;
  }

  void _onHandleDown(PointerDownEvent event) {
    final x = _cursorX;
    final at = _inPlot(event.position);
    if (x == null || at == null) return;
    _secondTap = _handleTapped?.isActive ?? false;
    _handleTapped?.cancel();
    _handleTapped = null;
    _handleDown = event.position;
    _handleMoved = false;
    // The cursor keeps its distance from the finger, so a grab off its
    // centre does not jump.
    _handleGrab = _pixelOf(x, _shown ?? widget.extent) - at.dx;
  }

  void _onHandleMove(PointerMoveEvent event) {
    final down = _handleDown;
    final at = _inPlot(event.position);
    if (down == null || at == null) return;
    if (!_handleMoved && (event.position - down).distance <= kTouchSlop) {
      // Still a tap, maybe the second of two: the cursor stays put.
      return;
    }
    _handleMoved = true;
    _moveCursorTo(at.dx + _handleGrab);
  }

  void _onHandleUp(PointerUpEvent event) {
    if (_handleDown == null) return;
    _handleDown = null;
    if (_handleMoved) return;
    if (_secondTap) {
      _secondTap = false;
      _cursorX = null;
      return;
    }
    _handleTapped = Timer(kDoubleTapTimeout, () => _handleTapped = null);
  }

  void _onHandleCancel(PointerCancelEvent event) {
    _handleDown = null;
    _secondTap = false;
  }

  /// A screen reader's step of the cursor, [direction] 1 to the right and
  /// -1 to the left.
  void _step(int direction) {
    final x = _cursorX;
    if (x != null) _cursorX = _stepped(x, direction);
  }

  /// Where a screen reader's step in [direction] takes the cursor from [x].
  double _stepped(double x, int direction) {
    final shown = _visible;
    final step = (shown.end - shown.start) * chartCursorStepShare;
    return (x + direction * step).clamp(shown.start, shown.end).toDouble();
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
    final cursor = _cursorX;
    final header = widget.header;
    final plot = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        _plotWidth = width - widget.leftInset - widget.rightInset;
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
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: RawGestureDetector(
            gestures: gestures,
            child: Padding(
              padding: const EdgeInsets.only(top: chartCursorBandHeight),
              child: widget.builder(context, window),
            ),
          ),
        );
        final shown = window ?? widget.extent;
        final slack = (shown.end - shown.start) * 1e-6;
        final px =
            cursor == null ||
                cursor < shown.start - slack ||
                cursor > shown.end + slack
            ? null
            : _pixelOf(cursor, shown);
        final label = widget.resetLabel;
        return Stack(
          key: _stackKey,
          children: [
            touchable,
            if (px != null) _line(context, px),
            if (widget.zoomable && label != null && window != null)
              Positioned(
                top: chartCursorBandHeight,
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
            if (px != null && cursor != null)
              _handle(context, px, width, cursor),
          ],
        );
      },
    );
    if (header == null) return plot;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [header(context, window, cursor), plot],
    );
  }

  /// The cursor's line, from the handle down to the foot of the plot.
  Widget _line(BuildContext context, double px) {
    const width = 1.5;
    return Positioned(
      left: px - width / 2,
      width: width,
      top: chartCursorBandHeight / 2,
      bottom: widget.bottomInset,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(color: Theme.of(context).velorki.accent),
        ),
      ),
    );
  }

  /// The handle at the pixel [px] of a chart [width] wide, on the cursor
  /// [x]: the badge at the top of the band, its target reaching down into
  /// the plot. Both are kept inside the chart, where a finger can reach
  /// them: at the very edge the badge stops short of the line, as a
  /// slider's thumb stops at the end of its track.
  Widget _handle(BuildContext context, double px, double width, double x) {
    final theme = Theme.of(context);
    final colors = theme.velorki;
    const outer = chartCursorBadgeRadius + chartCursorRimWidth;
    final centre = px.clamp(outer, math.max(outer, width - outer)).toDouble();
    final left = (centre - chartCursorTargetSize / 2)
        .clamp(0.0, math.max(0.0, width - chartCursorTargetSize))
        .toDouble();
    return Positioned(
      left: left,
      top: 0,
      width: chartCursorTargetSize,
      height: chartCursorTargetSize,
      child: Semantics(
        container: true,
        slider: true,
        label:
            widget.cursorLabel ?? AppLocalizations.of(context).chartCursorRoute,
        value: widget.cursorValue?.call(x),
        increasedValue: widget.cursorValue?.call(_stepped(x, 1)),
        decreasedValue: widget.cursorValue?.call(_stepped(x, -1)),
        onIncrease: () => _step(1),
        onDecrease: () => _step(-1),
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onHandleDown,
          onPointerMove: _onHandleMove,
          onPointerUp: _onHandleUp,
          onPointerCancel: _onHandleCancel,
          // Every touch on the handle is the handle's from the moment it
          // lands: the sheet's drag, a page's swipe and the plot's pan all
          // lose it.
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: <Type, GestureRecognizerFactory>{
              EagerGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                    EagerGestureRecognizer.new,
                    (_) {},
                  ),
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: centre - left - outer,
                  top: chartCursorBandHeight / 2 - outer,
                  width: outer * 2,
                  height: outer * 2,
                  child: DecoratedBox(
                    key: chartCursorHandleKey,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.accent,
                      border: Border.all(
                        color: colors.waypointStroke,
                        width: chartCursorRimWidth,
                        strokeAlign: BorderSide.strokeAlignInside,
                      ),
                    ),
                    child: Icon(
                      riderCursorIcon,
                      size: 16,
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

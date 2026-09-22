import 'package:flutter/material.dart';

/// How long the chrome of a tab takes to slide in.
const Duration tabChromeSlideDuration = Duration(milliseconds: 200);

/// How long a sheet takes to settle when its tab comes on screen: from where
/// the last tab's sheet was, or up from docked to its resting height.
const Duration tabSheetSettleDuration = Duration(milliseconds: 300);

/// The curve of every tab-change animation: the chrome sliding in, the
/// control column moving, the sheet settling.
const Curve tabChromeSlideCurve = Curves.easeOutCubic;

/// A value that glides from one place to another over
/// [tabChromeSlideDuration], for the map's control column: its top moves
/// between one tab's chrome and the other's.
///
/// Explicit rather than an implicit animation: a tab off screen has its
/// tickers off, so an implicit animation given its target there has already
/// finished, or snaps, by the time the tab shows. This one is started once
/// the tab is coming on screen, from where the last tab left the value, and
/// its first tick is the tab's first visible frame.
class ValueGlide {
  /// Creates a value at rest at [initial].
  ValueGlide({required TickerProvider vsync, required double initial})
    : _tween = Tween<double>(begin: initial, end: initial),
      _controller = AnimationController(
        vsync: vsync,
        duration: tabChromeSlideDuration,
        value: 1,
      ) {
    animation = _tween.animate(
      CurvedAnimation(parent: _controller, curve: tabChromeSlideCurve),
    );
  }

  final Tween<double> _tween;
  final AnimationController _controller;

  /// The value as it moves.
  late final Animation<double> animation;

  /// Where the value is heading, or is.
  double get target => _tween.end!;

  /// Whether anything has ever placed the value: before that it is only a
  /// default, and the first owner may take it without a glide.
  bool get everMoved => _everMoved;
  bool _everMoved = false;

  bool _disposed = false;

  /// Puts the value at [to] without moving.
  void jump(double to) {
    if (_disposed) return;
    _everMoved = true;
    if (_tween.begin == to && _tween.end == to && !_controller.isAnimating) {
      return;
    }
    _tween
      ..begin = to
      ..end = to;
    _controller.value = 1;
  }

  /// Moves the value to [to], from [from] or from where it is now.
  void glide({double? from, required double to}) {
    if (_disposed) return;
    _everMoved = true;
    final start = from ?? animation.value;
    if ((start - to).abs() < 0.5) {
      jump(to);
      return;
    }
    _tween
      ..begin = start
      ..end = to;
    _controller.forward(from: 0);
  }

  /// Releases the ticker; later calls do nothing.
  void dispose() {
    _disposed = true;
    _controller.dispose();
  }
}

/// Chrome at the top of a tab's map that slides in from above the screen
/// when the tab comes on screen, and slides out when it goes.
///
/// The shell keeps a departing tab painted for the length of the slide, on
/// top of the arriving tab's identical map, so the slide out is seen; once
/// the tab is offstage its ticker is muted and whatever is left of the
/// slide waits. The [child] should include the safe-area padding, so that a
/// full slide moves it clear of the status bar too.
class TabChromeSlide extends StatefulWidget {
  /// Creates the slide.
  const TabChromeSlide({required this.active, required this.child, super.key});

  /// Whether the owning tab is the one on screen.
  final bool active;

  /// The chrome.
  final Widget child;

  @override
  State<TabChromeSlide> createState() => _TabChromeSlideState();
}

class _TabChromeSlideState extends State<TabChromeSlide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: tabChromeSlideDuration,
    value: widget.active ? 1 : 0,
  );

  late final Animation<Offset> _position =
      Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero).animate(
        CurvedAnimation(
          parent: _controller,
          curve: tabChromeSlideCurve,
          reverseCurve: Curves.easeInCubic,
        ),
      );

  @override
  void didUpdateWidget(TabChromeSlide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    if (widget.active) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SlideTransition(position: _position, child: widget.child);
}

/// The opacity of a tab's sheet, or of the list inside it, around a change
/// between the Plan and Record tabs: one sheet's fades out while the
/// other's fades in, over the length of the hold, at the same time.
///
/// The shell keeps Plan painted on top for the hold with its map offstage,
/// so the two sheets are both in view: Plan's whole sheet fades over
/// Record's, whose list fades under it.
class SheetFade {
  /// Creates the fade, [visible] or not.
  SheetFade({required TickerProvider vsync, required bool visible})
    : _controller = AnimationController(
        vsync: vsync,
        duration: tabChromeSlideDuration,
        value: visible ? 1 : 0,
      );

  final AnimationController _controller;

  /// The opacity as it moves.
  Animation<double> get animation => _controller;

  /// Fades in, from wherever it is.
  void show() => _controller.forward();

  /// Fades out, from wherever it is.
  void hide() => _controller.reverse();

  /// Releases the ticker.
  void dispose() => _controller.dispose();
}

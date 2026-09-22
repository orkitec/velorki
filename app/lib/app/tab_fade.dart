import 'package:flutter/material.dart';

import '../features/shared/presentation/tab_chrome_slide.dart';

/// How long a tab takes to fade in over the one before it.
const Duration tabFadeDuration = Duration(milliseconds: 150);

/// The shell's branch container: every tab stays alive with its state, one
/// is on screen, and a change of tab is a short cross-fade rather than a
/// swap. While the fade runs both tabs are painted and ticking; before and
/// after, the tabs not on screen are offstage with their tickers off, as
/// go_router's own indexed stack keeps them.
///
/// Between the tabs in [instantBetween] there is no fade: they share their
/// picture (one map, kept in step) and animate their own chrome across.
/// Both are painted, fully, for [tabChromeSlideDuration], with [chromeTab]
/// on top whether it is going or coming, so its chrome is seen sliding out
/// over the other tab's identical map, or sliding in over it.
class TabFadeStack extends StatefulWidget {
  /// Creates the container.
  const TabFadeStack({
    required this.index,
    required this.children,
    this.instantBetween = const <int>{},
    this.chromeTab,
    super.key,
  });

  /// Tab indices that swap without a fade when the change is between two
  /// of them: tabs that share their picture and animate the rest across.
  final Set<int> instantBetween;

  /// The tab among [instantBetween] whose chrome slides; painted on top of
  /// the other for the length of the slide.
  final int? chromeTab;

  /// The tab on screen.
  final int index;

  /// The tabs, one widget each, in the bar's order.
  final List<Widget> children;

  @override
  State<TabFadeStack> createState() => _TabFadeStackState();
}

class _TabFadeStackState extends State<TabFadeStack>
    with TickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: tabFadeDuration,
    value: 1,
  );
  late final Animation<double> _in = CurvedAnimation(
    parent: _fade,
    curve: Curves.easeOut,
  );
  late final Animation<double> _out = ReverseAnimation(_in);

  /// The time both tabs of an instant swap stay painted.
  late final AnimationController _hold = AnimationController(
    vsync: this,
    duration: tabChromeSlideDuration,
    value: 1,
  );

  /// The tab going away, while one is: fading, or held painted under (or
  /// over) the arriving one for the swap.
  int? _leaving;

  /// Whether the change under way is an instant swap rather than a fade.
  bool _swap = false;

  @override
  void initState() {
    super.initState();
    _fade.addStatusListener((status) {
      if (status == AnimationStatus.completed && _leaving != null && !_swap) {
        setState(() => _leaving = null);
      }
    });
    _hold.addStatusListener((status) {
      if (status == AnimationStatus.completed && _swap) {
        setState(() {
          _leaving = null;
          _swap = false;
        });
      }
    });
  }

  @override
  void didUpdateWidget(TabFadeStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index == oldWidget.index) return;
    _leaving = oldWidget.index;
    if (widget.instantBetween.contains(widget.index) &&
        widget.instantBetween.contains(oldWidget.index)) {
      _swap = true;
      _fade.value = 1;
      _hold.forward(from: 0);
      return;
    }
    _swap = false;
    _hold.value = 1;
    _fade.forward(from: 0);
  }

  @override
  void dispose() {
    _fade.dispose();
    _hold.dispose();
    super.dispose();
  }

  Animation<double> _opacityOf(int i) {
    if (_swap) return kAlwaysCompleteAnimation;
    if (i == widget.index) return _in;
    if (i == _leaving) return _out;
    return kAlwaysCompleteAnimation;
  }

  @override
  Widget build(BuildContext context) {
    // Natural order, except that during a swap the chrome tab is painted
    // last, on top. The branches are keyed, so moving one keeps its state.
    final order = [for (var i = 0; i < widget.children.length; i++) i];
    final chrome = widget.chromeTab;
    if (_swap && chrome != null && order.remove(chrome)) order.add(chrome);
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final i in order)
          TabFadeBranch(
            key: ValueKey<int>(i),
            tab: i,
            shown: i == widget.index,
            leaving: i == _leaving,
            opacity: _opacityOf(i),
            child: widget.children[i],
          ),
      ],
    );
  }
}

/// One tab in the [TabFadeStack]: on screen, going away, or put away. The
/// same chain of widgets in every state, so a tab keeps its element and its
/// state through a change.
class TabFadeBranch extends StatelessWidget {
  /// Creates the branch wrapper.
  const TabFadeBranch({
    required this.tab,
    required this.shown,
    required this.leaving,
    required this.opacity,
    required this.child,
    super.key,
  });

  /// The tab's index in the bar.
  final int tab;

  /// Whether this is the tab on screen.
  final bool shown;

  /// Whether this is the tab going away: fading out, or held painted while
  /// the chrome slides across.
  final bool leaving;

  /// The tab's opacity: rising, falling, or one.
  final Animation<double> opacity;

  /// The tab.
  final Widget child;

  /// Whether the tab is painted at all.
  bool get offstage => !shown && !leaving;

  @override
  Widget build(BuildContext context) => Offstage(
    offstage: offstage,
    child: TickerMode(
      enabled: !offstage,
      child: ExcludeFocus(
        excluding: !shown,
        child: IgnorePointer(
          ignoring: !shown,
          child: FadeTransition(opacity: opacity, child: child),
        ),
      ),
    ),
  );
}

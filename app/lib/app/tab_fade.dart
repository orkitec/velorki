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
/// The fade is the leaving tab's alone: it is painted on top, fully there
/// at first, and fades out over the arriving tab, which is painted whole
/// underneath from the first frame. To the eye that is a cross-fade, and
/// unlike two half-transparent tabs it never lets the map show through
/// where both have a sheet in the same place.
///
/// The tabs in [chromeTabs] hold no map of their own: they are chrome over
/// the one map the shell paints under the whole stack. A change between two
/// of them takes [tabChromeSlideDuration], in step with the chrome sliding
/// and the control column gliding across.
class TabFadeStack extends StatefulWidget {
  /// Creates the container.
  const TabFadeStack({
    required this.index,
    required this.children,
    this.chromeTabs = const <int>{},
    super.key,
  });

  /// Tab indices whose screens are chrome over the shell's shared map; a
  /// change between two of them takes the chrome's own time.
  final Set<int> chromeTabs;

  /// The tab on screen.
  final int index;

  /// The tabs, one widget each, in the bar's order.
  final List<Widget> children;

  @override
  State<TabFadeStack> createState() => _TabFadeStackState();
}

class _TabFadeStackState extends State<TabFadeStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: tabFadeDuration,
    value: 1,
  );
  late final Animation<double> _out = ReverseAnimation(
    CurvedAnimation(parent: _fade, curve: Curves.easeOut),
  );

  /// The tab fading out, while one is.
  int? _leaving;

  @override
  void initState() {
    super.initState();
    _fade.addStatusListener((status) {
      if (status == AnimationStatus.completed && _leaving != null) {
        setState(() => _leaving = null);
      }
    });
  }

  @override
  void didUpdateWidget(TabFadeStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index == oldWidget.index) return;
    _leaving = oldWidget.index;
    final overMap =
        widget.chromeTabs.contains(widget.index) &&
        widget.chromeTabs.contains(oldWidget.index);
    _fade
      ..duration = overMap ? tabChromeSlideDuration : tabFadeDuration
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  Animation<double> _opacityOf(int i) =>
      i == _leaving ? _out : kAlwaysCompleteAnimation;

  @override
  Widget build(BuildContext context) {
    // Natural order, except that the tab fading out is painted last, on
    // top. The branches are keyed, so moving one keeps its state.
    final order = [for (var i = 0; i < widget.children.length; i++) i];
    final leaving = _leaving;
    if (leaving != null && order.remove(leaving)) order.add(leaving);
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

  /// Whether this is the tab fading out.
  final bool leaving;

  /// The tab's opacity: falling while it leaves, one otherwise.
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

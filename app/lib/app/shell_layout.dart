import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'shell_layout.g.dart';

/// The side of the screen the phone's bottom edge went to when it was
/// turned on its side: where the navigation rail goes in landscape, so the
/// bar the rider knows from portrait is still under the same thumb.
enum RailSide { left, right }

/// How the shell lays itself out on the screen it has.
///
/// Portrait: the floating bar at the bottom and the sheets over it.
/// Landscape (wider than tall): a rail on [side] and the panels beside it.
@immutable
class ShellLayout {
  /// Creates a layout.
  const ShellLayout({required this.sideRail, this.side = RailSide.right});

  /// The layout for a screen of [size] whose bottom edge is at [side], or
  /// [debugShellLayoutOverride] where a test set one.
  factory ShellLayout.resolve(Size size, RailSide side) =>
      debugShellLayoutOverride ??
      ShellLayout(sideRail: size.width > size.height, side: side);

  /// The portrait layout, the one every screen had before landscape.
  static const ShellLayout bottomBar = ShellLayout(sideRail: false);

  /// Whether the navigation is a rail at the side rather than a bar at the
  /// bottom.
  final bool sideRail;

  /// Where the rail is; meaningless without [sideRail].
  final RailSide side;

  /// The layout the shell handed down, or, outside a shell (a test pumping
  /// one screen), the one the screen's own size implies with the rail on
  /// the right.
  static ShellLayout of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellLayoutScope>()?.layout ??
      ShellLayout.resolve(MediaQuery.sizeOf(context), RailSide.right);

  /// Upright, the side does not count: two bottom-bar layouts are the
  /// same layout, and the screens need not rebuild for a side they do not
  /// use.
  @override
  bool operator ==(Object other) =>
      other is ShellLayout &&
      other.sideRail == sideRail &&
      (!sideRail || other.side == side);

  @override
  int get hashCode => sideRail ? Object.hash(true, side) : false.hashCode;

  @override
  String toString() =>
      sideRail ? 'ShellLayout(rail ${side.name})' : 'ShellLayout(bottom bar)';
}

/// The layout every screen gets whatever its size, for tests; `null`, the
/// default, leaves it to the screen.
///
/// The test screen is 800 by 600, wider than tall, and the widget tests were
/// written for a phone held upright: `test/flutter_test_config.dart` sets the
/// bar at the bottom for all of them, and the tests of the rail clear it.
ShellLayout? debugShellLayoutOverride;

/// Hands the shell's [ShellLayout] down to the screens.
class ShellLayoutScope extends InheritedWidget {
  /// Creates the scope.
  const ShellLayoutScope({
    required this.layout,
    required super.child,
    super.key,
  });

  /// The layout.
  final ShellLayout layout;

  @override
  bool updateShouldNotify(ShellLayoutScope oldWidget) =>
      oldWidget.layout != layout;
}

/// Asks the platform which side the phone's bottom edge is on.
///
/// A size tells portrait from landscape but not one landscape from the
/// other, and on an iPhone the safe area is the same on both sides, so the
/// platform is asked. Mirrored in `ios/Runner/AppDelegate.swift` and
/// `android/.../MainActivity.kt`: `side` answers `left`, `right` or
/// `null` (portrait, or not known), and the platform calls `sideChanged`
/// when the screen turns.
class ScreenSideChannel {
  /// Creates the channel wrapper; [channel] is only replaced by tests.
  ScreenSideChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  /// The channel's name.
  static const String channelName = 'velorki/orientation';

  final MethodChannel _channel;

  /// The side the bottom edge is on now, or `null` when the screen is
  /// upright or the platform cannot say.
  Future<RailSide?> current() async {
    try {
      return parse(await _channel.invokeMethod<String>('side'));
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Calls [onChanged] whenever the platform reports a turn.
  void listen(void Function(RailSide? side) onChanged) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sideChanged') onChanged(parse(call.arguments));
    });
  }

  /// Stops listening.
  void close() => _channel.setMethodCallHandler(null);

  /// The side a platform answer names, or `null`.
  static RailSide? parse(Object? value) => switch (value) {
    'left' => RailSide.left,
    'right' => RailSide.right,
    _ => null,
  };
}

/// The channel the rail side is read through; tests replace it.
@Riverpod(keepAlive: true)
ScreenSideChannel screenSideChannel(Ref ref) => ScreenSideChannel();

/// The side the navigation rail goes on in landscape.
///
/// Kept when the screen turns upright, so a rail that comes back comes back
/// where it was until the platform says otherwise; right before the platform
/// has said anything.
@Riverpod(keepAlive: true)
class RailSideNotifier extends _$RailSideNotifier {
  @override
  RailSide build() {
    final channel = ref.watch(screenSideChannelProvider);
    channel.listen(_take);
    ref.onDispose(channel.close);
    unawaited(refresh());
    return RailSide.right;
  }

  /// Asks the platform again: after the screen's size changed, which a turn
  /// by a quarter always does.
  Future<void> refresh() async {
    final side = await ref.read(screenSideChannelProvider).current();
    if (ref.mounted) _take(side);
  }

  void _take(RailSide? side) {
    if (side != null && side != state) state = side;
  }
}

/// Builds the shell for the [ShellLayout] of the screen it is on, hands
/// that layout down, and asks the platform for the rail's side again
/// whenever the screen turns.
class ShellLayoutHost extends ConsumerStatefulWidget {
  /// Creates the host.
  const ShellLayoutHost({required this.builder, super.key});

  /// The shell, for the layout.
  final Widget Function(BuildContext context, ShellLayout layout) builder;

  /// How far the content has faded back in since the layout last changed,
  /// 0 to 1; always 1 outside a host. The sheets fade their content with it
  /// and the shell its map controls, so a turn of the phone does not jump
  /// from one layout to the other. The sheets themselves, the bar and the
  /// rail stay in view and only move; the map is never faded, as a native
  /// view it would show black.
  static Animation<double> turnFadeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_TurnFadeScope>()?.fade ??
      kAlwaysCompleteAnimation;

  @override
  ConsumerState<ShellLayoutHost> createState() => _ShellLayoutHostState();
}

/// How long the shell's chrome takes to fade back in after a turn.
const Duration shellTurnFadeDuration = Duration(milliseconds: 260);

class _ShellLayoutHostState extends ConsumerState<ShellLayoutHost>
    with SingleTickerProviderStateMixin {
  Orientation? _orientation;
  ShellLayout? _layout;

  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: shellTurnFadeDuration,
    value: 1,
  );
  late final Animation<double> _fadeCurve = CurvedAnimation(
    parent: _fade,
    curve: Curves.easeOut,
  );

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final orientation = size.width > size.height
        ? Orientation.landscape
        : Orientation.portrait;
    if (_orientation != null && orientation != _orientation) {
      // After the frame: a build may not change a provider.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(ref.read(railSideProvider.notifier).refresh());
      });
    }
    _orientation = orientation;
    final layout = ShellLayout.resolve(size, ref.watch(railSideProvider));
    final before = _layout;
    if (before != null && before != layout && !_fade.isAnimating) {
      // The new layout's content comes in faded and fades up. Once: the
      // platform's word on the rail's side often comes a moment after the
      // turn and changes the layout again, which must not start it over.
      // Only listeners that repaint hang on the animation, so starting it
      // here is safe.
      _fade.forward(from: 0);
    }
    _layout = layout;
    return ShellLayoutScope(
      layout: layout,
      child: _TurnFadeScope(
        fade: _fadeCurve,
        child: Builder(builder: (context) => widget.builder(context, layout)),
      ),
    );
  }
}

/// Hands the host's turn fade down.
class _TurnFadeScope extends InheritedWidget {
  const _TurnFadeScope({required this.fade, required super.child});

  final Animation<double> fade;

  @override
  bool updateShouldNotify(_TurnFadeScope oldWidget) => oldWidget.fade != fade;
}

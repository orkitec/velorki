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

/// The three ways the shell can lay itself out; see [ShellLayout].
enum ShellMode {
  /// The floating bar at the bottom and the sheets over it.
  bottomBar,

  /// A phone turned sideways: the rail on the side and the sheets turned
  /// with it.
  sideRail,

  /// A tablet-class window: everything laid out as on a phone held upright,
  /// in a column on the left, the map beside it.
  widePanel,
}

/// Where the column of a wide window stands: the tabs, their bar, sheets
/// and pages, the map filling the rest. The rider picks the left or the
/// right side; the middle stays possible in code.
enum WideColumnSide {
  /// Along the window's left edge.
  left,

  /// In the middle, the map either side.
  centre,

  /// Along the window's right edge.
  right;

  /// The side named [name], or [left] when the name is unknown.
  static WideColumnSide fromName(String? name) => WideColumnSide.values
      .firstWhere((s) => s.name == name, orElse: () => left);
}

/// The least shortest side of a window, in logical pixels, that gets the
/// wide layout; no phone's screen has it.
const double wideWindowShortestSide = 600;

/// The least width of a window that gets the wide layout: narrower, a
/// column beside the map would leave the map too little. A foldable's inner
/// screen upright and half of an iPad's are just wider.
const double wideWindowMinWidth = 600;

/// Whether a window of [size] gets the wide layout.
bool isWideWindow(Size size) =>
    size.shortestSide >= wideWindowShortestSide &&
    size.width >= wideWindowMinWidth;

/// How the shell lays itself out on the window it has.
///
/// Decided by the window, not the device: an iPad's window in a third of the
/// screen gets the upright phone layout, a foldable's inner screen the wide
/// one.
///
/// Upright: the floating bar at the bottom and the sheets over it.
/// A phone turned sideways (wider than tall): a rail on [side] and the
/// panels beside it.
/// A tablet-class window ([isWideWindow]): the tabs, their bar, sheets and
/// pages as on a phone held upright, in a column on the left over the map.
@immutable
class ShellLayout {
  /// Creates a layout: the rail's when [sideRail], else the bar's.
  const ShellLayout({required bool sideRail, this.side = RailSide.right})
    : mode = sideRail ? ShellMode.sideRail : ShellMode.bottomBar;

  const ShellLayout._wide() : mode = ShellMode.widePanel, side = RailSide.right;

  /// The layout for a window of [size] whose bottom edge is at [side], or
  /// [debugShellLayoutOverride] where a test set one.
  ///
  /// Decided by the window alone, never by the device: the rail is for a
  /// window shaped like a phone on its side (wider than tall, its shortest
  /// side a phone's), whatever it runs on, and a wide window never gets it.
  factory ShellLayout.resolve(Size size, RailSide side) {
    final override = debugShellLayoutOverride;
    if (override != null) return override;
    if (isWideWindow(size)) return wide;
    return ShellLayout(
      sideRail:
          size.width > size.height &&
          size.shortestSide < wideWindowShortestSide,
      side: side,
    );
  }

  /// The portrait layout, the one every screen had before landscape.
  static const ShellLayout bottomBar = ShellLayout(sideRail: false);

  /// The layout of a tablet-class window.
  static const ShellLayout wide = ShellLayout._wide();

  /// Which of the three layouts this is.
  final ShellMode mode;

  /// Whether the navigation is a rail at the side rather than a bar at the
  /// bottom: a phone turned sideways.
  bool get sideRail => mode == ShellMode.sideRail;

  /// Whether the app is in a column on the left of a wide window.
  bool get widePanel => mode == ShellMode.widePanel;

  /// Where the rail is; meaningless without [sideRail].
  final RailSide side;

  /// The layout the window at [context] implies, its rail at [side].
  static ShellLayout resolveAt(BuildContext context, RailSide side) =>
      ShellLayout.resolve(MediaQuery.sizeOf(context), side);

  /// The layout the shell handed down, or, outside a shell (a test pumping
  /// one screen), the one the screen's own size implies with the rail on
  /// the right.
  static ShellLayout of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellLayoutScope>()?.layout ??
      resolveAt(context, RailSide.right);

  /// Without the rail, the side does not count: two bottom-bar layouts are
  /// the same layout, and the screens need not rebuild for a side they do
  /// not use.
  @override
  bool operator ==(Object other) =>
      other is ShellLayout &&
      other.mode == mode &&
      (!sideRail || other.side == side);

  @override
  int get hashCode => sideRail ? Object.hash(mode, side) : mode.hashCode;

  @override
  String toString() => switch (mode) {
    ShellMode.sideRail => 'ShellLayout(rail ${side.name})',
    ShellMode.bottomBar => 'ShellLayout(bottom bar)',
    ShellMode.widePanel => 'ShellLayout(wide panel)',
  };
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

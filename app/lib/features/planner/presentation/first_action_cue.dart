import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'first_action_cue.g.dart';

/// Whether the empty Plan tab draws the eye to its two ways in. Off where
/// pictures are taken of the app, which must never catch it mid-way.
@Riverpod(keepAlive: true)
bool firstActionCueEnabled(Ref ref) => true;

// One after the other, with a breath between, so each is seen, and each
// in the same accent outline so they read as one hint: the headline, then
// the search field, then the not-downloaded chip when there is one, then
// the map. Times from the start of the cue.

/// The headline's pulse, once the sheet has settled.
const Duration _headlinePulseStart = Duration(milliseconds: 600);

/// One pulse of outline: the headline's, the search field's, the chip's.
const Duration _pulseDuration = Duration(milliseconds: 900);

/// The search field's pulse, after the headline's.
const Duration _pulseStart = Duration(milliseconds: 1700);

/// The chip's pulse, after the field's.
const Duration _chipPulseStart = Duration(milliseconds: 2800);

/// The ring's spread from the middle of the map, after the chip's pulse,
/// or after the field's where there is no chip.
const Duration _ringStartWithChip = Duration(milliseconds: 3900);
const Duration _ringStartWithoutChip = Duration(milliseconds: 2800);
const Duration _ringDuration = Duration(milliseconds: 1100);

/// How far the ring spreads.
const double _ringRadius = 90;

/// The pulse around the headline, while it is drawn.
@visibleForTesting
const Key firstActionCueHeadlinePulseKey = ValueKey<String>(
  'firstActionCueHeadlinePulse',
);

/// The pulse around the search field, while it is drawn.
@visibleForTesting
const Key firstActionCuePulseKey = ValueKey<String>('firstActionCuePulse');

/// The pulse around the not-downloaded chip, while it is drawn.
@visibleForTesting
const Key firstActionCueChipPulseKey = ValueKey<String>(
  'firstActionCueChipPulse',
);

/// The ring over the map, while it is drawn.
@visibleForTesting
const Key firstActionCueRingKey = ValueKey<String>('firstActionCueRing');

/// The empty Plan tab's one short hint at how to start, one part after the
/// other: after a moment the headline's outline pulses, then the search
/// field's, then the not-downloaded chip's if one is shown, then a ring
/// spreads once from the middle of the map. Stopped at once by the rider's
/// first touch anywhere; the parts listen to [progress]. A run that ends by
/// itself can ask to be played again once nothing has touched the screen
/// for [idleAgainAfter]. A chip that comes only after the run has started
/// is taken in or given a pulse of its own ([chipAppeared]).
class FirstActionCue {
  /// Creates the cue, at rest.
  FirstActionCue({required TickerProvider vsync})
    : _controller = AnimationController(
        vsync: vsync,
        duration: _durationFor(withChip: false),
        value: 1,
      ) {
    _controller.addStatusListener((status) {
      if (status != AnimationStatus.forward) _end(status);
    });
  }

  /// How long nothing must touch the screen after a run that ended by
  /// itself before its `again` is called.
  static const Duration idleAgainAfter = Duration(seconds: 15);

  static Duration _durationFor({required bool withChip}) =>
      (withChip ? _ringStartWithChip : _ringStartWithoutChip) + _ringDuration;

  final AnimationController _controller;

  /// Through the whole cue, 0 to 1; 1 at rest.
  Animation<double> get progress => _controller;

  /// Whether the cue is running.
  ValueListenable<bool> get running => _running;
  final ValueNotifier<bool> _running = ValueNotifier<bool>(false);

  /// Whether this run pulses the not-downloaded chip too.
  bool _withChip = false;

  /// Whether this run is the chip's pulse alone ([chipAppeared]).
  bool _chipOnly = false;

  /// Whether the chip's own pulse follows this run when it ends by itself.
  bool _chipAfter = false;

  /// The whole of this run.
  Duration get _total => _controller.duration!;

  /// Called once the screen has been left alone for [idleAgainAfter] after
  /// this run ended by itself.
  VoidCallback? _again;
  Timer? _idle;

  bool _listening = false;

  /// Runs the cue from its start, the chip's pulse in it if [withChip]. If
  /// it ends by itself and nothing touches the screen for [idleAgainAfter]
  /// after, [again] is called, once.
  void play({bool withChip = false, VoidCallback? again}) {
    _run(chipOnly: false, withChip: withChip, again: again);
  }

  /// Tells the cue the not-downloaded chip has just come, after the run
  /// started without it. A run that has not yet reached where the chip's
  /// step would be takes it in, the ring after it as in a run started with
  /// the chip; one further on is followed by the chip's pulse alone, as long
  /// as its step, once it ends by itself; and a cue waiting to play again
  /// plays the chip's pulse at once, the wait starting over after it.
  /// Anything else (a run that has the chip, a cue stopped or done) is left
  /// as it is. Whether the chip is going to pulse.
  bool chipAppeared() {
    if (_chipOnly && _running.value) return false;
    if (_running.value) {
      if (_withChip || _chipAfter) return false;
      final elapsed = _total * _controller.value;
      if (elapsed < _chipPulseStart) {
        _withChip = true;
        final total = _durationFor(withChip: true);
        _controller.duration = total;
        // Where it was, in the longer run. Never back to 0, which would
        // end the run: still at its start, it simply runs on from there.
        final from = elapsed.inMicroseconds / total.inMicroseconds;
        if (from > 0) {
          _controller.forward(from: from);
        } else {
          _controller.forward();
        }
      } else {
        _chipAfter = true;
      }
      return true;
    }
    if (_idle == null) return false;
    _run(chipOnly: true, withChip: true, again: _again);
    return true;
  }

  void _run({
    required bool chipOnly,
    required bool withChip,
    VoidCallback? again,
  }) {
    _idle?.cancel();
    _idle = null;
    _again = null;
    _chipAfter = false;
    _chipOnly = chipOnly;
    _withChip = withChip;
    _controller.duration = chipOnly
        ? _pulseDuration
        : _durationFor(withChip: withChip);
    // First, while the jump back to the start may still end a run.
    _controller.forward(from: 0);
    _again = again;
    _running.value = true;
    _listen();
  }

  /// Ends the cue where it is, the rest gone, and anything waiting to play
  /// it again.
  void stop() {
    _again = null;
    _chipAfter = false;
    _idle?.cancel();
    _idle = null;
    if (_running.value) {
      _controller.value = 1;
    } else {
      _unlisten();
    }
  }

  void _onPointer(PointerEvent event) {
    if (event is PointerDownEvent || event is PointerSignalEvent) stop();
  }

  void _end(AnimationStatus status) {
    _running.value = false;
    final again = _again;
    if (status == AnimationStatus.completed && _chipAfter) {
      // Ended by itself, and the chip came during it: its pulse now, the
      // wait to play again after that.
      _run(chipOnly: true, withChip: true, again: again);
    } else if (status == AnimationStatus.completed && again != null) {
      // Ended by itself: still listening, a touch while it waits stops it.
      _idle = Timer(idleAgainAfter, () {
        _idle = null;
        _again = null;
        _unlisten();
        again();
      });
    } else {
      _again = null;
      _unlisten();
    }
  }

  void _listen() {
    if (_listening) return;
    _listening = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }

  void _unlisten() {
    if (!_listening) return;
    _listening = false;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
  }

  /// Lets go of the ticker, the pointer and the wait.
  void dispose() {
    _again = null;
    _chipAfter = false;
    _idle?.cancel();
    _idle = null;
    _unlisten();
    _controller.dispose();
    _running.dispose();
  }

  /// How far through the part that runs [length] from [start] the cue is
  /// at [t], 0..1 of the whole, or `null` outside it.
  double? _phase(double t, Duration start, Duration length) {
    final local =
        (t * _total.inMicroseconds - start.inMicroseconds) /
        length.inMicroseconds;
    return local < 0 || local >= 1 ? null : local;
  }

  /// How far through its pulse the headline is at [t], or `null` outside
  /// it.
  double? headlinePulseAt(double t) =>
      _chipOnly ? null : _phase(t, _headlinePulseStart, _pulseDuration);

  /// How far through its pulse the field is at [t], or `null` outside it.
  double? pulseAt(double t) =>
      _chipOnly ? null : _phase(t, _pulseStart, _pulseDuration);

  /// How far through its pulse the chip is at [t], or `null` outside it
  /// and in a run without the chip. The chip's pulse alone is the whole
  /// run.
  double? chipPulseAt(double t) => !_withChip
      ? null
      : _phase(t, _chipOnly ? Duration.zero : _chipPulseStart, _pulseDuration);

  /// How far through its spread the ring is at [t], or `null` outside it.
  double? ringAt(double t) => _chipOnly
      ? null
      : _phase(
          t,
          _withChip ? _ringStartWithChip : _ringStartWithoutChip,
          _ringDuration,
        );

  /// The cue handed down from [FirstActionCueScope], if any.
  static FirstActionCue? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<FirstActionCueScope>()?.cue;
}

/// Hands [cue] down to the parts that show it.
class FirstActionCueScope extends InheritedWidget {
  /// Creates the scope.
  const FirstActionCueScope({
    required this.cue,
    required super.child,
    super.key,
  });

  /// The cue.
  final FirstActionCue cue;

  @override
  bool updateShouldNotify(FirstActionCueScope oldWidget) =>
      cue != oldWidget.cue;
}

/// [child], the empty sheet's headline, with the cue's first pulse of
/// outline around it.
class FirstActionCueHeadline extends StatelessWidget {
  /// Creates the pulse around the headline.
  const FirstActionCueHeadline({required this.child, super.key});

  /// The headline and its detail.
  final Widget child;

  @override
  Widget build(BuildContext context) => _CuePulse(
    pulseKey: firstActionCueHeadlinePulseKey,
    phaseOf: (cue) => cue.headlinePulseAt,
    pad: 8,
    radius: 16,
    child: child,
  );
}

/// [child], the search field, with the cue's pulse of outline around it.
class FirstActionCuePulse extends StatelessWidget {
  /// Creates the pulse around [child].
  const FirstActionCuePulse({required this.child, super.key});

  /// The search field.
  final Widget child;

  @override
  Widget build(BuildContext context) => _CuePulse(
    pulseKey: firstActionCuePulseKey,
    phaseOf: (cue) => cue.pulseAt,
    child: child,
  );
}

/// [child], the not-downloaded chip over the map, with the cue's pulse of
/// outline around it in a run that has the chip.
class FirstActionCueChipPulse extends StatelessWidget {
  /// Creates the pulse around [child].
  const FirstActionCueChipPulse({required this.child, super.key});

  /// The chip.
  final Widget child;

  @override
  Widget build(BuildContext context) => _CuePulse(
    pulseKey: firstActionCueChipPulseKey,
    phaseOf: (cue) => cue.chipPulseAt,
    pad: 4,
    // The chip's glass panel's.
    radius: 22,
    child: child,
  );
}

/// [child] with a pulse of outline painted around it in its turn of the
/// cue: over it and beyond its edge, taking no room and no touch. With
/// animations off it is simply [child].
class _CuePulse extends StatelessWidget {
  const _CuePulse({
    required this.pulseKey,
    required this.phaseOf,
    required this.child,
    this.pad = 0,
    this.radius,
  });

  final Key pulseKey;

  /// Which of the cue's parts this is.
  final double? Function(double t) Function(FirstActionCue cue) phaseOf;

  final double pad;
  final double? radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cue = FirstActionCue.maybeOf(context);
    if (cue == null || MediaQuery.disableAnimationsOf(context)) return child;
    final colour = Theme.of(context).colorScheme.primary;
    final phaseAt = phaseOf(cue);
    return AnimatedBuilder(
      // Rebuilt as the cue runs, so the pulse is there only in its turn.
      animation: Listenable.merge(<Listenable>[cue.running, cue.progress]),
      builder: (context, child) => Stack(
        // The child's own size and constraints, whatever the pulse paints.
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        children: [
          child!,
          if (cue.running.value && phaseAt(cue.progress.value) != null)
            Positioned.fill(
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: CustomPaint(
                    key: pulseKey,
                    painter: _PulsePainter(
                      cue.progress,
                      colour,
                      phaseAt,
                      pad: pad,
                      radius: radius,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      child: child,
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter(
    this.progress,
    this.colour,
    this.phaseAt, {
    this.pad = 0,
    this.radius,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final Color colour;

  /// Where in its pulse the outline is at the cue's progress.
  final double? Function(double t) phaseAt;

  /// How far outside the child the outline runs.
  final double pad;

  /// The outline's corner radius; a pill's when `null`.
  final double? radius;

  @override
  void paint(Canvas canvas, Size size) {
    final phase = phaseAt(progress.value);
    if (phase == null) return;
    // One pulse, up and down again, growing a little outwards.
    final strength = math.sin(math.pi * phase);
    final spread = pad + 1 + 3 * phase;
    final rect = (Offset.zero & size).inflate(spread);
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular((radius ?? math.min(28, size.height / 2)) + spread),
    );
    canvas
      ..drawRRect(
        rrect.inflate(2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..color = colour.withValues(alpha: 0.18 * strength),
      )
      ..drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = colour.withValues(alpha: 0.85 * strength),
      );
  }

  @override
  bool shouldRepaint(_PulsePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.phaseAt != phaseAt ||
      oldDelegate.colour != colour ||
      oldDelegate.pad != pad ||
      oldDelegate.radius != radius;
}

/// The cue's ring over the map, spreading once from [centre] (in the
/// window, where it is drawn) as a tap's ripple would. Painted on the
/// app's top overlay, so in a wide window it reaches the map beside the
/// column; it takes no touch and says nothing to a screen reader. Lays out
/// as nothing where it is placed.
class FirstActionCueRing extends StatefulWidget {
  /// Creates the ring.
  const FirstActionCueRing({required this.centre, super.key});

  /// The middle of the visible map in the window, asked as the ring
  /// starts.
  final Offset Function() centre;

  @override
  State<FirstActionCueRing> createState() => _FirstActionCueRingState();
}

class _FirstActionCueRingState extends State<FirstActionCueRing> {
  final OverlayPortalController _portal = OverlayPortalController()..show();

  @override
  Widget build(BuildContext context) {
    final cue = FirstActionCue.maybeOf(context);
    if (cue == null) return const SizedBox.shrink();
    final colour = Theme.of(context).colorScheme.primary;
    final still = MediaQuery.disableAnimationsOf(context);
    return OverlayPortal(
      overlayLocation: OverlayChildLocation.rootOverlay,
      controller: _portal,
      overlayChildBuilder: (context) => AnimatedBuilder(
        // Rebuilt as the cue runs, so the ring is there only in its turn.
        animation: Listenable.merge(<Listenable>[cue.running, cue.progress]),
        builder: (context, _) =>
            !cue.running.value ||
                still ||
                cue.ringAt(cue.progress.value) == null
            ? const SizedBox.shrink()
            : IgnorePointer(
                child: ExcludeSemantics(
                  child: SizedBox.expand(
                    child: CustomPaint(
                      key: firstActionCueRingKey,
                      painter: FirstActionCueRingPainter(
                        cue,
                        widget.centre(),
                        colour,
                      ),
                    ),
                  ),
                ),
              ),
      ),
      child: const SizedBox.shrink(),
    );
  }
}

/// Paints the cue's ring.
class FirstActionCueRingPainter extends CustomPainter {
  /// Creates the painter.
  FirstActionCueRingPainter(this.cue, this.centre, this.colour)
    : super(repaint: cue.progress);

  /// The cue, whose run says when the ring spreads.
  final FirstActionCue cue;

  /// Where the ring spreads from, in the overlay, which is the window.
  final Offset centre;

  /// The ring's colour.
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final ring = cue.ringAt(cue.progress.value);
    if (ring == null) return;
    final radius = _ringRadius * Curves.easeOut.transform(ring);
    final fade = 1 - ring;
    canvas
      ..drawCircle(
        centre,
        radius,
        Paint()..color = colour.withValues(alpha: 0.12 * fade),
      )
      ..drawCircle(
        centre,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = colour.withValues(alpha: 0.6 * fade),
      );
  }

  @override
  bool shouldRepaint(FirstActionCueRingPainter oldDelegate) =>
      oldDelegate.cue != cue ||
      oldDelegate.centre != centre ||
      oldDelegate.colour != colour;
}

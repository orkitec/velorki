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

// One after the other, with a breath between, so each is seen: the
// headline, then the search field, then the map. Times from the start of
// the cue.

/// Before anything moves: the sheet has just settled.
const Duration _revealStart = Duration(milliseconds: 600);

/// The headline's fade and rise.
const Duration _revealDuration = Duration(milliseconds: 700);

/// The search field's two pulses, after the headline.
const Duration _pulseStart = Duration(milliseconds: 1600);
const Duration _pulseDuration = Duration(milliseconds: 1400);

/// The ring's spread from the middle of the map, after the pulses.
const Duration _ringStart = Duration(milliseconds: 3200);
const Duration _ringDuration = Duration(milliseconds: 1100);

/// The whole cue.
const Duration _cueDuration = Duration(milliseconds: 4300);

/// How far below its place the headline starts.
const double _revealRise = 16;

/// How far the ring spreads.
const double _ringRadius = 90;

/// The pulse around the search field, while it is drawn.
@visibleForTesting
const Key firstActionCuePulseKey = ValueKey<String>('firstActionCuePulse');

/// The ring over the map, while it is drawn.
@visibleForTesting
const Key firstActionCueRingKey = ValueKey<String>('firstActionCueRing');

/// The empty Plan tab's one short hint at how to start, one part after the
/// other: after a moment the headline fades in, then the search field
/// pulses twice, then a ring spreads once from the middle of the map. One run, stopped at once by the rider's first
/// touch anywhere; the parts listen to [progress].
class FirstActionCue {
  /// Creates the cue, at rest.
  FirstActionCue({required TickerProvider vsync})
    : _controller = AnimationController(
        vsync: vsync,
        duration: _cueDuration,
        value: 1,
      ) {
    _controller.addStatusListener((status) {
      if (status != AnimationStatus.forward) _end();
    });
  }

  final AnimationController _controller;

  /// Through the whole cue, 0 to 1; 1 at rest.
  Animation<double> get progress => _controller;

  /// Whether the cue is running.
  ValueListenable<bool> get running => _running;
  final ValueNotifier<bool> _running = ValueNotifier<bool>(false);

  bool _listening = false;

  /// Runs the cue from its start.
  void play() {
    // First, while the jump back to the start may still end a run.
    _controller.forward(from: 0);
    _running.value = true;
    if (!_listening) {
      _listening = true;
      GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    }
  }

  /// Ends the cue where it is: the headline shown, the rest gone.
  void stop() {
    if (_running.value) _controller.value = 1;
  }

  void _onPointer(PointerEvent event) {
    if (event is PointerDownEvent || event is PointerSignalEvent) stop();
  }

  void _end() {
    _running.value = false;
    if (_listening) {
      _listening = false;
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    }
  }

  /// Lets go of the ticker and the pointer.
  void dispose() {
    _end();
    _controller.dispose();
    _running.dispose();
  }

  /// How far through the part that runs [length] from [start] the cue is
  /// at [t], 0..1 of the whole: below 0 before it, 1 or more after it.
  static double _local(double t, Duration start, Duration length) =>
      (t * _cueDuration.inMicroseconds - start.inMicroseconds) /
      length.inMicroseconds;

  /// The headline's share of its way in at [t], eased.
  static double revealAt(double t) => Curves.easeOut.transform(
    _local(t, _revealStart, _revealDuration).clamp(0.0, 1.0),
  );

  /// How far through its two pulses the field is at [t], or `null` outside
  /// them.
  static double? pulseAt(double t) {
    final local = _local(t, _pulseStart, _pulseDuration);
    return local < 0 || local >= 1 ? null : local;
  }

  /// How far through its spread the ring is at [t], or `null` outside it.
  static double? ringAt(double t) {
    final local = _local(t, _ringStart, _ringDuration);
    return local < 0 || local >= 1 ? null : local;
  }

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

/// [child], the empty sheet's headline, fading in and rising into place as
/// the cue starts. With animations off it is simply there.
class FirstActionCueReveal extends StatelessWidget {
  /// Creates the reveal.
  const FirstActionCueReveal({required this.child, super.key});

  /// The headline and its detail.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cue = FirstActionCue.maybeOf(context);
    if (cue == null || MediaQuery.disableAnimationsOf(context)) return child;
    return AnimatedBuilder(
      animation: cue.progress,
      builder: (context, child) {
        final shown = FirstActionCue.revealAt(cue.progress.value);
        return Opacity(
          opacity: shown,
          // Read out from the start, faded or not.
          alwaysIncludeSemantics: true,
          child: Transform.translate(
            offset: Offset(0, (1 - shown) * _revealRise),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// [child], the search field, with the cue's two pulses of outline painted
/// around it: over it and beyond its edge, taking no room and no touch.
class FirstActionCuePulse extends StatelessWidget {
  /// Creates the pulse around [child].
  const FirstActionCuePulse({required this.child, super.key});

  /// The search field.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cue = FirstActionCue.maybeOf(context);
    if (cue == null) return child;
    final colour = Theme.of(context).colorScheme.primary;
    final still = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      // Rebuilt as the cue runs, so the pulse is there only in its turn.
      animation: Listenable.merge(<Listenable>[cue.running, cue.progress]),
      builder: (context, child) => Stack(
        // The field's own size and constraints, whatever the pulse paints.
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        children: [
          child!,
          if (cue.running.value &&
              !still &&
              FirstActionCue.pulseAt(cue.progress.value) != null)
            Positioned.fill(
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: CustomPaint(
                    key: firstActionCuePulseKey,
                    painter: _PulsePainter(cue.progress, colour),
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
  _PulsePainter(this.progress, this.colour) : super(repaint: progress);

  final Animation<double> progress;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final pulse = FirstActionCue.pulseAt(progress.value);
    if (pulse == null) return;
    // Two pulses, each up and down again, growing a little outwards.
    final phase = (pulse * 2) % 1;
    final strength = math.sin(math.pi * phase);
    final spread = 1 + 3 * phase;
    final rect = (Offset.zero & size).inflate(spread);
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(math.min(28, size.height / 2) + spread),
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
      oldDelegate.progress != progress || oldDelegate.colour != colour;
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
                FirstActionCue.ringAt(cue.progress.value) == null
            ? const SizedBox.shrink()
            : IgnorePointer(
                child: ExcludeSemantics(
                  child: SizedBox.expand(
                    child: CustomPaint(
                      key: firstActionCueRingKey,
                      painter: FirstActionCueRingPainter(
                        cue.progress,
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
  FirstActionCueRingPainter(this.progress, this.centre, this.colour)
    : super(repaint: progress);

  /// The cue's progress.
  final Animation<double> progress;

  /// Where the ring spreads from, in the overlay, which is the window.
  final Offset centre;

  /// The ring's colour.
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final ring = FirstActionCue.ringAt(progress.value);
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
      oldDelegate.progress != progress ||
      oldDelegate.centre != centre ||
      oldDelegate.colour != colour;
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme.dart';

/// The AI's sparkle, painted in [VelorkiColors.aiGradient]: on the buttons
/// that ask the AI and beside what it answered, so its work reads as its
/// own whatever accent the rider picked.
class AiSparkle extends StatelessWidget {
  /// Creates the sparkle.
  const AiSparkle({
    super.key,
    this.icon = Icons.auto_awesome_rounded,
    this.size,
    this.disabledColor,
  });

  /// The icon: the sparkle unless a button has its own.
  final IconData icon;

  /// The icon's size; the surrounding [IconTheme]'s when `null`.
  final double? size;

  /// When set, the sparkle is drawn flat in this colour instead: a disabled
  /// button's, which must not look as if it could be pressed.
  final Color? disabledColor;

  @override
  Widget build(BuildContext context) {
    final disabled = disabledColor;
    if (disabled != null) return Icon(icon, size: size, color: disabled);
    final gradient = Theme.of(context).velorki.aiGradient;
    return ShaderMask(
      // Diagonal across the icon, so both ends show in its small square.
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: gradient.colors,
      ).createShader(bounds),
      blendMode: BlendMode.srcIn,
      child: Icon(icon, size: size, color: Colors.white),
    );
  }
}

/// The AI card's edge: a line in [gradient] up one side of a card whose top
/// corners are rounded by [radius], round those corners, along the top and
/// down the other side. In the card's own frame, so a card turned sideways
/// has it along its turned edges.
class AiEdgePainter extends CustomPainter {
  /// Creates the painter.
  const AiEdgePainter({
    required this.gradient,
    required this.radius,
    this.width = 2,
  });

  /// The line's colours, across the card.
  final LinearGradient gradient;

  /// The card's top corner radius.
  final double radius;

  /// The line's width.
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    // Half the line in, so all of it lies inside the card's clip.
    final inset = width / 2;
    final radius = math.min(this.radius, size.height);
    final r = radius - inset;
    final path = Path()
      ..moveTo(inset, size.height)
      ..lineTo(inset, radius)
      ..arcToPoint(Offset(radius, inset), radius: Radius.circular(r))
      ..lineTo(size.width - radius, inset)
      ..arcToPoint(
        Offset(size.width - inset, radius),
        radius: Radius.circular(r),
      )
      ..lineTo(size.width - inset, size.height);
    canvas.drawPath(
      path,
      Paint()
        ..shader = gradient.createShader(Offset.zero & size)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(AiEdgePainter old) =>
      old.gradient != gradient || old.radius != radius || old.width != width;
}

/// What the AI wrote, marked as its own: [child] beside the AI's sparkle.
class AiAnswer extends StatelessWidget {
  /// Creates the marked answer.
  const AiAnswer({required this.child, super.key});

  /// The answer.
  final Widget child;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // On the first line's middle, at the reading size.
      const Padding(
        padding: EdgeInsets.only(top: 2),
        child: AiSparkle(size: 20),
      ),
      const SizedBox(width: 10),
      Expanded(child: child),
    ],
  );
}

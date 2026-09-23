import 'package:flutter/material.dart';

/// Empty-state body used by the tabs whose feature lands in a later milestone.
class PlaceholderBody extends StatelessWidget {
  /// Creates the body.
  const PlaceholderBody({required this.icon, required this.message, super.key});

  /// The icon inside the circle.
  final IconData icon;

  /// The line under the circle.
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // A scroll view rather than a bare column: a docked card leaves a few
    // pixels of height, and a column that does not fit them would throw an
    // overflow every frame, where a scroll view simply shows what it can.
    // At any ordinary height nothing scrolls and the look is the same.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 32, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

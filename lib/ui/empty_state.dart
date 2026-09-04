import 'package:flutter/material.dart';

/// A "nothing here yet" placeholder — an icon, a short message, and an
/// optional action. Replaces the ad-hoc `Center(child: Text(...))` blocks and
/// the old per-screen `_Empty` locals.
class EmptyState extends StatelessWidget {
  const EmptyState(
    this.text, {
    super.key,
    this.icon,
    this.action,
    this.padding = const EdgeInsets.symmetric(vertical: 24),
  });

  final String text;
  final IconData? icon;
  final Widget? action;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 32, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 8),
          ],
          Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (action != null) ...[
            const SizedBox(height: 12),
            action!,
          ],
        ],
      ),
    );
  }
}

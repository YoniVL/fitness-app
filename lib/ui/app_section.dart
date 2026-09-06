import 'package:flutter/material.dart';

import '../app/theme.dart';

/// A card-wrapped section with a heading — the standard way to group related
/// content on a screen (Voortgang, Instellingen, …). Modernist: a chamfered
/// surface, an optional all-caps accent kicker, an Archivo-800 title, and a
/// 2px rule under the header.
class AppSection extends StatelessWidget {
  const AppSection({
    super.key,
    required this.title,
    required this.child,
    this.kicker,
    this.trailing,
  });

  final String title;
  final Widget child;

  /// A short all-caps label above the title (e.g. "VANDAAG · KRACHT").
  final String? kicker;

  /// Optional widget at the end of the heading row (e.g. a "bekijk alles"-link).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (kicker != null) ...[
                  Text(kicker!.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: p.accent, letterSpacing: 1.4)),
                  const SizedBox(height: 6),
                ],
                Row(
                  children: [
                    Expanded(
                      child: Text(title,
                          style: theme.textTheme.titleLarge),
                    ),
                    ?trailing,
                  ],
                ),
              ],
            ),
          ),
          Container(height: 2, color: p.rule),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// A plain (non-card) heading above a group of list tiles or a section of a
/// scrolling screen — e.g. Instellingen's "Mijn materiaal", "Rusttijden".
/// Modernist: small, all-caps, wide tracking, muted.
class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader(this.text, {super.key, this.padding});
  final String text;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding ?? const EdgeInsets.fromLTRB(16, 22, 16, 8),
        child: Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
              ),
        ),
      );
}

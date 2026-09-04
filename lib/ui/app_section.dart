import 'package:flutter/material.dart';

/// A card-wrapped section with a heading — the standard way to group related
/// content on a screen (Voortgang, Instellingen, …).
class AppSection extends StatelessWidget {
  const AppSection({super.key, required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;

  /// Optional widget at the end of the heading row (e.g. a "bekijk alles"-link).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title, style: Theme.of(context).textTheme.titleMedium),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// A plain (non-card) heading above a group of list tiles or a section of a
/// scrolling screen — e.g. Instellingen's "Mijn materiaal", "Rusttijden".
class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader(this.text, {super.key, this.padding});
  final String text;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding ?? const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}

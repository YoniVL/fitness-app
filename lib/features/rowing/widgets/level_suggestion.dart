import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/settings_repository.dart';
import '../../../domain/models/program.dart';
import '../../../domain/rowing_ftp.dart';

/// If the FTP-implied level differs from the stored one, ask whether to switch.
Future<void> maybePromptLevelFromFtp(
    BuildContext context, WidgetRef ref, double ftpWatts) async {
  final suggested = suggestedLevelFromFtp(ftpWatts);
  final current =
      ref.read(rowingLevelProvider).valueOrNull ?? ProgramLevel.medium;
  if (suggested == current) return;

  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Trainingsniveau'),
      content: Text(
        'Op basis van je FTP past niveau "${suggested.label}" beter '
        '(nu "${current.label}").\n\n'
        'Ruwe schatting — geen lichaamsgewicht meegerekend.',
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Laat staan')),
        FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Naar ${suggested.label}')),
      ],
    ),
  );
  if (ok == true) {
    await ref.read(settingsRepositoryProvider).setRowingLevel(suggested);
    ref.invalidate(rowingLevelProvider);
  }
}

/// A card shown near a level selector when the FTP suggests a different level.
/// Tapping "Overnemen" switches the shared `rowing_level`.
class LevelSuggestionCard extends ConsumerWidget {
  const LevelSuggestionCard({super.key, required this.ftpWatts});
  final double ftpWatts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final suggested = suggestedLevelFromFtp(ftpWatts);
    final current =
        ref.watch(rowingLevelProvider).valueOrNull ?? ProgramLevel.medium;
    if (suggested == current) return const SizedBox.shrink();

    return Card(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Op basis van je FTP: niveau "${suggested.label}" '
                '(ruwe schatting)',
                style: theme.textTheme.bodySmall,
              ),
            ),
            TextButton(
              onPressed: () async {
                await ref
                    .read(settingsRepositoryProvider)
                    .setRowingLevel(suggested);
                ref.invalidate(rowingLevelProvider);
              },
              child: const Text('Overnemen'),
            ),
          ],
        ),
      ),
    );
  }
}

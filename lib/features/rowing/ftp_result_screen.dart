import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/rowing_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/rowing_format.dart';
import '../../domain/rowing_ftp.dart';
import 'widgets/level_suggestion.dart';

/// Shown after a guided FTP test finishes: the computed FTP, with the option to
/// save it as the reference.
class FtpResultScreen extends ConsumerWidget {
  const FtpResultScreen({super.key, required this.sessionId});
  final int sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final detailAsync = ref.watch(rowingSessionDetailProvider(sessionId));
    final dragK = ref.watch(rowingDragKProvider).valueOrNull ?? kGeneric;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Testresultaat'),
        automaticallyImplyLeading: false,
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fout: $e')),
        data: (detail) {
          if (detail == null) {
            return const Center(child: Text('Sessie niet gevonden'));
          }
          final proto = FtpProtocol.fromKind(detail.rowing.kind) ??
              FtpProtocol.test20;
          final res = computeFtp((
            samples: detail.samples,
            planSegments: detail.planSegments,
            totalDistanceM: detail.rowing.totalDistanceM,
            durationSeconds: detail.rowing.durationSeconds,
          ), proto);

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            children: [
              Text(proto.label, style: theme.textTheme.labelLarge),
              const SizedBox(height: 16),
              if (res.watts <= 0)
                Text(
                  'Kon geen bruikbaar vermogen uit deze sessie halen. '
                  'Probeer opnieuw met de trainer verbonden.',
                  style: theme.textTheme.bodyLarge,
                )
              else ...[
                Text('Je FTP', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text('${res.watts.round()} W',
                    style: theme.textTheme.displayMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
                Text(
                  '${paceLabel(splitForWatts(res.watts, dragK: dragK))}'
                  '${res.effortWatts != null ? '  ·  inspanning ${res.effortWatts!.round()} W' : ''}',
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 6),
                Text(
                  switch (res.method) {
                    FtpMethod.criticalPower =>
                      'via Critical Power (60 s + 4 min)',
                    FtpMethod.multiplier =>
                      'via ${(proto.multiplier * 100).round()} %-factor',
                  },
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                if (res.lowConfidence) ...[
                  const SizedBox(height: 12),
                  Text('Ruwe schatting — weinig meetdata in het meetblok.',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ],
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: () => _save(context, ref, res, proto),
                  child: const Text('Opslaan als mijn FTP'),
                ),
                const SizedBox(height: 8),
              ],
              TextButton(
                onPressed: () =>
                    context.go('/rowing/log/session/$sessionId'),
                child: const Text('Niet opslaan'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _save(BuildContext context, WidgetRef ref, FtpResult res,
      FtpProtocol proto) async {
    final ftp = RowingFtp(
      watts: res.watts,
      setAt: DateTime.now(),
      source: proto.source,
    );
    final repo = ref.read(settingsRepositoryProvider);
    await repo.setRowingFtp(ftp);
    await repo.appendFtpHistory(ftp);
    ref.invalidate(rowingFtpProvider);
    ref.invalidate(rowingFtpHistoryProvider);
    if (!context.mounted) return;

    await maybePromptLevelFromFtp(context, ref, ftp.watts);
    if (context.mounted) context.go('/rowing/log/session/$sessionId');
  }
}

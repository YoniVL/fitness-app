import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/rowing_plan.dart';
import '../../domain/rowing_format.dart';
import 'rower_service.dart';
import 'state/active_rowing_provider.dart';

class RowingActiveScreen extends ConsumerWidget {
  const RowingActiveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(activeRowingProvider);
    final status = ref.watch(rowerStatusProvider).valueOrNull ??
        ref.watch(rowerServiceProvider).status;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Roeisessie'),
        actions: [
          Center(child: _StatusChip(status: status)),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v != 'discard') return;
              final ok = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Sessie weggooien?'),
                  content: const Text('Niets wordt opgeslagen.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Annuleren')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Weggooien')),
                  ],
                ),
              );
              if (ok != true) return;
              await ref.read(activeRowingProvider.notifier).discard();
              if (context.mounted) context.go('/rowing/today');
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'discard', child: Text('Sessie weggooien')),
            ],
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fout: $e')),
        data: (state) {
          if (state == null) {
            return const Center(child: Text('Geen actieve roeisessie'));
          }
          return _Body(state: state);
        },
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final RowerConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (status) {
      RowerConnectionStatus.connected => ('Verbonden', scheme.primary),
      RowerConnectionStatus.demo => ('Demo', scheme.tertiary),
      RowerConnectionStatus.connecting => ('Verbinden…', scheme.onSurfaceVariant),
      RowerConnectionStatus.disconnected =>
        ('Niet verbonden', scheme.onSurfaceVariant),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.bluetooth, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.state});
  final ActiveRowingState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = state.live;
    final notifier = ref.read(activeRowingProvider.notifier);
    final seg = state.currentSegment;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _BigStat(
                label: 'Afstand',
                value: distanceLabel(live?.distanceM ?? 0),
              ),
              const SizedBox(height: 16),
              _BigStat(label: 'Tijd', value: hmsLabel(state.elapsed)),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _MidStat(
                        label: 'Tempo',
                        value: paceLabel(live?.paceSec500m, withUnit: false)),
                  ),
                  Expanded(
                    child: _MidStat(
                        label: 'Slag', value: spmLabel(live?.strokeRate)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _SmallStat(
                        label: 'Vermogen', value: powerLabel(live?.powerW)),
                  ),
                  Expanded(
                    child: _SmallStat(
                      label: 'Hartslag',
                      value: live?.heartRate == null
                          ? '–'
                          : '${live!.heartRate} bpm',
                    ),
                  ),
                ],
              ),
              if (seg != null) ...[
                const SizedBox(height: 24),
                _SegmentBanner(state: state),
              ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: notifier.togglePause,
                    icon: Icon(state.paused
                        ? Icons.play_arrow
                        : Icons.pause),
                    label: Text(state.paused ? 'Hervat' : 'Pauze'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _finish(context, ref),
                    icon: const Icon(Icons.flag),
                    label: const Text('Afronden'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _finish(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sessie afronden?'),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Notitie (optioneel)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Afronden'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final note = controller.text.trim();
    final id = await ref
        .read(activeRowingProvider.notifier)
        .finish(notes: note.isEmpty ? null : note);
    if (context.mounted) {
      if (id != null) {
        context.go('/rowing/log/session/$id');
      } else {
        context.go('/rowing/today');
      }
    }
  }
}

class _SegmentBanner extends StatelessWidget {
  const _SegmentBanner({required this.state});
  final ActiveRowingState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final seg = state.currentSegment!;
    final total = seg.durationSeconds;
    final remaining = state.segmentRemaining ?? Duration.zero;
    final progress = total == 0 ? 0.0 : 1 - remaining.inSeconds / total;
    final drill = RowDrill.fromKey(seg.drillKey);
    final next = state.segmentIndex + 1 < state.segments.length
        ? state.segments[state.segmentIndex + 1]
        : null;

    return Card(
      color: seg.isRest
          ? theme.colorScheme.surfaceContainerHighest
          : theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(seg.intensityLabel,
                      style: theme.textTheme.titleMedium),
                ),
                Text(hmsLabel(remaining),
                    style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              [
                'Blok ${state.segmentIndex + 1}/${state.segments.length}',
                if (seg.targetStrokeRate != null)
                  'streef ${seg.targetStrokeRate} spm',
                if (next != null) 'straks: ${next.intensityLabel}',
              ].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
            if (drill != null) ...[
              const SizedBox(height: 6),
              Text(drill.tip, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _BigStat extends StatelessWidget {
  const _BigStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelMedium),
        Text(value,
            style: theme.textTheme.displaySmall
                ?.copyWith(fontFeatures: const [])),
      ],
    );
  }
}

class _MidStat extends StatelessWidget {
  const _MidStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelMedium),
        Text(value, style: theme.textTheme.headlineSmall),
      ],
    );
  }
}

class _SmallStat extends StatelessWidget {
  const _SmallStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelSmall),
        Text(value, style: theme.textTheme.titleMedium),
      ],
    );
  }
}

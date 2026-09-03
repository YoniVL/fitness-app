import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/rowing_plan.dart';
import '../../domain/rowing_format.dart';
import 'rower_service.dart';
import 'state/active_rowing_provider.dart';
import 'widgets/interval_profile.dart';

/// The live rowing screen. Forced to landscape for a big, readable readout.
class RowingActiveScreen extends ConsumerStatefulWidget {
  const RowingActiveScreen({super.key});

  @override
  ConsumerState<RowingActiveScreen> createState() => _RowingActiveScreenState();
}

class _RowingActiveScreenState extends ConsumerState<RowingActiveScreen> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(activeRowingProvider);
    final status = ref.watch(rowerStatusProvider).valueOrNull ??
        ref.watch(rowerServiceProvider).status;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 44,
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
        data: (state) => state == null
            ? const Center(child: Text('Geen actieve roeisessie'))
            : _Body(state: state),
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
      RowerConnectionStatus.connecting =>
        ('Verbinden…', scheme.onSurfaceVariant),
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
    final hasSegments = state.segments.isNotEmpty;

    final numbers = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HugeStat(
            label: 'Afstand', value: distanceLabel(live?.distanceM ?? 0)),
        const SizedBox(height: 6),
        _HugeStat(label: 'Tijd', value: hmsLabel(state.elapsed)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MidStat(
                  label: 'Tempo /500m',
                  value: paceLabel(live?.paceSec500m, withUnit: false)),
            ),
            Expanded(
              child: _MidStat(
                  label: 'Slag', value: spmLabel(live?.strokeRate)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _SmallStat(
                  label: 'Vermogen', value: powerLabel(live?.powerW)),
            ),
            Expanded(
              child: _SmallStat(
                label: 'Hartslag',
                value:
                    live?.heartRate == null ? '–' : '${live!.heartRate} bpm',
              ),
            ),
          ],
        ),
      ],
    );

    final controls = Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: notifier.togglePause,
            icon: Icon(state.paused ? Icons.play_arrow : Icons.pause),
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
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
        child: hasSegments
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 5,
                    child: SingleChildScrollView(
                      child: Align(
                          alignment: Alignment.centerLeft, child: numbers),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    flex: 6,
                    child: Column(
                      children: [
                        IntervalProfile(
                          blocks: profileFromSegments(state.segments),
                          height: 48,
                          progressFraction: _sessionProgress(),
                        ),
                        const SizedBox(height: 8),
                        Expanded(child: _SegmentBanner(state: state)),
                        const SizedBox(height: 8),
                        controls,
                      ],
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(child: numbers),
                    ),
                  ),
                  controls,
                ],
              ),
      ),
    );
  }

  double _sessionProgress() {
    final total = state.plannedTotalSeconds;
    if (total <= 0) return 0;
    return (state.elapsed.inSeconds / total).clamp(0.0, 1.0);
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
      context.go(id != null ? '/rowing/log/session/$id' : '/rowing/today');
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
      margin: EdgeInsets.zero,
      color: seg.isRest
          ? theme.colorScheme.surfaceContainerHighest
          : theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(seg.intensityLabel,
                      style: theme.textTheme.titleLarge),
                ),
                Text(hmsLabel(remaining), style: theme.textTheme.titleLarge),
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
              style: theme.textTheme.bodyMedium,
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

class _HugeStat extends StatelessWidget {
  const _HugeStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelMedium),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value,
              style: theme.textTheme.displaySmall
                  ?.copyWith(fontWeight: FontWeight.w700, height: 1.05)),
        ),
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
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value, style: theme.textTheme.headlineSmall),
        ),
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

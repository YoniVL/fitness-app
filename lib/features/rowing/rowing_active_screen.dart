import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/rowing_plan.dart';
import '../../domain/rowing_format.dart';
import '../../domain/rowing_workouts.dart';
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

    final secondary = <String>[
      if ((live?.powerW ?? 0) > 0) powerLabel(live!.powerW),
      if (live?.heartRate != null) '${live!.heartRate} bpm',
    ].join('   ·   ');

    final numbers = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Stat(
          label: 'Afstand',
          value: distanceLabel(live?.distanceM ?? 0),
          size: _StatSize.hero,
        ),
        const SizedBox(height: 14),
        _Stat(
          label: 'Tijd',
          value: hmsLabel(state.elapsed),
          size: _StatSize.hero,
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _Stat(
                label: 'Tempo /500m',
                value: paceLabel(live?.paceSec500m, withUnit: false),
                size: _StatSize.big,
              ),
            ),
            Expanded(
              child: _Stat(
                label: 'Slag',
                value: spmLabel(live?.strokeRate),
                size: _StatSize.big,
              ),
            ),
          ],
        ),
        if (secondary.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(secondary,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
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
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
        child: hasSegments
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 4,
                    child: SingleChildScrollView(
                      child: Align(
                          alignment: Alignment.centerLeft, child: numbers),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 5,
                    child: Column(
                      children: [
                        IntervalProfile(
                          blocks: profileFromSegments(state.segments),
                          height: 40,
                          progressFraction: _sessionProgress(),
                        ),
                        const SizedBox(height: 10),
                        Expanded(child: _NowNextCard(state: state)),
                        const SizedBox(height: 10),
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

/// The calm centrepiece: the current segment (label + countdown + target rate)
/// and — prominently — what's coming next so you can prepare the rating.
class _NowNextCard extends StatelessWidget {
  const _NowNextCard({required this.state});
  final ActiveRowingState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final seg = state.currentSegment!;
    final total = seg.durationSeconds;
    final remaining = state.segmentRemaining ?? Duration.zero;
    final progress = total == 0 ? 0.0 : 1 - remaining.inSeconds / total;
    final drill = RowDrill.fromKey(seg.drillKey);
    final next = state.segmentIndex + 1 < state.segments.length
        ? state.segments[state.segmentIndex + 1]
        : null;
    final zone = intensityColor(
        RowBlock.zoneFor(spm: seg.targetStrokeRate, isRest: seg.isRest),
        scheme);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: scheme.surfaceContainerHigh,
      child: Row(
        children: [
          Container(width: 6, color: zone),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Text(seg.intensityLabel,
                            style: theme.textTheme.titleLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      Text(hmsLabel(remaining),
                          style: theme.textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: scheme.surfaceContainerHighest,
                      color: zone,
                    ),
                  ),
                  if (seg.targetStrokeRate != null) ...[
                    const SizedBox(height: 8),
                    Text('doel ${seg.targetStrokeRate} spm',
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant)),
                  ],
                  if (drill != null)
                    Text(drill.tip,
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  const Divider(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text('STRAKS  ',
                          style: theme.textTheme.labelMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                              letterSpacing: 1.5)),
                      Expanded(
                        child: Text(
                          next == null
                              ? 'Sessie afronden'
                              : [
                                  next.intensityLabel,
                                  if (next.targetStrokeRate != null)
                                    '${next.targetStrokeRate} spm',
                                ].join('  ·  '),
                          style: theme.textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _StatSize { hero, big }

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.size});
  final String label;
  final String value;
  final _StatSize size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueStyle = switch (size) {
      _StatSize.hero => theme.textTheme.displaySmall
          ?.copyWith(fontWeight: FontWeight.w700, height: 1.05),
      _StatSize.big => theme.textTheme.headlineSmall,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: valueStyle),
        ),
      ],
    );
  }
}

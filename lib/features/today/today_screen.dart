import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/repositories/exercise_repository.dart';
import '../../data/repositories/program_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/workout_session_repository.dart';
import '../../domain/models/program.dart';
import '../../domain/progression.dart';
import '../strength/state/active_workout_provider.dart';

/// (name, "N×M") for each exercise of a program day.
final _dayPreviewProvider =
    FutureProvider.family<List<(String, String)>, int>((ref, dayId) async {
  final pes = await ref.watch(programRepositoryProvider).exercisesForDay(dayId);
  final names = await ref
      .watch(exerciseRepositoryProvider)
      .byIds(pes.map((e) => e.exerciseId));
  return [
    for (final pe in pes)
      (
        names[pe.exerciseId]?.name ?? 'Oefening',
        '${pe.targetSets} × ${pe.targetReps}'
      )
  ];
});

/// Number of finished strength sessions in the current ISO week.
final _thisWeekCountProvider = FutureProvider<int>((ref) async {
  final sessions = await ref.watch(recentSessionsProvider.future);
  final now = DateTime.now();
  final monday = DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: now.weekday - 1));
  return sessions
      .where((s) =>
          s.session.isFinished && !s.session.startedAt.isBefore(monday))
      .length;
});

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeWorkoutProvider);
    final program = ref.watch(activeProgramProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Vandaag'),
            Text(
              DateFormat('EEEE d MMMM', 'nl').format(DateTime.now()),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(activeProgramProvider);
          ref.invalidate(activeWorkoutProvider);
          ref.invalidate(recentSessionsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _WeekStrip(),
            const SizedBox(height: 16),
            active.maybeWhen(
              data: (s) => s == null || s.blocks.isEmpty
                  ? const SizedBox.shrink()
                  : _ResumeCard(setCount: s.totalSets),
              orElse: () => const SizedBox.shrink(),
            ),
            program.when(
              loading: () => const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (e, _) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Kon programma niet laden: $e'),
                ),
              ),
              data: (p) => p == null
                  ? _NoProgramCard()
                  : _ProgramDayCard(active: p),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () async {
                await ref.read(activeWorkoutProvider.notifier).startEmpty();
                if (context.mounted) context.push('/workout/active');
              },
              icon: const Icon(Icons.add),
              label: const Text('Losse training'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResumeCard extends StatelessWidget {
  const _ResumeCard({required this.setCount});
  final int setCount;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.play_circle_fill),
        title: const Text('Training bezig'),
        subtitle: Text('$setCount set(s) gelogd — hervat waar je gebleven was'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/workout/active'),
      ),
    );
  }
}

class _NoProgramCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nog geen programma gekozen',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
                'Kies een programma in de bibliotheek of stel er zelf een samen.'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => context.go('/library'),
              child: const Text('Naar de bibliotheek'),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekStrip extends ConsumerWidget {
  const _WeekStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(_thisWeekCountProvider).valueOrNull ?? 0;
    final streak = ref.watch(trainingWeekStreakProvider).valueOrNull ?? 0;

    return Row(
      children: [
        Expanded(
          child: _StatChip(
            icon: Icons.event_available,
            label: 'Deze week',
            value: count == 0
                ? 'Nog niks'
                : '$count training${count == 1 ? '' : 'en'}',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatChip(
            icon: Icons.local_fire_department,
            label: 'Reeks',
            value: streak < 2 ? '—' : '$streak weken',
            dim: streak < 2,
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    this.dim = false,
  });
  final IconData icon;
  final String label;
  final String value;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = dim
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: fg),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelSmall),
              Text(value,
                  style: theme.textTheme.titleSmall?.copyWith(color: fg)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProgramDayCard extends ConsumerWidget {
  const _ProgramDayCard({required this.active});
  final ActiveProgram active;

  String _roundLabel(WidgetRef ref, int round) {
    final autoOn = ref.watch(autoProgressionProvider).valueOrNull ?? true;
    if (!autoOn) return 'Ronde $round';
    final d = progressTargets(baseSets: 0, baseReps: 0, round: round);
    final parts = [
      if (d.sets > 0) '+${d.sets} set${d.sets > 1 ? 's' : ''}',
      if (d.reps > 0) '+${d.reps} reps',
    ];
    return parts.isEmpty
        ? 'Ronde $round'
        : 'Ronde $round · ${parts.join(' · ')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final day = active.currentDay;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${active.program.name} · dag '
              '${active.currentDayIndex + 1}/${active.dayCount}',
              style: theme.textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            Text(day.label, style: theme.textTheme.headlineSmall),
            if (active.round > 1)
              Text(_roundLabel(ref, active.round),
                  style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            ref.watch(_dayPreviewProvider(day.id)).maybeWhen(
                  data: (rows) => Column(
                    children: [
                      for (final (name, sets) in rows)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(name,
                                    style: theme.textTheme.bodyMedium),
                              ),
                              Text(sets,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme
                                          .colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                    ],
                  ),
                  orElse: () => const SizedBox.shrink(),
                ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  await ref
                      .read(activeWorkoutProvider.notifier)
                      .startFromDay(day);
                  if (context.mounted) context.push('/workout/active');
                },
                child: const Text('Start deze dag'),
              ),
            ),
            TextButton(
              onPressed: () => _pickDay(context, ref),
              child: const Text('Andere dag'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDay(BuildContext context, WidgetRef ref) async {
    final chosen = await showModalBottomSheet<ProgramDay>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < active.days.length; i++)
              ListTile(
                leading: Text('${i + 1}'),
                title: Text(active.days[i].label),
                trailing: i == active.currentDayIndex
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(context, active.days[i]),
              ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    await ref
        .read(programRepositoryProvider)
        .setCursor(active.program.id, chosen.dayIndex);
    ref.invalidate(activeProgramProvider);
    if (context.mounted) {
      await ref.read(activeWorkoutProvider.notifier).startFromDay(chosen);
      if (context.mounted) context.push('/workout/active');
    }
  }
}

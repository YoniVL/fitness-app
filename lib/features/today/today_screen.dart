import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/program_repository.dart';
import '../../domain/models/program.dart';
import '../strength/state/active_workout_provider.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeWorkoutProvider);
    final program = ref.watch(activeProgramProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vandaag'),
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
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
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

class _ProgramDayCard extends ConsumerWidget {
  const _ProgramDayCard({required this.active});
  final ActiveProgram active;

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
            Text(active.program.name, style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(
              'Dag ${active.currentDayIndex + 1}/${active.dayCount}: ${day.label}',
              style: theme.textTheme.headlineSmall,
            ),
            if (active.round > 1)
              Text('Ronde ${active.round}', style: theme.textTheme.bodySmall),
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

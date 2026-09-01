import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/program_repository.dart';
import '../strength/state/active_workout_provider.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeWorkoutProvider);
    final scheduled = ref.watch(scheduledDayTodayProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Vandaag')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          active.maybeWhen(
            data: (session) => session == null
                ? const SizedBox.shrink()
                : _ResumeCard(setCount: session.totalSets),
            orElse: () => const SizedBox.shrink(),
          ),
          scheduled.when(
            loading: () => const _PlannedCard.loading(),
            error: (e, _) => _PlannedCard.error('$e'),
            data: (day) => _PlannedCard(
              title: day?.label,
              onStart: day == null
                  ? null
                  : () async {
                      await ref
                          .read(activeWorkoutProvider.notifier)
                          .startFromDay(day);
                      if (context.mounted) context.push('/workout/active');
                    },
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () async {
              await ref.read(activeWorkoutProvider.notifier).startEmpty();
              if (context.mounted) context.push('/workout/active');
            },
            icon: const Icon(Icons.add),
            label: const Text('Lege training starten'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => context.go('/library'),
            icon: const Icon(Icons.library_books_outlined),
            label: const Text('Kies een programma uit de bibliotheek'),
          ),
        ],
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

class _PlannedCard extends StatelessWidget {
  const _PlannedCard({this.title, this.onStart})
      : _loading = false,
        _error = null;
  const _PlannedCard.loading()
      : title = null,
        onStart = null,
        _loading = true,
        _error = null;
  const _PlannedCard.error(String message)
      : title = null,
        onStart = null,
        _loading = false,
        _error = message;

  final String? title;
  final VoidCallback? onStart;
  final bool _loading;
  final String? _error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Gepland voor vandaag', style: theme.textTheme.labelMedium),
            const SizedBox(height: 8),
            if (_loading)
              const LinearProgressIndicator()
            else if (_error != null)
              Text('Kon schema niet laden: $_error')
            else if (title == null)
              const Text('Niets gepland. Kies vrij een training.')
            else ...[
              Text(title!, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: onStart,
                child: const Text('Start deze training'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

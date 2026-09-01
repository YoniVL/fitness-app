import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/repositories/exercise_repository.dart';
import '../../data/repositories/workout_session_repository.dart';
import '../../domain/models/exercise.dart';
import '../../domain/models/strength_set.dart';
import '../../domain/models/workout_session.dart';

class _SessionView {
  _SessionView(this.detail, this.exerciseNames);
  final WorkoutSessionDetail detail;
  final Map<int, Exercise> exerciseNames;
}

final _sessionViewProvider =
    FutureProvider.family<_SessionView?, int>((ref, sessionId) async {
  final detail =
      await ref.watch(workoutSessionRepositoryProvider).sessionDetail(sessionId);
  if (detail == null) return null;
  final names = await ref
      .read(exerciseRepositoryProvider)
      .byIds(detail.sets.map((s) => s.exerciseId));
  return _SessionView(detail, names);
});

class SessionDetailScreen extends ConsumerWidget {
  const SessionDetailScreen({super.key, required this.sessionId});

  final int sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(_sessionViewProvider(sessionId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sessie'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
      body: view.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fout: $e')),
        data: (data) {
          if (data == null) {
            return const Center(child: Text('Sessie niet gevonden'));
          }
          return _Body(view: data);
        },
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sessie verwijderen?'),
        content: const Text('Dit kan niet ongedaan worden gemaakt.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Verwijderen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(workoutSessionRepositoryProvider).deleteSession(sessionId);
    ref.invalidate(recentSessionsProvider);
    if (context.mounted) context.pop();
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.view});
  final _SessionView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = view.detail.session;
    final dateFmt = DateFormat('EEEE d MMMM y · HH:mm', 'nl');

    final byExercise = <int, List<StrengthSet>>{};
    for (final s in view.detail.sets) {
      byExercise.putIfAbsent(s.exerciseId, () => []).add(s);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(dateFmt.format(session.startedAt), style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          children: [
            _Stat(label: 'Volume', value: '${view.detail.totalVolume.toStringAsFixed(0)} kg'),
            _Stat(label: 'Sets', value: '${view.detail.sets.length}'),
            _Stat(label: 'Oefeningen', value: '${view.detail.exerciseCount}'),
            if (session.duration != null)
              _Stat(label: 'Duur', value: _fmtDuration(session.duration!)),
          ],
        ),
        const Divider(height: 32),
        for (final entry in byExercise.entries) ...[
          Text(
            view.exerciseNames[entry.key]?.name ?? 'Oefening ${entry.key}',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          ...entry.value.map(
            (s) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(width: 28, child: Text('${s.setIndex}')),
                  Text('${s.reps} reps × ${s.weight.toStringAsFixed(1)} kg'),
                  if (s.isWarmup) ...[
                    const SizedBox(width: 8),
                    Text('opwarming', style: theme.textTheme.labelSmall),
                  ],
                  const Spacer(),
                  Text('${s.volume.toStringAsFixed(0)} kg',
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (session.notes != null && session.notes!.isNotEmpty) ...[
          const Divider(),
          Text('Notities', style: theme.textTheme.titleSmall),
          Text(session.notes!),
        ],
      ],
    );
  }

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return h > 0 ? '${h}u ${m}m' : '${m}m';
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: theme.textTheme.titleLarge),
        Text(label, style: theme.textTheme.labelSmall),
      ],
    );
  }
}

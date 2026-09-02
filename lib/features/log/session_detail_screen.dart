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
  _SessionView(this.detail, this.exerciseNames, this.muscleNames);
  final WorkoutSessionDetail detail;
  final Map<int, Exercise> exerciseNames;
  final Map<int, String> muscleNames;
}

final _sessionViewProvider =
    FutureProvider.family<_SessionView?, int>((ref, sessionId) async {
  final detail =
      await ref.watch(workoutSessionRepositoryProvider).sessionDetail(sessionId);
  if (detail == null) return null;
  final exRepo = ref.read(exerciseRepositoryProvider);
  final names = await exRepo.byIds(detail.sets.map((s) => s.exerciseId));
  final muscleNames = await exRepo.muscleGroupNames();
  return _SessionView(detail, names, muscleNames);
});

class SessionDetailScreen extends ConsumerWidget {
  const SessionDetailScreen({super.key, required this.sessionId});

  final int sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(_sessionViewProvider(sessionId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Samenvatting'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_note),
            tooltip: 'Notitie',
            onPressed: () => _editNote(
                context, ref, view.valueOrNull?.detail.session.notes),
          ),
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
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () => context.go('/today'),
            child: const Text('Klaar'),
          ),
        ),
      ),
    );
  }

  Future<void> _editNote(
      BuildContext context, WidgetRef ref, String? current) async {
    final controller = TextEditingController(text: current ?? '');
    final saved = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Notitie'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Notitie bij deze sessie'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Opslaan'),
          ),
        ],
      ),
    );
    if (saved == null) return;
    await ref
        .read(workoutSessionRepositoryProvider)
        .updateNotes(sessionId, saved.isEmpty ? null : saved);
    ref.invalidate(_sessionViewProvider(sessionId));
    ref.invalidate(recentSessionsProvider);
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

    final muscles = view.detail.muscleGroupSetCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(dateFmt.format(session.startedAt),
            style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        Wrap(
          spacing: 20,
          runSpacing: 8,
          children: [
            if (session.duration != null)
              _Stat(label: 'Duur', value: _fmtDuration(session.duration!)),
            _Stat(label: 'Sets', value: '${view.detail.workingSetCount}'),
            _Stat(label: 'Oefeningen', value: '${view.detail.exerciseCount}'),
            _Stat(label: 'Reps', value: '${view.detail.totalReps}'),
          ],
        ),
        if (muscles.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Getrainde spieren', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in muscles)
                Chip(
                  label: Text(
                      '${view.muscleNames[m.key] ?? '?'} · ${m.value}'),
                ),
            ],
          ),
        ],
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
                  Text('${s.reps} reps'),
                  if (s.isWarmup) ...[
                    const SizedBox(width: 8),
                    Text('opwarming', style: theme.textTheme.labelSmall),
                  ],
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

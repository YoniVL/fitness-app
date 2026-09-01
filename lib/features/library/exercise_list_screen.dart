import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/repositories/exercise_repository.dart';
import '../../domain/models/exercise.dart';
import '../../domain/models/muscle_group.dart';
import '../../domain/taxonomy.dart';
import '../exercises/exercise_media.dart';

void _showDetail(
    BuildContext context, Exercise ex, List<MuscleGroup> groups) {
  final names = {for (final g in groups) g.id: g.name};
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          24, 0, 24, 24 + MediaQuery.viewPaddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasExercisePhoto(ex.name)) ...[
            ExerciseDemo(exerciseName: ex.name, height: 200),
            const SizedBox(height: 12),
          ],
          Text(ex.name, style: Theme.of(context).textTheme.titleLarge),
          if (ex.pattern != null)
            Text(ex.pattern!.label,
                style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text(names[ex.primaryMuscleGroupId] ?? '?')),
              for (final id in ex.secondaryMuscleGroupIds)
                Chip(
                  label: Text(names[id] ?? '?'),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Materiaal: ${ex.equipmentTags.map(Equipment.label).join(', ')}',
              style: Theme.of(context).textTheme.bodySmall),
          if (hasExercisePhoto(ex.name)) ...[
            const SizedBox(height: 4),
            Text('Foto: everkinetic (CC BY-SA 3.0) — zie Instellingen › Credits.',
                style: Theme.of(context).textTheme.labelSmall),
          ],
        ],
      ),
    ),
  );
}

/// (muscleGroupId?, search) filter for the exercise list.
typedef ExerciseFilter = ({int? muscleGroupId, String search});

final exerciseFilterProvider = StateProvider<ExerciseFilter>(
  (ref) => (muscleGroupId: null, search: ''),
);

final filteredExercisesProvider = FutureProvider<List<Exercise>>((ref) {
  final filter = ref.watch(exerciseFilterProvider);
  return ref.watch(exerciseRepositoryProvider).exercises(
        muscleGroupId: filter.muscleGroupId,
        search: filter.search,
      );
});

/// Shown standalone (browse) and as a picker (returns an exercise id via
/// `Navigator.pop`) — [pickMode] switches the tap behaviour.
class ExerciseListScreen extends ConsumerWidget {
  const ExerciseListScreen({super.key, this.pickMode = false});

  final bool pickMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muscleGroups = ref.watch(muscleGroupsProvider);
    final exercises = ref.watch(filteredExercisesProvider);
    final filter = ref.watch(exerciseFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(pickMode ? 'Kies oefening' : 'Oefeningen'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Zoek oefening',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => ref
                  .read(exerciseFilterProvider.notifier)
                  .update((f) => (muscleGroupId: f.muscleGroupId, search: value)),
            ),
          ),
          SizedBox(
            height: 48,
            child: muscleGroups.when(
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
              data: (groups) => ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _FilterChip(
                    label: 'Alle',
                    selected: filter.muscleGroupId == null,
                    onSelected: () => ref
                        .read(exerciseFilterProvider.notifier)
                        .update((f) => (muscleGroupId: null, search: f.search)),
                  ),
                  for (final g in groups)
                    _FilterChip(
                      label: g.name,
                      selected: filter.muscleGroupId == g.id,
                      onSelected: () => ref.read(exerciseFilterProvider.notifier).update(
                          (f) => (muscleGroupId: g.id, search: f.search)),
                    ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: exercises.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Fout: $e')),
              data: (list) => _ExerciseList(
                list: list,
                groups: muscleGroups.valueOrNull ?? const [],
                pickMode: pickMode,
                onTap: pickMode
                    ? (ex) => Navigator.of(context).pop(ex.id)
                    : (ex) => _showDetail(
                        context, ex, muscleGroups.valueOrNull ?? const []),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExerciseList extends StatelessWidget {
  const _ExerciseList(
      {required this.list,
      required this.groups,
      this.onTap,
      this.pickMode = false});

  final List<Exercise> list;
  final List<MuscleGroup> groups;
  final void Function(Exercise)? onTap;
  final bool pickMode;

  @override
  Widget build(BuildContext context) {
    if (list.isEmpty) {
      return const Center(child: Text('Geen oefeningen gevonden'));
    }
    final iconByGroup = {for (final g in groups) g.id: g.iconKey};
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (context, index) {
        final ex = list[index];
        return ListTile(
          leading: CircleAvatar(
            child: Icon(muscleGroupIcon(iconByGroup[ex.primaryMuscleGroupId] ?? '')),
          ),
          title: Text(ex.name),
          subtitle: Text(ex.equipmentTags.map(Equipment.label).join(' · ')),
          trailing: onTap == null
              ? null
              : Icon(pickMode ? Icons.add : Icons.chevron_right),
          onTap: onTap == null ? null : () => onTap!(ex),
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
      ),
    );
  }
}

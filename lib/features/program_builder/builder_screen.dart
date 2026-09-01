import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/exercise_repository.dart';
import '../../data/repositories/program_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/models/program.dart';
import '../../domain/taxonomy.dart';
import 'program_generator.dart';

class BuilderScreen extends ConsumerStatefulWidget {
  const BuilderScreen({super.key});

  @override
  ConsumerState<BuilderScreen> createState() => _BuilderScreenState();
}

class _BuilderScreenState extends ConsumerState<BuilderScreen> {
  final _nameController = TextEditingController();
  int _days = 4;
  ProgramLevel _level = ProgramLevel.medium;
  final Set<String> _muscleGroups = {...MuscleGroups.all};
  GeneratedProgram? _result;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final owned = ref.watch(ownedEquipmentProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Schema samenstellen')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Naam (optioneel)',
            ),
          ),
          const SizedBox(height: 16),
          Text('Dagen per week', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 2, label: Text('2')),
              ButtonSegment(value: 3, label: Text('3')),
              ButtonSegment(value: 4, label: Text('4')),
              ButtonSegment(value: 5, label: Text('5')),
            ],
            selected: {_days},
            onSelectionChanged: (s) => setState(() => _days = s.first),
          ),
          const SizedBox(height: 16),
          Text('Niveau', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          SegmentedButton<ProgramLevel>(
            segments: [
              for (final l in ProgramLevel.values)
                ButtonSegment(value: l, label: Text(l.label)),
            ],
            selected: {_level},
            onSelectionChanged: (s) => setState(() => _level = s.first),
          ),
          const SizedBox(height: 16),
          Text('Spiergroepen', style: Theme.of(context).textTheme.labelLarge),
          Wrap(
            spacing: 8,
            children: [
              for (final mg in MuscleGroups.all)
                FilterChip(
                  label: Text(mg),
                  selected: _muscleGroups.contains(mg),
                  onSelected: (v) => setState(() {
                    v ? _muscleGroups.add(mg) : _muscleGroups.remove(mg);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          owned.maybeWhen(
            data: (tags) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.fitness_center),
              title: Text('Materiaal: ${tags.map(Equipment.label).join(', ')}'),
              trailing: TextButton(
                onPressed: () => context.push('/settings'),
                child: const Text('Wijzig'),
              ),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _busy ? null : _generate,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Genereer'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (_result != null) ..._preview(_result!),
        ],
      ),
    );
  }

  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final catalogue =
          await ref.read(exerciseRepositoryProvider).strengthCatalogue();
      final equipment = await ref.read(settingsRepositoryProvider).ownedEquipment();
      final gen = ProgramGenerator(catalogue);
      final result = gen.generate(GeneratorInput(
        daysPerWeek: _days,
        level: _level,
        muscleGroups: _muscleGroups,
        equipment: equipment,
        name: _nameController.text,
        restBetweenSets:
            await ref.read(settingsRepositoryProvider).restBetweenSets(),
        restAfterExercise:
            await ref.read(settingsRepositoryProvider).restAfterExercise(),
      ));
      setState(() => _result = result);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  List<Widget> _preview(GeneratedProgram program) {
    final theme = Theme.of(context);
    return [
      const Divider(height: 32),
      Text(program.name, style: theme.textTheme.titleLarge),
      for (final w in program.warnings)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('⚠ $w', style: theme.textTheme.bodySmall),
        ),
      const SizedBox(height: 8),
      for (final day in program.days)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(day.label, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                for (final ge in day.exercises)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(child: Text(ge.exercise.name)),
                        Text('${ge.sets} × ${ge.reps}',
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _busy ? null : _generate,
              child: const Text('Opnieuw'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: _busy ? null : () => _save(program),
              child: const Text('Opslaan'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 24),
    ];
  }

  Future<void> _save(GeneratedProgram program) async {
    setState(() => _busy = true);
    final repo = ref.read(programRepositoryProvider);
    final id = await repo.createProgram(NewProgramDraft(
      name: program.name,
      category: ProgramCategory.strengthGenerated,
      equipmentProfile: program.equipmentProfile,
      level: program.level,
      daysPerWeek: program.daysPerWeek,
      days: [
        for (final day in program.days)
          NewProgramDayDraft(
            label: day.label,
            exercises: [
              for (final ge in day.exercises)
                NewProgramExerciseDraft(
                  exerciseId: ge.exercise.id,
                  sets: ge.sets,
                  reps: ge.reps,
                  restBetweenSets: ge.restBetweenSets,
                  restAfterExercise: ge.restAfterExercise,
                ),
            ],
          ),
      ],
    ));
    ref.invalidate(visibleStrengthProgramsProvider);
    if (!mounted) return;

    final setActive = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Opgeslagen'),
        content: const Text('Dit schema als je actieve programma instellen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ja, instellen'),
          ),
        ],
      ),
    );
    if (setActive == true) {
      await repo.setActiveProgram(id);
      ref.invalidate(activeProgramProvider);
    }
    if (mounted) context.go('/library/program/$id');
  }
}

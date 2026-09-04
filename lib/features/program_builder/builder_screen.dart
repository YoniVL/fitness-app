import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/exercise_repository.dart';
import '../../data/repositories/program_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/models/exercise.dart';
import '../../domain/models/program.dart';
import '../../domain/taxonomy.dart';
import '../../ui/async_view.dart';
import '../../ui/confirm_dialog.dart';
import '../../ui/spacing.dart';
import 'program_editor_widgets.dart';
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
  int? _minutes; // null = op basis van niveau
  final Set<String> _muscleGroups = {...MuscleGroups.all};

  List<EditableDay>? _editDays;
  List<String> _warnings = const [];
  List<Exercise> _catalogue = const [];
  Set<String> _equipment = const {};
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
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Naam (optioneel)'),
          ),
          Gap.l,
          _label('Dagen per week'),
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
          Gap.l,
          _label('Niveau (bepaalt sets & reps)'),
          SegmentedButton<ProgramLevel>(
            segments: [
              for (final l in ProgramLevel.values)
                ButtonSegment(value: l, label: Text(l.label)),
            ],
            selected: {_level},
            onSelectionChanged: (s) => setState(() => _level = s.first),
          ),
          Gap.l,
          _label('Tijd per dag'),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Op niveau'),
                selected: _minutes == null,
                onSelected: (_) => setState(() => _minutes = null),
              ),
              for (final m in const [20, 30, 45, 60, 75])
                ChoiceChip(
                  label: Text('$m min'),
                  selected: _minutes == m,
                  onSelected: (_) => setState(() => _minutes = m),
                ),
            ],
          ),
          Gap.l,
          _label('Spiergroepen'),
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
          Gap.m,
          owned.viewOrNothing(
            (tags) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.fitness_center),
              title: Text('Materiaal: ${tags.map(Equipment.label).join(', ')}'),
              trailing: TextButton(
                onPressed: () => context.push('/settings'),
                child: const Text('Wijzig'),
              ),
            ),
          ),
          Gap.s,
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _busy ? null : _generate,
            icon: const Icon(Icons.auto_awesome),
            label: Text(_editDays == null ? 'Genereer' : 'Genereer opnieuw'),
          ),
          if (_error != null) ...[
            Gap.m,
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (_editDays != null) ..._preview(),
        ],
      ),
      bottomNavigationBar: _editDays == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : _generate,
                        child: const Text('Opnieuw'),
                      ),
                    ),
                    Gap.m,
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy ? null : _save,
                        child: const Text('Opslaan'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text, style: Theme.of(context).textTheme.labelLarge),
      );

  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _catalogue = await ref.read(exerciseRepositoryProvider).strengthCatalogue();
      _equipment = await ref.read(settingsRepositoryProvider).ownedEquipment();
      final settings = ref.read(settingsRepositoryProvider);
      final result = ProgramGenerator(_catalogue).generate(GeneratorInput(
        daysPerWeek: _days,
        level: _level,
        muscleGroups: _muscleGroups,
        equipment: _equipment,
        name: _nameController.text,
        minutesPerSession: _minutes,
        restBetweenSets: await settings.restBetweenSets(),
        restAfterExercise: await settings.restAfterExercise(),
      ));
      setState(() {
        _warnings = result.warnings;
        _editDays = [
          for (final day in result.days)
            EditableDay(day.label, [
              for (final ge in day.exercises)
                EditableExercise(ge.exercise, ge.sets, ge.reps,
                    ge.restBetweenSets, ge.restAfterExercise),
            ]),
        ];
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _editDays = null;
      });
    } finally {
      setState(() => _busy = false);
    }
  }

  List<Widget> _preview() {
    final theme = Theme.of(context);
    return [
      const Divider(height: 32),
      for (final w in _warnings)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('⚠ $w', style: theme.textTheme.bodySmall),
        ),
      Gap.xs,
      for (var i = 0; i < _editDays!.length; i++)
        Card(
          child: InkWell(
            onTap: () => _editDay(i),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(_editDays![i].label,
                            style: theme.textTheme.titleMedium),
                      ),
                      const Icon(Icons.edit_outlined, size: 18),
                    ],
                  ),
                  Gap.xs,
                  for (final e in _editDays![i].exercises)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(child: Text(e.exercise.name)),
                          Text('${e.sets} × ${e.reps}',
                              style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
    ];
  }

  Future<void> _editDay(int index) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DayEditorSheet(
        day: _editDays![index],
        catalogue: _catalogue,
        equipment: _equipment,
        onChanged: () => setState(() {}),
      ),
    );
    setState(() {});
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final repo = ref.read(programRepositoryProvider);
    final name = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : 'Mijn schema (${_level.label})';
    final id = await repo.createProgram(NewProgramDraft(
      name: name,
      category: ProgramCategory.strengthGenerated,
      equipmentProfile: _equipment.toList(),
      level: _level,
      daysPerWeek: _editDays!.length,
      days: [
        for (final day in _editDays!)
          NewProgramDayDraft(
            label: day.label,
            exercises: [
              for (final e in day.exercises)
                NewProgramExerciseDraft(
                  exerciseId: e.exercise.id,
                  sets: e.sets,
                  reps: e.reps,
                  restBetweenSets: e.restBetween,
                  restAfterExercise: e.restAfter,
                ),
            ],
          ),
      ],
    ));
    ref.invalidate(visibleStrengthProgramsProvider);
    if (!mounted) return;

    final setActive = await confirmDialog(
      context,
      title: 'Opgeslagen',
      message: 'Dit schema als je actieve programma instellen?',
      cancelLabel: 'Later',
      confirmLabel: 'Ja, instellen',
    );
    if (setActive) {
      await repo.setActiveProgram(id);
      ref.invalidate(activeProgramProvider);
    }
    if (mounted) context.go('/strength/library/program/$id');
  }
}

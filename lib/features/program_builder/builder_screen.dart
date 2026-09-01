import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/exercise_repository.dart';
import '../../data/repositories/program_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/models/exercise.dart';
import '../../domain/models/program.dart';
import '../../domain/taxonomy.dart';
import '../strength/widgets/number_stepper.dart';
import 'program_generator.dart';

class _EditExercise {
  _EditExercise(this.exercise, this.sets, this.reps, this.restBetween,
      this.restAfter);
  Exercise exercise;
  int sets;
  int reps;
  int restBetween;
  int restAfter;
}

class _EditDay {
  _EditDay(this.label, this.exercises);
  String label;
  final List<_EditExercise> exercises;
}

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

  List<_EditDay>? _editDays;
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
          const SizedBox(height: 16),
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
          const SizedBox(height: 16),
          _label('Niveau (bepaalt sets & reps)'),
          SegmentedButton<ProgramLevel>(
            segments: [
              for (final l in ProgramLevel.values)
                ButtonSegment(value: l, label: Text(l.label)),
            ],
            selected: {_level},
            onSelectionChanged: (s) => setState(() => _level = s.first),
          ),
          const SizedBox(height: 16),
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
          const SizedBox(height: 16),
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
            label: Text(_editDays == null ? 'Genereer' : 'Genereer opnieuw'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
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
                    const SizedBox(width: 12),
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
            _EditDay(day.label, [
              for (final ge in day.exercises)
                _EditExercise(ge.exercise, ge.sets, ge.reps, ge.restBetweenSets,
                    ge.restAfterExercise),
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
      const SizedBox(height: 4),
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
                  const SizedBox(height: 4),
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
      builder: (context) => _DayEditor(
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

class _DayEditor extends StatefulWidget {
  const _DayEditor({
    required this.day,
    required this.catalogue,
    required this.equipment,
    required this.onChanged,
  });

  final _EditDay day;
  final List<Exercise> catalogue;
  final Set<String> equipment;
  final VoidCallback onChanged;

  @override
  State<_DayEditor> createState() => _DayEditorState();
}

class _DayEditorState extends State<_DayEditor> {
  void _bump() {
    setState(() {});
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(widget.day.label, style: theme.textTheme.titleLarge),
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              scrollController: scroll,
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
              buildDefaultDragHandles: false,
              itemCount: widget.day.exercises.length,
              // ignore: deprecated_member_use
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex--;
                  final item = widget.day.exercises.removeAt(oldIndex);
                  widget.day.exercises.insert(newIndex, item);
                });
                widget.onChanged();
              },
              itemBuilder: (context, i) => _ExerciseEditRow(
                key: ValueKey(widget.day.exercises[i]),
                index: i,
                entry: widget.day.exercises[i],
                onRemove: widget.day.exercises.length > 1
                    ? () {
                        setState(() => widget.day.exercises.removeAt(i));
                        widget.onChanged();
                      }
                    : null,
                onSwap: () => _swap(i),
                onChanged: _bump,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + bottomInset),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _addExercise,
                icon: const Icon(Icons.add),
                label: const Text('Oefening toevoegen'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _swap(int index) async {
    final current = widget.day.exercises[index];
    final replacement = await _pickExercise(pattern: current.exercise.pattern);
    if (replacement != null) {
      setState(() => current.exercise = replacement);
      widget.onChanged();
    }
  }

  Future<void> _addExercise() async {
    final ex = await _pickExercise();
    if (ex == null) return;
    setState(() => widget.day.exercises.add(_EditExercise(ex, 3, 10, 30, 60)));
    widget.onChanged();
  }

  Future<Exercise?> _pickExercise({MovementPattern? pattern}) {
    final options = widget.catalogue
        .where((e) => e.canPerformWith(widget.equipment))
        .where((e) => pattern == null || e.pattern == pattern)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return showModalBottomSheet<Exercise>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => ListView(
        children: [
          if (pattern != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Vervangers voor ${pattern.label}'),
            ),
          for (final e in options)
            ListTile(
              title: Text(e.name),
              subtitle: Text(e.equipmentTags.map(Equipment.label).join(' · ')),
              onTap: () => Navigator.pop(context, e),
            ),
        ],
      ),
    );
  }
}

class _ExerciseEditRow extends StatelessWidget {
  const _ExerciseEditRow({
    super.key,
    required this.index,
    required this.entry,
    required this.onRemove,
    required this.onSwap,
    required this.onChanged,
  });

  final int index;
  final _EditExercise entry;
  final VoidCallback? onRemove;
  final VoidCallback onSwap;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final setStep = entry.exercise.isUnilateral ? 2.0 : 1.0;
    final setMin = entry.exercise.isUnilateral ? 2.0 : 1.0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(Icons.drag_handle),
                  ),
                ),
                Expanded(
                  child: Text(entry.exercise.name,
                      style: theme.textTheme.titleSmall),
                ),
                IconButton(
                  icon: const Icon(Icons.swap_horiz, size: 20),
                  tooltip: 'Vervang',
                  onPressed: onSwap,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: onRemove,
                ),
              ],
            ),
            if (entry.exercise.isUnilateral)
              Text('Per kant — sets blijven even',
                  style: theme.textTheme.labelSmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                NumberStepper(
                  label: 'Sets',
                  value: entry.sets.toDouble(),
                  step: setStep,
                  min: setMin,
                  max: 10,
                  onChanged: (v) {
                    entry.sets = v.round();
                    onChanged();
                  },
                ),
                NumberStepper(
                  label: 'Reps',
                  value: entry.reps.toDouble(),
                  min: 1,
                  max: 30,
                  onChanged: (v) {
                    entry.reps = v.round();
                    onChanged();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

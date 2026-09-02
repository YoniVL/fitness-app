import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/exercise_repository.dart';
import '../../data/repositories/program_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/models/exercise.dart';
import '../../domain/models/program.dart';
import 'program_editor_widgets.dart';

/// Edits an existing program (template or own). Templates are forked into a
/// new owned program on save; owned programs are updated in place.
class ProgramEditorScreen extends ConsumerStatefulWidget {
  const ProgramEditorScreen({super.key, required this.programId});

  final int programId;

  @override
  ConsumerState<ProgramEditorScreen> createState() =>
      _ProgramEditorScreenState();
}

class _ProgramEditorScreenState extends ConsumerState<ProgramEditorScreen> {
  final _nameController = TextEditingController();
  Program? _program;
  List<EditableDay>? _days;
  List<Exercise> _catalogue = const [];
  Set<String> _equipment = const {};
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final programs = ref.read(programRepositoryProvider);
      final exercises = ref.read(exerciseRepositoryProvider);
      final program = await programs.programById(widget.programId);
      if (program == null) throw StateError('Programma niet gevonden');
      final days = await programs.daysForProgram(widget.programId);
      final editable = <EditableDay>[];
      for (final day in days) {
        final prescribed = await programs.exercisesForDay(day.id);
        final exMap = await exercises.byIds(prescribed.map((e) => e.exerciseId));
        editable.add(EditableDay(day.label, [
          for (final pe in prescribed)
            if (exMap[pe.exerciseId] != null)
              EditableExercise(exMap[pe.exerciseId]!, pe.targetSets,
                  pe.targetReps, pe.restBetweenSets, pe.restAfterExercise ?? 60),
        ]));
      }
      _catalogue = await exercises.strengthCatalogue();
      _equipment = program.isTemplate
          ? await ref.read(settingsRepositoryProvider).ownedEquipment()
          : program.equipmentProfile.toSet();
      setState(() {
        _program = program;
        _nameController.text =
            program.isTemplate ? '${program.name} (aangepast)' : program.name;
        _days = editable;
      });
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final program = _program;
    return Scaffold(
      appBar: AppBar(title: const Text('Programma aanpassen')),
      body: _error != null
          ? Center(child: Text('Fout: $_error'))
          : program == null || _days == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: EdgeInsets.fromLTRB(16, 16, 16,
                      24 + MediaQuery.viewPaddingOf(context).bottom + 72),
                  children: [
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: 'Naam'),
                    ),
                    const SizedBox(height: 8),
                    if (program.isTemplate)
                      Text(
                        'Dit is een vast schema — aanpassen maakt er een eigen '
                        'kopie van; het origineel blijft ongewijzigd.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    const SizedBox(height: 16),
                    for (var i = 0; i < _days!.length; i++) ...[
                      _DayCard(
                        day: _days![i],
                        onTap: () => _editDay(i),
                        onRemove: _days!.length > 1
                            ? () => setState(() => _days!.removeAt(i))
                            : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                    OutlinedButton.icon(
                      onPressed: _addDay,
                      icon: const Icon(Icons.add),
                      label: const Text('Dag toevoegen'),
                    ),
                  ],
                ),
      bottomNavigationBar: program == null || _days == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _save,
                    child: Text(program.isTemplate
                        ? 'Opslaan als eigen schema'
                        : 'Wijzigingen opslaan'),
                  ),
                ),
              ),
            ),
    );
  }

  Future<void> _editDay(int index) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DayEditorSheet(
        day: _days![index],
        catalogue: _catalogue,
        equipment: _equipment,
        onChanged: () => setState(() {}),
      ),
    );
    setState(() {});
  }

  void _addDay() {
    setState(() =>
        _days!.add(EditableDay('Dag ${_days!.length + 1}', [])));
  }

  Future<void> _save() async {
    final nonEmptyDays = _days!.where((d) => d.exercises.isNotEmpty).toList();
    if (nonEmptyDays.isEmpty) {
      setState(() => _error = 'Voeg minstens één oefening toe.');
      return;
    }
    setState(() => _busy = true);
    final repo = ref.read(programRepositoryProvider);
    final name = _nameController.text.trim().isEmpty
        ? _program!.name
        : _nameController.text.trim();
    final draftDays = [
      for (final day in nonEmptyDays)
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
    ];

    int id;
    if (_program!.isTemplate) {
      id = await repo.createProgram(NewProgramDraft(
        name: name,
        category: ProgramCategory.strengthGenerated,
        equipmentProfile: _equipment.toList(),
        level: _program!.level,
        daysPerWeek: draftDays.length,
        days: draftDays,
      ));
    } else {
      id = _program!.id;
      await repo.updateProgramContent(id, name: name, days: draftDays);
    }
    ref.invalidate(visibleStrengthProgramsProvider);
    ref.invalidate(activeProgramProvider);
    if (mounted) context.go('/strength/library/program/$id');
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.day, required this.onTap, this.onRemove});
  final EditableDay day;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(day.label, style: theme.textTheme.titleMedium),
                  ),
                  if (onRemove != null)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: onRemove,
                    ),
                  const Icon(Icons.edit_outlined, size: 18),
                ],
              ),
              const SizedBox(height: 4),
              if (day.exercises.isEmpty)
                Text('Nog geen oefeningen — tik om toe te voegen',
                    style: theme.textTheme.bodySmall)
              else
                for (final e in day.exercises)
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
    );
  }
}

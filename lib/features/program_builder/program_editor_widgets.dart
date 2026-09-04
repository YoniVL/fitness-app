import 'package:flutter/material.dart';

import '../../domain/models/exercise.dart';
import '../../domain/taxonomy.dart';
import '../../ui/spacing.dart';
import '../strength/widgets/number_stepper.dart';

/// In-memory, editable copy of a prescribed exercise. Used by both the program
/// builder (post-generate preview) and the program editor (existing programs).
class EditableExercise {
  EditableExercise(
      this.exercise, this.sets, this.reps, this.restBetween, this.restAfter);
  Exercise exercise;
  int sets;
  int reps;
  int restBetween;
  int restAfter;
}

class EditableDay {
  EditableDay(this.label, this.exercises);
  String label;
  final List<EditableExercise> exercises;
}

/// Bottom sheet: reorder (tap-and-hold anywhere on a card), edit sets/reps/rest,
/// remove, swap (same movement pattern) or add an exercise, and rename the day.
class DayEditorSheet extends StatefulWidget {
  const DayEditorSheet({
    super.key,
    required this.day,
    required this.catalogue,
    required this.equipment,
    required this.onChanged,
  });

  final EditableDay day;
  final List<Exercise> catalogue;
  final Set<String> equipment;
  final VoidCallback onChanged;

  @override
  State<DayEditorSheet> createState() => _DayEditorSheetState();
}

class _DayEditorSheetState extends State<DayEditorSheet> {
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
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(widget.day.label, style: theme.textTheme.titleLarge),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  tooltip: 'Naam dag wijzigen',
                  onPressed: _renameDay,
                ),
              ],
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
              itemBuilder: (context, i) => ReorderableDelayedDragStartListener(
                key: ValueKey(widget.day.exercises[i]),
                index: i,
                child: ExerciseEditRow(
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

  Future<void> _renameDay() async {
    final controller = TextEditingController(text: widget.day.label);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Naam dag'),
        content: TextField(controller: controller, autofocus: true),
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
    if (name != null && name.isNotEmpty) {
      setState(() => widget.day.label = name);
      widget.onChanged();
    }
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
    setState(
        () => widget.day.exercises.add(EditableExercise(ex, 3, 10, 30, 60)));
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

class ExerciseEditRow extends StatelessWidget {
  const ExerciseEditRow({
    super.key,
    required this.index,
    required this.entry,
    required this.onRemove,
    required this.onSwap,
    required this.onChanged,
  });

  final int index;
  final EditableExercise entry;
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
            Gap.xs,
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
                NumberStepper(
                  label: 'Rust/set (s)',
                  value: entry.restBetween.toDouble(),
                  step: 15,
                  min: 0,
                  max: 300,
                  onChanged: (v) {
                    entry.restBetween = v.round();
                    onChanged();
                  },
                ),
                NumberStepper(
                  label: 'Rust na (s)',
                  value: entry.restAfter.toDouble(),
                  step: 15,
                  min: 0,
                  max: 300,
                  onChanged: (v) {
                    entry.restAfter = v.round();
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

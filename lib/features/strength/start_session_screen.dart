import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/program_repository.dart';
import '../../domain/models/program.dart';
import 'state/active_workout_provider.dart';

class _TemplateDay {
  _TemplateDay(this.program, this.day);
  final Program program;
  final ProgramDay day;
}

final _strengthTemplateDaysProvider =
    FutureProvider<List<_TemplateDay>>((ref) async {
  final repo = ref.read(programRepositoryProvider);
  final programs = await repo.templates(discipline: Discipline.strength);
  final out = <_TemplateDay>[];
  for (final program in programs) {
    for (final day in await repo.daysForProgram(program.id)) {
      out.add(_TemplateDay(program, day));
    }
  }
  return out;
});

/// Pick a template day to start from, or an empty session.
class StartSessionScreen extends ConsumerWidget {
  const StartSessionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = ref.watch(_strengthTemplateDaysProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Training starten')),
      body: days.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fout: $e')),
        data: (list) => ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Lege sessie'),
              subtitle: const Text('Voeg zelf oefeningen toe'),
              onTap: () async {
                await ref.read(activeWorkoutProvider.notifier).startEmpty();
                if (context.mounted) context.pushReplacement('/workout/active');
              },
            ),
            const Divider(),
            for (final td in list)
              ListTile(
                leading: const Icon(Icons.fitness_center),
                title: Text(td.day.label),
                subtitle: Text(td.program.name),
                onTap: () async {
                  await ref
                      .read(activeWorkoutProvider.notifier)
                      .startFromDay(td.day);
                  if (context.mounted) {
                    context.pushReplacement('/workout/active');
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}

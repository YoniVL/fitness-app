import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/home_shell.dart';
import '../../data/repositories/program_repository.dart';
import '../../domain/models/program.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key, required this.discipline});

  final Discipline discipline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isRowing = discipline == Discipline.rowing;
    return Scaffold(
      appBar: AppBar(
        leading: const DisciplineSwitchButton(),
        title: const Text('Bibliotheek'),
      ),
      body: ListView(
        children: isRowing ? _rowing(context, ref) : _strength(context, ref),
      ),
    );
  }

  List<Widget> _strength(BuildContext context, WidgetRef ref) {
    final strength = ref.watch(visibleStrengthProgramsProvider);
    return [
      ListTile(
        leading: const Icon(Icons.fitness_center),
        title: const Text('Oefeningendatabase'),
        subtitle: const Text('Alle oefeningen, per spiergroep'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/strength/library/exercises'),
      ),
      ListTile(
        leading: const Icon(Icons.auto_awesome),
        title: const Text('Stel zelf een schema samen'),
        subtitle: const Text('Op basis van je materiaal en spiergroepen'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/program/builder'),
      ),
      const Divider(),
      _sectionHeader(context, 'Krachtprogramma\'s'),
      strength.when(
        loading: () => const _LoadingTile(),
        error: (e, _) => _ErrorTile('$e'),
        data: (programs) {
          if (programs.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Geen programma\'s. Stel er zelf een samen.'),
            );
          }
          return _programList(programs);
        },
      ),
      const SizedBox(height: 24),
    ];
  }

  List<Widget> _rowing(BuildContext context, WidgetRef ref) {
    final rowing = ref.watch(rowingProgramsProvider);
    return [
      ListTile(
        leading: const Icon(Icons.auto_awesome),
        title: const Text('Stel zelf een roeiplan samen'),
        subtitle: const Text('Op basis van je doel en sessieduur'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/rowing/builder'),
      ),
      const Divider(),
      _sectionHeader(context, 'Roeiprogramma\'s'),
      rowing.when(
        loading: () => const _LoadingTile(),
        error: (e, _) => _ErrorTile('$e'),
        data: _programList,
      ),
      const SizedBox(height: 24),
    ];
  }

  Widget _programList(List<Program> programs) {
    final own = programs.where((p) => !p.isTemplate).toList();
    final templates = programs.where((p) => p.isTemplate).toList();
    return Column(
      children: [
        for (final p in own) _ProgramTile(program: p, own: true),
        if (own.isNotEmpty && templates.isNotEmpty)
          const Divider(indent: 16, endIndent: 16),
        for (final p in templates) _ProgramTile(program: p),
      ],
    );
  }

  Widget _sectionHeader(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}

class _ProgramTile extends StatelessWidget {
  const _ProgramTile({required this.program, this.own = false});
  final Program program;
  final bool own;

  @override
  Widget build(BuildContext context) {
    final isRowing = program.discipline == Discipline.rowing;
    final bits = <String>[
      if (own) 'Eigen schema',
      if (isRowing && program.goal != null) program.goal!.label,
      if (program.level != null) program.level!.label,
      if (program.daysPerWeek != null) '${program.daysPerWeek}×/week',
    ];
    final prefix = isRowing ? '/rowing' : '/strength';
    return ListTile(
      leading: Icon(isRowing ? Icons.rowing : Icons.fitness_center),
      title: Text(program.name),
      subtitle: bits.isEmpty ? null : Text(bits.join(' · ')),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('$prefix/library/program/${program.id}'),
    );
  }
}

class _LoadingTile extends StatelessWidget {
  const _LoadingTile();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
}

class _ErrorTile extends StatelessWidget {
  const _ErrorTile(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Fout: $message'),
      );
}

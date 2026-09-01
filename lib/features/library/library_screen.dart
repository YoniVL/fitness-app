import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/program_repository.dart';
import '../../domain/models/program.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strength = ref.watch(visibleStrengthProgramsProvider);
    final rowing = ref.watch(rowingTemplatesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Bibliotheek')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.fitness_center),
            title: const Text('Oefeningendatabase'),
            subtitle: const Text('Alle oefeningen, per spiergroep'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/library/exercises'),
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
            },
          ),
          _sectionHeader(context, 'Roeiprogramma\'s'),
          rowing.when(
            loading: () => const _LoadingTile(),
            error: (e, _) => _ErrorTile('$e'),
            data: (programs) => Column(
              children: [for (final p in programs) _ProgramTile(program: p)],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
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
      if (own)
        'Eigen schema'
      else if (isRowing)
        'Roeien'
      else
        'Kracht',
      if (program.level != null) program.level!.label,
      if (program.daysPerWeek != null) '${program.daysPerWeek}×/week',
    ];
    return ListTile(
      leading: Icon(isRowing ? Icons.rowing : Icons.fitness_center),
      title: Text(program.name),
      subtitle: Text(bits.join(' · ')),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/library/program/${program.id}'),
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
